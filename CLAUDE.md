# CLAUDE.md

MC6 Virtual is a macOS app that runs an MC6 Pro "All Banks" backup and sends its MIDI through two CoreMIDI virtual ports. See `README.md` for what the app does and for the policy table.

## Commands

```sh
swift build           # debug build
scripts/test.sh       # all tests (Swift Testing)
scripts/make-app.sh   # release build, dist/MC6 Virtual.app, ad hoc signature
scripts/test.sh --filter GestureTests   # one suite: the script passes its arguments to swift test
```

- Quit any running MC6App before `scripts/test.sh`. The app holds the CoreMIDI unique IDs that the loopback test uses. Check with `pgrep -fl MC6App`.
- The tests read `fixtures/` and `inventory/` from the spec package next to this repository.

## Toolchain notes (Command Line Tools only, no Xcode)

- Plain `swift test` fails: it cannot find the TestingMacros plugin. `scripts/test.sh` passes `-Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing`. Always use the script.
- The `@State` macro is not available: its SwiftUIMacros plugin is not in the Command Line Tools. Do not use the `@State` attribute. Keep state in the `@Observable` `AppModel`, or use a plain stored `State(initialValue:)`.
- The linker prints warnings about missing search paths under `CommandLineTools/Developer`. They are harmless.

## Rules

- Musical values come only from the backup. No bank names, preset names, channels, CC or PC numbers or other values from the fixture go in `Sources/`. Tests can use them.
- A backup outside the v1 profile is a load error with its JSON Pointer. Never ignore an unknown value without a note.
- The importer never writes the backup.
- Logic lives in `MC6Core` (no AppKit, no CoreMIDI). `MC6MIDI` holds the virtual ports. `MC6App` is a thin SwiftUI layer.
- Write tests first, from spec values or the fixture, never from engine output. Put the policy ID in the test name, for example `U04: ...`.

## Spec

The spec package is `/Users/andreyivanov/dev/etc/midi/mc6-virtual-spec`. It is read-only. Do not change it.

- `SPECIFICATION.md`: encodings in section 7, scenarios S1 to S10 in section 9, open questions U01 to U12 in section 10.
- `reference/SEMANTICS.md`: decoding rules.
- `fixtures/`: the acceptance fixture.
- `inventory/`: `active-messages.json` (the expected set of the sweep) and `BANK-MANIFEST.md` (the expected bytes of the scenario tests). Tests read them through `Fixture.inventory(_:)`.

## Where the policies live

The policies U01 to U12 are named constants and plain code, not switchable strategies. The table is in `README.md`.

- U01, profile and settings checks: `Sources/MC6Core/Import/Importer.swift`, `Commands.swift`.
- U02, U03, U11, limits (`Engine.maxDepth`, `Engine.maxMessagesPerTrigger`): `Sources/MC6Core/Engine/Engine.swift`.
- U04, U05: `Sources/MC6Core/Engine/Navigation.swift`, `RuntimeState.swift`.
- U06, U07, U09: `Engine.swift`, `MessageScroll.swift`, `RuntimeState.swift`.
- U08 (`longPress`, `GestureRecognizer.doubleTapWindow`) and focus loss: `Sources/MC6Core/Gesture/GestureRecognizer.swift`.
- U10, Dry Run and the log: `Sources/MC6Core/Session/Session.swift`.
- U12: the start values are in `Sources/MC6Core/Engine/RuntimeState.swift` and `Importer.startBank`. Dry Run at start is in `Session.swift`.

## Architecture notes

- One generation counter, `Engine.generation`. `Engine.cancel()`, `Engine.reset()` and every fault bump it. A bump drops the queue, the frame stack and the pending wake-up. `GestureRecognizer` reads the generation at each entry and in each timer, and drops a gesture from an older generation.
- Session calls `engine.cancel()` on import, arm, disarm and reset.
- Dry Run routing: `Session` wraps the real sink in a private `ArmedSink`. It passes bytes on only while the session is live.
- The log gets the source pointer from `Engine.onOutput`. `MidiSink` does not carry it.
- `Engine` and `Session` are `@Observable`. Timers change `engine.state` without a UI call, so the window observes the engine too.
- `Engine.execute` has an exhaustive `Command` switch with no `default`. A new `Command` case needs its own arm there.
- Test hooks: `Engine.onExecute` is internal and exists only for the sweep. `Importer.engageCycles` is internal so a test can run it on a synthetic chain. `Engine.state` has an internal setter, so `@testable` tests can prepare a state.

## Tests

- Mark tests that use the engine, the recognizer or the session `@MainActor`. Mark real-time and CoreMIDI suites `.serialized`.
- Helpers are in `Tests/MC6CoreTests/Support`:
  - `EngineHarness`: an engine and a recognizer with `FakeScheduler` and `RecordingSink`. `tap` runs actions 1, 2, 9 and `hold` runs 1, 3, 4, 9.
  - `FakeScheduler.advance(by:)` moves time and fires the due wake-ups.
  - `Fixture.mutated([Edit])` makes a changed copy of the fixture for load-error cases. `Fixture.resolve(_:in:)` reads the value at a JSON Pointer.
- Main-actor tests can hold the main queue for seconds while the first test parses the fixture. For this reason, the `DispatchScheduler` timing test measures inside the callback and takes the fastest of five tries.
