import CloudKit
import ComposableArchitecture
import CryptoKit
import SwiftUI

/// A record-level journal: unrelated offline additions are unioned, never replaced by a snapshot.
struct CloudStudyItem: Codable, Equatable {
    var key: String
    var kind: String
    var payload: Data
    var modified: Date
    var revision: String
    var recording: String?

    func wins(over other: Self) -> Bool {
        modified == other.modified ? revision > other.revision : modified > other.modified
    }
}

struct DeletedExpression: Codable, Equatable {
    var id: UUID
    var date: Date
}

struct CloudStudySnapshot: Equatable {
    var deletedVocabulary: [DeletedExpression]
    var vocabulary: [SavedExpression]
    var results: [StudyResult]
    var papers: [ExamUnit]

    init(state: StudyFeature.State) {
        deletedVocabulary = state.deletedVocabulary
        vocabulary = state.vocabulary; results = state.records; papers = state.papers
    }
    init(vocabulary: [SavedExpression] = [], results: [StudyResult] = [], papers: [ExamUnit] = [], deletedVocabulary: [DeletedExpression] = []) {
        self.deletedVocabulary = deletedVocabulary
        self.vocabulary = vocabulary; self.results = results; self.papers = papers
    }
    func items(at date: Date) throws -> [CloudStudyItem] {
        func item<T: Encodable>(_ kind: String, _ id: String, _ value: T, recording: String? = nil) throws -> CloudStudyItem {
            let key = kind + "-" + SHA256.hash(data: Data(id.utf8)).map { String(format: "%02x", $0) }.joined()
            return try .init(key: key, kind: kind, payload: StudyPersistence.encode(value), modified: date, revision: UUID().uuidString, recording: recording)
        }
        let tombstones = try deletedVocabulary.map { deleted -> CloudStudyItem in
            var value = try item("word", deleted.id.uuidString, deleted)
            value.kind = "deletedWord"; value.modified = deleted.date
            return value
        }
        return try tombstones + vocabulary.map { try item("word", $0.id.uuidString, $0) }
            + results.map { try item("result", $0.id.uuidString, $0, recording: $0.recordingFile) }
            + papers.map { try item("paper", $0.id, $0) }
    }
}

struct CloudStudyJournal: Codable {
    var items: [String: CloudStudyItem] = [:]
    var account: String?

    mutating func capture(_ snapshot: CloudStudySnapshot, at date: Date = Date()) throws {
        for item in try snapshot.items(at: date) where items[item.key]?.payload != item.payload {
            items[item.key] = item
        }
    }
    mutating func merge(_ remote: [CloudStudyItem]) {
        for item in remote {
            if let local = items[item.key], !item.wins(over: local) { continue }
            items[item.key] = item
        }
    }
    func snapshot() throws -> CloudStudySnapshot {
        let sorted = items.values.sorted { $0.modified == $1.modified ? $0.key < $1.key : $0.modified > $1.modified }
        let decoder = JSONDecoder()
        return try .init(
            vocabulary: sorted.filter { $0.kind == "word" }.map { try decoder.decode(SavedExpression.self, from: $0.payload) },
            results: sorted.filter { $0.kind == "result" }.map { try decoder.decode(StudyResult.self, from: $0.payload) }.sorted { $0.date > $1.date },
            papers: sorted.filter { $0.kind == "paper" }.map { try decoder.decode(ExamUnit.self, from: $0.payload) },
            deletedVocabulary: sorted.filter { $0.kind == "deletedWord" }.map { try decoder.decode(DeletedExpression.self, from: $0.payload) })
    }
    static func accepts(account: String, previous: String?) -> Bool { previous == nil || previous == account }
    static func safeRecordingURL(_ name: String, directory: URL) -> URL? {
        guard name == (name as NSString).lastPathComponent, !name.hasPrefix("."), name.hasSuffix(".m4a") else { return nil }
        return directory.appendingPathComponent(name)
    }
}

/// Main-actor ownership protects the UI store and journal across network suspension points.
@MainActor @Observable
final class StudyCloudSync {
    static let containerIdentifier = "iCloud.app.pocketielts.study"
    var status = String(localized: "同期を準備中")
    var syncing = false
    var lastSynced: Date?
    var enabled: Bool {
        didSet { defaults.set(enabled, forKey: "iCloudSyncEnabled"); if !enabled { status = String(localized: "同期はオフです") } }
    }
    private let defaults: UserDefaults
    private let store: StoreOf<StudyFeature>
    private var journal: CloudStudyJournal
    private let isTesting: Bool
    private let journalKey = "iCloudStudyJournal.v1"
    // Lazily create CloudKit only when needed, so previews and isolated tests require no entitlement.
    @ObservationIgnored private lazy var container = CKContainer(identifier: StudyCloudSync.containerIdentifier)
    private let zone = CKRecordZone.ID(zoneName: "PocketIELTSStudy")

    init(store: StoreOf<StudyFeature>, defaults: UserDefaults = .standard, isTesting: Bool = false) {
        self.store = store; self.defaults = defaults; self.isTesting = isTesting
        enabled = defaults.object(forKey: "iCloudSyncEnabled") as? Bool ?? true
        journal = defaults.data(forKey: "iCloudStudyJournal.v1").flatMap { try? JSONDecoder().decode(CloudStudyJournal.self, from: $0) } ?? .init()
        lastSynced = defaults.object(forKey: "iCloudLastSynced") as? Date
        if isTesting { status = String(localized: "テスト環境・端末内に保存") }
    }
    func captureLocalChanges() {
        guard !isTesting else { return }
        do {
            try journal.capture(CloudStudySnapshot(vocabulary: store.vocabulary, results: store.records, papers: store.papers, deletedVocabulary: store.deletedVocabulary))
            try persist()
        } catch { status = String(localized: "同期用データを保存できませんでした。端末の空き容量を確認してください。") }
    }
    private func persist() throws { defaults.set(try StudyPersistence.encode(journal), forKey: journalKey) }

