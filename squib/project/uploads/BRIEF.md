# squib — Design Handoff Brief

## What is squib

squib is a **macOS desktop companion app** that watches AI coding agents (Claude Code, opencode, pi-mono) and reacts to what they're doing in real-time. A small creature sits on the user's desktop, always visible on top of other windows, and animates through different states as the agent thinks, works, sleeps, errors, etc. When Claude Code needs permission to run a tool, a card bubble pops up for the user to approve or deny.

The app is built in Swift/AppKit. The pet is rendered in a transparent, always-on-top, click-through window — it floats over everything, always visible regardless of what app is in focus.

---

## What you are designing

Two things:

1. **A new pet character** — a redesign of clawd the crab (from the reference project) in a new aesthetic. Same species, new soul.
2. **A permission bubble UI** — the card that appears when the agent needs tool approval.

Both share the same aesthetic language. The bubble is more strictly "zine UI." The pet expresses that aesthetic through its art style, not its layout.

---

## Aesthetic Direction: Coder Zine-line

Think: a developer's field notebook, a photocopied zine, an ink stamp, a typewriter printout. Not pixel art, not flat/corporate, not overly cute.

**Key qualities:**
- **Ink on paper** — linework feels hand-drawn, slightly imperfect, expressive weight variation
- **Minimal palette** — off-white/cream paper, dark ink, one warm accent (think a red stamp, a yellow highlighter mark, a faded blue ink)
- **Paper texture feel** — not literal texture but the *sense* of it: matte, flat, no shiny gradients
- **Readable at a glance** — this sits on a desktop permanently; it can't be visually noisy
- **Character > polish** — a slightly wobbly line has more personality than a perfect bezier

**What it is NOT:**
- Not glossy / skeuomorphic
- Not Notion/Linear flat minimalism (too sterile)
- Not pixel art
- Not anime/chibi-cute
- Not brutalist or purely typographic

**Reference aesthetic moods:** Merveilles collective art, BUJO hacker notebooks, early 2000s indie game sprites, linocut illustration, risograph printing.

---

## 1. The Pet Character

### Base: clawd the crab

The reference project (`/Users/vinayak.kaushik/Developer/clawd-on-desk-ref`) ships a character called **clawd** — an expressive animated crab. It has a full animation set at high quality. You are redesigning clawd in the squib zine aesthetic: same species, same expressiveness, new visual language.

Study these reference GIFs before designing:

```
/Users/vinayak.kaushik/Developer/clawd-on-desk-ref/assets/gif/clawd-idle.gif
/Users/vinayak.kaushik/Developer/clawd-on-desk-ref/assets/gif/clawd-idle-reading.gif
/Users/vinayak.kaushik/Developer/clawd-on-desk-ref/assets/gif/clawd-thinking.gif
/Users/vinayak.kaushik/Developer/clawd-on-desk-ref/assets/gif/clawd-typing.gif
/Users/vinayak.kaushik/Developer/clawd-on-desk-ref/assets/gif/clawd-sleeping.gif
/Users/vinayak.kaushik/Developer/clawd-on-desk-ref/assets/gif/clawd-error.gif
/Users/vinayak.kaushik/Developer/clawd-on-desk-ref/assets/gif/clawd-happy.gif
/Users/vinayak.kaushik/Developer/clawd-on-desk-ref/assets/gif/clawd-notification.gif
/Users/vinayak.kaushik/Developer/clawd-on-desk-ref/assets/gif/clawd-sweeping.gif
/Users/vinayak.kaushik/Developer/clawd-on-desk-ref/assets/gif/clawd-debugger.gif
/Users/vinayak.kaushik/Developer/clawd-on-desk-ref/assets/gif/clawd-mini-idle.gif
/Users/vinayak.kaushik/Developer/clawd-on-desk-ref/assets/gif/clawd-mini-peek.gif
/Users/vinayak.kaushik/Developer/clawd-on-desk-ref/assets/gif/clawd-mini-alert.gif
/Users/vinayak.kaushik/Developer/clawd-on-desk-ref/assets/gif/clawd-mini-crabwalk.gif
```

### Required animation states (v1 — ship blockers)

These 6 states must be delivered:

