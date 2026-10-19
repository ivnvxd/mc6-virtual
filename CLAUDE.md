# CLAUDE.md

MC6 Virtual is a macOS app that runs an MC6 Pro "All Banks" backup and sends its MIDI through two CoreMIDI virtual ports. See `README.md` for what the app does. The policy tables are in "Policies" below.

## Commands

```sh
swift build           # debug build
scripts/test.sh       # all tests (Swift Testing)
scripts/make-app.sh   # release build, dist/MC6 Virtual.app, ad hoc signature
scripts/test.sh --filter GestureTests   # one suite: the script passes its arguments to swift test
scripts/snapshot.sh <backup.json> <out.png> [state]   # draw the panel to a PNG, no window, no ports
```

- Use `scripts/snapshot.sh` to look at the panel after a UI change. `screencapture` needs the Screen Recording permission, which agents do not have. `ImageRenderer` draws shapes, text and images, but not controls or lists, so only the panel is in the PNG.
- Quit any running MC6App before `scripts/test.sh`. The app holds the CoreMIDI unique IDs that the loopback test uses. Check with `pgrep -fl MC6App`.
- The tests read `fixtures/` and `inventory/` from the spec package next to this repository.
- `docs/` is not tracked. Keep plans in `docs/plans/` on your machine only.

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

The spec package is `../mc6-virtual-spec`, next to this repository. It is private and read-only. Do not change it, and do not copy its files into this repository.

- `SPECIFICATION.md`: encodings in section 7, scenarios S1 to S10 in section 9, open questions U01 to U12 in section 10.
- `reference/SEMANTICS.md`: decoding rules.
- `fixtures/`: the acceptance fixture.
- `inventory/`: `active-messages.json` (the expected set of the sweep) and `BANK-MANIFEST.md` (the expected bytes of the scenario tests). Tests read them through `Fixture.inventory(_:)`.

## Where the policies live

The policies U01 to U12 and the v2 decisions V01 to V11 are named constants and plain code, not switchable strategies. The tables are in "Policies" below.

- U01, profile and settings checks: `Sources/MC6Core/Import/Importer.swift`, `Commands.swift`.
- U02, U03, U11, limits (`Engine.maxDepth`, `Engine.maxMessagesPerTrigger`): `Sources/MC6Core/Engine/Engine.swift`.
- U04, U05: `Sources/MC6Core/Engine/Navigation.swift`, `RuntimeState.swift`.
- U06, U07, U09: `Engine.swift`, `MessageScroll.swift`, `RuntimeState.swift`.
- U08 (`backupLongPress`, `GestureTiming.defaultDoubleTapWindow`), V08 (`GestureTiming`) and focus loss: `Sources/MC6Core/Gesture/GestureRecognizer.swift`.
- U10, Dry Run and the log: `Sources/MC6Core/Session/Session.swift`.
- U12: the start values are in `Sources/MC6Core/Engine/RuntimeState.swift` and `Importer.startBank`. Dry Run at start is in `Session.swift`.
- V01 to V03, V05 (`NavigationStep`, `RuntimeState.navigate`): `Sources/MC6Core/Engine/Navigation.swift`. V04 (`Engine.engage(preset:)`): `Engine.swift`.
- V06 (color checks and notes): `Importer.swift`. The palette: `Sources/MC6Core/Display/Palette.swift`. The icon table: `Sources/MC6Core/Display/Icons.swift`.
- V07 and the screens (`ScreenDisplay`, `Band`, `Screen`): `Sources/MC6Core/Display/ScreenDisplay.swift`.
- V10 (`TapTempo`): `Sources/MC6Core/Session/TapTempo.swift`. V11 (`RecentFiles`): `Sources/MC6Core/Session/RecentFiles.swift`. V09 and V11 at launch: `AppModel.init` in `Sources/MC6App/MC6VirtualApp.swift`.
- The key map (`KeyCommand`, `KeyModifiers`): `Sources/MC6Core/Gesture/KeyCommand.swift`. `KeyInput` in the app only passes events to it.

## Architecture notes

- One generation counter, `Engine.generation`. `Engine.cancel()`, `Engine.reset()` and every fault bump it. A bump drops the queue, the frame stack and the pending wake-up. `GestureRecognizer` reads the generation at each entry and in each timer, and drops a gesture from an older generation.
- Session calls `engine.cancel()` on import, arm, disarm and reset.
- Dry Run routing: `Session` wraps the real sink in a private `ArmedSink`. It passes bytes on only while the session is live.
- The log gets the source pointer from `Engine.onOutput`. `MidiSink` does not carry it.
- `Engine` and `Session` are `@Observable`. Timers change `engine.state` without a UI call, so the window observes the engine too.
- `Engine.execute` has an exhaustive `Command` switch with no `default`. A new `Command` case needs its own arm there.
- `ScreenDisplay` takes plain values, not the engine or the session, so snapshot mode can use it. The values are a `RuntimeState`, the `Backup`, the last pressed preset, the pedal value and the BPM. `PanelView` takes the result and draws only.
- The app layer: `Preferences` holds the settings in UserDefaults and calls `onChange`, and `AppModel.applyPreferences` passes them to the session. `AppModel.attach` takes the main `NSWindow` through `WindowReader`: keys work only while it is key, closing it quits the app, and "Keep on top" sets its level.
- Navigation goes through the engine queue as `Work.navigate`. The pedal merge scan in `moveExpression` stops at a navigation, as it stops at a trigger.
- Test hooks: `Engine.onExecute` is internal and exists only for the sweep. `Importer.engageCycles` is internal so a test can run it on a synthetic chain. `Engine.state` has an internal setter, so `@testable` tests can prepare a state.

