# Memory Bank Index

Read this file at the start of every session to restore context.

## Status
- **Phase**: Phase 1e+ complete — bubble system at reference parity
- **Last updated**: 2026-04-20 (Session 5)

## Agent Instructions
- Read this file first, every session
- After any meaningful work, update the relevant file and bump "Last updated" above
- If a file listed below no longer reflects reality, fix it — don't leave stale entries
- New memory files must be registered in the table below before closing a session

## Active Decisions
- Swift/AppKit, SPM only, NWListener HTTP server, WKWebView
- 12 states: idle (SVG+eye tracking), thinking/working/building/juggling/conducting/error/attention/notification/sweeping/carrying/sleeping (all GIF)
- Idle: `clawd-idle-follow.svg` inline; eye tracking via `#eyes-js` translate, max 3.0 SVG units
- Multi-session StateEngine: priority + stale eviction; synthetic sessions for subagent (juggling/conducting) and notification

## Files
| File | Contents |
|------|----------|
| `reference-notes.md` | Key observations from clawd-on-desk source |
| `decisions.md` | Architecture and design decisions log |
| `progress.md` | Task-level progress log |

## Reference
- Source: `/Users/vinayak.kaushik/Developer/clawd-on-desk-ref`
- Original repo: https://github.com/rullerzhou-afk/clawd-on-desk
