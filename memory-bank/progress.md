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

## 2026-04-21 — Session 12: Animation gap fixes

- **Priority bugs fixed** (TASK-1, TASK-2): `sweeping` 2→6, `carrying` 2→4 in `PetState.priority`. Both now beat `working` (3) as the reference requires. Tests updated + 3 new StateEngine tests added.
- **SVGs bundled** (TASK-3, 5, 8, 9): `clawd-wake`, `clawd-mini-sleep`, `clawd-mini-enter-sleep`, `clawd-mini-typing`, `clawd-idle-living`, `clawd-working-debugger` copied from reference.
- **Wake sequence** (TASK-4): `startWakePoll()` (200ms) starts after doze; cursor movement triggers `playWakeSequence()` (clawd-wake.svg, 1.4s, then restore). Deep sleep: 60s no-move → skip to collapse. `wakePollTimer` invalidated on cancelSequences + before collapse step.
- **DND mini mode** (TASK-6): `doNotDisturb: Bool = false` on PetWindow. Three sites fixed: `enterMiniMode`, `showMiniState`, `miniPeekOut` all use `clawd-mini-enter-sleep`/`clawd-mini-sleep` when DND is on.
- **mini-working** (TASK-7): working/thinking/juggling/building/conducting states in mini mode now play `clawd-mini-typing` (4s).
- **Idle variants expanded** (TASK-8, 9): `clawd-idle-living` (16s) and `clawd-working-debugger` (14s) added to `idleVariants` pool.
- **Stale SVGs deleted** (TASK-12): `attention.svg`, `error.svg`, `idle.svg`, `sleeping.svg`, `thinking.svg`, `working.svg` removed from Resources.
- **Tests**: 81/81 passing (3 new StateEngine tests: sweeping beats working, carrying beats working, sweeping end fallback).
- **Deferred**: TASK-10 (doze eye tracking — `clawd-idle-doze.svg` lacks #eyes-js; needs SVG edit first), TASK-11 (click reactions).

## 2026-04-21 — Session 13: Doze eye tracking + click reactions

- **Doze eye tracking** (TASK-10): Edited `clawd-idle-doze.svg` — wrapped shadow in `<g id="shadow-js">`, body in `<g id="body-js">`, renamed `eyes-doze` → `eyes-js`. CSS breathing animation runs on inner `.doze-body`; JS `setAttribute` runs on wrapper groups (no conflict). Added `isShowingDoze: Bool` to PetWindow; set true on doze swap, false in `cancelSequences()`, `playWakeSequence()`, and both collapse paths (2s timer + deep sleep). `mouseMoved` checks `isShowingDoze` alongside `currentState.supportsEyeTracking`.
- **Click reactions** (TASK-11): Copied `clawd-react-left/right/double/double-jump/annoyed.svg` from reference. Added `playClickReaction(svg:duration:)` helper (guards against drag/mini/miniAnimating). Left-click: `clickCount==1` → react-left (2.5s), `clickCount==2` → react-double or react-double-jump randomly (3.5s), `clickCount≥3` → react-annoyed (3.5s). Right-click local monitor → react-right (2.5s, consumes event). Drag threshold cancels pending click reaction and replaces with react-drag (both local + global drag handlers). `cancelSequences()` clears `clickReactionTimer` + `isClickReacting`. `deinit` invalidates `clickReactionTimer`.
- **Tests**: 81/81 passing (no new tests needed — reaction logic is UI-only).

## 2026-04-21 — Session 14: PiJSONLParser bug fix

- **Root cause**: `PiJSONLParser` was built against the Anthropic API message format, not pi-mono's actual format. Tests were written against the same wrong schema so all 13 tests passed with no real coverage.
- **Fixed**: message nesting (payload under `"message"` key), content block type (`"toolCall"` not `"tool_use"`), stop reason values (`"stop"/"toolUse"/"aborted"`), compaction handling (`{"type":"compaction",...}` now emits PostCompact).
- **Fixed**: integration test fixtures in `PiWatcherIntegrationTests` updated from flat format to nested pi-mono format.
- **Result**: 84/84 tests passing with correct pi-mono format fixtures.

## 2026-04-22 — Session 15: Hook registration overhaul + PiWatcher startup fix

- **HookEventName enum**: Added `HookEventName` to `HookEvent.swift` with compile-time string constants for all 16 event names including `PermissionRequest`. `hookedEvents` in `HookInstaller` now references `HookEventName.*` — typos caught at build time.
- **Single settings.json write**: `installIfNeeded()` now only copies the script. New `registerClaudeHooks(port:)` merges event hooks + permission hook into one read/write pass; called from `hookServer.onReady` in AppDelegate. Old `registerClaudeHooks()` (no-arg) and `registerPermissionHook(port:)` deleted.
- **PermissionRequest upsert**: URL changed from `/permission` to `/squib/permission` (distinctive, identifiable). Registration filters out existing entries where URL is on `127.0.0.1` + ends with `/squib/permission` (stale port from previous launch), then appends fresh entry. Third-party PermissionRequest entries preserved. HookServer routes `POST /squib/permission`.
- **agent_id in clawd-hook.js**: Added `agent_id: 'claude-code'` to payload, matching the opencode plugin's `agent_id: 'opencode'`.
- **opencode session.compacted fix**: Was mapped to `PostToolUse` with stale "v1 has no sweeping state" comment. Now correctly maps to `PostCompact`.
- **settings.json cleanup**: Removed 56 duplicate clawd-on-desk hook entries that accumulated from the reference project's installer lacking idempotency.
- **PiWatcher startup fix**: squib was showing error state on every launch because PiWatcher replayed all historical pi-mono JSONL data on startup. Fix: `start()` calls `seedExistingFiles()` first, which fast-forwards all pre-existing files to their current byte offset (no events). Regular polls then only process new bytes / truly new files (which still get `SessionStart` + full content). New "pre-existing file content is skipped on startup" regression test added.
- **Tests**: 85/85 passing (1 new PiWatcher test; 3 PiWatcher tests restructured to create files after watcher starts).

## 2026-04-22 — Session 16: Precise drag hitboxes

- **Problem**: 65pt circle centered at (100,100) was too large and too high — clawd's body sits in the bottom half of the 200×200 frame, so users could drag by clicking empty space above the character's head.
- **Fix**: Replaced circle with three state-aware rectangles ported directly from the reference's `theme.json` hitBoxes (same SVG viewBox, same geometry math):
  - default `{x:-1,y:5,w:17,h:12}` → AppKit rect (50.7, 10.0, 98.6×69.6) — all idle/working states
  - wide `{x:-3,y:3,w:21,h:14}` → AppKit rect (39.1, 10.0, 121.8×81.2) — conducting, error, notification
  - sleeping `{x:-2,y:9,w:19,h:7}` → AppKit rect (44.9, 15.8, 110.2×40.6) — sleeping, idle-collapse
- `PetView.currentSVGName` tracks the active SVG (updated in both `loadSVG` and `swapInlineSVG`)
- `PetView.hitRect` is a synchronous computed property — no async needed
- `PetWindow.hitTestPending` removed; `mouseMoved` handler simplified to direct `hitRect.contains(local)`

## 2026-04-22 — Session 17: Permission suggestions key fix

- **Bug**: Suggestion buttons ("Allow all", "Always allow X", "Allow Bash in dir/") never appeared in permission popups. `HookParser.parsePermissionPayload` read `obj["suggestions"]` but Claude Code sends the key as `"permission_suggestions"`.
- **Fix**: One-line change in `Sources/SquibCore/HookParser.swift` line 58: `obj["suggestions"]` → `obj["permission_suggestions"]`.
- **Tests**: 85 → 87 passing. Two new tests in both `HookParserTests.swift` files: one confirms `permission_suggestions` is parsed, one confirms the legacy `suggestions` key is ignored.

## 2026-04-22 — Session 18: Allow Session shortcut

- **Feature**: `A` key now triggers "Allow Session" instead of the first suggestion button's permanent rule.
- **AppDelegate**: Added `trustedSessions: Set<String>`. `onPermissionRequest` checks this set first — if the session is trusted, calls `resolvePermission(.allow)` immediately and returns without showing a bubble. `onEvent` removes session from `trustedSessions` on `SessionEnd`. `onTrustSession` callback inserts session into `trustedSessions`, resolves the current permission, and clears notification + pending map entry.
- **BubbleManager**: Added `onTrustSession: ((UUID, String?) -> Void)?`. Wired in `add()` via `win.onTrustSession`. `handleKey` case `"a"` → `allowSessionViaKey()`.
- **BubbleWindow (Swift)**: `allowAllViaKey()` replaced by `allowSessionViaKey()` (calls `keyAllowSession()` in JS). `onTrustSession: (() -> Void)?` property added. `BubbleMsgHandler.handleStringDecide` handles `"trust-session"` by calling `win.onTrustSession?()` — does NOT call `didDecide`, so no `PermissionDecision` case needed.
- **BubbleWindow (HTML/JS)**: `btnAllowSession` static button inside `<div id="sugs">` (hidden by default). `loadPermission()` regular mode: after `renderSuggestions`, prepends `btnAllowSession` and shows it when suggestions are present (session-scoped allow only meaningful alongside permanent options). `renderSuggestions` no longer attaches `[A]` kbd hint to the first suggestion. `keyAllowAll()` removed; `keyAllowSession()` added (clicks `btnAllowSession` if visible, falls back to `keyAllow()`). Click handler posts `{type:"decide", value:"trust-session"}`. `disableAll()` explicitly disables `btnAllowSession`.
- **Decision**: "Allow Session" only shown when `suggestions.length > 0` — in plan review and elicitation modes the button is not shown (the shortcut falls back to `keyAllow()`).
- **Build**: clean (4.29s).

## Current Status
- **Phase**: Session 18 complete — Allow Session shortcut implemented
- **Next**: complete SVG migration (pending changes in PetState/PetView/Resources with new working-state SVGs)
- **Skipped**: mini-crabwalk — purely cosmetic, current 100ms snap is acceptable, complexity not worth it
