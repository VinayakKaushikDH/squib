# Reference Notes — clawd-on-desk

Key observations from the source at `/Users/vinayak.kaushik/Developer/clawd-on-desk-ref`.

## Overview
Desktop pet (Electron + Node.js) that watches AI coding agent processes and animates based on what they're doing.

## Tech Stack
- Electron ^41 + electron-builder + electron-updater
- Native Windows FFI via `koffi` (AllowSetForegroundWindow)
- HTML parsing via `htmlparser2`
- Entry point: `src/main.js` (~40k tokens — monolithic orchestrator), launcher: `launch.js`
- Pure JavaScript (no TypeScript)

## Agent Support
Claude Code, Codex CLI, Copilot CLI, Gemini CLI, Cursor Agent, Codebuddy, Kiro CLI, opencode

## Architecture — Key Modules

### `src/state.js` — State machine + session tracking
- Sessions tracked in a `Map` (max 20), keyed by session_id
- State priority: `error(8) > notification(7) > sweeping(6) > attention(5) > carrying(4) = juggling(4) > working(3) > thinking(2) > idle(1) > sleeping(0)`
- `resolveDisplayState()` picks the highest-priority state across all active sessions
- Stale cleanup every 10s: checks if source/agent process is still alive via `process.kill(pid, 0)`
- Sessions auto-expire after SESSION_STALE_MS (10min) or WORKING_STALE_MS (5min) if in working state
- Juggling state: used when a session spawns a subagent; restores prior state on SubagentStop
- `deriveSessionBadge()`: 4-category user-facing badge (running/done/interrupted/idle)

### `src/tick.js` — Main 20fps tick loop
- Cursor polling for: eye tracking, idle detection, sleep sequencing, mini-peek hover
- Eye tracking: computes relative cursor position vs. eye center; sends dx/dy to renderer
- Idle pipeline: 20s no movement → random idle animation; 60s → yawn → doze → deep sleep
- Wake poll: after sleeping, polls every 200ms for cursor movement to wake

### `src/server.js` — Local HTTP server
- Receives POST /state, POST /permission, GET /health from hook scripts
- Routes events to `updateSession()` in state.js
- Permission requests show a blocking bubble window (agent waits for approve/deny)
- Also watches Claude Code's settings.json for hook sync

### `agents/` — Agent registry
- Each agent exports: `id`, `name`, `processNames` (per-platform), `eventSource` ("hook" or "log-poll"), `eventMap` (event→state), `capabilities`, `pidField`
- Claude Code uses HTTP hook (`eventSource: "hook"`)
- Codex and Gemini use log-file polling (`eventSource: "log-poll"`)
- Registry: `getAllAgents()`, `getAgent(id)`, `getAllProcessNames()`

### `hooks/clawd-hook.js` — Claude Code hook script
- Installed into Claude Code's hooks config as a PostToolUse/PreToolUse/etc. hook
- Reads stdin JSON, extracts session_id, cwd, pid chain, session title
- POSTs state to local HTTP server via `postStateToRunningServer()`
- Reads transcript JSONL tail (256KB) to extract session title from `custom-title`/`agent-name` events

### `src/permission.js` — Permission bubble
- Stacked floating BrowserWindows anchored near the pet
- Layout: below pet → side of pet → corner fallback
- Handles: tool permission approve/deny, ElicitationRequest, ExitPlanMode (plan review)
- Restores focus to previous foreground app after interaction

### Theme system
- SVG-based animations per state
- Theme defines: state files, timings (minDisplay, autoReturn, yawnDuration, etc.), hitboxes, eye tracking ratios, idle animations, working tiers (different SVG for 1 vs N parallel sessions)
- Hot-swappable at runtime

### `src/mini.js` — Mini mode
- Collapsed to screen edge, shows only a sliver
- Peek-on-hover: slides in when cursor approaches
- States: mini-idle, mini-working, mini-peek, mini-sleep, mini-alert, mini-happy

### Window layout
- Two windows: transparent render window (always click-through) + invisible hit-test window
- Hit window captures mouse events, send to main, routes clicks/drags
- Pet position persisted to prefs per theme (theme-aware position)

## Claude Code Event → State Mapping
```
SessionStart        → idle
SessionEnd          → sleeping (with optional sweeping if /clear was used)
UserPromptSubmit    → thinking
PreToolUse          → working
PostToolUse         → working
PostToolUseFailure  → error  (oneshot)
Stop                → attention  (oneshot)
StopFailure         → error  (oneshot)
SubagentStart       → juggling
SubagentStop        → working (restores pre-subagent state)
PreCompact          → sweeping  (oneshot)
PostCompact         → attention (oneshot)
Notification        → notification (oneshot)
Elicitation         → notification (oneshot)
WorktreeCreate      → carrying (oneshot)
```
Oneshot states auto-return after their minDisplay timeout.

## Key Concepts to Evaluate
- [x] 12 animation states (idle, thinking, working, juggling, error, attention/happy, sleeping, sweeping, carrying, notification, mini variants)
- [x] Eye tracking (cursor follow during idle)
- [x] Permission bubbles (in-app tool permission review)
- [x] Mini mode (collapsed edge display, peek-on-hover)
- [x] Multi-session tracking across agent processes
- [ ] Custom theme / character swap — TBD for squib
- [x] Hook-based agent integrations (per-agent install scripts)

## Areas to Rethink for squib
- `src/main.js` is 40k+ tokens and mixes everything — split from day one
- Electron may be worth replacing with Tauri for lighter binary (evaluate ARM compat)
- TypeScript would help with the complex state machine
- Permission bubble UI could be simplified or deferred
- Multi-agent support could be added incrementally (Claude Code first)
- Mini mode is polish — defer to v2
