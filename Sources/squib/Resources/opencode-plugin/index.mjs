// squib — opencode plugin
// Runs inside the opencode process (Bun runtime) and forwards session/tool
// events to the squib HTTP server.
//
// Design (derived from clawd-on-desk reference, stripped to squib's model):
//   - Zero dependencies (Bun built-in fetch + node:fs + node:path + node:os)
//   - Fire-and-forget: event hook never awaits fetch, so squib cannot stall opencode
//   - Same-state dedup — consecutive identical (hookEventName, sessionId) skip POST
//   - Active-state gate — suppresses thinking regression when already working
//     (opencode emits session.status=busy between every tool call as the LLM
//      deliberates the next step; without this gate the pet flashes thinking↔working)
//   - Port cached after first successful POST; re-read from config on miss

import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';

const CONFIG_PATH  = join(homedir(), '.squib', 'server-config.json');
const POST_TIMEOUT = 1000; // ms — generous; squib's IPC roundtrip runs under load
const AGENT_ID     = 'opencode';

// Suppress the thinking regression when already in an active state.
// Mirrors clawd's ACTIVE_STATES_BLOCKING_THINKING (minus sweeping, which squib v1 omits).
const BLOCKS_THINKING = new Set(['working']);

let _cachedPort    = null;
let _lastEventName = null;
let _lastSessionId = null;

// ── Port discovery ───────────────────────────────────────────────────────────

function readPort() {
    try {
        const raw  = JSON.parse(readFileSync(CONFIG_PATH, 'utf8'));
        const port = Number(raw && raw.port);
        return Number.isInteger(port) && port > 0 ? port : null;
    } catch {
        return null;
    }
}

function getPort() {
    if (_cachedPort !== null) return _cachedPort;
    return readPort();
}

// ── HTTP POST ────────────────────────────────────────────────────────────────

function postState(hookEventName, sessionId) {
    const port = getPort();
    if (!port) return;

    const payload = JSON.stringify({
        hook_event_name: hookEventName,
        session_id:      sessionId || 'default',
        tool_name:       '',
        agent_id:        AGENT_ID,
    });

    (async () => {
        const controller = new AbortController();
        const timer      = setTimeout(() => controller.abort(), POST_TIMEOUT);
        try {
            const res = await fetch(`http://127.0.0.1:${port}/state`, {
                method:  'POST',
                headers: { 'Content-Type': 'application/json' },
                body:    payload,
                signal:  controller.signal,
            });
            clearTimeout(timer);
            if (res.ok) {
                _cachedPort = port;
                try { await res.text(); } catch {}
            } else {
                _cachedPort = null;
            }
        } catch {
            clearTimeout(timer);
            _cachedPort = null;
        }
    })().catch(() => {});
}

// ── Dedup + gate ─────────────────────────────────────────────────────────────

function sendState(hookEventName, sessionId) {
    if (!hookEventName) return;

    // Suppress thinking when already in an active state — prevents working↔thinking flicker.
    if (hookEventName === 'UserPromptSubmit' && BLOCKS_THINKING.has(_lastEventName)) return;

    // Same-state dedup.
    if (hookEventName === _lastEventName && sessionId === _lastSessionId) return;

    _lastEventName = hookEventName;
    _lastSessionId = sessionId;
    postState(hookEventName, sessionId);
}

// ── Event translation ────────────────────────────────────────────────────────
//
// Maps opencode SDK events to squib hook_event_names (PascalCase, matching
// Claude Code's vocabulary so PetState.from(hookEventName:) is shared).
//
// Event shapes (from opencode runtime observation + clawd reference):
//   { type: "session.created",       properties: { sessionID } }
//   { type: "session.status",        properties: { sessionID, status: { type } } }
//   { type: "message.part.updated",  properties: { sessionID, part: { type, state: { status } } } }
//   { type: "session.idle",          properties: { sessionID } }
//   { type: "session.error",         properties: { sessionID } }
//   { type: "session.deleted",       properties: { sessionID } }
//   { type: "server.instance.disposed" }
//   { type: "session.compacted",     properties: { sessionID } }

function translate(event) {
    if (!event || typeof event.type !== 'string') return null;
    const props = event.properties || {};

    switch (event.type) {
        case 'session.created':
            return 'SessionStart';

        case 'session.status': {
            const type = props.status && props.status.type;
            return type === 'busy' ? 'UserPromptSubmit' : null;
        }

        case 'message.part.updated': {
            const part   = props.part;
            if (!part || part.type !== 'tool') return null;
            const status = part.state && part.state.status;
            if (status === 'running')   return 'PreToolUse';
            if (status === 'completed') return 'PostToolUse';
            if (status === 'error')     return 'PostToolUseFailure';
            return null;
        }

        case 'session.compacted':
            // squib v1 has no sweeping state — map to working (pet stays busy during compaction)
            return 'PostToolUse';

        case 'session.idle':
            return 'Stop';

        case 'session.error':
            return 'StopFailure';

        case 'session.deleted':
        case 'server.instance.disposed':
            return 'SessionEnd';

        default:
            return null;
    }
}

// ── Plugin entrypoint ────────────────────────────────────────────────────────

export default async (_ctx) => {
    return {
        event: async ({ event }) => {
            try {
                if (!event || typeof event.type !== 'string') return;
                const hookEventName = translate(event);
                if (!hookEventName) return;
                const sessionId = (event.properties && event.properties.sessionID) || 'default';
                sendState(hookEventName, sessionId);
            } catch {}
        },
    };
};
