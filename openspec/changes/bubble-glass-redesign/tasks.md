## 1. BubbleViewModel — new key action

- [x] 1.1 Add `editPlan` case to the `BubbleKeyAction` enum in `BubbleViewModel.swift`
- [x] 1.2 Add `triggerEditPlan()` method that sets `pendingKeyAction = .editPlan`

## 2. BubbleWindow — per-mode width + Edit Plan handler

- [x] 2.1 Change `BubbleWindow.init(request:)` to set `width = request.isElicitation ? 380 : 340` (replace the `static let width = 340` where it sets the initial frame)
- [x] 2.2 Add `editPlanViaKey()` method that calls `viewModel.triggerEditPlan()`

## 3. BubbleCardView — visual tokens

- [x] 3.1 Update `pillColor(for:)` with the correct hex values: Edit `#5b7fb8`, Read `#6a9b7c`, Write `#c79556`, Glob `#8e78b6`, Grep `#b87c8e`, Agent `#6aa3b0`
- [x] 3.2 Add Plan and Ask pill cases in `ToolPill` — neutral glass style: `rgba(255,255,255,0.12)` tint, `rgba(255,255,255,0.20)` border, white text; map from `pillColor` or branch in `ToolPill` body
- [x] 3.3 Update `ToolPill` to show "Plan" for `ExitPlanMode` and "Ask" for `AskUserQuestion` tool names
- [x] 3.4 Update `BubbleActionButtonStyle.cornerRadius` from 7 → 14pt
- [x] 3.5 Update `CommandBlock` background `RoundedRectangle` cornerRadius from 8 → 10pt
- [x] 3.6 Update `BubbleSuggestionButton` font from `.system(size: 11.5, weight: .medium)` → `.system(size: 12, design: .monospaced)`

## 4. BubbleCardView — UX copy + key action wiring

- [x] 4.1 In `planReviewContent`, change secondary button from `BubbleActionButton("Go to Terminal", hint: "⌘⇧N", role: .deny)` → `BubbleActionButton("Edit Plan", hint: "⌘⇧E", role: .deny)`
- [x] 4.2 In `elicitationContent`, change secondary button label from `"Go to Terminal"` → `"Skip"` (hint stays `"⌘⇧N"`)
- [x] 4.3 In the `.onChange(of: model.pendingKeyAction)` handler, add `case .editPlan: handleDeny()` (same wire behavior as deny)

## 5. BubbleCardView — entry animation spring overshoot

- [x] 5.1 Replace the current `.offset(x: appeared ? 0 : 40).opacity(...)` + `.animation(.easeOut(duration: 0.28))` with a spring animation: start at `offset(x: 30) + scaleEffect(0.96) + opacity(0)`, settle to identity using `.spring(response: 0.5, dampingFraction: 0.7)` or a custom `timingCurve(0.2, 0.9, 0.2, 1.05)` to produce the overshoot

## 6. BubbleManager — ⌘⇧E monitor + ⌘⇧N plan guard

- [x] 6.1 In `BubbleManager.handleKey(_:)`, add a case for `"e"` with `⌘⇧` modifiers: call `editPlanViaKey()` on the topmost `BubbleWindow` only if `window.request.toolName == "ExitPlanMode"`
- [x] 6.2 Guard the `"n"` key handler: skip `denyViaKey()` when the topmost window's `request.toolName == "ExitPlanMode"`

## 7. Build and verify

- [x] 7.1 `swift build` — zero warnings, zero errors
- [ ] 7.2 `swift run squibTestRunner` — all existing tests pass (no test changes needed)
- [ ] 7.3 Visual smoke test: launch squib, trigger a Bash permission — confirm orange pill, 14pt buttons, mono suggestion font
- [ ] 7.4 Visual smoke test: trigger a Write permission — confirm amber/gold pill (not purple)
- [ ] 7.5 Visual smoke test: trigger a plan review — confirm "Plan" pill, "Edit Plan [⌘⇧E]" secondary, ⌘⇧E fires deny
- [ ] 7.6 Visual smoke test: trigger an elicitation (AskUserQuestion) — confirm "Ask" pill, 380pt width, "Skip [⌘⇧N]" secondary
