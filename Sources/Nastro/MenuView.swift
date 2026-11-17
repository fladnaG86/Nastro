import AppKit
import AVFoundation
import NastroCore
import SwiftUI

/// What the panel shows about the recorder, as plain values.
struct PanelStatus {
    var state: RecorderState
    var elapsedSeconds: Int
    var systemLevelDB: Float
    var microphoneLevelDB: Float
    var warnings: Set<Warning>
    /// The problem to explain (see `MenuLayout.displayedProblem`).
    var problem: StartProblem?
}

/// The source lists offered in the panel.
struct PanelSources {
    var displays: [DisplayInfo] = []
    var windows: [WindowInfo] = []
    var microphones: [MicInfo] = []
    var defaultMicrophoneName: String?

    /// Microphones always; displays and windows only when screen access is already granted, so
    /// loading never triggers a permission prompt.
    static func load() async -> PanelSources {
        var sources = PanelSources(microphones: SourceCatalog.microphones(),
                                   defaultMicrophoneName: AVCaptureDevice.default(for: .audio)?.localizedName)
        if Permissions.screenGranted, let loaded = try? await SourceCatalog.load() {
            sources.displays = loaded.displays
            sources.windows = loaded.windows
        }
        return sources
    }
}

struct PanelActions {
    var toggle: () -> Void = {}
    var openFolder: () -> Void = {}
    var openSettings: () -> Void = {}
    var quit: () -> Void = {}
    var openSystemSettings: (PermissionPane) -> Void = { _ in }
}

/// The menu bar panel: idle choices, or the running recording with its level meters.
struct MenuView: View {
    let status: PanelStatus
    let sources: PanelSources
    @Binding var settings: NastroCore.Settings
    let actions: PanelActions

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(sections, id: \.self) { section in
                row(section)
            }
        }
        .padding(12)
        .frame(width: 300)
    }

    private var sections: [MenuSection] {
        MenuLayout.sections(state: status.state, mode: settings.mode, problem: status.problem)
    }

    private var editable: Bool { MenuLayout.choicesEditable(status.state) }

    @ViewBuilder
    private func row(_ section: MenuSection) -> some View {
        switch section {
        case .problem: problemRow
        case .start: startRow
        case .mode: modeRow
        case .videoSource: videoSourceRow
        case .audio: audioRow
        case .stop: stopRow
        case .meters: metersRow
        case .preparing: preparingRow
        case .openFolder:
            VStack(spacing: 2) {
                Divider().padding(.bottom, 4)
                MenuRowButton(title: L10n.t(.openRecordingsFolder), action: actions.openFolder)
            }
        case .settings: MenuRowButton(title: L10n.t(.settingsEllipsis), action: actions.openSettings)
        case .quit: MenuRowButton(title: L10n.t(.quit), action: actions.quit)
        }
    }

    // MARK: Idle

    @ViewBuilder
    private var problemRow: some View {
        if let problem = status.problem {
            VStack(alignment: .leading, spacing: 8) {
                Label {
                    Text(L10n.t(problem.messageKey)).fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: MenuBarLabel.warningSymbol).foregroundStyle(.orange)
                }
                if let pane = MenuLayout.permissionPane(for: problem) {
                    Button(L10n.t(.openSystemSettings)) { actions.openSystemSettings(pane) }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var startRow: some View {
        Button(action: actions.toggle) {
            HStack {
                Image(systemName: "record.circle.fill").foregroundStyle(.red)
                Text(L10n.t(.startRecording))
                Spacer()
                Text(HotKeyLetters.display(settings.hotKeyLetter)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .disabled(!MenuLayout.startEnabled(status.state))
    }

    private var modeRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(L10n.t(.menuWhatToRecord))
            Picker(L10n.t(.menuWhatToRecord), selection: $settings.mode) {
                Text(L10n.t(.modeVideoAndAudio)).tag(RecordingMode.videoAndAudio)
                Text(L10n.t(.modeAudioOnly)).tag(RecordingMode.audioOnly)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .disabled(!editable)
        }
    }

    private var videoSourceRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(L10n.t(.menuVideoSource))
            Picker(L10n.t(.menuVideoSource), selection: $settings.videoSource) {
                if !sources.displays.contains(where: \.isMain) {
                    Text(L10n.t(.mainDisplayPlaceholder)).tag(VideoSource.mainDisplay)
                }
                if !SourceChoice.isAvailable(settings.videoSource, displayIDs: sources.displays.map(\.id),
                                             windowIDs: sources.windows.map(\.id)) {
                    Text(L10n.t(.sourceNotAvailable)).tag(settings.videoSource)
                }
                if !sources.displays.isEmpty {
                    Section(L10n.t(.menuDisplays)) {
                        ForEach(sources.displays) { display in
                            Text(display.name).tag(SourceChoice.source(forDisplay: display.id, isMain: display.isMain))
                        }
                    }
                }
                if !sources.windows.isEmpty {
                    Section(L10n.t(.menuWindows)) {
                        ForEach(sources.windows) { window in
                            Text(SourceChoice.windowLabel(app: window.appName, title: window.title))
                                .tag(VideoSource.window(id: window.id))
                        }
                    }
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .disabled(!editable)
        }
    }

    private var audioRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(L10n.t(.menuAudio))
            Toggle(isOn: $settings.systemAudio) {
                Text(L10n.t(.systemAudio))
            }
            Toggle(isOn: $settings.microphone) {
                Text(microphoneTitle).lineLimit(1).truncationMode(.middle)
            }
        }
        .toggleStyle(.checkbox)
        .disabled(!editable)
    }

    private var microphoneTitle: String {
        let name = SourceChoice.microphoneName(selectedID: settings.microphoneID,
                                               available: sources.microphones.map { ($0.id, $0.name) },
                                               systemDefault: sources.defaultMicrophoneName)
        return L10n.t(.microphone) + ": " + (name ?? L10n.t(.microphoneNotConnected))
    }

    // MARK: Recording

    private var stopRow: some View {
        HStack(spacing: 12) {
            Button(action: actions.toggle) {
                HStack {
                    Image(systemName: "stop.fill").foregroundStyle(.red)
                    Text(L10n.t(.stopRecording))
                    Spacer(minLength: 0)
                    Text(HotKeyLetters.display(settings.hotKeyLetter)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            Text(TimeFormat.elapsed(status.elapsedSeconds))
                .font(.title2.monospacedDigit().weight(.medium))
        }
    }

    @ViewBuilder
    private var metersRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            if settings.systemAudio {
                MeterRow(title: L10n.t(.systemAudio), db: status.systemLevelDB,
                         warnings: MeterWarnings.for(.system, in: status.warnings))
            }
            if settings.microphone {
                MeterRow(title: L10n.t(.microphone), db: status.microphoneLevelDB,
                         warnings: MeterWarnings.for(.microphone, in: status.warnings))
            }
        }
    }

    private var preparingRow: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(L10n.t(.preparingFile))
        }
    }
}

private struct SectionHeader: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
    }
}

