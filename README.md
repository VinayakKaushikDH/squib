# squib

A macOS desktop agent watcher — our variation on clawd-on-desk.

## Running Tests

Tests use Swift Testing and run via a standalone executable (not `swift test`):

```bash
swift run squibTestRunner
```

Expected output ends with:
```
✔ Test run with 78 tests in 6 suites passed after 0.430 seconds.
```

## Test Structure

All tests live in `Sources/squibTestRunner/` and import `SquibCore` directly.

| Suite | File | Tests |
|---|---|---|
| `PetState` | `PetStateTests.swift` | Priority ordering, asset extensions, eye tracking, `from(hookEventName:)` mapping |
| `StateEngine` | `StateEngineTests.swift` | Session lifecycle, priority resolution, subagent counting, notification state, `reset()`, `sessionSnapshot`, callbacks |
| `HookParser` | `HookParserTests.swift` | HTTP request parsing, permission payload parsing, response serialisation |
| `PiJSONLParser` | `PiJSONLParserTests.swift` | JSONL line parsing, role mapping, stop reason handling |
| `HookServer Integration` | `HookServerIntegrationTests.swift` | Health check, event dispatch, bad JSON → 400, StateEngine wiring, 404, debug routes |
| `PiWatcher Integration` | `PiWatcherIntegrationTests.swift` | New file → SessionStart, JSONL parsing, appended lines, non-.jsonl ignored |

## Why a standalone runner?

`swift test` uses a bundle runner that only activates Swift Testing when `Testing` is a
formal package dependency (i.e. pulled from a Swift package URL). Since the CLI tools ship
`Testing.framework` at a non-standard path and we link it via `unsafeFlags`, SPM never passes
`--testing-library swift-testing` to the runner, so zero tests execute.

The workaround: `squibTestRunner` is a regular executable target that calls
`Testing.__swiftPMEntryPoint()` directly. The `@Test` and `@Suite` macros register tests into
a global list at load time; the entry point discovers and runs them all.

## Architecture

```
Sources/
  SquibCore/          — library: pure logic, no AppKit (fully testable)
    StateEngine.swift
    HookParser.swift
    PiJSONLParser.swift
    HookServer.swift
    PiWatcher.swift
    PetState.swift
    HookEvent.swift
    PermissionRequest.swift
    PermissionDecision.swift
  squib/              — executable: AppKit app, depends on SquibCore
    AppDelegate.swift
    PetWindow.swift
    PetView.swift
    ...
  squibTestRunner/    — executable: test runner, depends on SquibCore
    main.swift        — Testing.__swiftPMEntryPoint() entry point
    *Tests.swift      — one file per suite
```
