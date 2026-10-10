# CLAUDE.md

MC6 Virtual is a macOS app that runs an MC6 Pro "All Banks" backup and sends its MIDI through two CoreMIDI virtual ports. See `README.md` for what the app does and for the policy table.

## Commands

```sh
swift build           # debug build
scripts/test.sh       # all tests (Swift Testing)
scripts/make-app.sh   # release build, dist/MC6 Virtual.app, ad hoc signature
```

- Quit any running MC6App before `scripts/test.sh`. The app holds the CoreMIDI unique IDs that the loopback test uses. Check with `pgrep -fl MC6App`.
- The tests read the fixture from the spec package next to this repository.

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

## Where the policies live

The policies U01 to U12 are named constants and plain code, not switchable strategies. The table is in `README.md`.

- U01, profile and settings checks: `Sources/MC6Core/Import/Importer.swift`, `Commands.swift`.
- U02, U03, U11, limits (`Engine.maxDepth`, `Engine.maxMessagesPerTrigger`): `Sources/MC6Core/Engine/Engine.swift`.
- U04, U05: `Sources/MC6Core/Engine/Navigation.swift`, `RuntimeState.swift`.
- U06, U07, U09: `Engine.swift`, `MessageScroll.swift`, `RuntimeState.swift`.
- U08 (`longPress`, `GestureRecognizer.doubleTapWindow`) and focus loss: `Sources/MC6Core/Gesture/GestureRecognizer.swift`.
- U10, U12, Dry Run and the log: `Sources/MC6Core/Session/Session.swift`.