/// A menu-like row: plain text, highlighted under the pointer.
private struct MenuRowButton: View {
    let title: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(hovering ? Color.accentColor.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 5))
        .onHover { hovering = $0 }
    }
}

/// One labelled level bar (-60…0 dB) with its warnings below.
private struct MeterRow: View {
    let title: String
    let db: Float
    let warnings: [Warning]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(db <= LevelMeter.floorDB ? "−∞ dB" : String(format: "%.0f dB", db))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule()
                        .fill(LinearGradient(colors: [.green, .green, .yellow, .red],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: geometry.size.width)
                        .mask(alignment: .leading) {
                            Rectangle().frame(width: geometry.size.width * LevelMeter.fraction(db))
                        }
                }
            }
            .frame(height: 8)
            .accessibilityLabel(title)
            .accessibilityValue(String(format: "%.0f dB", db))
            ForEach(warnings, id: \.self) { warning in
                WarningText(warning: warning)
            }
        }
    }
}

private struct WarningText: View {
    let warning: Warning

    var body: some View {
        if MeterWarnings.isCritical(warning) {
            Label(L10n.t(warning.messageKey), systemImage: "xmark.octagon.fill")
                .font(.callout.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.red, in: RoundedRectangle(cornerRadius: 6))
        } else {
            Label(L10n.t(warning.messageKey), systemImage: MenuBarLabel.warningSymbol)
                .font(.callout)
                .foregroundStyle(.orange)
        }
    }
}

/// The menu bar item: one image (symbol, red while recording, plus the warning triangle) and
/// the running time.
struct MenuBarLabelView: View {
    let label: MenuBarLabel

    var body: some View {
        HStack(spacing: 4) {
            Image(nsImage: Self.image(for: label))
            if let elapsed = label.elapsed {
                Text(elapsed).monospacedDigit()
            }
        }
    }

    static func image(for label: MenuBarLabel) -> NSImage {
        let pointSize: CGFloat = 14
        func symbol(_ name: String, color: NSColor?) -> NSImage? {
            var configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
            if let color { configuration = configuration.applying(.init(paletteColors: [color])) }
            return NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                .withSymbolConfiguration(configuration)
        }
        let colored = label.isRed
        var parts: [NSImage] = []
        if let main = symbol(label.symbol, color: colored ? .systemRed : nil) { parts.append(main) }
        if label.showsWarning, let triangle = symbol(MenuBarLabel.warningSymbol, color: colored ? .systemOrange : nil) {
            parts.append(triangle)
        }
        let spacing: CGFloat = 3
        let width = parts.map(\.size.width).reduce(0, +) + spacing * CGFloat(max(parts.count - 1, 0))
        let height = parts.map(\.size.height).max() ?? pointSize
        let image = NSImage(size: NSSize(width: max(width, 1), height: height), flipped: false) { _ in
            var x: CGFloat = 0
            for part in parts {
                part.draw(in: NSRect(x: x, y: (height - part.size.height) / 2,
                                     width: part.size.width, height: part.size.height))
                x += part.size.width + spacing
            }
            return true
        }
        // Template images follow the menu bar's light or dark appearance; the red one keeps its colours.
        image.isTemplate = !colored
        return image
    }
}
