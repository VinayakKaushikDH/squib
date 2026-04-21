#!/usr/bin/env node
// clawd-hook.js — Claude Code hook script for squib
// Receives hook event via stdin JSON, POSTs to squib's HookServer.
// Installed to ~/.squib/hooks/ by squib on launch.

'use strict';

const fs   = require('fs');
const http = require('http');
const os   = require('os');
const path = require('path');

function readConfig() {
    try {
        const p = path.join(os.homedir(), '.squib', 'server-config.json');
        return JSON.parse(fs.readFileSync(p, 'utf8'));
    } catch {
        return null;
    }
}

function post(port, body) {
    return new Promise((resolve, reject) => {
        const req = http.request(
            {
                hostname: '127.0.0.1',
                port,
                path: '/state',
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'Content-Length': Buffer.byteLength(body),
                },
            },
            (res) => { res.resume(); res.on('end', resolve); }
        );
        req.on('error', reject);
        req.setTimeout(500, () => { req.destroy(); reject(new Error('timeout')); });
        req.write(body);
        req.end();
    });
}

async function main() {
    const raw = fs.readFileSync(0, 'utf8').trim();
    let event;
    try { event = JSON.parse(raw); } catch { process.exit(0); }

    const config = readConfig();
    if (!config?.port) process.exit(0); // squib not running — exit silently

    const payload = JSON.stringify({
        hook_event_name: event.hook_event_name ?? '',
        session_id:      event.session_id      ?? '',
        tool_name:       event.tool_name       ?? '',
        agent_id:        'claude-code',
    });

    try {
        await post(config.port, payload);
    } catch {
        // best-effort; never block Claude Code
    }
    process.exit(0);
}

main();
