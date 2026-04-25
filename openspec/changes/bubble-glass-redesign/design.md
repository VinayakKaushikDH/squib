## Context

The bubble permission card was rewritten to native SwiftUI + `NSGlassEffectView` in Session 19. The `Squib Glass Reference.html` handoff (frozen design, ISS. 004) has since been delivered and defines exact visual tokens, button semantics, and UX copy. Several values in the current `BubbleCardView.swift` diverge from this reference.

The Chat window shown in Section 04 of the reference is explicitly marked **FUTURE SHIP** and is out of scope here.

## Goals / Non-Goals

**Goals:**
- Align all visual tokens (pill colors, radii, suggestion font) with the frozen design reference
- Update plan review secondary button to "Edit Plan [⌘⇧E]"
- Update elicitation secondary button label to "Skip"
- Widen elicitation cards to 380pt
- Upgrade entry animation to spring-with-overshoot

**Non-Goals:**
- Revert to WKWebView / HTML rendering (native SwiftUI is correct technology choice)
- Implement the Chat window (Section 04 of reference — "FUTURE SHIP")
- Add new bubble modes or new Swift bridge APIs
- Touch `BubbleManager` stacking logic or `AppDelegate` permission flow

## Decisions

**Stay with SwiftUI, not WKWebView**
The reference checklist says "lift the CSS into `bubbleHTML`" but also says to use whatever technology makes sense. `NSGlassEffectView` + SwiftUI is unambiguously superior on macOS 26: native material compositing, no WKWebView retain-cycle workarounds, no JS bridge height-reporting hack. The visual output is identical.

**"Edit Plan" fires `.deny` (same wire as "Go to Terminal")**
`deny` tells Claude Code "don't proceed with the plan" — the user goes back to the terminal/editor. "Edit Plan" has the same semantics; only the label and shortcut change. No new `PermissionDecision` case is needed.

**⌘⇧E is plan-review only; ⌘⇧N stays on permission + elicitation**
The keybinding table in Section 06 of the reference specifies ⌘⇧E for "Edit Plan" scoped to plan review. ⌘⇧N stays for Deny (permission) and Skip (elicitation). The global key monitor in `BubbleManager` must check the topmost bubble's mode before dispatching.

**No `BubbleManager` width tracking required**
`BubbleWindow.width` is currently a static 340. For elicitation, `BubbleWindow` must use 380. The cleanest fix is to make `init(request:)` set `width` based on `request.isElicitation`, removing the need for `BubbleManager` to know about widths.

## Risks / Trade-offs

- [Visual regression on stacked bubbles] Changing card width for elicitation shifts the horizontal position of the stack. `BubbleManager.add()` already computes X from `BubbleWindow.width` — it will use the instance width automatically once `BubbleWindow.init` sets it per-mode. Low risk.
- [Corner radius visual change] Action buttons grow from 7pt → 14pt radius. May look rounder than expected. Accept — matches design spec.
- [⌘⇧E only fires in plan mode] If a non-plan bubble is topmost, ⌘⇧E does nothing. This is correct per the spec and prevents accidental deny.

## Open Questions

None — all decisions resolved against the frozen design reference.
