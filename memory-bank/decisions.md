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

## 2026-04-19 — pi-mono JSONL schema: tool use embedded in message content
pi-mono JSONL (schema version 3) uses `type=message` entries with `role=user|assistant`. Tool use is NOT a discrete line — it is embedded inside `message.content` as `{ "type": "tool_use", ... }` blocks (Anthropic API format). State mapping: new file → idle; `role=user` → thinking; `role=assistant` + `content` has `tool_use` block → working; `stop_reason=error` → error; `stop_reason=end_turn` → attention.

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

## 2026-04-20 — StateEngine: onSessionsChange callback for TrayMenu
TrayMenu reads the full `[String: PetState]` snapshot. StateEngine gained an `onSessionsChange: (([String: PetState]) -> Void)?` callback that fires alongside `onStateChange`, consistent with the existing closure pattern throughout the codebase.
