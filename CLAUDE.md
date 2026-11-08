# CLAUDE.md

MC6 Virtual is a macOS app that runs an MC6 Pro "All Banks" backup and sends its MIDI through two CoreMIDI virtual ports. See `README.md` for what the app does. The policy tables are in "Policies" below.

## Commands

```sh
swift build           # debug build
scripts/test.sh       # all tests (Swift Testing)
scripts/make-app.sh   # release build, dist/MC6 Virtual.app, ad hoc signature
scripts/test.sh --filter GestureTests   # one suite: the script passes its arguments to swift test
scripts/snapshot.sh <backup.json> <out.png> [state]   # draw the panel to a PNG, no window, no ports
swift scripts/make-icon.swift   # Resources/AppIcon.icns from packaging/icon/*.svg
```

- Use `scripts/snapshot.sh` to look at the panel after a UI change. The state keys are listed in `Snapshot.swift`, for example `held=9` (a switch bit mask), `activity=1` and `zoom=150`. `screencapture` needs the Screen Recording permission, which agents do not have. `ImageRenderer` draws shapes, text and images, but not controls or lists, so only the panel is in the PNG.
- Quit any running MC6App before `scripts/test.sh`. The app holds the CoreMIDI unique IDs that the loopback test uses. Check with `pgrep -fl MC6App`.
- The tests read `fixtures/` and `inventory/` from the spec package next to this repository.
- `docs/` is not tracked. Keep plans in `docs/plans/` on your machine only.
- The app icon: `packaging/icon/AppIcon.svg` (64 px and up) and `AppIcon-small.svg` (16 and 32 px). `scripts/make-icon.swift` renders both with `NSImage` and packs them with `iconutil`. `Resources/AppIcon.icns` is committed, so `make-app.sh` and CI only copy it.

## CI and releases

- `.github/workflows/ci.yml` runs `swift build`, `swift test` and a universal `scripts/make-app.sh` on `macos-15` for each push to `main` and each pull request. The runner has Xcode, so CI calls `swift test` directly, not `scripts/test.sh`.
- The spec package is not on the runner. Each suite that reads `Fixture` carries the `.needsSpec` trait (`Tests/MC6CoreTests/Support/Fixture.swift`). If `CI` is set and the spec is missing, the trait skips the suite. On a dev machine, a missing spec still fails. Give a new fixture suite the trait too.
- `.github/workflows/release.yml` runs on a `v*` tag. It builds the universal app with `VERSION` from the tag, zips it with `ditto` and publishes a GitHub Release. If the `TAP_TOKEN` secret exists, it then writes `packaging/mc6-virtual.rb` with the version and checksum to `ivnvxd/homebrew-tap`.
- The app has only an ad hoc signature and is not notarized. The cask prints the Open Anyway steps and never removes the quarantine flag itself.

## Toolchain notes (Command Line Tools only, no Xcode)

- Plain `swift test` fails: it cannot find the TestingMacros plugin. `scripts/test.sh` passes `-Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing`. Always use the script.
- The `@State` macro is not available: its SwiftUIMacros plugin is not in the Command Line Tools. Do not use the `@State` attribute. Keep state in the `@Observable` `AppModel`, or use a plain stored `State(initialValue:)`.
- The linker prints warnings about missing search paths under `CommandLineTools/Developer`. They are harmless.

## Rules

- Musical values come only from the backup. No bank names, preset names, channels, CC or PC numbers or other values from the fixture go in `Sources/`. Tests can use them.
- Some files are a load error with its JSON Pointer: a file that is not an MC6 Pro All Banks backup, misses a key or breaks the structure. Other content outside the v1 profile loads, and the importer skips it with a note (V18). Never ignore an unknown value without a note.
- Text about the import goes through `ImportText`, so the windows, the snapshot errors and the Copy buttons say the same thing.
- The importer never writes the backup.
- Logic lives in `MC6Core` (no AppKit, no CoreMIDI). `MC6MIDI` holds the virtual ports. `MC6App` is a thin SwiftUI layer.
- Write tests first, from spec values or the fixture, never from engine output. Put the policy ID in the test name, for example `U04: ...`.

