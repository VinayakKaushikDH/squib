# Visual Test Harness — Design Document

**Status:** Agreed, not yet implemented  
**Session:** 2026-04-25

---

## Goal

Give an AI agent (Claude) full visibility into how the permission popup UI looks and works.
The agent should be able to render the UI in any scenario configuration and verify it matches
a written spec.

Scope is **single-bubble headless rendering only**. Stacked bubbles (multi-bubble layout via
BubbleManager) are explicitly out of scope for now — noted at the bottom.

---

## What We Are Testing

The permission popup is the most complex UI in squib:

- `BubbleCardView` — SwiftUI, ~700 lines. Three layout branches: regular permission, plan
  review, elicitation. Tool colour pill, command/file block, suggestion buttons, Allow/Deny.
- `BubbleViewModel` — `@MainActor ObservableObject`. Drives card state, key action triggers,
  decision callbacks.
- `BubbleWindow` — AppKit shell (`NSPanel` + `NSGlassEffectView`). Not under test here.

`BubbleCardView` and `BubbleViewModel` have **no AppKit dependencies** — they import SwiftUI
and SquibCore only. This is what makes headless rendering possible.

---

## Architecture

### The problem with the current SPM layout

`BubbleCardView` and `BubbleViewModel` currently live in `Sources/squib/`, which is an
**executable target**. SPM executables cannot be imported. A separate snapshot tool cannot
reach these types.

### Solution: extract to `SquibUI` library

Move the two files to a new `Sources/SquibUI/` library target.

```
Sources/
  SquibCore/             (unchanged — PermissionRequest, HookServer, StateEngine, …)
  SquibUI/               (NEW library)
    BubbleCardView.swift   (moved from squib/)
    BubbleViewModel.swift  (moved from squib/)
  squib/                 (unchanged except loses the two moved files)
    AppDelegate.swift
    BubbleManager.swift
    BubbleWindow.swift     (only consumer of the moved types; gains import SquibUI)
    PetWindow.swift
    …
  bubbleSnapshotTool/    (NEW executable)
    main.swift
    Fixture.swift
  squibTestRunner/       (unchanged)
```

`squib` depends on `SquibUI` + `SquibCore`.  
`bubbleSnapshotTool` depends on `SquibUI` + `SquibCore`.  
`SquibUI` depends on `SquibCore`.

The only required code changes to the moved files: mark `BubbleCardView`, `BubbleViewModel`,
their initialisers, and `@Published` properties `public`. Also add `_renderImmediately`
parameter to `BubbleCardView.init` (see Animation section below).

### Package.swift additions

```swift
.target(
    name: "SquibUI",
    dependencies: ["SquibCore"],
    path: "Sources/SquibUI",
    swiftSettings: [.swiftLanguageMode(.v5)]
),
.executableTarget(
    name: "bubbleSnapshotTool",
    dependencies: ["SquibUI", "SquibCore"],
    path: "Sources/bubbleSnapshotTool",
    swiftSettings: [.swiftLanguageMode(.v5)]
),
```

Update `squib` dependencies to `["SquibCore", "SquibUI"]`.

---

## The Snapshot Tool

`swift run bubbleSnapshotTool [--all | --id <name>] [--out <dir>] [--fixtures <dir>]`

**What it does:**

1. Reads JSON fixture files from `--fixtures` (default `Tests/Snapshots/fixtures/`)
2. For each fixture, builds a `PermissionRequest` via a `Codable` `Fixture` intermediate struct
3. Creates `BubbleViewModel(request:)` and `BubbleCardView(model:_renderImmediately:true)`
4. Wraps in `.frame(width: w).background(Color(white: 0.10)).preferredColorScheme(.dark)`
5. Renders via `ImageRenderer` at `scale: 2.0`
6. Writes PNG to `--out` dir (default `Tests/Snapshots/output/`)
7. Prints the output path for each rendered file

The `@main` struct and rendering loop must run on `@MainActor` because `BubbleViewModel` is
`@MainActor`.

### Animation: `_renderImmediately` flag

`BubbleCardView` has an entry animation: `opacity`, `offset`, and `scale` driven by an
`appeared` `@State` Bool, toggled in `.onAppear`. `ImageRenderer` does not run `.onAppear`,
so the view renders in its pre-animation state (invisible / offset / scaled-down) by default.

Fix: add `_renderImmediately: Bool = false` to `BubbleCardView.init`. When `true`, initialise
`_appeared = State(initialValue: true)` so the settled layout is what ImageRenderer sees.

The snapshot tool always passes `_renderImmediately: true`. The live app never sets it.

### Fixture format (JSON, one file per scenario)

Mirrors the wire payload Claude Code sends to `/squib/permission`, plus a top-level `id`
field. `tool_input` is a JSON-encoded string (same as wire). `permission_suggestions` is an
array of objects.

