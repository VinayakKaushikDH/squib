## ADDED Requirements

### Requirement: Pill colors match design tokens
Tool pill backgrounds SHALL use the following hex values from the frozen design reference:
- Bash: `#d8724e`
- Edit: `#5b7fb8`
- Read: `#6a9b7c`
- Write: `#c79556`
- Glob: `#8e78b6`
- Grep: `#b87c8e`
- Agent: `#6aa3b0`
- Plan / Ask (ExitPlanMode / AskUserQuestion): neutral glass — `rgba(255,255,255,0.12)` background with a `rgba(255,255,255,0.20)` border, white text

#### Scenario: Bash permission bubble shows warm orange pill
- **WHEN** a Bash permission request is displayed
- **THEN** the tool pill background SHALL be `#d8724e`

#### Scenario: Write permission bubble shows amber pill
- **WHEN** a Write permission request is displayed
- **THEN** the tool pill background SHALL be `#c79556` (amber/gold), NOT purple

#### Scenario: Plan review shows neutral glass pill labeled "Plan"
- **WHEN** a plan review card is displayed (toolName == ExitPlanMode)
- **THEN** the pill SHALL read "Plan" with a neutral glass background (no solid color)

#### Scenario: Elicitation shows neutral glass pill labeled "Ask"
- **WHEN** an elicitation card is displayed (isElicitation == true)
- **THEN** the pill SHALL read "Ask" with a neutral glass background (no solid color)

---

### Requirement: Action button corner radius is 14pt
The Allow / Deny / Approve / Submit action buttons SHALL use a corner radius of 14pt.

#### Scenario: Allow button has correct radius
- **WHEN** the permission bubble is rendered
- **THEN** the Allow and Deny buttons SHALL each have a corner radius of 14pt

---

### Requirement: Inner block corner radius is 10pt
The command preview block and elicitation form background SHALL use a corner radius of 10pt.

#### Scenario: Command block uses 10pt radius
- **WHEN** a permission card with a command detail is rendered
- **THEN** the command preview block background SHALL have a corner radius of 10pt

---

### Requirement: Suggestion buttons use monospaced font at 12pt
The suggestion row buttons (Allow Session, Always allow…) SHALL use a monospaced system font at 12pt, not the UI sans-serif font.

#### Scenario: Suggestion button text is monospaced
- **WHEN** suggestion buttons are visible on a permission card
- **THEN** the button label text SHALL render in `SF Mono` / monospaced system font at size 12pt

---

### Requirement: Elicitation card width is 380pt
When displaying an elicitation card, the `BubbleWindow` width SHALL be 380pt instead of the default 340pt.

#### Scenario: Elicitation window is wider
- **WHEN** `BubbleWindow` is initialized with a request where `isElicitation == true`
- **THEN** the window width SHALL be 380pt

#### Scenario: Non-elicitation windows remain 340pt
- **WHEN** `BubbleWindow` is initialized with a permission or plan review request
- **THEN** the window width SHALL be 340pt

---

### Requirement: Entry animation uses spring overshoot
The card entry animation SHALL slide in from the right with a spring overshoot: starts at `translateX(30pt) scale(0.96) opacity(0)`, overshoots to `translateX(-3pt) scale(1.005)` at ~70% progress, then settles to identity. Duration approximately 0.5s.

#### Scenario: Card appears with overshoot spring
- **WHEN** a bubble card first becomes visible
- **THEN** it SHALL animate from right with a scale-and-translate spring that briefly overshoots past zero before settling