## Spec

The spec package is `../mc6-virtual-spec`, next to this repository. It is private and read-only. Do not change it, and do not copy its files into this repository.

- `SPECIFICATION.md`: encodings in section 7, scenarios S1 to S10 in section 9, open questions U01 to U12 in section 10.
- `reference/SEMANTICS.md`: decoding rules.
- `fixtures/`: the acceptance fixture and the audited backup of 2026-11-07.
- `inventory/`: `active-messages.json` (the expected set of the sweep) and `BANK-MANIFEST.md` (the expected bytes of the scenario tests). Tests read them through `Fixture.inventory(_:)`.

## Where the policies live

The policies U01 to U12 and the decisions V01 to V19 are named constants and plain code, not switchable strategies. The tables are in "Policies" below.

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
- V18 and V19 (`ImportNote.Kind`, `Backup.skippedPresets`, `Band.skipped`): `Importer.swift` (`decodeMessage`, `settingNotes`) and `Backup.swift`.
- V20 (`SwitchAction.noAction`, `SwitchAction.targets`): `Backup.swift`. V21 import (`decodeBankMessage`, `BankMessage`, `Bank.enterMessages`, the Bank Jump `enter` flag): `Commands.swift`, `Importer.decodeBank`. V21 run (`enterQueue`, `enterBank`, `RuntimeState.enteredOnce`): `Engine.swift`.
- V22 (`Engine.powerOn`, the order in `Session.load`, `reset` and `arm`): `Engine.swift`, `Session.swift`. The Arm tooltip: `ModeText.armHelp`.
- V23 (`Command.scrollCounter`, `MessageScroll.next`, `cueScroll`): `Commands.swift`, `MessageScroll.swift`.
- V24 (`NameKind`, `NameKey`, `RuntimeState.names` and `colors`, `Command.presetColors`): `Commands.swift`, `RuntimeState.swift`, read by `ScreenDisplay.band`.
- U01 note lines (`ImportText.lines`): `Sources/MC6Core/Display/ImportText.swift`.
- The import text (`ImportText`, the plain names of `TypeNames`) and the mode text (`ModeText`): `Sources/MC6Core/Display/`.
- V10 (`TapTempo`): `Sources/MC6Core/Session/TapTempo.swift`. V11 (`RecentFiles`): `Sources/MC6Core/Session/RecentFiles.swift`. V09 (`Preferences.startLive`) and V11 at launch: `AppModel.init` in `Sources/MC6App/MC6VirtualApp.swift`.
- V12 (`MidiText`, `Backup.source(of:)`): `Sources/MC6Core/Display/MidiText.swift`, `SourceText.swift`. V12 groups (`Session.groupOutputs`, `groupTime`) and V13 (`Session.outputCount`): `Session.swift`. The Sent strip, the activity light and the lit band are app views.
- V15, the key map (`KeyBindings`, `KeyFunction`): `Sources/MC6Core/Gesture/KeyBindings.swift`. `KeyCommand(keyCode:modifiers:map:)` reads it. The type is not `KeyMap`, because Carbon's HIToolbox has a `KeyMap` and the tests import Carbon. The recorder is `KeyInput.record` and `AppModel.recording`.
- V16 (`PedalRamp`): `Sources/MC6Core/Gesture/PedalRamp.swift`. The sweep timer is in `AppModel.startPedal`. V17 (`ScrollSteps`): `Sources/MC6Core/Gesture/ScrollSteps.swift`. `KeyInput` reads scroll events while `AppModel.pedalHovered` is set.
- `KeyInput` in the app only passes events on. It never acts on the OS key repeat.

## Architecture notes

