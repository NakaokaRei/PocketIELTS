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

    static func request(text: String, key: String) throws -> URLRequest {
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
        let parts = chunks(text)
        for (index, part) in parts.enumerated() {
            try Task.checkCancellation()
            let hash = SHA256.hash(data: Data((model + voice + instructions + part).utf8)).map { String(format: "%02x", $0) }.joined()
            let url = directory.appendingPathComponent(hash + ".pcm")
            if let cached = try? Data(contentsOf: url), !cached.isEmpty, cached.count.isMultiple(of: 2) {
                pcm.append(cached)
            } else {
                guard let key = try KeyStore.read(account: SpeechCredentials.account), !key.isEmpty else { throw StudyError.message(String(localized: "設定で音声生成用のAPIキーを登録してください。")) }
                let (data, response) = try await URLSession.shared.data(for: request(text: part, key: key))
                try Task.checkCancellation()
                try validate(response, data: data)
                try data.write(to: url, options: .atomic)
                pcm.append(data)
            }
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
        error = nil; generating = true; completed = 0; total = SpeechAudio.chunks(script).count
        let id = UUID(); generationID = id
        operation = Task { [weak self] in
            do {
                let data = try await generate(script) { [weak self] completed, total in
                    guard let self, self.generationID == id else { return }
                    self.completed = completed; self.total = total
                }
                try Task.checkCancellation()
                guard let self, self.generationID == id else { return }
                self.player = try AVAudioPlayer(data: data)
                self.generating = false
                self.play(script: script)
            } catch {
                guard let self, self.generationID == id else { return }
                self.generating = false
                if !Task.isCancelled { self.error = error.localizedDescription }
            }
        }
    }
    func pause() { player?.pause() }
    func stop() {
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
                    ProgressView()
                    Text(String(format: String(localized: "音声を生成中 %@ / %@"), String(playback.completed), String(playback.total))).font(StudyTypography.subheadline)
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
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in playback.stop() }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { _ in playback.stop() }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { notification in
            if notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue { playback.stop() }
        }
    }
    private func time(_ value: Double) -> String { String(format: "%d:%02d", Int(value) / 60, Int(value) % 60) }
}
