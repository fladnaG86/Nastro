import AppKit
import NastroCore
import SwiftUI

/// The Settings window: folder, video quality, separate tracks, microphone, shortcut.
struct SettingsView: View {
    @Binding var settings: NastroCore.Settings
    let microphones: [MicInfo]
    /// A recording is running or being prepared: everything but the shortcut is locked
    /// (see `SettingsLock`).
    let locked: Bool
    let hotKey: HotKeyOutcome

    var body: some View {
        Form {
            if locked {
                Section {
                    Label(L10n.t(.settingsAppliesNextRecording), systemImage: "lock.fill")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Section {
                nextRecordingSettings.disabled(locked)
            }
            Section {
                hotKeyPicker
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var hotKeyPicker: some View {
        Picker(L10n.t(.settingsHotKey), selection: $settings.hotKeyLetter) {
            ForEach(HotKeyLetters.allowed, id: \.self) { letter in
                Text(HotKeyLetters.display(letter)).tag(letter)
            }
        }
        if let shortcut = HotKeyLetters.conflict(hotKey) {
            Label(String(format: L10n.t(.hotKeyInUseSettings), shortcut), systemImage: MenuBarLabel.warningSymbol)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var nextRecordingSettings: some View {
        LabeledContent(L10n.t(.settingsFolder)) {
            HStack {
                Text((settings.outputFolder.standardizedFileURL.path as NSString).abbreviatingWithTildeInPath)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(locked ? .secondary : .primary)
                    .help(settings.outputFolder.standardizedFileURL.path)
                Button(L10n.t(.chooseFolder), action: chooseFolder)
            }
        }
        Picker(L10n.t(.settingsMaxResolution), selection: $settings.maxLongSide) {
            ForEach(SettingsChoices.resolutions(including: settings.maxLongSide), id: \.self) { value in
                Text(SettingsChoices.resolutionLabel(value)).tag(value)
            }
        }
        Picker(L10n.t(.settingsFramesPerSecond), selection: $settings.fps) {
            ForEach(SettingsChoices.framesPerSecond(including: settings.fps), id: \.self) { value in
                Text("\(value)").tag(value)
            }
        }
        Toggle(L10n.t(.settingsKeepSeparateTracks), isOn: $settings.keepSeparateTracks)
        Picker(L10n.t(.settingsMicrophone), selection: $settings.microphoneID) {
            Text(L10n.t(.systemDefaultMicrophone)).tag(String?.none)
            if let id = settings.microphoneID, !microphones.contains(where: { $0.id == id }) {
                Text(L10n.t(.microphoneNotConnected)).tag(String?.some(id))
            }
            ForEach(microphones) { mic in
                Text(mic.name).tag(String?.some(mic.id))
            }
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = settings.outputFolder
        if panel.runModal() == .OK, let url = panel.url { settings.outputFolder = url }
    }
}