- One generation counter, `Engine.generation`. `Engine.cancel()`, `Engine.reset()` and every fault bump it. A bump drops the queue, the frame stack and the pending wake-up. `GestureRecognizer` reads the generation at each entry and in each timer, and drops a gesture from an older generation.
- Session calls `engine.cancel()` on import, arm, disarm and reset.
- `Engine.enqueue` returns a token. A gesture keeps the token of its Press, so focus loss withdraws exactly that trigger.
- If the log is full, it drops its oldest tenth at once. `Session.logID(at:)` gives the Log window ids that do not move.
- In an `@Observable` class, a `didSet` that assigns the same property again recurses. `Session.logLimit` uses a computed property over private storage.
- `Engine.maxDepth` and `Engine.maxMessagesPerTrigger` are `nonisolated`, so the import and mode text can use them.
- Dry Run routing: `Session` wraps the real sink in a private `ArmedSink`. It passes bytes on only while the session is live.
- The log gets the source pointer from `Engine.onOutput`. `MidiSink` does not carry it.
- `Engine` and `Session` are `@Observable`. Timers change `engine.state` without a UI call, so the window observes the engine too.
- `Engine.execute` has an exhaustive `Command` switch with no `default`. A new `Command` case needs its own arm there.
- `ZoomedPanel` scales the panel with a `Layout` that reports the natural size times the zoom. `MainWindow` and snapshot mode both use it. A size measured into `State` needs a second render pass, which `ImageRenderer` does not run.
- The panel's bank and page print lines are gestures with `contentShape`, not `Button`s, so `ImageRenderer` draws them.
- `ScreenDisplay` takes plain values, not the engine or the session, so snapshot mode can use it. The values are a `RuntimeState`, the `Backup`, the last pressed preset, the pedal value and the BPM. `PanelView` takes the result and draws only.
- The app layer: `Preferences` holds the settings in UserDefaults and calls `onChange`, and `AppModel.applyPreferences` passes them to the session. `AppModel.attach` takes the main `NSWindow` through `WindowReader`: keys work only while it is key, closing it quits the app, and "Keep on top" sets its level.
- V21: `run()` takes work from `enterQueue` before `queue` whenever no frame is on the stack. `cancel()` clears both. Enter work keeps the message count, so an input and its whole enter cascade share the 512 messages. Only work from `queue` and `powerOn()` reset the count.
- V22: `Session.load` and `reset` call `engine.powerOn()` after `stop(.dryRun)`, so their start messages never reach the ports. `arm` calls it after `output.live = true`.
- Snapshot mode builds a `RuntimeState` with no engine, so it shows the state before power-on: no temporary names or colors from the start messages.
- Navigation goes through the engine queue as `Work.navigate`. The pedal merge scan in `moveExpression` stops at a navigation, as it stops at a trigger.
- Test hooks: `Engine.onExecute` is internal and exists only for the sweep. `Importer.engageCycles` is internal so a test can run it on a synthetic chain. `Engine.state` has an internal setter, so `@testable` tests can prepare a state.

## Tests

- Mark tests that use the engine, the recognizer or the session `@MainActor`. Mark real-time and CoreMIDI suites `.serialized`.
- Helpers are in `Tests/MC6CoreTests/Support`:
  - `EngineHarness`: an engine and a recognizer with `FakeScheduler` and `RecordingSink`. `tap` runs actions 1, 2, 9 and `hold` runs 1, 3, 4, 9.
  - `FakeScheduler.advance(by:)` moves time and fires the due wake-ups.
  - `Fixture.mutated([Edit])` makes a changed copy of the fixture for load-error cases. `Fixture.resolve(_:in:)` reads the value at a JSON Pointer.
  - `Fixture.audited()` and `Fixture.auditedData()` read the second fixture, `Morningstar_MC6PRO_All_Banks_Audited_20261107.json`. It uses No Action, bank messages, Utility 0 and 8 and Rename types 3 and 4, and it runs on the user's MC6 Pro. `AuditedBackupTests` holds its acceptance tests.
- Main-actor tests can hold the main queue for seconds while the first test parses the fixture. For this reason, the `DispatchScheduler` timing test measures inside the callback and takes the fastest of five tries.

## Policies

These are the rules for the firmware behaviors that the manual does not document, as the code implements them. Test names and code comments cite their IDs. The public README describes the behavior without the IDs.

