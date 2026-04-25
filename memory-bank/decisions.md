# Design Decisions

Log of architectural and product decisions with rationale.

## Format
Each entry: **date — decision — rationale**

---

## 2026-04-19 — Framework: Swift/AppKit (macOS only)
Chose Swift/AppKit over Electron/Tauri. macOS only — no cross-platform requirement.
- No ~150MB Electron binary; WKWebView for SVG rendering is ~10MB total
- NSPanel, NSTrackingArea, NSStatusItem are first-class APIs for this use case
- No koffi/FFI needed; AppKit handles all window management natively

## 2026-04-19 — Language: Swift
Follows from framework choice. Swift async/await for tick loop and network server. No TypeScript/JS in the main app (hook scripts remain Node.js since they run in the agent's environment).

## 2026-04-19 — Build: Swift Package Manager only
`swift build` / `swift run`. No .xcodeproj. All config in Package.swift. Agent-friendly.

## 2026-04-19 — Agents (v1): Claude Code, opencode, pi-mono
- Claude Code: HTTP hook scripts POSTing to HookServer (same pattern as reference)
- opencode: Plugin registered in ~/.config/opencode/opencode.json (adapt reference plugin)
- pi-mono (`@mariozechner/pi-coding-agent`): File-watcher on ~/.pi/agent/sessions/ JSONL
  - pi-mono also has `pi.on('tool_call', ...)` extension API — evaluate for v1.1
  - Ref: https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent

## 2026-04-19 — v1 Scope: Core loop + permission bubbles
- Pet on screen, transparent click-through window (NSPanel + WKWebView)
- Animates through: idle, thinking, working, error, sleeping, attention, sweeping
- Claude Code hooks installed and active
- Permission bubble (BubbleWindow) for tool approval
- opencode plugin + pi-mono file watcher
- TrayMenu with session list
- NO mini mode, NO settings UI, NO multi-theme (all deferred)

## 2026-04-19 — SVG rendering: WKWebView
WKWebView inside NSPanel loads a minimal HTML wrapper. State changes swap the SVG `src` 
via `evaluateJavaScript`. Same model as the reference (Electron renderer), without Chromium.
macOS 12+ handles SVG natively in WKWebView.

## 2026-04-19 — HTTP server: Network.framework (NWListener)
Replaces Node's `http` module. NWListener on localhost for receiving hook POSTs.
Port discovery: write port to a known config file (same pattern as reference's server-config.js).

## 2026-04-19 — SVG tentacle constraint: start at body base, curve outward
In thinking.svg, the raised tentacle must start at the same y=82 position as the other tentacles and curve hard outward before going up — paths that begin inside or near the body center pass through the body and are invisible. Confirmed correct on the third iteration after two rejections.

## 2026-04-19 — No dual-window hit-test
The reference uses two windows (render + hit-test) due to Electron limitations.
AppKit: single NSPanel with setIgnoreMouseEvents(true) + NSTrackingArea for hover detection.
Drag handled via NSEvent.addLocalMonitorForEvents.

## 2026-04-19 — SVG rendering: inline HTML required (not <img src>)
PetView loads SVG as inline HTML so WKWebView's JS can access the DOM and reposition pupil elements. An `<img src>` tag sandboxes the SVG DOM — `evaluateJavaScript` targeting `id="lp"`/`id="rp"` silently does nothing.

## 2026-04-19 — Eye tracking: global NSEvent monitor
Eye tracking uses `NSEvent.addGlobalMonitorForEvents(.mouseMoved)` in PetWindow, not a local monitor. Local monitors only fire when the app is frontmost; the global monitor fires regardless of focus, which is required since the pet is always behind other windows.

## 2026-04-19 — SVG pupil ID convention: lp / rp
Pupil circles in SVGs that support eye tracking carry `id="lp"` (left pupil) and `id="rp"` (right pupil). States without pupils (error, sleeping) intentionally omit these IDs — `updateEyes(dx:dy:)` becomes a no-op naturally. New states that should support eye tracking must include both IDs.

## 2026-04-19 — Hook event name: SessionEnd, not SessionStop
Claude Code's valid hook event for session termination is `SessionEnd`. `SessionStop` is silently ignored by the harness. `PetState.from(_:)` must map `"SessionEnd"` → `.sleeping`.

## 2026-04-19 — opencode plugin: copy to stable path before registering
`Bundle.module` path changes between builds. The plugin must be copied to `~/.squib/plugins/opencode-plugin/` at launch (same pattern as `clawd-hook.js` → `~/.squib/hooks/`). Register the stable `~/.squib/plugins/` path in `opencode.json`, not the bundle path.

## 2026-04-19 — opencode plugin: thinking-regression gate required
opencode emits `session.status=busy` between every tool call, which would fire a `UserPromptSubmit`-equivalent event and regress the pet from `working` back to `thinking`. The plugin must track `lastState` and suppress `UserPromptSubmit` when `lastState=working`.

## 2026-04-19 — opencode plugin: no bridge/permission for v1
opencode's permission flow requires an in-process Bun bridge (`startBridge()`, `Bun.serve`), fundamentally different from Claude Code's HTTP hook model. Correctly deferred to v1.1.

## 2026-04-19 — pi-mono watcher: 2s polling timer, not kqueue
`DispatchSourceFileSystemObject` (kqueue) was rejected for pi-mono because the sessions root is two-level (`~/.pi/agent/sessions/<encoded-cwd>/<sessionId>.jsonl`) — kqueue fires on direct children only and would require recursive watchers. A 2s `Timer` that scans all subdirs is simpler, handles the two-level layout naturally, and matches the pattern of StateEngine's stale eviction timer.

## 2026-04-21 — pi-mono JSONL schema: nested message wrapper, camelCase types (CORRECTED)
pi-mono JSONL uses `{"type":"message","message":{"role":...,"content":...,"stopReason":...}}` — the payload is nested under a `"message"` key, NOT at the top level. Content block type is `"toolCall"` (camelCase), NOT `"tool_use"`. Stop reasons are `"stop"`, `"toolUse"`, `"aborted"`, NOT `"end_turn"/"tool_use"/"stop_sequence"`. Compaction entries `{"type":"compaction",...}` must be handled explicitly (emit PostCompact). State mapping: new file → idle; `role=user` → thinking; `role=assistant` + content has `toolCall` block → working; `stopReason=error` → error; `stopReason=stop` → attention. The original parser (and its tests) was built against the Anthropic API format — all tests passed but the parser never worked against real pi-mono sessions.

## 2026-04-20 — BubbleWindow: WKWebView with inline HTML, not native controls
Rewrote BubbleWindow from NSTextField/NSButton to WKWebView with inline HTML/CSS/JS (same pattern as PetView). Native controls could not support: dynamic measured height reporting back to Swift, 4 distinct bubble mode layouts (permission, plan review, elicitation, default), suggestion buttons with variable count, or scrollable command blocks. JS measures `card.offsetHeight + 12` and posts via `messageHandlers.squib`; Swift resizes the window and repositions the stack. WKUserContentController retain cycle prevented by calling `removeScriptMessageHandler(forName:)` in `BubbleWindow.close()` override — not in `deinit`.

## 2026-04-20 — PermissionDecision: typed enum over Bool
Replaced `resolvePermission(id:allow:Bool)` with `resolvePermission(id:decision:PermissionDecision)`. The 4 cases (allow, deny, allowWithPermissions, allowWithUpdatedInput) cannot be expressed as a Bool and require different response body shapes that `buildResponseBody(for:)` serialises per case.

## 2026-04-20 — Elicitation detection: tool_name, not isElicitation field
Claude Code never sends `isElicitation: true` in the permission payload. Detect elicitation by checking `toolName == "AskUserQuestion"` in `HookServer.parsePermissionPayload` — exactly as the reference does in `server.js`. Any check of an `isElicitation` field will silently always be false. Also: `JSONSerialization` decodes JSON booleans as `NSNumber`, so boolean fields parsed with `obj["x"] as? Bool` always return nil; use `(obj["x"] as? NSNumber)?.boolValue ?? false` for all boolean fields from hook payloads.

## 2026-04-20 — Sleep sequence: swapInlineSVG for steps 2–4 to avoid WKWebView reload flash
Step 1 (yawn) uses loadSVG (full page load, sets base URL). Steps 2–4 (doze, collapse, sleeping) use swapInlineSVG which calls evaluateJavaScript to replace document.body.innerHTML via a JS template literal. This avoids a blank-frame flash during page reloads. SVGs must not contain backticks (they don't). CSS animations restart cleanly on innerHTML swap, which is the desired behavior for each sequence step.

## 2026-04-20 — Idle variant pool: random timer in PetWindow, 20–45s interval
PetWindow.scheduleIdleVariant() picks a random idle SVG (look 10s, reading 14s, yawn 3.8s) after a 20–45s random delay, plays it for its natural duration, then returns to clawd-idle-follow and schedules the next variant. cancelSequences() clears both sequenceTimer and idleVariantTimer on any state change, so no variant bleeds into a non-idle state.

## 2026-04-20 — Assets: clawd-idle-follow.svg for idle, GIFs for all other states
Idle uses the reference SVG (inline in WKWebView) because it has CSS `breathe` + `eye-blink` animations and `#eyes-js` for cursor tracking. All other 11 states use GIFs — simpler, no DOM needed. Eye tracking targets `#eyes-js` via `style.transform = translate(dx, dy)` (max 3.0 SVG units per theme spec), NOT `lp`/`rp` `cx`/`cy` as in the old hand-drawn SVGs. `PetWindow.currentState` gates the mouse monitor to only call `updateEyes` when `state.supportsEyeTracking`.

## 2026-04-20 — StateEngine: synthetic session keys for subagent and notification states
Subagent state uses `__subagent__` key; notification uses `__notification__<UUID>`. `isSynthetic()` identifies these by prefix/equality and the stale eviction timer skips them — they are managed explicitly (SubagentStart/Stop and setNotification). Real anonymous sessions use `[anon]` key (evictable). Building detection: after updating a session on PreToolUse/PostToolUse, count real (non-synthetic) sessions; if ≥3, upgrade that session to `.building`.

## 2026-04-20 — Mini states: SVGs not GIFs
Reference uses SVGs with `viewBox="-15 -25 45 45"` for all mini states (idle, enter, peek, alert, happy). This tiny viewport zooms in on just the peeking portion of the pet — the enter animation slides in from `translate(25px,0)` which is off the right edge of that viewport. GIFs (302×300) scale to fill the full window, showing the entire body and looking oversized in the 103pt strip. All mini state loads use `loadSVG`, not `loadGIF`.

## 2026-04-20 — Mini slide animation: Timer not NSAnimationContext
`NSAnimationContext`+`animator().setFrame` uses the CoreAnimation layer path which bypasses `constrainFrameRect`. When the window is near a screen edge, CA applies its own resize constraint — the window gets bigger instead of going off-screen. Timer-based `animateSlide(toX:duration:)` calls `setFrameOrigin` which stays in the AppKit path and respects the `constrainFrameRect` override. All mini mode X-slides use this helper.

## 2026-04-20 — Arc direction: + arc in AppKit (not - arc from Electron)
`animateParabola` uses `arc = -4*h*p*(p-1)` which is positive at midpoint. In Electron (Y from top), `y - arc` goes UP the screen. In AppKit (Y from bottom), `y + arc` goes UP. Using `-arc` (copied literally from JS) made the pet dive downward during mini exit. Fixed to `+ arc`.

## 2026-04-20 — Drag: local mouseDown + global mouseDragged/Up
Local monitors only fire for events dispatched to our process. When cursor enters the menu bar area (a separate system process), local drag monitors stop receiving events — the pet freezes. Fix: keep local `leftMouseDown` (consume to block text selection) and add permanent global `leftMouseDragged`/`leftMouseUp` monitors. Global monitors fire for events in OTHER processes, so there is no double-fire when cursor is over our window.

## 2026-04-20 — clampToScreen: loose clamp via visibleFrame ± 25%
Matches reference `computeLooseClamp`. Uses `visibleFrame` (excludes menu bar + dock) with 25% of pet size as margin at each edge. Allows the pet to sit partially in the menu bar area at the top (50pt above visible area for a 200pt pet) and in the dock area at the bottom. Previous `screen.frame` clamp was exactly at the screen edge with no margin.

## 2026-04-20 — StateEngine: onSessionsChange callback for TrayMenu
TrayMenu reads the full `[String: PetState]` snapshot. StateEngine gained an `onSessionsChange: (([String: PetState]) -> Void)?` callback that fires alongside `onStateChange`, consistent with the existing closure pattern throughout the codebase.

## 2026-04-20 — Permission auto-dismiss: PostToolUse, not connection close
When Claude Code resolves a permission in its own UI, it does NOT close the held HTTP connection — it resolves internally and proceeds. The `.cancelled` eviction path in `HookServer.stateUpdateHandler` never fires. Fix: `AppDelegate` tracks `pendingPermissionsBySession: [String: UUID]`; when a `PostToolUse` event arrives for a session that has a pending permission, it auto-dismisses (removes bubble, clears notification state, closes connection). Map populated on `onPermissionRequest`, cleared on `onPermissionEvicted` and auto-dismiss.

## 2026-04-22 — Permission suggestions key: `permission_suggestions`, not `suggestions`
Claude Code sends permission suggestions under the key `"permission_suggestions"` in the PermissionRequest payload. `HookParser.parsePermissionPayload` must read `obj["permission_suggestions"]` — reading `obj["suggestions"]` silently returns nil and suggestion buttons ("Allow all", "Always allow X", "Allow Bash in dir/") never appear.

## 2026-04-22 — HookEventName: compile-time constants for all hook event name strings
Added `HookEventName` enum to `HookEvent.swift` (SquibCore) with `static let` constants for all 16 event names. `hookedEvents` in `HookInstaller` references these instead of raw strings. Motivation: a typo like `"SessionStop"` (happened once) compiles silently and is never registered. The enum catches it at build time.

## 2026-04-22 — Claude Code hook registration: single atomic settings.json write
`installIfNeeded()` only copies the hook script. `registerClaudeHooks(port:)` does one read → update event hooks + PermissionRequest hook → one write, called from `hookServer.onReady` after the port is known. Previously two independent read/write cycles (one at launch, one in `onReady`) raced against each other and wrote the same file twice every launch.

## 2026-04-22 — PermissionRequest hook: /squib/permission path + filter+replace upsert
URL registered in settings.json is `http://127.0.0.1:{port}/squib/permission` (not `/permission`). The `/squib/` prefix is distinctive enough to identify our entry unambiguously. On each launch, registration filters existing entries by `url.contains("127.0.0.1") && url.hasSuffix("/squib/permission")` and removes them (stale port), then appends the new one. Other tools' PermissionRequest entries are preserved. HookServer routes `POST /squib/permission`.

## 2026-04-22 — PiWatcher: seed pre-existing files on startup, never replay history
`start()` calls `seedExistingFiles()` before scheduling the poll timer. This fast-forwards all existing JSONL files to their current byte size — no events are emitted for content that existed before squib launched. Regular polls then handle: (a) new bytes in known files → parse and emit; (b) files first seen after startup (lastOffset == nil) → emit SessionStart + process from byte 0. Without this, squib replayed entire pi-mono session histories on every launch, which reliably caused error state on startup if any historical session had ended with PostToolUseFailure.

## 2026-04-22 — Allow Session: session-scoped trust, no new PermissionDecision case
`A` key triggers "Allow Session" — future permission requests from the same session ID are approved silently without a bubble. Implemented as `trustedSessions: Set<String>` in AppDelegate, not a new `PermissionDecision` case. The bubble resolves with `.allow` (same wire format as a plain allow); the session trust is purely local state. Trust is cleared on `SessionEnd`. The "Allow Session" button is only shown in regular permission mode when `suggestions.length > 0` — in elicitation and plan-review modes the shortcut falls back to plain allow.

## 2026-04-20 — SquibCore module: all public-facing declarations need explicit `public`
Moving types from the `squib` target to `SquibCore` requires `public` on every class/struct/enum/init/property/method that crosses the module boundary. Swift internals do not cross module boundaries — omitting `public` compiles within the module but produces "cannot find type" errors in the importing target. This applies to `HookEvent`, `HookServer`, `PermissionDecision`, `PermissionRequest`, `PetState`, `PiWatcher`, `StateEngine`, and any new SquibCore types.

## 2026-04-22 — SMAppService login item (Session 20)
- Used `SMAppService.mainApp` (macOS 13+) — no helper app needed; registers the running app itself.
- Requires app to be a proper .app bundle with CFBundleIdentifier. Running bare from swift run will not persist the login item correctly.
- `SMAppService.mainApp.status` is the source of truth; menu checkmark refreshed on every `menuWillOpen`.

## 2026-04-22 — dist/ staging dir must not linger after make install (Session 20)
`make app` creates `dist/squib.app` inside the project folder. Spotlight indexes it alongside `~/Applications/squib.app`, showing two squib entries in the app launcher. After `make install`, delete `dist/` (`make clean`) — it is a build artefact, not a distribution target. Never leave `dist/squib.app` on disk alongside the installed copy.

## 2026-04-23 — Bubble keyboard shortcuts: addGlobalMonitorForEvents + Accessibility required
`addLocalMonitorForEvents` cannot be used for bubble keyboard shortcuts — when Claude Code is frontmost (which it always is when a permission bubble appears), key events go to Claude Code's process, not Squib. `addGlobalMonitorForEvents` is the correct API but requires macOS Accessibility permission (`AXIsProcessTrustedWithOptions`). The app must request this at launch; without it the monitor installs silently and never fires. Additionally, every binary replacement (e.g. `make install`) invalidates the existing Accessibility grant — the user must re-grant in System Settings after each reinstall because macOS ties the grant to the binary hash.

## 2026-04-23 — Bubble shortcut layout: ⌘⇧A on first suggestion, ⌘⇧S on Allow Session
`⌘⇧A` triggers the first "Always allow..." suggestion button in `BubbleCardView` (the button that previously had no shortcut). `⌘⇧S` remains on the "Allow Session" button. These are distinct: suggestion buttons create permanent Claude Code rules; Allow Session creates session-scoped trust in squib only. User explicitly corrected an attempt to put `⌘⇧A` on Allow Session.

## 2026-04-25 — Trusted session: elicitations must never be auto-approved (Session 23)
`AppDelegate.hookServer.onPermissionRequest` skips the bubble and calls `resolvePermission(.allow)` immediately when a session is trusted. This guard must check `!request.isElicitation` — elicitation requests present the user with multi-choice questions that require an explicit answer; silently allowing them sends an empty/wrong answer back to Claude Code. Regular yes/no permission requests are the only kind that should be auto-approved for trusted sessions. Plan-review (`ExitPlanMode`) requests are also binary (Approve / Go to Terminal) and are intentionally left in the auto-approve path.

## 2026-04-23 — Dual Claude config hook registration (Session 22)
`registerClaudeHooks(port:)` writes hooks to both `~/.claude/settings.json` and `~/.claude-personal/settings.json` via a `writeHooks` helper. The helper checks that the target directory exists before writing — if `.claude-personal` is not installed on a machine it silently skips rather than creating a dangling file. This means any user with a personal Claude config gets squib hooks automatically without requiring the `.claude-personal` directory to exist everywhere.

## 2026-04-22 — Menubar icon: makeMenubarIcon() must always return non-nil (Session 20)
If both SVG bundle loading and `cat.fill` SF Symbol lookup fail (e.g. wrong iOS-only symbol name on macOS), `statusItem.button?.image` stays nil — the statusItem is invisible with no title fallback. `makeMenubarIcon()` must have a guaranteed `NSBezierPath` programmatic fallback that draws the silhouette directly, so the menubar item always appears regardless of asset availability.