```json
{
  "id": "bash-short",
  "tool_name": "Bash",
  "tool_input": "{\"command\":\"ls -la\"}",
  "cwd": "/Users/me/myrepo",
  "session_id": "abc-123",
  "is_elicitation": false,
  "permission_suggestions": []
}
```

The `Fixture` struct in `Fixture.swift` is `Codable`. `permission_suggestions` decodes as
`[[String: JSONValue]]` (where `JSONValue` is a local recursive enum) and converts to
`[[String: Any]]` for `PermissionRequest`.

---

## The Spec Files (YAML, one per scenario)

Tracked in `Tests/Snapshots/specs/`. The agent reads the PNG alongside the spec and reasons
about whether the rendered UI matches the declared expectations.

```yaml
id: bash-short
title: "Bash short command — regular permission, no suggestions"
fixture: bash-short.json

expect:
  card_kind: regular          # regular | plan_review | elicitation
  width_pt: 340
  tool_pill:
    text: "BASH"
    color: orange             # orange | blue | green | tan | purple | pink | teal | gray
  command_block:
    visible: true
    prefix: "$"
    contains: "ls -la"
    truncated: false
  buttons:
    - { label: "Allow", hint: "⌘⇧Y", style: primary }
    - { label: "Deny",  hint: "⌘⇧N", style: secondary }
  suggestions: []

notes: |
  Single-line bash command. CommandBlock should not show a scrollbar.
  No "Allow Session" or suggestion buttons (suggestions=[]).
  Session tag appears under the tool pill (shows abbreviated session_id).
```

Every `expect` key maps to something the agent can verify by looking at the PNG. No invisible
state, no pixel-coordinate assertions. The `notes` field is free-form prose for edge-case
guidance.

---

## File Layout

```
Tests/Snapshots/
  DESIGN.md              ← this file
  fixtures/              ← tracked, input JSON for the snapshot tool
    bash-short.json
    bash-long.json
    edit-file.json
    write-file.json
    read-file.json
    permission-with-suggestions.json
    elicitation-ask.json
  specs/                 ← tracked, YAML the agent reads alongside PNGs
    bash-short.yaml
    bash-long.yaml
    edit-file.yaml
    write-file.yaml
    read-file.yaml
    permission-with-suggestions.yaml
    elicitation-ask.yaml
  output/                ← GITIGNORED, generated PNGs
    bash-short.png
    …
```

`Tests/Snapshots/output/` must be added to `.gitignore`.

---

## Scenarios

| id | tool_name | key things to test |
|----|-----------|--------------------|
| `bash-short` | Bash | orange pill, short command, no truncation, no suggestions |
| `bash-long` | Bash | long command wraps / scrolls in CommandBlock |
| `edit-file` | Edit | blue pill, file path shown |
| `write-file` | Write | tan pill, file path shown |
| `read-file` | Read | green pill, file path shown |
| `permission-with-suggestions` | Bash | "Allow Session" button + suggestion rows render |
| `elicitation-ask` | AskUserQuestion | 380pt wide card, elicitation layout, no Allow/Deny |

---

## Makefile Interface

```makefile
snapshots:        ## Render all scenarios → Tests/Snapshots/output/
snapshot:         ## Render one: make snapshot NAME=bash-short
snapshots-clean:  ## Delete Tests/Snapshots/output/
```

---

## Agent Workflow

1. `make snapshot NAME=<id>` — renders one PNG
2. `Read Tests/Snapshots/output/<id>.png` — agent sees the rendered card
3. `Read Tests/Snapshots/specs/<id>.yaml` — agent reads the spec
4. Agent reasons: does the rendered PNG satisfy each `expect` key?
5. If not: agent fixes `BubbleCardView.swift`, reruns `make snapshot`, checks again
6. If spec is wrong: agent updates the YAML

---

## Cleanup Required Before Implementing

The previous approach (screenshot the running app via CGWindowListCreateImage) was partially
implemented before this design was settled. The following must be reverted:

- `Sources/SquibCore/HookServer.swift` — remove `screenshotEnabled`, `onScreenshot`,
  `onSetState`, `routeScreenshot()`, `queryParam()` additions
- `Sources/squib/ScreenshotCapture.swift` — delete this file (wrong approach)
- Task #1 "Add screenshot routes to HookServer" — close as superseded

---

## Out of Scope (Future)

**Stacked bubbles / multi-bubble layout** — testing `BubbleManager`'s stacking and offset
logic requires the real running app (multiple `BubbleWindow` instances, `onOffsetChange`
callbacks, pet window displacement). The right approach when we get there: launch squib with
`SQUIB_SCREENSHOT_MODE=1`, POST multiple `/squib/permission` payloads with held connections,
screenshot the window stack. Not needed now.

**Pixel-diff reference comparison** — a `Tests/Snapshots/reference/` directory of committed
PNGs and a `make snapshots-diff` target using ImageMagick or a Swift pixel comparator. Useful
for CI. Not needed while the agent is the reviewer.

**Pet window / animation state screenshots** — separate concern from the bubble UI.
