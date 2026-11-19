import Foundation
import NastroCore
import NastroTranscribe

/// `Nastro --probe-summarize <file>` runs the whole `SummaryPipeline` from the terminal: Italian
/// speech model, transcript (reused when already there), summary from the LLM in the saved
/// settings. Prints each phase change with elapsed seconds, then both paths, or the summary
/// failure (transcript kept, exit 2). A thrown error prints it and exits 1.
enum ProbeSummarize {
    static func run(_ arguments: [String]) -> Never {
        guard let path = arguments.first else {
            print("usage: Nastro --probe-summarize <file>")
            exit(1)
        }
        guard #available(macOS 26, *) else {
            print("PROBE-SUMMARIZE failed requires macOS 26")
            exit(1)
        }
        let recording = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        Task {
            do {
                exit(try await summarize(recording))
            } catch {
                print("PROBE-SUMMARIZE failed \(error)")
                exit(1)
            }
        }
        dispatchMain()
    }

    @available(macOS 26, *)
    private static func summarize(_ recording: URL) async throws -> Int32 {
        let settings = SummarySettingsStore(defaults: .standard).load()
        print("LLM \(settings.baseURL) model \(settings.model)")
        let pipeline = SummaryPipeline.live(settings: settings)
        let started = Date()
        let printer = PhasePrinter(started: started)
        let result = try await pipeline.run(recording: recording, phase: { printer.show($0) })
        let elapsed = String(format: "%.1f", Date().timeIntervalSince(started))
        print("transcript \(result.transcript.path)")
        if let summary = result.summary {
            print("summary \(summary.path)")
            print("PROBE-SUMMARIZE ok \(elapsed) s elapsed")
            return 0
        }
        print("PROBE-SUMMARIZE summary failed \(result.failure.map { "\($0)" } ?? "unknown"), \(elapsed) s elapsed")
        return 2
    }
}

/// Prints a phase when it changes; transcription progress only in 10 % steps.
private final class PhasePrinter: @unchecked Sendable {
    private let lock = NSLock()
    private let started: Date
    private var last: String?

    init(started: Date) { self.started = started }

    func show(_ phase: SummaryPhase) {
        let line: String
        switch phase {
        case .preparing: line = "preparing"
        case .transcribing(let fraction): line = "transcribing \(Int(fraction * 10) * 10)%"
        case .summarizing(let part, let total): line = "summarizing \(part)/\(total)"
        }
        lock.lock(); defer { lock.unlock() }
        guard line != last else { return }
        last = line
        print("[\(String(format: "%6.1f", Date().timeIntervalSince(started))) s] \(line)")
    }
}
