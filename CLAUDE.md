# squib

A desktop agent watcher — our own variation inspired by clawd-on-desk.

## Reference
The original project lives at `/Users/vinayak.kaushik/Developer/clawd-on-desk-ref` for reference only. We are building a completely new codebase.

## Project Goals
- TBD — decided incrementally as we explore the reference and define our own direction

## Version Management
This project uses **jujutsu** (`jj`) for version control.

Common jj commands:
- `jj status` — working copy status
- `jj diff` — pending changes
- `jj describe -m "message"` — set commit description
- `jj new` — start a new change
- `jj log` — history

## Memory Bank

The memory bank is the agent's primary source of persistent context. It is not a log — it is a living document that should be actively improved over time.

**At the start of every session:**
1. Read `memory-bank/index.md` first
2. Check `memory-bank/progress.md` for where things left off
3. Check `memory-bank/decisions.md` for constraints that affect current work

**During a session — update memory when:**
- A non-obvious decision is made (add to `decisions.md` with rationale)
- Work is completed or a direction changes (update `progress.md`)
- A meaningful observation about the reference is made (update `reference-notes.md`)
- A new concept, file, or area becomes important (add a new file and register it in `index.md`)

**Quality bar:**
- Entries should be useful to a future agent with zero session context
- Prefer specificity over vague summaries ("chose Tauri over Electron because koffi native bindings broke on ARM" beats "evaluated frameworks")
- Remove or correct stale entries rather than appending conflicting notes
- If the index is wrong, fix the index

**File index is in `memory-bank/index.md`.** If you add a new memory file, register it there.

The memory bank is only as useful as the agent makes it. Treat improving it as part of the work, not overhead.

## Conventions
- TBD
