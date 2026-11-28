import AVFoundation
import CryptoKit
import SwiftUI

/// Personal API credentials never enter study snapshots or iCloud.
enum SpeechCredentials {
    static let account = "listening-audio-api"
}

enum SpeechAudio {
    static let preparationPreference = "prepare-listening-audio"
    static let model = "gpt-4o-mini-tts"
    static let voice = "marin"
    private static let announcerVoice = "nova"
    // The role label also keys the cached announcement and the assembled practice track.
    static let announcementPrefix = "Test announcer (\(announcerVoice)): "
    static let instructions = "Read this IELTS listening script exactly, in clear natural British English at a measured conversational pace. Use natural pauses and distinct intonation for dialogue. Do not add commentary."

    /// Keep requests below the API character limit, preserving all whitespace and text.
    static func chunks(_ text: String, limit: Int = 2800) -> [String] {
        guard limit > 0 else { return [] }
        var remaining = text[...]
        var result: [String] = []
        while !remaining.isEmpty {
            let end = remaining.index(remaining.startIndex, offsetBy: min(limit, remaining.count))
            let prefix = remaining[..<end]
            let boundary = end == remaining.endIndex ? end : prefix.lastIndex(where: { $0.isWhitespace }).map { remaining.index(after: $0) } ?? end
            result.append(String(remaining[..<boundary]))
            remaining = remaining[boundary...]
        }
        return result
    }

    struct Segment: Equatable {
        let text: String
        let voice: String
        let speaker: String?
        let accent: String
        let legacyVoice: String
    }

