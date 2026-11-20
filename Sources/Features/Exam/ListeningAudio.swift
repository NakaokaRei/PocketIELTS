import AVFoundation
import CryptoKit
import SwiftUI

/// Personal API credentials never enter study snapshots or iCloud.
enum SpeechCredentials {
    static let account = "listening-audio-api"
}

enum SpeechAudio {
    static let model = "gpt-4o-mini-tts"
    static let voice = "marin"
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
    }

    /// Labels are metadata, never spoken input. A voice stays stable across turns.
    static func segments(_ script: String) -> [Segment] {
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
        let roles = Set(["narrator", "speaker", "lecturer", "guide", "receptionist", "caller", "student", "tutor", "man", "woman", "interviewer"])
        var voices: [String: String] = [:]
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
            if voices[key] == nil { voices[key] = palette[voices.count % palette.count] }
            return chunks(words.trimmingCharacters(in: .whitespacesAndNewlines)).map {
                Segment(text: $0, voice: voices[key]!, speaker: speaker)
            }
        }
    }

    static func request(text: String, key: String, voice: String = SpeechAudio.voice) throws -> URLRequest {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/speech")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["model": model, "voice": voice, "instructions": instructions, "input": text, "response_format": "pcm"])
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

    static func wave(_ pcm: Data) -> Data {
        var data = Data("RIFF".utf8)
        func number<T: FixedWidthInteger>(_ value: T) { var little = value.littleEndian; withUnsafeBytes(of: &little) { data.append(contentsOf: $0) } }
        number(UInt32(pcm.count + 36)); data.append(Data("WAVEfmt ".utf8))
        number(UInt32(16)); number(UInt16(1)); number(UInt16(1)); number(UInt32(24000)); number(UInt32(48000)); number(UInt16(2)); number(UInt16(16))
        data.append(Data("data".utf8)); number(UInt32(pcm.count)); data.append(pcm)
        return data
    }

    static func generate(_ text: String, progress: @escaping @MainActor (Int, Int) -> Void) async throws -> Data {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("ListeningAudio", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var pcm = Data()
        let parts = segments(text)
        await progress(0, parts.count)
        for (index, part) in parts.enumerated() {
            try Task.checkCancellation()
            let hash = SHA256.hash(data: Data(("dialogue-v1" + model + part.voice + instructions + part.text).utf8)).map { String(format: "%02x", $0) }.joined()
            let url = directory.appendingPathComponent(hash + ".pcm")
            if let cached = try? Data(contentsOf: url), !cached.isEmpty, cached.count.isMultiple(of: 2) {
                pcm.append(cached)
            } else {
                guard let key = try KeyStore.read(account: SpeechCredentials.account), !key.isEmpty else { throw StudyError.message(String(localized: "設定で音声生成用のAPIキーを登録してください。")) }
                let (stream, response) = try await URLSession.shared.bytes(for: request(text: part.text, key: key, voice: part.voice))
                var data = Data()
                let expected = response.expectedContentLength > 0 ? Int(response.expectedContentLength) : nil
                for try await byte in stream {
                    data.append(byte)
                    if data.count.isMultiple(of: 8192) {
                        try Task.checkCancellation()
                        await GenerationTransferProgress.received(data.count, expected: expected, estimate: 480000)
                    }
                }
                try Task.checkCancellation()
                try validate(response, data: data)
                try data.write(to: url, options: .atomic)
                pcm.append(data)
            }
            if index + 1 < parts.count { pcm.append(Data(repeating: 0, count: 7200)) } // 150 ms between turns.
            await progress(index + 1, parts.count)
        }
        guard !pcm.isEmpty else { throw StudyError.message(String(localized: "音声データを読み込めませんでした。")) }
        return wave(pcm)
    }
}

/// Screen-owned playback. Cancellation also invalidates late network responses.
@MainActor @Observable final class ListeningPlayer {
    private(set) var player: AVAudioPlayer?
    private(set) var generating = false
    private(set) var completed = 0
    private(set) var total = 0
    private(set) var error: String?
    private var operation: Task<Void, Never>?
    private var generationID = UUID()
    private var autoPlayWhenReady = false

    func play(script: String, generate: @escaping (String, @escaping @MainActor (Int, Int) -> Void) async throws -> Data = SpeechAudio.generate) {
        if let player {
            do {
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
                try AVAudioSession.sharedInstance().setActive(true)
                if player.currentTime >= player.duration { player.currentTime = 0 }
                guard player.play() else { throw StudyError.message(String(localized: "音声データを読み込めませんでした。")) }
            } catch { self.error = error.localizedDescription }
            return
        }
        guard !generating else { return }
        error = nil; generating = true; completed = 0; total = SpeechAudio.segments(script).count
        autoPlayWhenReady = UIApplication.shared.applicationState == .active
        let id = UUID(); generationID = id
        operation = Task { [weak self] in
            do {
                let data = try await BackgroundGeneration.run(title: String(localized: "音声を生成中"), total: SpeechAudio.segments(script).count) { progress in
                    try await generate(script) { [weak self] completed, total in
                        progress.update(completed: completed, total: total)
                        guard let self, self.generationID == id else { return }
                        self.completed = completed; self.total = total
                    }
                }
                try Task.checkCancellation()
                guard let self, self.generationID == id else { return }
                self.completed = self.total
                try await Task.sleep(for: .milliseconds(650))
                try Task.checkCancellation()
                guard self.generationID == id else { return }
                self.player = try AVAudioPlayer(data: data)
                self.generating = false
                if self.autoPlayWhenReady, UIApplication.shared.applicationState == .active { self.play(script: script) }
            } catch {
                guard let self, self.generationID == id else { return }
                self.generating = false
                if !Task.isCancelled { self.error = error.localizedDescription }
            }
        }
    }
    func pause() { autoPlayWhenReady = false; player?.pause() }
    func stop() {
        autoPlayWhenReady = false
        generationID = UUID(); operation?.cancel(); operation = nil; generating = false
        player?.stop(); player?.currentTime = 0
    }
    func seek(_ time: Double) { player?.currentTime = time }
}

struct ListeningAudioView: View {
    let script: String
    let openSettings: () -> Void
    @State private var playback = ListeningPlayer()
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
            let playing = playback.player?.isPlaying == true
            VStack(alignment: .leading, spacing: 16) {
                Label(String(localized: "リスニング音声"), systemImage: "headphones").font(StudyTypography.heading)
                Text(String(localized: "AI生成音声 · 英国英語")).font(StudyTypography.footnote).foregroundStyle(StudyColors.secondaryText)
                if playback.generating {
                    let fraction = Double(playback.completed) / Double(max(1, playback.total))
                    HStack {
                        Text(playback.completed == playback.total ? String(localized: "再生の準備ができました") : String(localized: "音声を生成中"))
                        Spacer()
                        Text("\(Int(fraction * 100))%").monospacedDigit()
                    }.font(StudyTypography.button)
                    ProgressView(value: fraction).animation(.easeInOut(duration: 0.35), value: fraction)
                    Text(String(format: String(localized: "生成済み %@ / %@ 音声区間"), String(playback.completed), String(playback.total))).font(StudyTypography.footnote)
                    Text(String(localized: "完了した音声区間の割合です。区間の生成中は数値が止まることがあります。"))
                        .font(StudyTypography.caption).foregroundStyle(StudyColors.secondaryText)
                }
                if let player = playback.player {
                    Slider(value: Binding(get: { player.currentTime }, set: { playback.seek($0) }), in: 0...max(0.01, player.duration))
                        .accessibilityLabel(String(localized: "再生位置"))
                    HStack { Text(time(player.currentTime)); Spacer(); Text(time(player.duration)) }.font(StudyTypography.footnote).monospacedDigit()
                }
                Button(playing ? String(localized: "一時停止") : playback.player == nil ? String(localized: "音声を生成して再生") : String(localized: "音声を再生"), systemImage: playing ? "pause.fill" : "play.fill") {
                    if playing { playback.pause() } else { playback.play(script: script) }
                }.buttonStyle(StudyPrimaryButtonStyle()).disabled(playback.generating).accessibilityIdentifier("listening.play")
                if playback.player != nil || playback.generating {
                    Button(playback.generating ? String(localized: "生成をキャンセル") : String(localized: "停止"), systemImage: "stop.fill") { playback.stop() }
                        .buttonStyle(StudySecondaryButtonStyle()).accessibilityIdentifier("listening.stop")
                }
                if let error = playback.error { Text(error).font(StudyTypography.subheadline).foregroundStyle(StudyColors.error) }
                Button(String(localized: "音声APIの設定"), systemImage: "gearshape") { playback.stop(); openSettings() }.buttonStyle(StudySecondaryButtonStyle())
                if playback.player == nil { Text(String(localized: "初回生成にはAPI利用料がかかります。生成済み音声は端末に保存して再利用します。")) .font(StudyTypography.caption).foregroundStyle(StudyColors.secondaryText) }
            }.padding(20).background(StudyColors.mockCard, in: RoundedRectangle(cornerRadius: 24))
        }
        .onDisappear { playback.stop() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in playback.pause() }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { _ in playback.pause() }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { notification in
            if notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue { playback.pause() }
        }
    }
    private func time(_ value: Double) -> String { String(format: "%d:%02d", Int(value) / 60, Int(value) % 60) }
}
