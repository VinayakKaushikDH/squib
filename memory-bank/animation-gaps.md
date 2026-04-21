# Animation State Gaps

Findings from Session 12 reference audit (2026-04-21).
Each task includes the exact files/lines to touch and the reference behaviour.

---

## 🔴 Priority 1 — Bugs (wrong behaviour today)

### TASK-1: Fix `sweeping` priority (2 → 6)

**File:** `Sources/SquibCore/PetState.swift`

Reference `STATE_PRIORITY`: `error:8, notification:7, sweeping:6, attention:5, carrying:4, juggling:4, working:3`

Our priority for `sweeping` is 2, lower than `working` (3). Because `sweeping` is a ONESHOT state
(triggered by `/clear` on `SessionEnd`), it needs to win over active working sessions. Currently
it is silently suppressed whenever any working session exists.

**Fix:** Change `case .sweeping: return 2` → `return 6` in `PetState.priority`.

---

### TASK-2: Fix `carrying` priority (2 → 4)

**File:** `Sources/SquibCore/PetState.swift`

Reference: `carrying: 4` (equal to juggling). Ours: `carrying: 2`. `WorktreeCreate` events while
a session is `working` (3) will never surface the carrying animation.

**Fix:** Change `case .carrying: return 2` → `return 4`.

---

## 🔴 Priority 2 — Missing Feature: Wake Sequence

### TASK-3: Add `clawd-wake.svg` to bundle

**File:** `Sources/squib/Resources/`

Copy `clawd-wake.svg` from `/Users/vinayak.kaushik/Developer/clawd-on-desk-ref/assets/svg/clawd-wake.svg`
into our Resources folder. Also add it to the SPM resource rule if needed (currently all `.svg`
files in Resources/ are included automatically via `.process("Resources")`).

---

### TASK-4: Implement wake poll + waking state

**Files:** `Sources/squib/PetWindow.swift`, `Sources/SquibCore/PetState.swift`

Reference behaviour (`src/state.js` `startWakePoll` + `wakeFromDoze`):
- After entering `dozing`, `collapsing`, or `sleeping`, start polling cursor position every 200ms
- If cursor moves: play `clawd-wake.svg` (full page load, not swap), then after `WAKE_DURATION`
  (reference default ~1400ms) resolve back to normal display state
- If cursor is still and we're in `dozing` and mouse-idle duration ≥ `DEEP_SLEEP_TIMEOUT`
  (reference default 60s), advance to `collapsing` → then `sleeping`

Currently our sleep sequence is purely timer-driven (yawn→doze→collapse→sleep on fixed timers).
Cursor movement has zero effect.

**Implementation sketch for PetWindow.swift:**
1. Add `private var wakePollTimer: Timer?` and `private var sleepEntryDate: Date?`
2. In `playSleepSequence()`, after showing doze SVG, start a 200ms repeating timer that checks
   `NSEvent.mouseLocation` against a stored position
3. On cursor move: invalidate poll, call `playWakeSequence()`
4. `playWakeSequence()`: `petView.loadSVG(name: "clawd-wake")`, then after ~1.4s call
   `loadState(currentState)` (which re-resolves to idle or whatever state is active)
5. Deep sleep advance: if mouse hasn't moved for 60s while in doze, skip to collapse

No new `PetState` case needed — `waking` is a transient visual-only sequence like the existing
sleep sequence steps.

---

## 🟡 Priority 3 — Mini Mode Gaps

### TASK-5: Add `clawd-mini-sleep.svg` and `clawd-mini-enter-sleep.svg` to bundle

**Source:**
- `/Users/vinayak.kaushik/Developer/clawd-on-desk-ref/assets/svg/clawd-mini-sleep.svg`
- `/Users/vinayak.kaushik/Developer/clawd-on-desk-ref/assets/svg/clawd-mini-enter-sleep.svg`

Copy both into `Sources/squib/Resources/`.

---

### TASK-6: Wire DND-aware mini state (mini-sleep / mini-enter-sleep)

**File:** `Sources/squib/PetWindow.swift`

Reference (`src/mini.js` line 260):
```js
const enterSvgState = ctx.doNotDisturb ? "mini-enter-sleep" : "mini-enter";
```
And `getMiniRestState()` returns `"mini-sleep"` when DND is on, `"mini-idle"` otherwise.

Three places to fix in PetWindow.swift:
1. `enterMiniMode()` — always plays `clawd-mini-enter`; should check DND and play
   `clawd-mini-enter-sleep` instead, then settle to `clawd-mini-sleep`
2. `showMiniState(gif:duration:)` — always restores to `clawd-mini-idle` after the alert/happy
   animation; should restore to `clawd-mini-sleep` when DND is active
3. `miniPeekOut()` — always restores to `clawd-mini-idle`; same fix