    /// Labels are metadata, never spoken input. A voice stays stable across turns.
    static func segments(_ script: String) -> [Segment] {
        if script.hasPrefix(announcementPrefix) {
            return chunks(String(script.dropFirst(announcementPrefix.count))).map {
                Segment(text: $0, voice: announcerVoice, speaker: "Test announcer", accent: "British", legacyVoice: announcerVoice)
            }
        }
        let pattern = #"^\s*(?:\*\*)?([A-Za-z][A-Za-z0-9 .’'()_-]{0,39}?)(?:\*\*)?\s*[:：]\s*(?:\*\*)?\s*(.*)$"#
        let regex = try! NSRegularExpression(pattern: pattern)
        let lines = script.components(separatedBy: .newlines)
        let ignored = Set(["note", "notes", "time", "answer", "example", "important", "instructions"])
        func label(_ line: String) -> (String, String)? {
            let ns = line as NSString
            guard let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { return nil }
            let name = ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
            guard !ignored.contains(name.lowercased()) else { return nil }
            return (name, ns.substring(with: match.range(at: 2)))
        }
        let labels = lines.compactMap(label)
        let counts = Dictionary(labels.map { ($0.0.lowercased(), 1) }, uniquingKeysWith: +)
        let roles = Set(["narrator", "speaker", "lecturer", "guide", "receptionist", "caller", "student", "tutor", "man", "woman", "interviewer", "test announcer"])
        var speakers: [String: Int] = [:]
        let seed = Array(SHA256.hash(data: Data(script.utf8)))
        let accents = ["British", "Australian", "New Zealand", "North American"]
        let palette = ["marin", "cedar", "coral", "ash", "sage", "verse", "ballad", "onyx"]
        var turns: [(String?, String)] = []
        for line in lines {
            if let (name, words) = label(line), counts.count > 1 || counts[name.lowercased(), default: 0] > 1 || roles.contains(name.lowercased()) {
                turns.append((name, words))
            } else if !turns.isEmpty {
                turns[turns.count - 1].1 += "\n" + line
            } else if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                turns.append((nil, line))
            }
        }
        return turns.flatMap { speaker, words -> [Segment] in
            let key = speaker?.lowercased() ?? "narrator"
            let index = speakers[key] ?? speakers.count
            speakers[key] = index
            let voice = key == "test announcer" ? "cedar" : palette[(Int(seed[0]) + index) % palette.count]
            let accent = key == "test announcer" ? "British" : accents[(Int(seed[1]) + index) % accents.count]
            return chunks(words.trimmingCharacters(in: .whitespacesAndNewlines)).map {
                Segment(text: $0, voice: voice, speaker: speaker, accent: accent, legacyVoice: palette[index % palette.count])
            }
        }
    }

    static func request(text: String, key: String, voice: String = SpeechAudio.voice, accent: String = "British") throws -> URLRequest {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/speech")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["model": model, "voice": voice, "instructions": instructions.replacingOccurrences(of: "British", with: accent), "input": text, "response_format": "pcm"])
        return request
    }

    static func validate(_ response: URLResponse, data: Data) throws {
        switch (response as? HTTPURLResponse)?.statusCode {
        case 200:
            guard !data.isEmpty, data.count.isMultiple(of: 2), response.mimeType?.contains("json") != true else { throw StudyError.message(String(localized: "音声データを読み込めませんでした。")) }
        case 401, 403: throw StudyError.message(String(localized: "音声APIキーと利用権限を設定で確認してください。"))
        case 429: throw StudyError.message(String(localized: "音声APIの利用枠または残高を確認してください。"))
        default: throw StudyError.message(String(localized: "音声を生成できませんでした。時間をおいて再試行してください。"))
        }
    }

    static func wave(_ pcm: Data, previewStartFrame: UInt32? = nil) -> Data {
        var data = Data("RIFF".utf8)
        func number<T: FixedWidthInteger>(_ value: T) { var little = value.littleEndian; withUnsafeBytes(of: &little) { data.append(contentsOf: $0) } }
        number(UInt32(pcm.count + 36 + (previewStartFrame == nil ? 0 : 36))); data.append(Data("WAVEfmt ".utf8))
        number(UInt32(16)); number(UInt16(1)); number(UInt16(1)); number(UInt32(24000)); number(UInt32(48000)); number(UInt16(2)); number(UInt16(16))
        if let frame = previewStartFrame {
            // RIFF cue point in sample frames, so seeking and the countdown use the same file.
            data.append(Data("cue ".utf8)); number(UInt32(28)); number(UInt32(1))
            number(UInt32(1)); number(frame); data.append(Data("data".utf8))
            number(UInt32(0)); number(UInt32(0)); number(frame)
        }
        data.append(Data("data".utf8)); number(UInt32(pcm.count)); data.append(pcm)
        return data
    }

    static var cacheDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("ListeningAudio", isDirectory: true)
    }

    static func segmentURL(_ part: Segment, directory: URL, legacy: Bool = false) -> URL {
        let profile = legacy ? part.legacyVoice + instructions : part.voice + instructions.replacingOccurrences(of: "British", with: part.accent)
        let hash = SHA256.hash(data: Data(("dialogue-v1" + model + profile + part.text).utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(hash + ".pcm")
    }

    static func completeURL(_ script: String, directory: URL) -> URL {
        let hash = SHA256.hash(data: Data(("complete-dialogue-v1" + model + instructions + script).utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(hash + ".wav")
    }

    static let gapBytes = 7200  // 150 ms of 24 kHz mono Int16 PCM.
    static let bytesPerSecond = 48000.0

    private static func usesLegacySegments(_ parts: [Segment], directory: URL) -> Bool {
        !parts.allSatisfy { FileManager.default.fileExists(atPath: segmentURL($0, directory: directory).path) } &&
        parts.allSatisfy { FileManager.default.fileExists(atPath: segmentURL($0, directory: directory, legacy: true).path) }
    }

    static func startTimes(_ script: String, parts: [Segment], directory: URL = cacheDirectory) -> [Double]? {
        let url = completeURL(script, directory: directory).appendingPathExtension("cues")
        if let data = try? Data(contentsOf: url),
           let times = try? JSONDecoder().decode([Double].self, from: data),
           times.count == parts.count, times.first == 0,
           zip(times, times.dropFirst()).allSatisfy({ $0 < $1 }) { return times }

        let legacy = usesLegacySegments(parts, directory: directory)
        var bytes = 0
        var times = [Double]()
        for part in parts {
            times.append(Double(bytes) / bytesPerSecond)
            guard let size = try? segmentURL(part, directory: directory, legacy: legacy).resourceValues(forKeys: [.fileSizeKey]).fileSize,
                  size > 0, size.isMultiple(of: 2) else { return nil }
            bytes += size + gapBytes
        }
        if !times.isEmpty { try? JSONEncoder().encode(times).write(to: url, options: .atomic) }
        return times
    }

    /// Also upgrades previously cached PCM segments without an API request or generation UI.
    static func cachedAudioURL(_ script: String, directory: URL = cacheDirectory) -> URL? {
        let complete = completeURL(script, directory: directory)
        if (try? AVAudioPlayer(contentsOf: complete)) != nil { return complete }
        let parts = segments(script)
        guard !parts.isEmpty else { return nil }
        let legacy = usesLegacySegments(parts, directory: directory)
        var pcm = Data()
        for (index, part) in parts.enumerated() {
            guard let data = try? Data(contentsOf: segmentURL(part, directory: directory, legacy: legacy)),
                  !data.isEmpty, data.count.isMultiple(of: 2) else { return nil }
            pcm.append(data)
            if index + 1 < parts.count { pcm.append(Data(repeating: 0, count: gapBytes)) }
        }
        do {
            try wave(pcm).write(to: complete, options: .atomic)
            return complete
        } catch { return nil }
    }

    static func prepare(for paper: ExamUnit, enabled: Bool = UserDefaults.standard.bool(forKey: preparationPreference),
                        directory: URL = cacheDirectory,
                        generateAudio: (String, @escaping @MainActor (Int, Int) -> Void) async throws -> Data = generate) async throws -> ExamUnit {
        guard enabled, paper.skill == "Listening", let script = paper.audio,
              !script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return paper }
        var prepared = paper
        do {
            if let preview = ListeningPreview(part: paper) {
                _ = try await preview.recording(for: script, directory: directory, generate: generateAudio) { _, _ in }
            } else if cachedAudioURL(script, directory: directory) == nil {
                _ = try await generateAudio(script) { _, _ in }
            }
            try Task.checkCancellation()
        } catch {
            if error is CancellationError { throw error }
            try Task.checkCancellation()
            prepared.audioPreparationFailed = true
        }
        return prepared
    }

    static func generate(_ text: String, progress: @escaping @MainActor (Int, Int) -> Void) async throws -> Data {
        let directory = cacheDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var pcm = Data()
        var times = [Double]()
        let parts = segments(text)
        await progress(0, parts.count)
        for (index, part) in parts.enumerated() {
            try Task.checkCancellation()
            times.append(Double(pcm.count) / bytesPerSecond)
            let url = segmentURL(part, directory: directory)
            if let cached = try? Data(contentsOf: url), !cached.isEmpty, cached.count.isMultiple(of: 2) {
                pcm.append(cached)
            } else {
                guard let key = try KeyStore.read(account: SpeechCredentials.account), !key.isEmpty else { throw StudyError.message(String(localized: "設定で音声生成用のAPIキーを登録してください。")) }
                let (stream, response) = try await URLSession.shared.bytes(for: request(text: part.text, key: key, voice: part.voice, accent: part.accent))
                var data = Data()
                for try await byte in stream {
                    data.append(byte)
                    if data.count.isMultiple(of: 8192) {
                        try Task.checkCancellation()
                        await GenerationTransferProgress.received(data.count)
                    }
                }
                try Task.checkCancellation()
                try validate(response, data: data)
                try data.write(to: url, options: .atomic)
                pcm.append(data)
            }
            if index + 1 < parts.count { pcm.append(Data(repeating: 0, count: gapBytes)) } // 150 ms between turns.
            await progress(index + 1, parts.count)
        }
        guard !pcm.isEmpty else { throw StudyError.message(String(localized: "音声データを読み込めませんでした。")) }
        let result = wave(pcm)
        let url = completeURL(text, directory: directory)
        try result.write(to: url, options: .atomic)
        try JSONEncoder().encode(times).write(to: url.appendingPathExtension("cues"), options: .atomic)
        return result
    }
}

/// Choose a break between answer-bearing turns, preferring a change of task near the middle.
struct ListeningPreview {
    let row: Int?
    let fraction: Double
    let questions: ClosedRange<Int>?
    static let seconds = 30
    private static let leadInSeconds = 2

    init?(part: ExamUnit) {
        guard ["Listening / Part 1", "Listening / Part 2", "Listening / Part 3"].contains(part.id.components(separatedBy: " · ")[0]),
              part.questions.count >= 2, let transcript = ListeningTranscript(part: part) else { return nil }
        let first = part.firstQuestionNumber
        let count = part.questions.count
        let rows = (0..<count).map { transcript.evidence[first + $0] }
        let candidates = (1..<count).filter { index in
            guard let previous = rows[index - 1], let next = rows[index], previous < next else { return false }
            return rows[..<index].compactMap { $0 }.allSatisfy { $0 < next } &&
                   rows[index...].compactMap { $0 }.allSatisfy { $0 >= next }
        }
        let split = candidates.min { a, b in
            func cost(_ i: Int) -> Int {
                abs(2 * i - count) + (part.questions[i-1].instruction == part.questions[i].instruction ? 3 : 0)
            }
            return cost(a) < cost(b)
        }
        // Old saved recordings may lack evidence or timestamp metadata.
        let boundary = split.flatMap { rows[$0] } ?? transcript.rows.count / 2
        row = boundary > 0 ? boundary : nil
        let lengths = transcript.rows.map { max(1, $0.text.count) }
        fraction = boundary > 0 ? Double(lengths.prefix(boundary).reduce(0, +)) / Double(lengths.reduce(0, +)) : 0.5
        questions = split.map { (first + $0)...(first + count - 1) }
    }
    var announcement: String {
        let target = questions.map { "questions \($0.lowerBound) to \($0.upperBound)" } ?? "the next questions"
        return SpeechAudio.announcementPrefix + "You now have thirty seconds to look at \(target) and check your answers."
    }

    private func trackURL(_ script: String, directory: URL) -> URL {
        SpeechAudio.completeURL("practice-v2\n\(Self.leadInSeconds) \(Self.seconds)\n\(row ?? -1) \(fraction)\n\(announcement)\n\(script)", directory: directory)
    }

    func cachedTrack(_ script: String, directory: URL) -> (url: URL, silence: Range<Double>)? {
        let url = trackURL(script, directory: directory)
        guard let file = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? file.close() }
        guard let header = try? file.read(upToCount: 80), header.count == 80,
              header[36..<40] == Data("cue ".utf8), header[72..<76] == Data("data".utf8) else { return nil }
        let frame = header.withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: 68, as: UInt32.self)) }
        let start = Double(frame) / 24000
        return (url, start..<(start + Double(Self.seconds)))
    }

    /// Source and announcer WAVs use SpeechAudio.wave's 44-byte header and 24 kHz mono Int16 PCM.
    func recording(for script: String, directory: URL,
                   generate: (String, @escaping @MainActor (Int, Int) -> Void) async throws -> Data,
                   progress: @escaping @MainActor (Int, Int) -> Void) async throws -> Data {
        if let track = cachedTrack(script, directory: directory),
           let data = try? Data(contentsOf: track.url), (try? AVAudioPlayer(data: data)) != nil { return data }
        let parts = SpeechAudio.segments(script)
        let total = parts.count + 1
        let source: Data
        if let url = SpeechAudio.cachedAudioURL(script, directory: directory) {
            source = try Data(contentsOf: url)
        } else {
            source = try await generate(script) { done, _ in progress(done, total) }
        }
        try Task.checkCancellation()
        await progress(parts.count, total)
        let cue: Data
        if let url = SpeechAudio.cachedAudioURL(announcement, directory: directory) {
            cue = try Data(contentsOf: url)
        } else {
            cue = try await generate(announcement) { _, _ in }
        }
        try Task.checkCancellation()
        guard source.count > 44, cue.count > 44, source.count.isMultiple(of: 2), cue.count.isMultiple(of: 2),
              source[36..<40] == Data("data".utf8), cue[36..<40] == Data("data".utf8) else {
            throw StudyError.message(String(localized: "音声データを読み込めませんでした。"))
        }
        let rate = SpeechAudio.bytesPerSecond
        let times = SpeechAudio.startTimes(script, parts: parts, directory: directory)
        let duration = Double(source.count - 44) / rate
        let boundary = row.flatMap { index in times.flatMap { $0.indices.contains(index) ? $0[index] : nil } } ?? duration * fraction
        let split = 44 + 2 * Int((min(duration, max(0, boundary)) * rate / 2).rounded())
        var pcm = Data(source[44..<split])
        pcm.append(Data(repeating: 0, count: Self.leadInSeconds * Int(rate)))
        pcm.append(cue.dropFirst(44))
        let silenceStartFrame = UInt32(pcm.count / 2)
        pcm.append(Data(repeating: 0, count: Self.seconds * Int(rate)))
        pcm.append(source[split...])
        let wav = SpeechAudio.wave(pcm, previewStartFrame: silenceStartFrame)
        try wav.write(to: trackURL(script, directory: directory), options: .atomic)
        await progress(total, total)
        return wav
    }

}

