# Memory Bank Index

Read this file at the start of every session to restore context.

## Status
- **Phase**: Session 19 complete — Liquid Glass BubbleWindow (NSGlassEffectView + SwiftUI)
- **Last updated**: 2026-04-22 (Session 19)

## Agent Instructions
- Read this file first, every session
- After any meaningful work, update the relevant file and bump "Last updated" above
- If a file listed below no longer reflects reality, fix it — don't leave stale entries
- New memory files must be registered in the table below before closing a session

## Active Decisions
- Swift/AppKit, SPM only, NWListener HTTP server, WKWebView
- 12 states: idle (SVG+eye tracking), all others in-progress migration to SVG (were GIFs)
- Idle: `clawd-idle-follow.svg` inline; eye tracking via `#eyes-js` translate, max 3.0 SVG units
- Multi-session StateEngine: priority + stale eviction; synthetic sessions for subagent (juggling/conducting) and notification
- Hook event names: use `HookEventName.*` constants (in SquibCore), never raw strings
- Claude Code hooks: one atomic settings.json write via `registerClaudeHooks(port:)` from `onReady`
- PermissionRequest URL: `/squib/permission` (distinctive path); filter+replace upsert preserves third-party entries
- PiWatcher: `seedExistingFiles()` on startup seals pre-existing files — no history replay, starts idle cleanly

## Files
| File | Contents |
|------|----------|
| `reference-notes.md` | Key observations from clawd-on-desk source |
| `decisions.md` | Architecture and design decisions log |
| `progress.md` | Task-level progress log |
| `animation-gaps.md` | Prioritised task list: missing states, priority bugs, mini gaps (Session 12) |

## Reference
- Source: `/Users/vinayak.kaushik/Developer/clawd-on-desk-ref`
- Original repo: https://github.com/rullerzhou-afk/clawd-on-desk
