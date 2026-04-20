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
- Bug fix: elicitation form rendered raw JSON in live squib — two root causes found and fixed: (1) Claude Code never sends `isElicitation: true`; must detect by `toolName == "AskUserQuestion"` in `HookServer.parsePermissionPayload`; (2) `JSONSerialization` returns `NSNumber` for JSON booleans so `as? Bool` always returned false — fixed with `.boolValue`

## 2026-04-20 — Session 6: GIF assets + full state set

- Replaced all hand-drawn SVGs with original clawd assets from clawd-on-desk-ref
- PetState expanded 6 → 12 states: added building, juggling, conducting, notification, sweeping, carrying
- Idle state uses `clawd-idle-follow.svg` (inline SVG, CSS breathe+blink animations, `#eyes-js` eye tracking)
- All other 11 states use clawd GIFs via `<img>` in WKWebView
- Eye tracking restored: targets `#eyes-js` via `style.transform = translate(dx, dy)`, max 3.0 SVG units (theme spec)
- PetWindow tracks `currentState` to gate eye tracking on `state.supportsEyeTracking` (idle only)
- StateEngine: subagent count tracked (`activeSubagents`); juggling (1) vs conducting (2+) via synthetic `__subagent__` session
- StateEngine: building upgrade — PreToolUse/PostToolUse with 3+ real sessions → .building
- StateEngine: `setNotification(id:active:)` manages synthetic `__notification__<id>` sessions; eviction-exempt
- AppDelegate: permission request/eviction/decision all call `setNotification` to drive notification state
- HookInstaller: added WorktreeCreate to hookedEvents
- All mini-mode, debugger, and reaction GIFs bundled (ready for later use)

## 2026-04-20 — Session 6b: SVG idle variants + sleep sequence

- Idle pool: PetWindow randomly cycles between clawd-idle-look (10s), clawd-idle-reading (14s), clawd-idle-yawn (3.8s) every 20–45s, returning to clawd-idle-follow after each variant
- Sleep sequence: yawn (3.8s) → doze (2s) → collapse (1s) → sleeping — all chained via Timer in PetWindow.playSleepSequence()
- Step 1 uses loadSVG (full page load); steps 2–4 use swapInlineSVG (JS innerHTML, no flash)
- PetState.sleeping now uses clawd-sleeping.svg (sploot + floating Zzz particles) instead of GIF
- PetView.swapInlineSVG: swaps body innerHTML via JS template literal — avoids WKWebView page reload between sequence steps
- All idle/sleep SVGs bundled: clawd-idle-yawn, clawd-idle-look, clawd-idle-reading, clawd-idle-doze, clawd-idle-collapse, clawd-sleeping
- Visually confirmed: transitions seamless (no flash between sequence steps)

## Current Status
- **Phase**: Session 6b complete — full clawd SVG animations, sleep sequence, idle variant pool
- **Next**: TBD (working-state SVGs, mini mode, theming)

## Build Phases
| Phase | Status | Description |
|-------|--------|-------------|
| 1a | done | SPM project, PetWindow on screen, idle SVG visible, transparent + always-on-top |
| 1b | done | HookServer (NWListener), StateEngine, 6 SVG states, clawd-hook.js, HookInstaller |
| 1c | done | StateEngine: multi-session, priority, stale cleanup, eye tracking |
| 1d | done | BubbleWindow: permission approve/deny, lower-right stack, pet slides up |
| 1e | done | opencode plugin, PiWatcher, TrayMenu — v1 scope complete |

## 2026-04-20 — Session 7: Drag + Mini Mode

- Drag: local mouseDown (consuming) + global mouseDragged/mouseUp monitors
  - Local mouseDown consumes event to prevent text-selection start in background apps
  - Global drag+up monitors fire when cursor enters other processes (menu bar area) — fills gap local monitors have
  - `dragThreshold = 3pt`, position saved to `~/.squib/position.json`, restored on launch
- Mini mode: SVG-based (not GIF) — reference uses `viewBox="-15 -25 45 45"` zoomed-in viewport
  - Entry: `clawd-mini-enter.svg` (100ms Timer slide + 3.2s timer) → `clawd-mini-idle.svg`
  - Exit: parabola arc `+ arc` (AppKit Y-from-bottom, NOT `- arc` like Electron Y-from-top)
  - Peek: cursor enters visible strip → `clawd-mini-peek.svg` + 25pt animateSlide in
  - All slides use Timer-based `animateSlide(toX:duration:)` — NSAnimationContext/CA layer path bypasses `constrainFrameRect` and resizes window at edges
  - Left edge GIFs flipped via CSS `svg{transform:scaleX(-1);}` in PetView.loadSVG
  - Eye tracking active in mini mode (all mini SVGs have `#eyes-js`)
- `clampToScreen()`: loose clamp — `visibleFrame ± 25% of size`, allows pet into menu bar/dock zone
- Window level 1500 (`CGAssistiveTechHighWindowLevel`), `constrainFrameRect` returns unchanged