    func sync() async {
        guard enabled, !syncing, !isTesting else { return }
        syncing = true; status = String(localized: "iCloudと同期中…")
        defer { syncing = false }
        do {
            captureLocalChanges()
            guard try await container.accountStatus() == .available else {
                status = String(localized: "iCloudにサインインしてください。データはこの端末に保存されています。"); return
            }
            let account = try await container.userRecordID().recordName
            guard CloudStudyJournal.accepts(account: account, previous: journal.account) else {
                status = String(localized: "Apple Accountが変更されています。元のアカウントに戻すまで同期を停止します。"); return
            }
            journal.account = account; try persist()
            let database = container.privateCloudDatabase
            _ = try await database.save(CKRecordZone(zoneID: zone))
            var records: [String: CKRecord] = [:]
            var remote: [CloudStudyItem] = []
            var token: CKServerChangeToken?
            // A full, paginated zone read avoids query indexes and preserves unknown newer record types.
            repeat {
                let page = try await database.recordZoneChanges(inZoneWith: zone, since: token, desiredKeys: ["payload"])
                for (_, result) in page.modificationResultsByID {
                    let record = try result.get().record
                    guard record.recordType == "StudyItem", let data = record["payload"] as? Data else { continue }
                    let item = try JSONDecoder().decode(CloudStudyItem.self, from: data)
                    guard item.key == record.recordID.recordName else { continue }
                    if let name = item.recording,
                       let destination = CloudStudyJournal.safeRecordingURL(name, directory: SpeakingRecorder.archiveDirectory),
                       !FileManager.default.fileExists(atPath: destination.path) {
                        let withAudio = try await database.record(for: record.recordID)
                        if let asset = withAudio["audio"] as? CKAsset, let source = asset.fileURL {
                            try FileManager.default.createDirectory(at: SpeakingRecorder.archiveDirectory, withIntermediateDirectories: true)
                            try FileManager.default.copyItem(at: source, to: destination)
                        }
                    }
                    records[item.key] = record; remote.append(item)
                }
                token = page.changeToken
                if !page.moreComing { break }
                try Task.checkCancellation()
            } while true
            try Task.checkCancellation()
            guard enabled, try await container.userRecordID().recordName == account else { return }
            // Capture edits made while downloading before resolving individual record versions.
            captureLocalChanges()
            journal.merge(remote)
            try persist()
            store.send(.applyCloudSnapshot(try journal.snapshot()))
            let remoteVersions = remote.reduce(into: [String: String]()) { $0[$1.key] = $1.revision }
            let pending = journal.items.values.filter { remoteVersions[$0.key] != $0.revision }
            for item in pending {
                try Task.checkCancellation()
                guard enabled else { return }
                let record = records[item.key] ?? CKRecord(recordType: "StudyItem", recordID: .init(recordName: item.key, zoneID: zone))
                record["payload"] = try StudyPersistence.encode(item) as CKRecordValue
                if let name = item.recording,
                   let url = CloudStudyJournal.safeRecordingURL(name, directory: SpeakingRecorder.archiveDirectory),
                   FileManager.default.fileExists(atPath: url.path) { record["audio"] = CKAsset(fileURL: url) }
                // A concurrent server edit fails safely; the next sync fetches and merges it.
                let result = try await database.modifyRecords(saving: [record], deleting: [], savePolicy: .ifServerRecordUnchanged, atomically: true)
                for saved in result.saveResults.values { _ = try saved.get() }
            }
            lastSynced = Date(); defaults.set(lastSynced, forKey: "iCloudLastSynced")
            status = String(localized: "iCloudと同期しました")
        } catch is CancellationError {
            status = String(localized: "次回の起動時に同期を再開します")
        } catch {
            if let cloud = error as? CKError, cloud.code == .notAuthenticated {
                status = String(localized: "iCloudにサインインしてください。データは端末に保存済みです。")
            } else {
                status = String(localized: "同期を完了できませんでした。接続・iCloud設定を確認して再試行してください。\n") + error.localizedDescription
            }
        }
    }
}

private struct StudyCloudKey: EnvironmentKey { static let defaultValue: StudyCloudSync? = nil }
extension EnvironmentValues {
    var studyCloud: StudyCloudSync? {
        get { self[StudyCloudKey.self] }
        set { self[StudyCloudKey.self] = newValue }
    }
}

struct StudyCloudHost: View {
    let store: StoreOf<StudyFeature>
    @State private var cloud: StudyCloudSync
    @Environment(\.scenePhase) private var phase
    init(store: StoreOf<StudyFeature>) {
        self.store = store
        _cloud = State(initialValue: StudyCloudSync(store: store, isTesting: ProcessInfo.processInfo.arguments.contains("--ui-testing") || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil))
    }
    var body: some View {
        HomeScreen(store: store).environment(\.studyCloud, cloud)
            .onChange(of: CloudStudySnapshot(vocabulary: store.vocabulary, results: store.records, papers: store.papers, deletedVocabulary: store.deletedVocabulary)) { _, _ in cloud.captureLocalChanges() }
            .task(id: phase) {
                guard phase == .active else { cloud.captureLocalChanges(); return }
                while !Task.isCancelled {
                    await cloud.sync()
                    do { try await Task.sleep(for: .seconds(30)) } catch { return }
                }
            }
    }
}