| State | Trigger | Behavior |
|-------|---------|----------|
| `idle` | Agent not running / between tasks | Relaxed, subtle ambient motion. Breathing, occasional blink, claw tap. |
| `thinking` | Agent received prompt, formulating | Thoughtful pose — maybe a claw to chin, eyes up, thought bubble optional. |
| `working` | Agent actively using tools (bash, file edits) | Busy, animated — typing motion, claws moving, focused expression. |
| `sleeping` | Session ended / no activity | Slumped, eyes closed, ZZZ. Still, slow breathing if anything. |
| `error` | Agent hit an error | Distressed expression — wide eyes, claws up, maybe sweat drop or X eyes. |
| `attention` | Agent needs input / permission requested | Alert, looking at viewer, excited/urgent expression. Exclamation. |

### Mini mode states (v1 — ship with core states)

Mini mode is a future collapsed view where the pet peeks from the edge of the screen. Design these as **small, edge-aware poses** — the character is partially off-screen, only the top half or a claw visible.

| State | Notes |
|-------|-------|
| `mini-idle` | Peeking neutrally from edge |
| `mini-alert` | Eyes wide, alert peek |
| `mini-peek` | Curious lean-in |

### Technical format: APNG

- **Format: APNG** (Animated PNG) — not GIF. APNG supports full alpha channel; GIF has binary transparency which creates jagged edges on transparent backgrounds. WKWebView renders APNG natively.
- **Background: fully transparent** — the pet floats over whatever wallpaper/windows are behind it. No background color, no shadow baked into the asset.
- **Canvas size:** Match clawd's reference dimensions as a baseline. The rendering window is approximately 200×260pt on a Retina display — deliver @2x assets.
- **Loop behavior:** All states loop continuously except `sleeping` which can slow/stop after settling.
- **Eye tracking note:** The current SVG implementation tracks the cursor and moves pupils via JavaScript DOM manipulation. This will **not** carry over to APNG — accepted tradeoff for animation quality. Design eyes to feel engaged without needing to track.

### Palette guidance

Zine palette for the crab:
- Body/ink: dark warm ink (`#1a1208` or similar near-black)
- Shell/carapace: off-white or warm cream with ink outline — or a muted single color (clay, rust, aged paper)
- Accent: one warm pop — consider a faded rust/terracotta, or a washed-out primary
- Eyes: expressive, high contrast, the clearest thing on the character
- Avoid: saturated gradients, gloss, drop shadows baked in

The current SVG octopus uses a saturated purple (`#6B73FF`) — the new character should feel more restrained, like it was drawn rather than rendered.

---

## 2. Permission Bubble UI

### What it is

When Claude Code requests permission to run a tool (e.g. a bash command, file edit), a card pops up in the lower-right corner of the screen. The user can Allow, Deny, or use smart suggestion buttons.

There are **4 bubble modes:**

**Regular permission** (most common)
- Header: tool name pill (Bash, Edit, Write, Read, Glob, Grep, Agent)
- Session tag: folder name + short session ID
- Command block: scrollable monospace display of what the tool will do
- Buttons: Deny / Allow
- Suggestion buttons below: "Allow X in dir/", "Auto-accept edits", etc.

**Plan review** (ExitPlanMode tool)
- Header: "Plan Review"
- Command block: the plan text
- Buttons: Approve / Go to Terminal

**Elicitation** (agent asking user a question)
- Header: "Needs Input"
- Form: radio/checkbox questions with options
- Buttons: Go to Terminal / Submit Answer

**Default fallback**
- Header + tool name only, Allow/Deny

### Zine UI direction for the bubble

The bubble is the most "designed" surface in the app — it's the primary interaction point. Apply the zine aesthetic more deliberately here.

**Card:**
- Off-white / aged paper background (`#f5f0e8` light, `#1c1a14` dark)
- Inked border — 1px solid, slightly warm dark (`#2a2418` ish), maybe a very subtle imperfection via `border-radius` variation
- Shadow: soft, warm-toned, not cool grey
- Slide-in animation from the right, slight overshoot or settle (physical feel)

**Typography:**
- UI labels (headers, button text): system font or a clean geometric — but tighter tracking, slightly smaller, feels like a label stamp
- Code/command block: monospace, looks like typewriter output — `SF Mono` / `Courier New` fallback
- Tone: terse. "Permission Request" → maybe just the tool name. "Deny" → "Nope". Consider whether copy should feel slightly hacker/zine-toned.

