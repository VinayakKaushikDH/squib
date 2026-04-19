# Progress Log

## 2026-04-19 — Session 3: Phase 1d
- BubbleWindow (NSPanel, nonactivatingPanel, dark card, Allow/Deny buttons) — lower-right corner, stacks upward
- BubbleManager: manages the stack, computes pet Y offset (= stackHeight), fires onOffsetChange
- PetWindow: stores baseFrame on init; setBubbleOffset animates with 0.15s easeOut
- HookServer refactored: tryParse() returns ParseResult enum; /permission route holds NWConnection open; onReady/onPermissionRequest/onPermissionEvicted callbacks; resolvePermission(id:allow:); denyAllPending() on quit; disconnect detection via stateUpdateHandler
- HookInstaller: fixed SessionStop→SessionEnd; added PostCompact, PreCompact, SubagentStart, SubagentStop, Elicitation to hookedEvents; new registerPermissionHook(port:) writes HTTP hook entry to settings.json
- AppDelegate: wires BubbleManager ↔ HookServer ↔ PetWindow; applicationWillTerminate denies all pending permissions

## 2026-04-19 — Session 2: Phase 1c
- StateEngine: replaced single-state with [sessionId: SessionRecord] dict; priority resolution (highest-priority state across active sessions wins, fallback .idle); 10s timer evicts sessions >30s stale; SessionEnd immediately removes session
- Eye tracking: global NSEvent monitor in PetWindow; circular clamping (300pt → 3.5 SVG units max offset); `updateEyes(dx:dy:)` moves `id="lp"` and `id="rp"` in SVG DOM via evaluateJavaScript
- PetView: switched from `<img src>` to inline SVG so JS can manipulate pupil elements
- SVGs updated: idle, thinking, working, attention have `id="lp"`/`id="rp"` on pupils; error and sleeping have no pupils so eye tracking is naturally a no-op
- Fixed settings.json: SessionStop → SessionEnd (invalid hook event name)

## 2026-04-19 — Session 1: Init + Discovery
- Initialized jujutsu repo at `/Users/vinayak.kaushik/Developer/squib`
- Cloned clawd-on-desk reference to `/Users/vinayak.kaushik/Developer/clawd-on-desk-ref`
- Created `CLAUDE.md` and `memory-bank/` structure
- Completed full discovery phase: read state.js, tick.js, server.js, agents/registry.js, agents/claude-code.js, agents/opencode.js, hooks/clawd-hook.js, hooks/opencode-install.js, hooks/opencode-plugin/
- Researched pi-mono coding agent (https://github.com/badlogic/pi-mono)
- Made all key architecture decisions (see decisions.md)

## 2026-04-19 — Session 4: Phase 1e
- opencode plugin: `Sources/squib/Resources/opencode-plugin/index.mjs` + `package.json` (~110 lines); reads port from `~/.squib/server-config.json`; fire-and-forget POST to `/state`; thinking-regression gate (suppresses `UserPromptSubmit` when `lastState=working` — opencode emits `session.status=busy` between every tool call); maps 7 opencode events to squib hook names
- PiWatcher: 2s polling timer (not kqueue) scans `~/.pi/agent/sessions/*/*.jsonl`; tracks byte offsets per file; parses `message` JSONL entries with `content` array `tool_use` block detection and `stop_reason` mapping
- TrayMenu: `NSStatusItem`; session list (id + state) + Quit; driven by new `onSessionsChange([String: PetState])` callback on `StateEngine`
- HookInstaller: added `registerOpencodePlugin()` — copies bundle to `~/.squib/plugins/opencode-plugin/`, upserts stable path into `~/.config/opencode/opencode.json`; skips if opencode not installed
- AppDelegate: wired TrayMenu, PiWatcher, `onSessionsChange` callback
- Build: clean

## 2026-04-20 — Session 5: Phase 1e+ bubble system redesign

- BubbleWindow fully rewritten from native NSTextField/NSButton to WKWebView with inline HTML/CSS/JS (same pattern as PetView)
- 4 bubble modes: regular permission (tool pill + scrollable command block + suggestion buttons), plan review (ExitPlanMode → Approve/Go to Terminal), elicitation (radio/checkbox form, Submit/Terminal buttons), default fallback
- Dynamic height: JS measures card.offsetHeight + 12 after render, posts via window.webkit.messageHandlers.squib.postMessage; BubbleManager uses measuredHeight per window — no more fixed constant
- Width changed from 320px to 340px (matching reference)
- New `PermissionDecision.swift`: typed enum `.allow`, `.deny`, `.allowWithPermissions(updatedPermissions:)`, `.allowWithUpdatedInput(updatedInput:)`
- `PermissionRequest` now carries `cwd`, `suggestions: [[String: Any]]`, `isElicitation: Bool`
- `HookServer.resolvePermission` now takes `decision: PermissionDecision`; `buildResponseBody` serialises all 4 decision types
- Suggestion buttons: `getSuggestionLabel` logic mirrors reference (addRules → "Allow X in dir/", setMode → "Auto-accept edits"); `resolveSuggestion` normalises to Claude Code's updatedPermissions format
- Elicitation: form rendered in JS, answers collected and posted as `{type: "elicitation-submit", answers}`; Swift merges into original toolInput as updatedInput
- WKWebView transparency: `webView.setValue(false, forKey: "drawsBackground")`
- Retain cycle in BubbleWindow avoided by calling `removeScriptMessageHandler(forName:)` in `BubbleWindow.close()` override

## Current Status
- **Phase**: Phase 1e+ complete — bubble system at feature parity with reference
- **Next**: TBD (v1.1 ideas: pi-mono extension API, mini mode, settings UI)

## Build Phases
| Phase | Status | Description |
|-------|--------|-------------|
| 1a | done | SPM project, PetWindow on screen, idle SVG visible, transparent + always-on-top |
| 1b | done | HookServer (NWListener), StateEngine, 6 SVG states, clawd-hook.js, HookInstaller |
| 1c | done | StateEngine: multi-session, priority, stale cleanup, eye tracking |
| 1d | done | BubbleWindow: permission approve/deny, lower-right stack, pet slides up |
| 1e | done | opencode plugin, PiWatcher, TrayMenu — v1 scope complete |
