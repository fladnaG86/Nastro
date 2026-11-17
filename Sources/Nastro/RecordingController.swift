import AppKit
import Foundation
import NastroCore
import NastroMedia
import ScreenCaptureKit

/// How the last recording attempt ended (for the diagnostics and the menu).
enum RecordingOutcome: Equatable {
    case saved(URL)
    case empty
    /// The work file stays on disk (finalization failed, skipped for lack of room, or the
    /// writer failed); recovery at the next launch picks it up.
    case keptWorkFile(URL)
    /// Stopped without keeping anything (no first video frame, or no audio in audio-only mode).
    case discarded
    /// The writer failed before any file existed: nothing was saved.
    case notSaved
    case notStarted(StartProblem)
}

/// Drives one recording at a time: start, stop, live levels, warnings, notifications, and
/// recovery of work files left by an interrupted recording.
@MainActor
final class RecordingController: ObservableObject {
    @Published private(set) var state: RecorderState = .idle
    @Published private(set) var elapsedSeconds: Int = 0
    @Published private(set) var systemLevelDB: Float = AudioLevel.floorDB
    @Published private(set) var microphoneLevelDB: Float = AudioLevel.floorDB
    @Published private(set) var warnings: Set<Warning> = []
    @Published private(set) var startProblem: StartProblem?
    /// The settings of the recording that is running (its snapshot), nil otherwise. The panel
    /// shows meters and warnings for these, not for the live `settings`.
    @Published private(set) var recordingSettings: Settings?
    /// Changes apply to the next recording, never to the one running.
    @Published var settings: Settings {
        didSet { store.save(settings.validated()) }
    }

    private(set) var lastOutcome: RecordingOutcome?
    /// Every warning shown during the current (or last) recording.
    private(set) var warningsSeen: Set<Warning> = []
    private(set) var lastRecoveryOutcomes: [RecoveryOutcome] = []

    private struct Active {
        let settings: Settings
        let session: CaptureSession
        let writer: MovieWriter
        let sink: RecordingSink
        /// Created by this recording (checked free before the writer made it), so the discard
        /// paths may delete it; never a work file kept from an earlier recording.
        let workURL: URL
        let finalURL: URL
        let startedAt: TimeInterval
    }

    private let store: SettingsStore
    private var machine = RecorderMachine()
    private var active: Active?
    private var ticker: Task<Void, Never>?
    private var stopTask: Task<Void, Never>?
    /// A stop requested while the start was still in progress.
    private var pendingStop: StopReason?
    private var sleepObserver: NSObjectProtocol?