| ID | Policy |
|---|---|
| U01 | The app does not use Engage `d3`, Engage `c` and Delay `d1`. The spec does not explain them, so the notes do not call them meaningless. The importer records each one as a note. The notes lists join the notes with the same text in one line with a message count and a bank count. |
| U02 | A position gate (`tg`) reads the live position. A Toggle Preset earlier in the same action changes what later messages see. |
| U03 | An Engage of a preset in another bank sends the MIDI of that preset. The screen does not move: the shown bank and page stay the same. Page changes inside it act on the shown bank. |
| U04 | BACK goes to the bank and page shown before the last jump to a different bank. It records the place it leaves, so BACK flips between two places. A jump within the same bank or a page change only changes the page. Engage never changes this history. BACK with no history does nothing. Last Bank (`d1=127`) goes to page 1 of the bank that BACK goes to. It follows the same history rule, and with no history it does nothing. |
| U05 | Page Up and Page Down wrap within `pageLimit` (0 means 4 pages). Hidden pages never show. A jump to a page past the limit shows the last visible page. |
| U06 | At startup each expression input selects message 0 only. The selection is global and stays across bank changes. A selection sends nothing until the pedal moves. The pedal sends the selected messages of the shown bank. |
| U07 | Message scroll starts at the first Release message. Each Release runs the group size of Release messages from the pointer, and the group ends early at the last message. Then the pointer moves on and wraps. It stays across bank changes. The scroll utility sets the group size but does not move the pointer. Reset, import and arm set it back to the first message. V23 can move it. |
| U08 | Long press starts at `100 + 50 * longPressTime` ms, unless Settings has a custom time. Only presets with action 5 to 8 messages wait for a second tap, 300 ms by default. Double Tap fires on the second up, with Double Tap Release and Release All. A second tap held past the long-press time fires Long Double Tap, then Long Double Tap Release and Release All on up. |
| U09 | A temporary name (Rename) and temporary colors (Utility 8 and 9) stay until reset, import or arm. |
| U10 | MIDI Clock Tap writes a "tap" line to the log. The app sends no F8 clock. |
| U11 | All presses and pedal moves go through one queue. A new press waits for the running one, delays included. Pedal moves of one input merge while they wait, but never move ahead of a press. |
| U12 | The app starts at the first bank, page 1, with all presets at Position 1, in Dry Run (V09 has one exception). Arm restores this state too (V22). The app saves its settings and recent files (V11), but never this state. |

### v2 to v5 decisions

