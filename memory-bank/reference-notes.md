# Reference Notes — clawd-on-desk

Key observations from the source at `/Users/vinayak.kaushik/Developer/clawd-on-desk-ref`.

## Overview
Desktop pet (Electron + Node.js) that watches AI coding agent processes and animates based on what they're doing.

## Tech Stack
- Electron ^41 + electron-builder + electron-updater
- Native bindings via `koffi`
- HTML parsing via `htmlparser2`
- Entry point: `src/main.js`, launcher: `launch.js`

## Agent Support
Claude Code, Codex CLI, Copilot CLI, Gemini CLI, Cursor Agent, Kiro CLI, opencode

## Key Concepts to Evaluate
- [ ] 12 animation states (idle, thinking, typing, building, juggling, error, happy, sleeping)
- [ ] Eye tracking (cursor follow during idle)
- [ ] Permission bubbles (in-app tool permission review)
- [ ] Mini mode (collapsed edge display, peek-on-hover)
- [ ] Multi-session tracking across agent processes
- [ ] Custom theme / character swap
- [ ] Hook-based agent integrations (per-agent install scripts)

## Areas to Rethink
*Fill in as we explore the source.*
