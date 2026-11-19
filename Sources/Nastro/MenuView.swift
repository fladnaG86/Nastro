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
    var hotKey: HotKeyOutcome
    /// The running recording's settings (meters and warnings follow these while recording).
    var recordingSettings: NastroCore.Settings? = nil
    /// The transcribe-and-summarize row is offered (macOS 26).
    var summaryAvailable = false
    /// The running summary job: recording name and phase.
    var summaryJob: (name: String, phase: SummaryPhase)? = nil
}

/// The source lists offered in the panel.
struct PanelSources {
    var displays: [DisplayInfo] = []
    var windows: [WindowInfo] = []
    var microphones: [MicInfo] = []
    var defaultMicrophoneName: String?
    /// False when displays and windows could not be loaded (no screen access): the empty lists
    /// then say nothing about which sources exist.
    var screenListsLoaded = false

    /// Microphones always; displays and windows only when screen access is already granted, so
    /// loading never triggers a permission prompt.
    static func load() async -> PanelSources {
        var sources = PanelSources(microphones: SourceCatalog.microphones(),
                                   defaultMicrophoneName: AVCaptureDevice.default(for: .audio)?.localizedName)
        if Permissions.screenGranted, let loaded = try? await SourceCatalog.load() {
            sources.displays = loaded.displays
            sources.windows = loaded.windows
            sources.screenListsLoaded = true
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
    var summarize: () -> Void = {}
    var cancelSummary: () -> Void = {}
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
        MenuLayout.sections(state: status.state, mode: settings.mode, problem: status.problem,
                            hotKeyConflict: HotKeyLetters.conflict(status.hotKey) != nil,
                            summaryAvailable: status.summaryAvailable, summaryRunning: status.summaryJob != nil)
    }

    private var editable: Bool { MenuLayout.choicesEditable(status.state) }

    @ViewBuilder
    private func row(_ section: MenuSection) -> some View {
        switch section {
        case .problem: problemRow
        case .hotKeyConflict: hotKeyConflictRow
        case .start: startRow
        case .mode: modeRow
        case .videoSource: videoSourceRow
        case .audio: audioRow
        case .stop: stopRow
        case .meters: metersRow
        case .preparing: preparingRow
        case .summaryJob: summaryJobRow
        case .summarize:
            VStack(spacing: 2) {
                // The job row above already opens the block with its divider.
                if status.summaryJob == nil { Divider().padding(.bottom, 4) }
                MenuRowButton(title: L10n.t(.summarizeEllipsis), action: actions.summarize)
                    .disabled(!MenuLayout.summarizeEnabled(state: status.state, summaryRunning: status.summaryJob != nil))
            }
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
            let row = MenuLayout.problemRow(for: problem)
            NoticeBox {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.t(problem.messageKey) + (row.needsRelaunch ? " " + L10n.t(.relaunchAfterGranting) : ""))
                        .fixedSize(horizontal: false, vertical: true)
                    VStack(alignment: .leading, spacing: 6) {
                        if let pane = row.pane {
                            Button(L10n.t(.openSystemSettings)) { actions.openSystemSettings(pane) }
                        }
                        if row.needsRelaunch {
                            Button(L10n.t(.quitNastro), action: actions.quit)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var hotKeyConflictRow: some View {
        if let shortcut = HotKeyLetters.conflict(status.hotKey) {
            NoticeBox {
                Text(String(format: L10n.t(.hotKeyInUseMenu), shortcut))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var startRow: some View {
        Button(action: actions.toggle) {
            HStack {
                Image(systemName: "record.circle.fill").foregroundStyle(.red)
                Text(L10n.t(.startRecording))
                Spacer()
                if let shortcut = HotKeyLetters.shortcutBadge(status.hotKey) {
                    Text(shortcut).foregroundStyle(.secondary)
                }
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
            Picker(L10n.t(.menuVideoSource), selection: videoSourceSelection) {
                if !sources.displays.contains(where: \.isMain) {
                    Text(L10n.t(.mainDisplayPlaceholder)).tag(VideoSource.mainDisplay)
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

    /// Always one of the picker's entries; writing stores the user's pick.
    private var videoSourceSelection: Binding<VideoSource> {
        Binding(
            get: {
                SourceChoice.pickerSelection(saved: settings.videoSource,
                                             displays: sources.displays.map { ($0.id, $0.isMain) },
                                             windowIDs: sources.windows.map(\.id))
            },
            set: { settings.videoSource = $0 })
    }

    private var audioRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(L10n.t(.menuAudio))
            Toggle(isOn: $settings.systemAudio) {
                Text(L10n.t(.systemAudio))
            }
            .disabled(!canToggle(.system))
            Toggle(isOn: $settings.microphone) {
                Text(microphoneTitle).lineLimit(1).truncationMode(.middle)
            }
            .disabled(!canToggle(.microphone))
        }
        .toggleStyle(.checkbox)
        .disabled(!editable)
    }

    /// Audio-only mode: the only enabled source cannot be unchecked.
    private func canToggle(_ channel: AudioChannel) -> Bool {
        MenuLayout.canToggleAudioSource(channel, mode: settings.mode, systemAudio: settings.systemAudio,
                                        microphone: settings.microphone)
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
                    if let shortcut = HotKeyLetters.shortcutBadge(status.hotKey) {
                        Text(shortcut).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            Text(TimeFormat.elapsed(status.elapsedSeconds))
                .font(.title2.monospacedDigit().weight(.medium))
        }
    }

    /// Meters for the sources of the recording that runs (its snapshot), then the warnings
    /// that belong to no meter.
    @ViewBuilder
    private var metersRow: some View {
        let recording = status.recordingSettings ?? settings
        VStack(alignment: .leading, spacing: 12) {
            if recording.systemAudio {
                MeterRow(title: L10n.t(.systemAudio), db: status.systemLevelDB,
                         warnings: MeterWarnings.for(.system, in: status.warnings))
            }
            if recording.microphone {
                MeterRow(title: L10n.t(.microphone), db: status.microphoneLevelDB,
                         warnings: MeterWarnings.for(.microphone, in: status.warnings))
            }
            let rows = MeterWarnings.panelRows(in: status.warnings)
            if !rows.isEmpty {
                Divider()
                ForEach(rows, id: \.self) { warning in
                    WarningText(warning: warning)
                }
            }
        }
    }

    private var preparingRow: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(L10n.t(.preparingFile))
        }
    }

    // MARK: Summary

    @ViewBuilder
    private var summaryJobRow: some View {
        if let job = status.summaryJob {
            VStack(alignment: .leading, spacing: 6) {
                Divider().padding(.bottom, 4)
                Text(job.name)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if case .transcribing(let fraction) = job.phase {
                    ProgressView(value: min(max(fraction, 0), 1))
                } else {
                    ProgressView().progressViewStyle(.linear)
                }
                HStack {
                    Text(SummaryMessages.phaseText(job.phase))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(L10n.t(.cancel), action: actions.cancelSummary)
                        .controlSize(.small)
                }
            }
        }
    }
}

/// An orange box with the warning triangle, for problems the user should act on.
private struct NoticeBox<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        Label {
            content
        } icon: {
            Image(systemName: MenuBarLabel.warningSymbol).foregroundStyle(.orange)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
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

/// The menu bar item: one image (symbol, red while recording, plus the warning triangle or the
/// red critical octagon) and the running time.
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
        func symbol(_ name: String, colors: [NSColor]) -> NSImage? {
            var configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
            if !colors.isEmpty { configuration = configuration.applying(.init(paletteColors: colors)) }
            return NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                .withSymbolConfiguration(configuration)
        }
        func symbol(_ name: String, color: NSColor?) -> NSImage? {
            symbol(name, colors: color.map { [$0] } ?? [])
        }
        let colored = label.isRed
        var parts: [NSImage] = []
        if let main = symbol(label.symbol, color: colored ? .systemRed : nil) { parts.append(main) }
        if label.showsWarning, let triangle = symbol(MenuBarLabel.warningSymbol, color: colored ? .systemOrange : nil) {
            parts.append(triangle)
        }
        // Always red with a white cross, whatever the state: a voice is not being recorded. The
        // cross keeps it from reading as a second recording dot.
        if label.showsCritical, let octagon = symbol(MenuBarLabel.criticalSymbol, colors: [.white, .systemRed]) {
            parts.append(octagon)
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
        // Template images follow the menu bar's light or dark appearance; a coloured one keeps its colours.
        image.isTemplate = !colored && !label.showsCritical
        return image
    }
}
