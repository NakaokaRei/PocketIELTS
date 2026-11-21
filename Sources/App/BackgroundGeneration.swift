import BackgroundTasks
import UIKit
import OSLog

/// Transport callbacks inherit the current generation job, without changing API credentials.
enum GenerationTransferProgress {
    @TaskLocal static var report: (@Sendable (Int) async -> Void)?

    static func received(_ bytes: Int) async {
        await report?(max(0, bytes))
    }
}

/// Owns a user-initiated job and its system lifetime. All lifetime and UI progress
/// mutations run on MainActor; URLSession still performs networking asynchronously.
@MainActor
final class BackgroundGeneration {
    private let identifier = "app.pocketielts.study.generation." + UUID().uuidString
    private let title: String
    private var total: Int
    private var sectionStarted = Date()
    private var progressTicker: Task<Void, Never>?
    private let onProgress: @MainActor (Double) -> Void
    private let completionDuration: Double
    private var completionStarted: Date?
    private var completionFrom = 0.0
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
    private var publishedPercent: Int?

    private init(title: String, total: Int, completionDuration: Double, onProgress: @escaping @MainActor (Double) -> Void) {
        self.onProgress = onProgress
        self.completionDuration = completionDuration
        self.title = title
        self.total = max(1, total)
    }

    static func run<T>(title: String, total: Int, useSystemScheduler: Bool = true,
                       completionDuration: Double = 0,
                       onProgress: @escaping @MainActor (Double) -> Void = { _ in },
                       operation: @escaping @MainActor (BackgroundGeneration) async throws -> T) async throws -> T {
        let job = BackgroundGeneration(title: title, total: total, completionDuration: completionDuration, onProgress: onProgress)
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                job.cancelBeforeStart = { continuation.resume(throwing: CancellationError()) }
                job.startWork = {
                    guard !job.finished, job.worker == nil else { return }
                    job.cancelBeforeStart = nil
                    job.sectionStarted = Date()
                    job.publishProgress()
                    job.progressTicker = Task { [weak job] in
                        while !Task.isCancelled {
                            do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
                            guard let job, !job.finished else { return }
                            job.publishProgress()
                        }
                    }
                    job.worker = Task {
                        do {
                            try Task.checkCancellation()
                            let value = try await GenerationTransferProgress.$report.withValue({ bytes in
                                await job.receiving(bytes: bytes)
                            }) { try await operation(job) }
                            try Task.checkCancellation()
                            job.update(completed: job.total, total: job.total)
                            if completionDuration > 0 {
                                try await Task.sleep(for: .seconds(completionDuration))
                                try Task.checkCancellation()
                                job.publishProgress()
                            }
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
        if useSystemScheduler, !ProcessInfo.processInfo.isiOSAppOnMac {
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
    private nonisolated static func submit(_ request: BGContinuedProcessingTaskRequest) async throws {
        #if compiler(>=6.4)
        if #available(iOS 27.0, *) {
            try await BGTaskScheduler.shared.submitTaskRequest(request)
            return
        }
        #endif
        try BGTaskScheduler.shared.submit(request)
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
        let prefix = fraction >= 1 ? "" : "≈"
        return "\(prefix)\(Int(fraction * 100))% · \(completed)/\(total) · \(receivedBytes / 1024) KB"
    }

    func receiving(bytes: Int) {
        guard !finished else { return }
        // Bytes are diagnostic only: payload size is not generation completion.
        receivedBytes = max(receivedBytes, bytes)
        publishProgress()
    }

    func update(completed: Int, total: Int) {
        guard !finished else { return }
        self.total = max(1, total)
        let next = min(self.total, max(self.completed, completed))
        if next > self.completed {
            sectionStarted = Date(); receivedBytes = 0
            if next == self.total {
                completionFrom = fraction
                completionStarted = Date()
            }
        }
        self.completed = next
        publishProgress()
    }

    private func publishProgress() {
        let value: Double
        if completed == total {
            let elapsed = Date().timeIntervalSince(completionStarted ?? Date())
            value = completionDuration > 0 ? GenerationProgress.finish(from: completionFrom, elapsed: elapsed * 0.8 / completionDuration) : 1
        } else {
            value = GenerationProgress.estimate(completed: completed, total: total, elapsed: Date().timeIntervalSince(sectionStarted))
        }
        fraction = max(fraction, value)
        onProgress(fraction)
        #if !targetEnvironment(macCatalyst)
        if let task = systemTask as? BGContinuedProcessingTask {
            let percent = Int(fraction * 100)
            guard publishedPercent != percent else { return }
            publishedPercent = percent
            task.progress.totalUnitCount = 100
            task.progress.completedUnitCount = Int64(percent)
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
        progressTicker?.cancel(); progressTicker = nil
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

// One prepared paper per section, shared by the section list and its loading screen.
@MainActor @Observable
final class SectionPreparation {
    static let shared = SectionPreparation()
    static let preference = "prepare-sections-in-advance"
    private let directory: URL
    private(set) var ready: [String: ExamUnit] = [:]
    private(set) var percent: [String: Int] = [:]
    private(set) var errors: [String: String] = [:]
    private var templates: [ExamUnit] = []
    private var automatic = false
    private var jobs: [String: Task<ExamUnit, Error>] = [:]
    private var automaticJobs = Set<String>()
    private var opened = Set<String>()

    private let generate: @MainActor (ExamUnit) async throws -> ExamUnit

    private static var cacheDirectory: URL {
        var root = URL.applicationSupportDirectory
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            root = URL.temporaryDirectory.appending(path: "SectionPreparation-UITests")
            if ProcessInfo.processInfo.arguments.contains("--ui-reset") { try? FileManager.default.removeItem(at: root) }
        }
        #endif
        return root.appending(path: "PreparedSections").appending(path: Bundle.main.preferredLocalizations.first ?? "en")
    }

    private static func generatePaper(_ template: ExamUnit) async throws -> ExamUnit {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            if ProcessInfo.processInfo.arguments.contains("--ui-generation-preview") { try await Task.sleep(for: .seconds(120)) }
            return template
        }
        #endif
        return try await StudyClient.generateUnit(like: template)
    }

    private convenience init() {
        self.init(directory: Self.cacheDirectory, generate: Self.generatePaper)
    }

    init(directory: URL, generate: @escaping @MainActor (ExamUnit) async throws -> ExamUnit) {
        self.directory = directory
        self.generate = generate
        for url in (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [] {
            if let data = try? Data(contentsOf: url), let unit = try? JSONDecoder().decode(ExamUnit.self, from: data) {
                ready[url.deletingPathExtension().lastPathComponent] = unit
            }
        }
    }

    func key(_ template: ExamUnit) -> String { template.id.replacingOccurrences(of: "/", with: "_") }

    func reset() throws {
        templates = []
        for job in jobs.values { job.cancel() }
        let allLanguages = directory.deletingLastPathComponent()
        if FileManager.default.fileExists(atPath: allLanguages.path) {
            try FileManager.default.removeItem(at: allLanguages)
        }
        ready.removeAll()
        errors.removeAll()
    }

    func configure(_ units: [ExamUnit], enabled: Bool, active: Bool) {
        templates = active ? units : []
        automatic = enabled
        if !enabled {
            for id in automaticJobs.subtracting(opened) { jobs[id]?.cancel() }
        }
        schedule()
    }

    private func schedule() {
        guard automatic else { return }
        for template in templates {
            let id = key(template)
            guard ready[id] == nil, errors[id] == nil, jobs[id] == nil else { continue }
            automaticJobs.insert(id)
            _ = start(template)
        }
    }

    func open(_ template: ExamUnit) async throws -> ExamUnit {
        let id = key(template)
        if let paper = ready[id] { return paper }
        opened.insert(id)
        defer { opened.remove(id) }
        return try await start(template).value
    }

    func leaveLoading(_ template: ExamUnit) {
        let id = key(template)
        if !automatic { jobs[id]?.cancel() }
    }

    func finished(_ template: ExamUnit, paper: ExamUnit) {
        let id = key(template)
        guard ready[id] == paper else { return }
        try? FileManager.default.removeItem(at: directory.appending(path: id + ".json"))
        ready[id] = nil
        schedule()
    }

    private func start(_ template: ExamUnit) -> Task<ExamUnit, Error> {
        let id = key(template)
        if let job = jobs[id] { return job }
        errors[id] = nil
        percent[id] = 0
        let job = Task<ExamUnit, Error> {
            defer {
                jobs[id] = nil
                percent[id] = nil
                automaticJobs.remove(id)
                schedule()
            }
            do {
                let unit = try await BackgroundGeneration.run(title: template.id, total: 1, useSystemScheduler: !automaticJobs.contains(id),
                    completionDuration: 0.8, onProgress: { fraction in
                        let value = Int(fraction * 100)
                        if self.percent[id] != value { self.percent[id] = value }
                    }) { _ in
                        try await self.generate(template)
                    }
                try Task.checkCancellation()
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try JSONEncoder().encode(unit).write(to: directory.appending(path: id + ".json"), options: .atomic)
                ready[id] = unit
                return unit
            } catch {
                if !Task.isCancelled {
                    errors[id] = error.localizedDescription
                }
                throw error
            }
        }
        jobs[id] = job
        return job
    }
}
