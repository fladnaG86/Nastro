import AppKit
import Foundation
import NastroCore
import NastroTranscribe
import UniformTypeIdentifiers

/// Runs one "transcribe and summarize" job at a time on a recording the user picks, publishes
/// its phase for the menu and notifies the outcome. A recording started meanwhile does not stop
/// the job.
@MainActor
final class SummaryController: ObservableObject {
    /// The recording's file name and the job's current phase; nil when no job runs.
    @Published private(set) var running: (name: String, phase: SummaryPhase)?
    private var task: Task<Void, Never>?
    /// Identifies the current job, so late phase updates of a finished one are dropped.
    private var job = UUID()

    static var isAvailable: Bool {
        if #available(macOS 26, *) { return true }
        return false
    }

    /// Asks for a recording in `folder`, then runs the job in the background.
    /// The picker opens on the next main-runloop turn, after the menu bar panel has closed; the
    /// job starts only if `canStart` still holds once a file is chosen (e.g. recorder idle).
    func chooseAndRun(folder: URL, canStart: @escaping @MainActor () -> Bool) {
        guard running == nil, Self.isAvailable else { return }
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.presentPicker(folder: folder, canStart: canStart) }
        }
    }

    private func presentPicker(folder: URL, canStart: @MainActor () -> Bool) {
        guard running == nil else { return }
        let panel = NSOpenPanel()
        panel.directoryURL = folder
        panel.allowedContentTypes = [.mpeg4Movie, .mpeg4Audio]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        NSApp.activate()
        guard panel.runModal() == .OK, let recording = panel.url else { return }
        guard running == nil, canStart() else { return }
        run(recording)
    }

    func cancel() {
        task?.cancel()
    }

    private func run(_ recording: URL) {
        guard #available(macOS 26, *) else { return }
        let id = UUID()
        job = id
        running = (recording.lastPathComponent, .preparing)
        let pipeline = SummaryPipeline.live()
        task = Task(priority: .utility) { [weak self] in
            let outcome: Result<SummaryResult, SummaryError>
            do {
                let result = try await pipeline.run(recording: recording, phase: { phase in
                    Task { @MainActor in self?.show(phase, job: id) }
                })
                outcome = .success(result)
            } catch let error as SummaryError {
                outcome = .failure(error)
            } catch {
                // The pipeline throws only SummaryError; anything else is treated as a cancel.
                outcome = .failure(.cancelled)
            }
            self?.finish(outcome, job: id)
        }
    }

    /// Only republishes when the shown text changes (transcription progress arrives often).
    private func show(_ phase: SummaryPhase, job id: UUID) {
        guard id == job, let current = running else { return }
        guard SummaryMessages.phaseText(phase) != SummaryMessages.phaseText(current.phase) else { return }
        running = (current.name, phase)
    }

    private func finish(_ outcome: Result<SummaryResult, SummaryError>, job id: UUID) {
        guard id == job else { return }
        running = nil
        task = nil
        switch outcome {
        case .success(let result):
            if let summary = result.summary {
                Notifier.summaryReady(summary)
            } else if let failure = result.failure {
                let detail = SummaryMessages.text(failure).map { "\n" + $0 } ?? ""
                Notifier.summaryFailed(L10n.t(.transcriptSavedSummaryFailed) + detail, transcript: result.transcript)
            }
        case .failure(let error):
            if let text = SummaryMessages.text(error) { Notifier.summaryFailed(text, transcript: nil) }
        }
    }
}

@available(macOS 26, *)
extension SummaryPipeline {
    /// The real pipeline: Italian speech model and the LLM in the saved settings with the saved key.
    static func live(settings: SummarySettings = SummarySettingsStore(defaults: .standard).load()) -> SummaryPipeline {
        SummaryPipeline(
            transcriber: SpeechTranscriberEngine(),
            chat: OpenAIChatClient(settings: settings, apiKey: APIKeyStore.read()),
            prepare: { try await SpeechTranscriberEngine.prepareModel() })
    }
}
