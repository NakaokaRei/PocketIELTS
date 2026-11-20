import BackgroundTasks
import UIKit
import OSLog

/// Transport callbacks inherit the current generation job, without changing API credentials.
enum GenerationTransferProgress {
    @TaskLocal static var report: (@Sendable (Double, Int) async -> Void)?

    static func received(_ bytes: Int, expected: Int? = nil, estimate: Double = 16000) async {
        guard let report else { return }
        let fraction = expected.map { Double(bytes) / Double(max(1, $0)) }
            ?? (1 - exp(-Double(max(0, bytes)) / estimate))
        await report(min(0.9, max(0, fraction) * 0.9), bytes)
    }
}

/// Owns a user-initiated job and its system lifetime. All lifetime and UI progress
/// mutations run on MainActor; URLSession still performs networking asynchronously.
@MainActor
final class BackgroundGeneration {
    private let identifier = "app.pocketielts.study.generation." + UUID().uuidString
    private let title: String
    private var total: Int
    private var partial = 0.0
    private var receivedBytes = 0
    private(set) var fraction = 0.0
    private let started = Date()
    private(set) var completed = 0
    private(set) var finished = false
    private var systemInterrupted = false
    private var worker: Task<Void, Never>?
    private var startWork: (() -> Void)?
    private var cancelBeforeStart: (() -> Void)?
    private var lease = UIBackgroundTaskIdentifier.invalid
    private var systemTask: BGTask?

    private init(title: String, total: Int) {
        self.title = title
        self.total = max(1, total)
    }

    static func run<T>(title: String, total: Int, useSystemScheduler: Bool = true,
                       operation: @escaping @MainActor (BackgroundGeneration) async throws -> T) async throws -> T {
        let job = BackgroundGeneration(title: title, total: total)
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                job.cancelBeforeStart = { continuation.resume(throwing: CancellationError()) }
                job.startWork = {
                    guard !job.finished, job.worker == nil else { return }
                    job.cancelBeforeStart = nil
                    job.worker = Task {
                        do {
                            try Task.checkCancellation()
                            let value = try await GenerationTransferProgress.$report.withValue({ fraction, bytes in
                                await job.receiving(fraction: fraction, bytes: bytes)
                            }) { try await operation(job) }
                            try Task.checkCancellation()
                            job.update(completed: job.total, total: job.total)
                            job.finish(success: true)
                            continuation.resume(returning: value)
                        } catch {
                            let failure: Error = job.systemInterrupted
                                ? StudyError.message(String(localized: "Generation was interrupted. Return to the app and retry; completed sections are kept.")) : error
                            job.finish(success: false)
                            continuation.resume(throwing: failure)
                        }
                    }
                }
                job.schedule(useSystemScheduler: useSystemScheduler)
            }
        } onCancel: {
            Task { @MainActor in job.cancel() }
        }
    }

    private func schedule(useSystemScheduler: Bool) {
        #if !targetEnvironment(macCatalyst) && !targetEnvironment(simulator)
        if #available(iOS 26.0, *), useSystemScheduler, !ProcessInfo.processInfo.isiOSAppOnMac {
            let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main) { [weak self] task in
                Task { @MainActor in
                    guard let self, !self.finished, let task = task as? BGContinuedProcessingTask else {
                        task.setTaskCompleted(success: false)
                        return
                    }
                    self.systemTask = task
                    task.expirationHandler = { [weak self] in
                        Task { @MainActor in self?.interrupt() }
                    }
                    self.update(completed: self.completed, total: self.total)
                    self.startWork?()
                    self.startWork = nil
                }
            }
            if registered {
                let request = BGContinuedProcessingTaskRequest(identifier: identifier, title: title, subtitle: progressLabel)
                request.strategy = .fail // Never queue paid API work for a later, unexpected start.
                Task { [weak self] in
                    guard let self, !self.finished else { return }
                    do { try await Self.submit(request) }
                    catch {
                        guard !self.finished else { return }
                        self.startWithShortLease(useSystemScheduler: useSystemScheduler)
                    }
                }
                return
            }
        }
        #endif
        startWithShortLease(useSystemScheduler: useSystemScheduler)
    }

    #if !targetEnvironment(macCatalyst)
    @available(iOS 26.0, *)
    private nonisolated static func submit(_ request: BGContinuedProcessingTaskRequest) async throws {
        if #available(iOS 27.0, *) {
            try await BGTaskScheduler.shared.submitTaskRequest(request)
        } else {
            try BGTaskScheduler.shared.submit(request)
        }
    }
    #endif

    private func startWithShortLease(useSystemScheduler: Bool) {
        guard !finished, worker == nil else { return }
        if useSystemScheduler {
            lease = UIApplication.shared.beginBackgroundTask(withName: title) { [weak self] in
                self?.interrupt()
            }
        }
        startWork?()
        startWork = nil
    }

    private var progressLabel: String {
        let prefix = completed == total ? "" : "≈"
        return "\(prefix)\(Int(fraction * 100))% · \(completed)/\(total) · \(receivedBytes / 1024) KB"
    }

    func receiving(fraction: Double, bytes: Int) {
        guard !finished else { return }
        partial = max(partial, min(0.9, max(0, fraction)))
        receivedBytes = max(receivedBytes, bytes)
        publishProgress()
    }

    func update(completed: Int, total: Int) {
        guard !finished else { return }
        self.total = max(1, total)
        let next = min(self.total, max(self.completed, completed))
        if next > self.completed { partial = 0; receivedBytes = 0 }
        self.completed = next
        publishProgress()
    }

    private func publishProgress() {
        fraction = max(fraction, min(1, (Double(completed) + partial) / Double(total)))
        #if !targetEnvironment(macCatalyst)
        if #available(iOS 26.0, *), let task = systemTask as? BGContinuedProcessingTask {
            task.progress.totalUnitCount = 100000
            task.progress.completedUnitCount = Int64(fraction * 100000)
            task.updateTitle(title, subtitle: progressLabel)
        }
        #endif
    }

    /// Shared by expiration and the system Live Activity's cancel action.
    func interrupt() {
        guard !finished else { return }
        Logger(subsystem: "app.pocketielts.study", category: "Generation").warning("System expiration/cancellation after \(Date().timeIntervalSince(self.started))s; completed=\(self.completed), receivedBytes=\(self.receivedBytes), appState=\(UIApplication.shared.applicationState.rawValue)")
        systemInterrupted = true
        cancel()
        // Release the system assertion immediately, even if a dependency ignores cancellation.
        finish(success: false)
    }

    private func cancel() {
        guard !finished else { return }
        worker?.cancel()
        if worker == nil {
            let resume = cancelBeforeStart
            cancelBeforeStart = nil
            finish(success: false)
            resume?()
        }
    }

    private func finish(success: Bool) {
        guard !finished else { return }
        finished = true
        startWork = nil
        cancelBeforeStart = nil
        systemTask?.setTaskCompleted(success: success)
        systemTask = nil
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
        if lease != .invalid {
            UIApplication.shared.endBackgroundTask(lease)
            lease = .invalid
        }
        worker = nil
    }
}