## 2026-04-20 — Session 9: Eye tracking fidelity + drag reaction

- **Body+shadow tracking**: `PetView.updateEyes` now drives three SVG elements:
  - `#eyes-js` — full (dx, dy) via `setAttribute('transform','translate(x,y)')` (SVG units)
  - `#body-js` — 33% of eye offset (subtle whole-body lean, matches reference `bodyScale=0.33`)
  - `#shadow-js` — horizontal stretch (`scaleX = 1 + |bdx| * 0.15`) + shift (`bdx * 0.3`)
  - Switched from CSS `style.transform = 'translate(Xpx, Ypx)'` to `setAttribute` — CSS px ≠ SVG units; previous code moved eyes only ~3px, setAttribute gives full 3 SVG units (~13px at 200px size)
- **Eye tracking math**: 0.5-unit grid snap (`rounded() / 2`), Y clamped to ±1.5 (50% of maxOffset); matches reference tick.js exactly
- **Bubble offset guard**: `setBubbleOffset` now checks if pet's `baseFrame` horizontally overlaps the bubble zone (`wa.maxX - 356`) AND vertically before animating — pet no longer slides when it's far from bubbles
- **Drag reaction**: `clawd-react-drag.svg` bundled and shown when drag threshold (3pt) is first crossed; restored via `loadState(currentState)` on mouseUp in both local and global handlers

## Missing states inventory (from reference audit this session)
- `dozing`: SVG with eye tracking (we only use it mid-sequence, not as named state)
- `waking`: `clawd-wake.svg` — wake-up animation when cursor moves after sleeping; entirely absent
- `mini-working`: `clawd-mini-typing.svg` — not implemented
- `mini-crabwalk`, `mini-enter-sleep`, `mini-sleep` — not implemented
- All click reactions: `clawd-react-left/right.svg` (2500ms), `clawd-react-annoyed.svg` (3500ms), `clawd-react-double[/jump].svg` (3500ms)
- `clawd-working-debugger.svg` missing from idle animation pool (reference plays it as 14s idle variant)

## 2026-04-20 — Session 10: SquibCore module split + permission auto-dismiss

- SquibCore module: moved `HookEvent`, `HookServer`, `PermissionDecision`, `PermissionRequest`, `PetState`, `PiWatcher`, `StateEngine` from `squib` target to `SquibCore` target; added `public` to all cross-boundary declarations
- `HookParser.swift` and `PiJSONLParser.swift` added to `SquibCore` — extracted pure parsing logic from `HookServer` and `PiWatcher` respectively
- Permission auto-dismiss: `AppDelegate.pendingPermissionsBySession: [String: UUID]` tracks open permissions per session; `PostToolUse` event for that session triggers auto-dismiss (removes bubble, calls `setNotification(active:false)`, closes connection) — replaces broken connection-close detection
- Root cause documented: Claude Code does not close the held HTTP connection when resolving a permission in its own UI; `.cancelled` eviction path was unreachable

## 2026-04-21 — Session 11: Test infrastructure

- `HookParser` and `PiJSONLParser` made fully public (struct + init + all methods)
- `squibTestRunner` executable target added to Package.swift — standalone Swift Testing runner
  - Calls `Testing.__swiftPMEntryPoint()` directly via `@_spi(ForToolsIntegrationOnly) import Testing`
  - Bypasses SPM's bundle runner which requires a formal Testing package dependency to activate swift-testing mode
  - Sources in `Sources/squibTestRunner/` use `import SquibCore` (no @testable needed since all APIs are public)
- 78 tests across 6 suites — all passing:
  - `PetState` (7 tests): priority ordering, asset extensions, eye tracking, `from(hookEventName:)` mapping
  - `StateEngine` (23 tests): session lifecycle, priority resolution, subagent counting, notification, `reset()`, `sessionSnapshot`, callbacks
  - `HookParser` (18 tests): HTTP request parsing, permission payload parsing, response serialisation
  - `PiJSONLParser` (13 tests): JSONL line parsing, role mapping, stop reason handling
  - `HookServer Integration` (8 tests): health, event dispatch, bad JSON, StateEngine wiring, 404, debug routes (state/inject/reset), disabled guard
  - `PiWatcher Integration` (4 tests): new file → SessionStart, JSONL parse+emit, appended lines, non-.jsonl ignored
- `StateEngine`: added `reset()` + `sessionSnapshot` public API
- `PiWatcher`: made `sessionsRoot`/`pollInterval` injectable via init; timer moved to `RunLoop.main` so it fires in test contexts
- README.md updated — 78/6 counts, integration suites added to table
- Run tests: `swift run squibTestRunner`

## Current Status
- **Phase**: Session 11 complete — full test infrastructure, 78/78 passing
- **Next**: waking state / click reactions, or mini-mode improvements (mini-working, mini-crabwalk)