| ID | Decision |
|---|---|
| V01 | Bank Down and Bank Up step through the banks that the first bank can reach, by number, and wrap around. The sidebar lists the same banks. Other banks never show, because the importer does not check them. |
| V02 | Bank Down, Bank Up and a sidebar click go to page 1 of the new bank, like a Bank Jump. So BACK can return (U04). |
| V03 | Page Down and Page Up wrap within the bank's page count (U05). |
| V04 | Keys 1, 2 and 3 run the stored presets I, J and K of the shown bank as a short tap. They do not wait for a second tap. In a bank with one page, they do nothing. A fault stops the rest of the tap. |
| V05 | Bank, page and sidebar steps send no MIDI themselves. A step into a bank with On Enter Bank messages runs them (V21). They work the same in Dry Run, Live and Error. |
| V06 | A color outside 0 to 127 loads as the nearest color, with a note. Colors 65 to 92 have no name in the Morningstar table. They load with a note and show as the dim version of the color 64 lower. |
| V07 | If a name has the same color as its background, the name shows white. On white, it shows black. |
| V08 | A long-press or double-tap change applies from the next press. |
| V09 | The app never arms by itself, with one exception: if "Start Live" is on in Settings and the ports work, the app arms after the launch opens the last backup. Open, Reload and Reset always go to Dry Run. |
| V10 | Tap tempo is the mean of the last 4 tap intervals. A pause of more than 2 seconds starts a new count. A tap less than 100 ms after the last one does not count. Two Clock Taps in one action therefore count once. |
| V11 | The app remembers the recent files and the settings, and it opens the last backup at launch. |
| V12 | The Sent strip and the Log window show each output as text: port, channel, type, number and value, and the source preset. Dry Run outputs show too, marked "dry". The Sent strip shows one group: all outputs since the last footswitch down or engage, with the time since that input. The first pedal move after one of them starts a new group, and later pedal moves add to it. Import, Reset and Arm start a group. A bank step that runs On Enter Bank messages starts a group. Other bank and page steps do not. The strip shows the newest 200 outputs, and its header counts the whole group. In Dry Run the header says that nothing went to the ports. |
| V13 | A band is lit while its switch is held, by any source. The activity light glows dim in the mode color and flashes bright for 120 ms on each output. A MIDI Clock Tap entry or a fault does not flash it. |
| V14 | The panel buttons do the same as the bank and page keys. They send no MIDI themselves (V05). |
| V15 | The key map gives each function one plain key or no key. A key cannot have Command, Control or Option. Shift is ignored. A key that goes to a new function leaves its old function, which then has no key. Escape cancels a recording. |
| V16 | A pedal key moves one step at its down. After 250 ms of hold, the pedal sweeps 127 steps in the sweep time, a quarter as fast with Option. Up, focus loss, a drag or a scroll stops it. A down of the other pedal key starts its own sweep. OS key repeats do nothing. |
| V17 | A scroll over the pedal moves it. The code also accepts it while another app is in front, which is not verified yet. Each wheel event moves one arrow step by its sign. A trackpad moves 1 step for each 4 points. Up raises the value, whatever the natural scrolling setting is. |
| V18 | A file loads unless it is not an MC6 Pro All Banks backup, misses a key or breaks the structure. The importer skips other content outside the v1 profile: messages, bank messages, settings and flags. Each skipped item gets one note with its kind. A skipped Bank Jump or Engage is no edge for the reachable banks. Only production banks get skip notes. A long-press time, page limit or color out of range uses the nearest value. A page limit out of range shows all 4 pages. A switch preset with a skipped message shows a "!" mark on its band. |
| V19 | Toggle Mode and toggle groups do not run, because their order against position gates needs a hardware test. Such a preset plays as a plain preset and shows the "!" mark. |
| V20 | A switch message with action 0 (No Action) loads. No press runs it. An Engage Preset with the target action No Action runs the No Action messages of its target. The editor offers No Action as an Engage target, and the user verified Engage, then No Action, then a CC on the MC6 Pro (2026-11-07). |
| V21 | A bank message of the type Engage Preset with the event On Enter Bank (1) or On Enter Bank, Execute Once Only (3), and `tg=2`, runs when the shown bank changes to its bank. The changes are a Bank Jump with the enter bit (`data[2]` bit 1), a bank step, the sidebar and a power-on (V22). An Engage of another bank and a jump within the bank run none. The messages run in slot order after the running action or step, before the next queued input. A gesture enqueues its actions one at a time, so a Bank Jump on Release runs them before the same gesture's Release All. Execute Once Only runs once after each power-on. The bank counts as entered when its messages are queued. A bank message with the event Nothing never runs and gets no note. Other bank messages are skipped with a note. Provisional: the hardware order and the once-only lifetime are not verified. |
| V22 | Open, Reload, Reset and Arm are a power-on of the MC6. Each restores the start state and runs the On Enter Bank messages of the first bank. Open, Reload and Reset run them in Dry Run. Arm runs them live, so the receiving app gets the start messages. Arm therefore drops what the user did in Dry Run. |
| V23 | Set Message Scroll Counter (Utility 0) names a preset of the frame bank (127 is the frame preset) and a message slot (127 is Reset). The next Release of that preset starts at the first Release message in that slot or after it. Without one, and for Reset, it starts at the first. Provisional for a slot without a Release message. |
| V24 | Preset Rename writes or restores the current, short, toggle or long name (`c` 1 to 6, 9 and 10). The current name wins. Without it, Position 2 shows the toggle name unless it is empty, else the short name shows. A Shift name rename is skipped. Utility 8 and 9 set temporary background, text and strip colors of the frame preset or a preset of the frame bank, for both positions. Bank colors off still show white on black. Provisional for the positions. |

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
- One press can run at most 512 messages, with the On Enter Bank messages that it causes (V21).

Either limit stops the press and puts the app in the Error state.