/// Screen-owned playback. Cancellation also invalidates late network responses.
@MainActor @Observable final class ListeningPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    private let preview: ListeningPreview?
    private let directory: URL
    private var silence: Range<Double>?
    private(set) var finishes = 0
    var previewSecondsRemaining: Int? {
        guard let time = player?.currentTime, let silence, silence.contains(time) else { return nil }
        return Int(ceil(silence.upperBound - time))
    }
    private(set) var player: AVAudioPlayer?
    private(set) var generating = false
    private(set) var completed = 0
    private(set) var total = 0
    private(set) var generationFraction = 0.0
    private(set) var error: String?
    private var operation: Task<Void, Never>?
    private var generationID = UUID()
    private var requestedRow: Int?
    private(set) var times: [Double]?
    private var autoPlayWhenReady = false

    init(script: String? = nil, cacheDirectory: URL = SpeechAudio.cacheDirectory, preview: ListeningPreview? = nil) {
        self.preview = preview
        self.directory = cacheDirectory
        super.init()
        if let script { loadCached(script, directory: cacheDirectory) }
    }

    private func loadCached(_ script: String, directory: URL = SpeechAudio.cacheDirectory) {
        guard player == nil, !generating else { return }
        let url: URL
        if let preview {
            guard let track = preview.cachedTrack(script, directory: directory) else { return }
            url = track.url
            silence = track.silence
        } else {
            guard let cached = SpeechAudio.cachedAudioURL(script, directory: directory) else { return }
            url = cached
            times = SpeechAudio.startTimes(script, parts: SpeechAudio.segments(script), directory: directory)
        }
        guard let audio = try? AVAudioPlayer(contentsOf: url) else { return }
        audio.enableRate = true
        player = audio
        completed = SpeechAudio.segments(script).count; total = completed
        generationFraction = 1
    }

    func play(script: String, row: Int? = nil, generate: @escaping (String, @escaping @MainActor (Int, Int) -> Void) async throws -> Data = SpeechAudio.generate) {
        loadCached(script, directory: directory)
        requestedRow = row
        if let player, row == nil || times != nil {
            do {
                error = nil
                if let row, let times, times.indices.contains(row) { seek(times[row]) }
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
                try AVAudioSession.sharedInstance().setActive(true)
                if player.currentTime >= player.duration { player.currentTime = 0 }
                player.delegate = self
                guard player.play() else { throw StudyError.message(String(localized: "音声データを読み込めませんでした。")) }
            } catch { self.error = error.localizedDescription }
            return
        }
        guard !generating else { return }
        error = nil; generating = true; generationFraction = 0; completed = 0; total = SpeechAudio.segments(script).count + (preview == nil ? 0 : 1)
        autoPlayWhenReady = UIApplication.shared.applicationState == .active
        let id = UUID(); generationID = id
        let preview = self.preview, directory = self.directory, steps = total
        operation = Task { [weak self] in
            do {
                let data = try await BackgroundGeneration.run(title: String(localized: "音声を生成中"), total: steps, onProgress: { [weak self] fraction in
                    guard let self, self.generationID == id else { return }
                    self.generationFraction = fraction
                }) { progress in
                    let report: @MainActor (Int, Int) -> Void = { [weak self] completed, total in
                        progress.update(completed: completed, total: total)
                        guard let self, self.generationID == id else { return }
                        self.completed = completed; self.total = total
                    }
                    if let preview {
                        return try await preview.recording(for: script, directory: directory, generate: generate, progress: report)
                    }
                    return try await generate(script, report)
                }
                try Task.checkCancellation()
                guard let self, self.generationID == id else { return }
                self.completed = self.total
                try await Task.sleep(for: .milliseconds(650))
                try Task.checkCancellation()
                guard self.generationID == id else { return }
                self.player = try AVAudioPlayer(data: data)
                self.player?.enableRate = true
                if let preview { self.silence = preview.cachedTrack(script, directory: directory)?.silence }
                else { self.times = SpeechAudio.startTimes(script, parts: SpeechAudio.segments(script), directory: directory) }
                self.generating = false
                if self.requestedRow != nil && self.times == nil { throw StudyError.message(String(localized: "音声データを読み込めませんでした。")) }
                if self.autoPlayWhenReady, UIApplication.shared.applicationState == .active { self.play(script: script, row: self.requestedRow) }
                await GenerationNotifications.post(title: String(localized: "リスニング音声"), body: String(localized: "再生の準備ができました"))
            } catch {
                guard let self, self.generationID == id else { return }
                self.generating = false
                if !Task.isCancelled { self.error = error.localizedDescription }
            }
        }
    }
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        guard flag, player === self.player else { return }
        finishes += 1
    }

    func pause() {
        autoPlayWhenReady = false
        player?.pause()
    }
    func stop() {
        pause()
        generationID = UUID(); operation?.cancel(); operation = nil; generating = false
        player?.stop(); player?.currentTime = 0
    }
    func seek(_ time: Double) {
        guard let player else { return }
        player.currentTime = min(player.duration, max(0, time))
    }
    func rewindTenSeconds() {
        guard let player else { return }
        seek(player.currentTime - 10)
    }
}