We don't have a DND flag yet. Add `var doNotDisturb: Bool = false` to PetWindow (or AppDelegate
can call a setter), then thread it through these three sites.

---

### TASK-7: Wire `mini-working` in mini mode

**File:** `Sources/squib/PetWindow.swift`

Reference (`src/state.js` `applyState` mini-mode block):
```js
if (state === "working" || state === "thinking" || state === "juggling") {
  if (hasOwnVisualFiles("mini-working")) return applyState("mini-working");
  return;
}
```

We need `clawd-mini-typing.svg` — copy from:
`/Users/vinayak.kaushik/Developer/clawd-on-desk-ref/assets/svg/clawd-mini-typing.svg`

In `PetWindow.loadState()` mini-mode switch, add:
```swift
case .working, .thinking, .juggling, .building, .conducting:
    showMiniState(gif: "clawd-mini-typing", duration: 4.0)
```

---

## 🟡 Priority 4 — Idle Variant Pool

### TASK-8: Add `clawd-idle-living.svg` to idle variant pool

**Source:** `/Users/vinayak.kaushik/Developer/clawd-on-desk-ref/assets/svg/clawd-idle-living.svg`

Copy into `Sources/squib/Resources/`.

**File:** `Sources/squib/PetWindow.swift` — `idleVariants` array:
```swift
private let idleVariants: [(name: String, duration: Double)] = [
    ("clawd-idle-look",    10.0),
    ("clawd-idle-reading", 14.0),
    ("clawd-idle-yawn",     3.8),
    // ADD:
    ("clawd-idle-living",  ???),   // measure duration from SVG animations
]
```
Duration: inspect the SVG's CSS animation durations to determine the cycle length.

---

### TASK-9: Add `clawd-working-debugger.svg` to idle variant pool

**Source:** `/Users/vinayak.kaushik/Developer/clawd-on-desk-ref/assets/svg/clawd-working-debugger.svg`

Reference: the debugger SVG is used as a ~14s idle variant (same as `clawd-idle-reading`).
Also used in the reference's app-update "checking" visual — not relevant to us right now.

Copy into `Sources/squib/Resources/`.

Add to `idleVariants` in `PetWindow.swift`:
```swift
("clawd-working-debugger", 14.0),
```

---

## 🟡 Priority 5 — Dozing Eye Tracking

### TASK-10: Enable eye tracking during `dozing`

**File:** `Sources/squib/PetWindow.swift` + `Sources/squib/PetView.swift`

Reference renderer.js line 22:
```js
_eyeTrackingStates = ["idle", "dozing", "mini-idle"]
```

Currently `supportsEyeTracking` on `PetState` only returns true for `.idle`. But `dozing` is not
a `PetState` case — it's a transient SVG loaded inline via `swapInlineSVG`.

The fix: add a `private var isShowingDoze: Bool` flag to `PetWindow`. Set it true when the doze
swap fires, false when transitioning out. In `mouseMoved` / `updateEyeTracking`, add:
```swift
} else if isShowingDoze {
    updateEyeTracking(cursor: cursor)
}
```
Eye targets (`#eyes-js`, `#body-js`, `#shadow-js`) must be present in `clawd-idle-doze.svg`
— verify against the SVG source before implementing.

---

## 🟠 Priority 6 — Click Reactions (future)

### TASK-11: Bundle reaction SVGs

**Source SVGs** (all in `/Users/vinayak.kaushik/Developer/clawd-on-desk-ref/assets/svg/`):
- `clawd-react-left.svg` — left-click reaction, ~2500ms
- `clawd-react-right.svg` — right-click reaction, ~2500ms
- `clawd-react-annoyed.svg` — repeated click reaction, ~3500ms
- `clawd-react-double.svg` — double-click reaction, ~3500ms
- `clawd-react-double-jump.svg` — double-click jump variant, ~3500ms

We already have `clawd-react-drag.svg` wired. Copy the above into Resources.

Wiring (in `PetWindow.startMouseMonitors`):
- Single left-click on pet body → `petView.loadSVG(name: "clawd-react-left")`, restore after 2500ms
- Right-click → `clawd-react-right`, restore after 2500ms
- Rapid successive clicks → escalate to `clawd-react-annoyed` (3500ms)
- Double-click → `clawd-react-double` or `clawd-react-double-jump` (3500ms)
- All reactions: check `isDragging` and skip if dragging; restore via `loadState(currentState)`

---

## 🧹 Cleanup

### TASK-12: Remove stale hand-drawn SVGs

**Files to delete from `Sources/squib/Resources/`:**
- `attention.svg`
- `error.svg`
- `idle.svg`
- `sleeping.svg`
- `thinking.svg`
- `working.svg`

These are the original hand-drawn prototypes, replaced by the clawd assets in Session 6.
They are never referenced by `PetState.assetName` and just bloat the bundle.
