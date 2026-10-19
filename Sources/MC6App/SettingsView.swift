import MC6Core
import SwiftUI

/// The Settings window. Every change applies at once, except the port names.
struct SettingsView: View {
    @Bindable var preferences: Preferences
    /// The loaded backup, for the "from backup" values.
    let backup: Backup?

    private static let logChoices = [1_000, 5_000, 10_000, 50_000, 100_000]

    var body: some View {
        Form {
            Section("Timing") {
                Picker("Long press", selection: $preferences.customLongPress) {
                    Text(verbatim: "From backup\(backup.map { " (\(100 + 50 * $0.longPressTime) ms)" } ?? "")").tag(false)
                    Text("Custom").tag(true)
                }
                if preferences.customLongPress {
                    milliseconds("Custom long press", $preferences.longPressMs, Preferences.longPressRange, step: 50)
                }
                milliseconds("Double tap window", $preferences.doubleTapMs, Preferences.doubleTapRange, step: 10)
            }
            Section("Pedal") {
                Stepper(value: $preferences.pedalStep, in: Preferences.pedalStepRange) {
                    Text(verbatim: "Arrow step: \(preferences.pedalStep)")
                }
                Stepper(value: $preferences.pedalFineStep, in: Preferences.pedalFineStepRange) {
                    Text(verbatim: "Fine step with Option: \(preferences.pedalFineStep)")
                }
            }
            Section("Display") {
                Picker("Screen brightness", selection: $preferences.customBrightness) {
                    Text(verbatim: "From backup\(backup.map { " (\(30 + 10 * $0.brightnessValue)%)" } ?? "")").tag(false)
                    Text("Custom").tag(true)
                }
                if preferences.customBrightness {
                    LabeledContent {
                        Slider(value: double($preferences.brightnessPercent), in: 30...100, step: 10)
                    } label: {
                        Text(verbatim: "Custom brightness: \(preferences.brightnessPercent)%")
                    }
                }
                Picker("Switch letters on screens", selection: $preferences.letters) {
                    Text(verbatim: "From backup\(backup.map { $0.showPresetLabels ? " (on)" : " (off)" } ?? "")")
                        .tag(LetterChoice.fromBackup)
                    Text("On").tag(LetterChoice.on)
                    Text("Off").tag(LetterChoice.off)
                }
            }
            Section("Log") {
                Picker("Keep entries", selection: $preferences.logLimit) {
                    ForEach(Self.logChoices, id: \.self) { Text(verbatim: $0.formatted()).tag($0) }
                }
            }
            Section {
                TextField("Port 1", text: portName(0))
                TextField("Port 2", text: portName(1))
            } header: {
                Text("MIDI ports")
            } footer: {
                Text("Applied at the next launch. The ports keep their unique IDs.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Startup and window") {
                Toggle("Open the last backup at launch", isOn: $preferences.openLastAtLaunch)
                Toggle("Keep the window on top", isOn: $preferences.keepOnTop)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func milliseconds(_ title: String, _ value: Binding<Int>, _ range: ClosedRange<Int>, step: Int) -> some View {
        LabeledContent {
            Slider(value: double(value), in: Double(range.lowerBound)...Double(range.upperBound), step: Double(step))
        } label: {
            Text(verbatim: "\(title): \(value.wrappedValue) ms")
        }
    }

    private func double(_ value: Binding<Int>) -> Binding<Double> {
        Binding(get: { Double(value.wrappedValue) }, set: { value.wrappedValue = Int($0.rounded()) })
    }

    /// An empty name falls back to the default name at the next launch.
    private func portName(_ index: Int) -> Binding<String> {
        Binding(
            get: { preferences.portNames[index] },
            set: { preferences.portNames[index] = $0 })
    }
}