## Tests

- Mark tests that use the engine, the recognizer or the session `@MainActor`. Mark real-time and CoreMIDI suites `.serialized`.
- Helpers are in `Tests/MC6CoreTests/Support`:
  - `EngineHarness`: an engine and a recognizer with `FakeScheduler` and `RecordingSink`. `tap` runs actions 1, 2, 9 and `hold` runs 1, 3, 4, 9.
  - `FakeScheduler.advance(by:)` moves time and fires the due wake-ups.
  - `Fixture.mutated([Edit])` makes a changed copy of the fixture for load-error cases. `Fixture.resolve(_:in:)` reads the value at a JSON Pointer.
- Main-actor tests can hold the main queue for seconds while the first test parses the fixture. For this reason, the `DispatchScheduler` timing test measures inside the callback and takes the fastest of five tries.

## Policies

These are the rules for the firmware behaviors that the manual does not document, as the code implements them. Test names and code comments cite their IDs. The public README describes the behavior without the IDs.

| ID | Policy |
|---|---|
| U01 | Engage `d3` and Engage `c` have no effect. Delay `d1` has no effect. The importer records each one as a note. The window lists the notes under "Import notes". |
| U02 | A position gate (`tg`) reads the live position. A Toggle Preset earlier in the same action changes what later messages see. |
| U03 | An Engage of a preset in another bank sends the MIDI of that preset. The screen does not move: the shown bank and page stay the same. Page changes inside it act on the shown bank. |
| U04 | BACK goes to the bank and page shown before the last jump to a different bank. It records the place it leaves, so BACK flips between two places. A jump within the same bank or a page change only changes the page. Engage never changes this history. BACK with no history does nothing. Last Bank (`d1=127`) goes to page 1 of the bank that BACK goes to. It follows the same history rule, and with no history it does nothing. |
| U05 | Page Up and Page Down wrap within `pageLimit` (0 means 4 pages). Hidden pages never show. A jump to a page past the limit shows the last visible page. |
| U06 | At startup each expression input selects message 0 only. The selection is global and stays across bank changes. A selection sends nothing until the pedal moves. The pedal sends the selected messages of the shown bank. |
| U07 | Message scroll starts at group 0. It moves to the next group on each Release and wraps. It stays across bank changes. The scroll utility sets the group size but does not move the pointer. Reset and import set it back to group 0. |
| U08 | Long press starts at `100 + 50 * longPressTime` ms, unless Settings has a custom time. Only presets with action 5 to 8 messages wait for a second tap, 300 ms by default. Double Tap fires on the second up, with Double Tap Release and Release All. A second tap held past the long-press time fires Long Double Tap, then Long Double Tap Release and Release All on up. |
| U09 | A temporary name (Rename) stays until reset or import. |
| U10 | MIDI Clock Tap writes a "tap" line to the log. The app sends no F8 clock. |
| U11 | All presses and pedal moves go through one queue. A new press waits for the running one, delays included. Pedal moves of one input merge while they wait, but never move ahead of a press. |
| U12 | The app starts at the first bank, page 1, with all presets at Position 1, in Dry Run. The app saves its settings and recent files (V11), but never this state. |

### v2 decisions

| ID | Decision |
|---|---|
| V01 | Bank Down and Bank Up step through the banks that the first bank can reach, by number, and wrap around. The sidebar lists the same banks. Other banks never show, because the importer does not check them. |
| V02 | Bank Down, Bank Up and a sidebar click go to page 1 of the new bank, like a Bank Jump. So BACK can return (U04). |
| V03 | Page Down and Page Up wrap within the bank's page count (U05). |
| V04 | Keys 1, 2 and 3 run the stored presets I, J and K of the shown bank as a short tap. They do not wait for a second tap. In a bank with one page, they do nothing. A fault stops the rest of the tap. |
| V05 | Bank, page and sidebar steps send no MIDI. They work the same in Dry Run, Live and Error. |
| V06 | A color outside 0 to 127 does not load. Colors 65 to 92 have no name in the Morningstar table. They load with a note and show as the dim version of the color 64 lower. |
| V07 | If a name has the same color as its background, the name shows white. On white, it shows black. |
| V08 | A long-press or double-tap change applies from the next press. |
| V09 | The app never arms by itself. Every launch, open and reload starts in Dry Run. |
| V10 | Tap tempo is the mean of the last 4 tap intervals. A pause of more than 2 seconds starts a new count. |
| V11 | The app remembers the recent files and the settings, and it opens the last backup at launch. |

### Focus loss

When the window loses focus while a button is held:

- After Long Press: Long Press Release and Release All.
- Before Long Press: the press is dropped. Nothing more fires.
- While a preset waits for a second tap: Release and Release All.
- After Long Double Tap on the second tap: Long Double Tap Release and Release All.
- Before Long Double Tap on the second tap: the second tap is dropped. Nothing more fires.

Another button pressed during that wait also ends the first tap as a single tap.

Focus loss ends the gesture. It does not stop an action that already runs. For example, a Press that waits at a Delay sends the rest of its messages. A dropped press that has not started yet, because it waits in the queue behind another action, is removed and sends nothing. Import and Reset stop all pending messages.

When a dialog, a panel or another window opens, the main window loses focus too. Examples are the Open panel, the Export panel, the Reset warning and the Log window.

### Limits

- One press can have at most 8 presets on its call stack: the pressed preset and 7 nested Engage calls.
- One press can run at most 512 messages.

Either limit stops the press and puts the app in the Error state.