**Tool pills:**
- Currently colored by tool type (Bash = orange, Edit = blue, etc.) — keep the differentiation but desaturate toward ink-stamp colors. Bash could be a worn red stamp, Edit a faded navy, etc.
- Shape: slightly less rounded than current, more "label" feel

**Buttons:**
- Primary (Allow/Approve/Submit): feels like a rubber stamp — solid ink color, no border, small caps or tight tracking
- Secondary (Deny): ghost/outline style — just an inked border, paper fill
- Suggestion buttons: subtle, like margin annotations — left-aligned, lighter weight, small arrow on hover

**Command block:**
- Background: slightly darker paper (`#ede8dc` light) or near-black (`#0e0d0a` dark)
- No rounded corners on inner blocks — sharp or very minimal radius, feels more like a type block
- Scrollbar: thin, matches ink color

**Dark mode:**
- Dark paper (`#1c1a14`), light ink (`#e8e4d8`), same warm-not-cool palette
- Not OLED black — warm charcoal

### Current bubble HTML source

The full current implementation is embedded below for reference. Redesign freely — the HTML/CSS structure can change completely. What must stay is the JavaScript bridge (`window.webkit.messageHandlers.squib.postMessage`) and the `loadPermission(data)` entry point.

```html
<!-- See: Sources/squib/BubbleWindow.swift — static let bubbleHTML -->
<!-- Full source is ~770 lines of inline HTML in BubbleWindow.swift -->
<!-- Key JS contract:
     - loadPermission(data) is called by Swift with the permission payload
     - post({ type: "height", value: N }) reports card height to Swift for window sizing
     - post({ type: "decide", value: "allow" | "deny" | "suggestion:N" }) sends decision
     - post({ type: "decide", value: { type: "elicitation-submit", answers: {...} } }) for forms
-->
```

Key data shape passed to `loadPermission`:
```js
{
  toolName: "Bash",           // tool identifier
  toolInput: { command: "ls" }, // raw tool arguments
  isElicitation: false,       // true = render question form
  sessionFolder: "squib",     // cwd last component
  sessionShortId: "a3f",      // last 3 chars of session ID
  suggestions: [              // smart allow suggestions
    { type: "addRules", toolName: "Bash", ruleContent: "...", behavior: "allow" },
    { type: "setMode", mode: "acceptEdits" }
  ]
}
```

---

## Deliverables

### Pet character
- APNG files for each state: `idle.png`, `thinking.png`, `working.png`, `sleeping.png`, `error.png`, `attention.png`
- Mini states: `mini-idle.png`, `mini-alert.png`, `mini-peek.png`
- All at @2x, transparent background

### Bubble UI
- Updated `bubbleHTML` — the full self-contained HTML/CSS/JS string to replace the current one in `BubbleWindow.swift`
- Must pass the same JS contract described above
- Must support light + dark mode via `prefers-color-scheme`
- Must dynamically report height via the `height` message (existing behavior)

### Optional / nice-to-have
- Character sheet / style reference showing the crab at rest with palette + proportions
- Alternate idle variant (`idle-reading.gif` equivalent — crab with a tiny terminal or book)

---

## Constraints summary

| Constraint | Detail |
|-----------|--------|
| Platform | macOS only, WKWebView renderer |
| Pet format | APNG, transparent bg, @2x |
| Bubble format | Self-contained HTML string (no external resources) |
| Fonts in bubble | System stack only (`-apple-system`, `SF Mono`) — no web font loads |
| Images in bubble | Inline SVG or data URIs only — no `<img src>` to external files |
| JS bridge | `window.webkit.messageHandlers.squib.postMessage` must remain |
| No animation libs | No GSAP, no Lottie, no React — vanilla HTML/CSS/JS only |
| Dark mode | Both pet palette and bubble must work on dark wallpapers / dark mode |

---

## Project files for context

```
/Users/vinayak.kaushik/Developer/squib/
  Sources/squib/
    BubbleWindow.swift       ← full current bubble implementation
    PetView.swift            ← how pet APNG will be loaded (currently SVG)
    PetWindow.swift          ← transparent floating window setup
    Resources/
      idle.svg               ← current pet states (to be replaced)
      thinking.svg
      working.svg
      sleeping.svg
      error.svg
      attention.svg

/Users/vinayak.kaushik/Developer/clawd-on-desk-ref/assets/gif/
  clawd-*.gif                ← primary reference character (study these)
  calico-*.gif               ← secondary reference character
```
