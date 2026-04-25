## ADDED Requirements

### Requirement: Plan review secondary button reads "Edit Plan"
In plan review mode, the secondary (left) action button SHALL read "Edit Plan" with the keybinding hint `[⌘⇧E]`. It SHALL NOT read "Go to Terminal". The button fires the `.deny` decision (same wire behavior — returns control to the terminal).

#### Scenario: Plan review shows "Edit Plan" secondary button
- **WHEN** a plan review card is displayed (toolName == ExitPlanMode)
- **THEN** the secondary button label SHALL be "Edit Plan"
- **AND** the keybinding hint SHALL display "[⌘⇧E]"

#### Scenario: Edit Plan fires deny decision
- **WHEN** the user taps or keyboard-triggers "Edit Plan"
- **THEN** the system SHALL resolve the permission with `.deny`

---

### Requirement: ⌘⇧E global shortcut triggers Edit Plan on the topmost plan review bubble
The global key monitor in `BubbleManager` SHALL fire `editPlanViaKey()` on the topmost `BubbleWindow` when ⌘⇧E is pressed, but ONLY if that window's request is a plan review card (toolName == ExitPlanMode).

#### Scenario: ⌘⇧E on plan review bubble triggers deny
- **WHEN** a plan review bubble is topmost and the user presses ⌘⇧E
- **THEN** the bubble SHALL resolve with `.deny` (Edit Plan)

#### Scenario: ⌘⇧E does nothing when topmost bubble is not plan review
- **WHEN** a regular permission bubble is topmost and the user presses ⌘⇧E
- **THEN** no action SHALL be taken

---

### Requirement: ⌘⇧N does not trigger secondary action on plan review bubbles
In plan review mode, ⌘⇧N SHALL have no effect. The ⌘⇧N shortcut is scoped to permission (Deny) and elicitation (Skip) modes only.

#### Scenario: ⌘⇧N ignored on plan review
- **WHEN** a plan review bubble is topmost and the user presses ⌘⇧N
- **THEN** no action SHALL be taken on the plan review bubble

---

### Requirement: Elicitation secondary button reads "Skip"
In elicitation mode, the secondary (left) action button label SHALL be "Skip" with keybinding hint `[⌘⇧N]`. It SHALL NOT read "Go to Terminal".

#### Scenario: Elicitation shows "Skip" secondary button
- **WHEN** an elicitation card is displayed
- **THEN** the secondary button label SHALL be "Skip"
- **AND** the keybinding hint SHALL display "[⌘⇧N]"