struct ListeningAudioView: View {
    let script: String
    let preparationFailed: Bool
    let openSettings: () -> Void
    let onFinished: () -> Void
    @StateObject private var playback: ListeningPlayer

    init(script: String, part: ExamUnit, preparationFailed: Bool = false, onFinished: @escaping () -> Void, openSettings: @escaping () -> Void) {
        self.script = script
        self.preparationFailed = preparationFailed
        self.onFinished = onFinished
        self.openSettings = openSettings
        _playback = StateObject(wrappedValue: ListeningPlayer(script: script, preview: ListeningPreview(part: part)))
    }
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
            let playing = playback.player?.isPlaying == true
            VStack(alignment: .leading, spacing: 16) {
                Label(String(localized: "リスニング音声"), systemImage: "headphones").font(StudyTypography.heading)
                Text(String(localized: "AI-generated English audio")).font(StudyTypography.footnote).foregroundStyle(StudyColors.secondaryText)
                if let seconds = playback.previewSecondsRemaining {
                    HStack {
                        Text(String(localized: "Preview the next questions"))
                        Text(verbatim: time(Double(seconds))).monospacedDigit()
                    }
                }
                let player = playback.player
                VStack(spacing: 4) {
                    Slider(value: Binding(get: { player?.currentTime ?? 0 }, set: { playback.seek($0) }),
                           in: 0...max(0.01, player?.duration ?? 0))
                        .disabled(player == nil)
                        .accessibilityLabel(String(localized: "再生位置"))
                    HStack {
                        Text(time(player?.currentTime ?? 0))
                        Spacer()
                        Text(verbatim: player.map { time($0.duration) } ?? "–:––")
                    }.font(StudyTypography.footnote).monospacedDigit()
                }
                HStack(spacing: 12) {
                    Button { playback.rewindTenSeconds() } label: {
                        Label(String(localized: "Rewind 10 seconds"), systemImage: "gobackward.10")
                            .labelStyle(.iconOnly)
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(StudyColors.accent)
                            .frame(width: 52, height: 52)
                            .background(StudyColors.accent.opacity(0.08), in: Circle())
                            .contentShape(Circle())
                    }.buttonStyle(.plain).accessibilityIdentifier("listening.rewind")
                        .disabled(player == nil)
                        .opacity(player == nil ? 0.45 : 1)
                    Button {
                        if playback.generating { playback.stop() }
                        else if playing { playback.pause() }
                        else { playback.play(script: script) }
                    } label: {
                        if playback.generating {
                            Label(String(localized: "生成をキャンセル"), systemImage: "xmark.circle")
                        } else if playing {
                            Label(String(localized: "一時停止"), systemImage: "pause.fill")
                        } else {
                            Label(playback.player == nil ? String(localized: "音声を生成して再生") : String(localized: "音声を再生"), systemImage: "play.fill")
                        }
                    }
                    .buttonStyle(StudyPrimaryButtonStyle())
                    .accessibilityIdentifier(playback.generating ? "listening.stop" : "listening.play")
                }
                if playback.generating {
                    let fraction = playback.generationFraction
                    HStack {
                        Text(playback.completed == playback.total ? String(localized: "再生の準備ができました") : String(localized: "音声を生成中"))
                        Spacer()
                        Text(fraction < 1 ? String(format: String(localized: "約 %@%% "), String(Int(fraction * 100))) : "100%").monospacedDigit()
                    }.font(StudyTypography.button)
                    ProgressView(value: fraction).animation(.easeInOut(duration: 0.35), value: fraction)
                    Text(String(format: String(localized: "生成済み %@ / %@ 音声区間"), String(playback.completed), String(playback.total))).font(StudyTypography.footnote)
                    Text(String(localized: "Generation progress is an estimate shared with Live Activity."))
                        .font(StudyTypography.caption).foregroundStyle(StudyColors.secondaryText)
                }
                if let error = playback.error { Text(error).font(StudyTypography.subheadline).foregroundStyle(StudyColors.error) }
                else if preparationFailed && playback.player == nil && !playback.generating {
                    Text(String(localized: "音声を生成できませんでした。時間をおいて再試行してください。"))
                        .font(StudyTypography.subheadline).foregroundStyle(StudyColors.error)
                }
                if !playback.generating && (playback.player == nil || playback.error != nil) {
                    Button {
                        playback.stop()
                        openSettings()
                    } label: {
                        Label(String(localized: "OpenAI API key"), systemImage: "gearshape")
                            .font(StudyTypography.footnote).foregroundStyle(StudyColors.accent)
                            .frame(minHeight: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
                if playback.player == nil { Text(String(localized: "初回生成にはAPI利用料がかかります。生成済み音声は端末に保存して再利用します。")) .font(StudyTypography.caption).foregroundStyle(StudyColors.secondaryText) }
            }.padding(20).background(StudyColors.mockCard, in: RoundedRectangle(cornerRadius: 24))
        }
        .onChange(of: playback.finishes) { _, _ in onFinished() }
        .onDisappear { playback.stop() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in playback.pause() }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { _ in playback.pause() }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { notification in
            if notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue { playback.pause() }
        }
    }
    private func time(_ value: Double) -> String { String(format: "%d:%02d", Int(value) / 60, Int(value) % 60) }
}
