## Why

The `Squib Glass Reference.html` design handoff finalizes the frosted-glass visual language for the permission bubble. The current SwiftUI implementation (Session 19) was built against an earlier draft: pill colors are wrong, button radii are too small, suggestion button typography is sans-serif instead of mono, and the plan-review UX diverges from the approved design (wrong secondary label and shortcut).

## What Changes

- **Pill colors**: Write, Read, Edit, Glob, Grep, Agent all use wrong hex values; plan/ask have no neutral variant yet
- **Button radii**: Action buttons should be 14px (currently 7); inner blocks should be 10px (currently 8)
- **Suggestion buttons**: Must use monospaced font at 12px (currently sans-serif 11.5px)
- **Plan review UX**: Secondary button changes from "Go to Terminal [⌘⇧N]" → "Edit Plan [⌘⇧E]"
- **Elicitation UX**: Secondary button label changes from "Go to Terminal" → "Skip"
- **Entry animation**: Upgrade from simple offset/opacity to spring-with-overshoot (`translateX(30px) scale(0.96)` → overshoot at 70% → settle)
- **Elicitation card width**: Widen from 340px to 380px to match `.sq-card.wide` spec
- **⌘⇧E shortcut**: New global key monitor entry for "Edit Plan" in plan review mode

## Capabilities

### New Capabilities

- `bubble-glass-visual`: Visual token corrections — pill colors, button radii, suggestion font, entry animation, elicitation card width
- `bubble-plan-edit`: "Edit Plan" UX in plan review — label change, ⌘⇧E shortcut, ⌘⇧N removal from plan mode

### Modified Capabilities

<!-- None — no existing specs -->

## Impact

| File | Change |
|------|--------|
| `Sources/squib/BubbleCardView.swift` | Pill colors, button radii, suggestion font, labels (Skip / Edit Plan), entry animation |
| `Sources/squib/BubbleViewModel.swift` | Add `editPlan` case to `BubbleKeyAction`; `triggerEditPlan()` method |
| `Sources/squib/BubbleWindow.swift` | Add `editPlanViaKey()` handler; elicitation width 380px |
| `Sources/squib/BubbleManager.swift` | ⌘⇧E global key monitor entry; pass elicitation width when creating BubbleWindow |