    init(store: SettingsStore) {
        self.store = store
        self.settings = store.load()
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.stop(.user) }
        }
    }

    // MARK: Commands

    func toggle() {
        switch state {
        case .idle: Task { await start() }
        case .recording: Task { await stop() }
        default: break
        }
    }

    func start() async {
        guard machine.apply(.startRequested) else { return }
        state = machine.state
        startProblem = nil
        warnings = []
        warningsSeen = []
        pendingStop = nil
        elapsedSeconds = 0
        let s = settings.validated()

        // Permissions: screen first (every mode), then the microphone when enabled.
        switch RecordingRules.permissionDecision(screenGranted: Permissions.screenGranted,
                                                 microphoneWanted: s.microphone, microphone: Self.microphoneAccess) {
        case .proceed: break
        case .askMicrophone:
            if !(await Permissions.requestMicrophone()) { return failStart(.microphonePermission) }
        case .fail(let problem): return failStart(problem)
        }

        do { try Destination.prepare(s.outputFolder) } catch { return failStart(problem(for: .folder, s)) }

        let sources: Sources
        do { sources = try await SourceCatalog.load() } catch { return failStart(problem(for: .other, s)) }

        let fileManager = FileManager.default
        let finalURL = FileNaming.finalURL(folder: s.outputFolder, date: Date(), timeZone: .current,
                                           hasVideo: s.mode == .videoAndAudio,
                                           exists: { final in
                                               FileNaming.isTaken(final: final) { fileManager.fileExists(atPath: $0.path) }
                                           })
        let workURL = FileNaming.workURL(forFinal: finalURL)
        // The name rule keeps clear of kept work files; this guards the race with another
        // writer. From here on, a file at `workURL` was created by this recording, so the
        // failure and discard paths below may delete it.
        guard !fileManager.fileExists(atPath: workURL.path) else { return failStart(problem(for: .other, s)) }

        let sink = RecordingSink(
            onLevels: { [weak self] system, microphone in
                Task { @MainActor in self?.applyLevels(system: system, microphone: microphone) }
            },
            onStopped: { [weak self] error in
                Task { @MainActor in self?.captureStopped(error: error) }
            })

        let session: CaptureSession
        do {
            session = try CaptureSession(settings: s, sources: sources, sink: sink)
        } catch {
            let failure: StartFailure = (error as? CaptureError) == .sourceUnavailable ? .sourceUnavailable : .other
            return failStart(problem(for: failure, s))
        }

        let writer: MovieWriter
        do {
            writer = try MovieWriter(url: workURL, video: session.videoSpec,
                                     systemAudio: s.systemAudio, microphone: s.microphone)
        } catch {
            try? fileManager.removeItem(at: workURL)
            return failStart(problem(for: .other, s))
        }
        sink.attach(writer)

        do {
            try await session.start()
        } catch {
            // Includes `CancellationError` (a stream stopped itself during start): no file, idle.
            await session.stop()
            _ = try? await writer.finish()        // nothing was accepted: deletes the file
            try? fileManager.removeItem(at: workURL)   // created by this recording (guard above)
            let failure: StartFailure
            switch error as? CaptureError {
            case .noPermission: failure = .permissionDenied
            case .sourceUnavailable: failure = .sourceUnavailable
            case nil: failure = .other
            }
            return failStart(problem(for: failure, s))
        }

        let startedAt = RecordingSink.now()
        sink.begin(at: startedAt)
        active = Active(settings: s, session: session, writer: writer, sink: sink,
                        workURL: workURL, finalURL: finalURL, startedAt: startedAt)
        recordingSettings = s
        _ = machine.apply(.started(at: Date()))
        state = machine.state
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled, let self else { return }
                await self.tick()
            }
        }
        if let reason = pendingStop {
            pendingStop = nil
            await stop(reason)
        }
    }

    /// Idempotent: a second call while finalizing waits for the first; when idle it does nothing.
    func stop(_ reason: StopReason = .user) async {
        switch machine.state {
        case .starting:
            pendingStop = pendingStop ?? reason
            return
        case .recording:
            break
        case .finalizing, .idle:
            if let stopTask { await stopTask.value }
            return
        }
        guard let active else { return }
        _ = machine.apply(.stopRequested(reason))
        state = machine.state
        let task = Task { await self.finish(active, reason: reason, discard: false) }
        stopTask = task
        await task.value
        stopTask = nil
    }

    func recoverLeftovers() async {
        guard state == .idle else { return }
        let s = settings.validated()
        let outcomes = await Recovery.run(in: s.outputFolder, keepSeparateTracks: s.keepSeparateTracks)
        lastRecoveryOutcomes = outcomes
        if !outcomes.isEmpty { Notifier.recovered(outcomes) }
    }

    // MARK: Capture events

    private func captureStopped(error: Error?) {
        let code: Int? = (error as NSError?).flatMap { $0.domain == SCStreamErrorDomain ? $0.code : nil }
        Task { await stop(RecordingRules.stopReason(streamErrorCode: code)) }
    }

    private func applyLevels(system: Float?, microphone: Float?) {
        guard case .recording = state else { return }
        if let system { systemLevelDB = system }
        if let microphone { microphoneLevelDB = microphone }
    }

    // MARK: Timer

    private func tick() async {
        guard case .recording = state, let active else { return }
        let now = RecordingSink.now()
        let seconds = now - active.startedAt
        elapsedSeconds = Int(seconds)
        let facts = active.sink.snapshot(at: now)

        let expectsVideo = active.session.videoSpec != nil
        if RecordingRules.firstFrameOverdue(expectsVideo: expectsVideo, sawVideo: facts.sawVideo,
                                            secondsSinceStart: seconds) {
            await abandon(active, messageKey: .noFirstFrame)
            return
        }
        let enabledAudio = [active.settings.systemAudio ? SampleKind.systemAudio : nil,
                            active.settings.microphone ? SampleKind.microphone : nil].compactMap { $0 }
        if RecordingRules.audioOverdue(expectsVideo: expectsVideo,
                                       sawAudio: enabledAudio.contains { facts.lastSampleAt[$0] != nil },
                                       secondsSinceStart: seconds) {
            await abandon(active, messageKey: .noAudio)
            return
        }

        // A level with no recent samples falls back to the floor.
        if facts.secondsSinceSample(.systemAudio, now: now) > 0.5 { systemLevelDB = AudioLevel.floorDB }
        if facts.secondsSinceSample(.microphone, now: now) > 0.5 { microphoneLevelDB = AudioLevel.floorDB }

        let lost = active.writer.sourcesWithoutTrack.union(active.writer.degradedSources)
        func sourceFacts(_ kind: SampleKind, silent: Bool) -> AudioSourceFacts {
            let last = facts.lastSampleAt[kind]
            return AudioSourceFacts(silent: silent,
                                    samplesStopped: RecordingRules.samplesStopped(lastSampleAt: last, now: now),
                                    notRecorded: lost.contains(kind),
                                    neverArrived: RecordingRules.samplesNeverArrived(lastSampleAt: last,
                                                                                     secondsSinceStart: seconds))
        }
        let current = RecordingRules.warnings(
            systemAudio: active.settings.systemAudio ? sourceFacts(.systemAudio, silent: facts.systemSilent) : nil,
            microphone: active.settings.microphone ? sourceFacts(.microphone, silent: facts.microphoneSilent) : nil,
            audioDropouts: !active.writer.droppedAudioBuffers.isEmpty)
        if current != warnings { warnings = current }
        for warning in RecordingRules.warningsToNotify(current: current, alreadyNotified: warningsSeen) {
            Notifier.failed(L10n.t(warning.messageKey))
        }
        warningsSeen.formUnion(current)

        if active.writer.failure != nil {
            await stop(.streamError)
        } else if let free = Self.freeBytes(at: active.settings.outputFolder),
                  DiskGuard.shouldStop(freeBytes: free, workFileBytes: Self.fileSize(active.workURL)) {
            await stop(.diskFull)
        }
    }

    // MARK: Ending

    private func finish(_ active: Active, reason: StopReason, discard: Bool) async {
        ticker?.cancel()
        ticker = nil
        await active.session.stop()
        self.active = nil
        defer {
            systemLevelDB = AudioLevel.floorDB
            microphoneLevelDB = AudioLevel.floorDB
            warnings = []
            recordingSettings = nil
            state = machine.state
        }
        let fileManager = FileManager.default

        let result: WriteResult
        do {
            result = try await active.writer.finish()
        } catch {
            if discard {
                try? fileManager.removeItem(at: active.workURL)
                return end(.discarded, finalized: false)
            }
            let exists = fileManager.fileExists(atPath: active.workURL.path)
            let message = RecordingRules.writeFailureMessageKeys(workFileExists: exists)
                .map { L10n.t($0) }.joined(separator: " ")
            guard exists else {
                Notifier.failed(message)
                return end(.notSaved, finalized: false)
            }
            Notifier.failed(message, file: active.workURL)
            return end(.keptWorkFile(active.workURL), finalized: false)
        }
        if discard {
            try? fileManager.removeItem(at: active.workURL)
            return end(.discarded, finalized: false)
        }
        guard case .written = result else {
            Notifier.failed(L10n.t(.recordingEmpty))
            return end(.empty, finalized: true)
        }

        guard RecordingRules.hasRoomToFinalize(freeBytes: Self.freeBytes(at: active.settings.outputFolder),
                                               workFileBytes: Self.fileSize(active.workURL)) else {
            Notifier.failed(L10n.t(.noRoomToFinalize) + " " + L10n.t(.workFileKept), file: active.workURL)
            return end(.keptWorkFile(active.workURL), finalized: false)
        }
        do {
            try await Finalizer.finalize(workFile: active.workURL, to: active.finalURL,
                                         keepSeparateTracks: active.settings.keepSeparateTracks)
        } catch {
            Notifier.failed(L10n.t(.finalizeFailed) + " " + L10n.t(.workFileKept), file: active.workURL)
            return end(.keptWorkFile(active.workURL), finalized: false)
        }
        try? fileManager.removeItem(at: active.workURL)
        Notifier.recordingStopped(reason: reason, url: active.finalURL)
        end(.saved(active.finalURL), finalized: true)
    }

    private func end(_ outcome: RecordingOutcome, finalized: Bool) {
        lastOutcome = outcome
        _ = machine.apply(finalized ? .finalized : .finalizeFailed)
    }

    /// Nothing usable is being recorded (video mode with no frame, or audio-only mode with no
    /// audio, within the limit): stop, keep no file, explain with `messageKey`.
    private func abandon(_ active: Active, messageKey: L10n.Key) async {
        _ = machine.apply(.stopRequested(.streamError))
        state = machine.state
        let task = Task { await self.finish(active, reason: .streamError, discard: true) }
        stopTask = task
        await task.value
        stopTask = nil
        startProblem = problem(for: .noFirstFrame, active.settings)
        Notifier.failed(L10n.t(messageKey))
    }

    private func failStart(_ problem: StartProblem) {
        _ = machine.apply(.startFailed)
        state = machine.state
        pendingStop = nil
        warnings = []
        startProblem = problem
        lastOutcome = .notStarted(problem)
        Notifier.failed(L10n.t(.startFailed) + ": " + L10n.t(problem.messageKey))
    }

    private func problem(for failure: StartFailure, _ s: Settings) -> StartProblem {
        RecordingRules.startProblem(for: failure, screenGranted: Permissions.screenGranted,
                                    microphoneWanted: s.microphone,
                                    microphoneAuthorized: Self.microphoneAccess == .authorized)
    }

    // MARK: System facts

    private static var microphoneAccess: MicrophoneAccess {
        switch Permissions.microphoneStatus {
        case .authorized: return .authorized
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }

    private static func freeBytes(at folder: URL) -> Int64? {
        Recovery.volumeFreeBytes(folder)
    }

    /// Current size of `url` in bytes; 0 if it does not exist (yet).
    private static func fileSize(_ url: URL) -> Int64 {
        ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.int64Value ?? 0
    }
}
