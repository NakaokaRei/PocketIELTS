import AVFoundation
import SwiftUI

struct ListeningTranscript {
    let script: String
    let rows: [SpeechAudio.Segment]
    let evidence: [Int: Int]  // Displayed question number to row.
    let times: [Double]?

    init?(part: ExamUnit) {
        guard part.skill == "Listening", let script = part.audio else { return nil }
        let rows = SpeechAudio.segments(script)
        guard !rows.isEmpty else { return nil }
        self.script = script
        self.rows = rows
        times = SpeechAudio.startTimes(script, parts: rows)
        func words(_ text: String) -> [String] {
            text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        }
        var tokens = [String]()
        var rowForToken = [Int]()
        for (i, row) in rows.enumerated() {
            let line = words([row.speaker, row.text].compactMap { $0 }.joined(separator: " "))
            tokens += line
            rowForToken += Array(repeating: i, count: line.count)
        }
        var evidence = [Int: Int]()
        for (i, question) in part.questions.enumerated() {
            let quote = words(question.evidenceQuote ?? "")
            guard let first = quote.first else { continue }
            let matches = tokens.indices.filter { tokens[$0] == first && tokens[$0...].starts(with: quote) }
            let matchedRows = Set(matches.map { rowForToken[$0] })
            if matchedRows.count == 1 { evidence[part.firstQuestionNumber + i] = matchedRows.first }
        }
        self.evidence = evidence
    }

    static func time(_ seconds: Double) -> String {
        String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60)
    }
}

struct ListeningReviewButton: View {
    let part: ExamUnit
    @Binding var transcript: ListeningTranscript?
    let question: Int?
    @State private var presented = false
    @State private var locating = false
    @State private var resolvedRow: Int?
    @State private var lookupError: String?

    var body: some View {
        if let model = transcript {
            let row = question.flatMap { model.evidence[$0] } ?? resolvedRow
            Group {
                if question != nil {
                    Button {
                        lookupError = nil
                        if row != nil { presented = true } else { locating = true }
                    } label: {
                        HStack(spacing: 5) {
                            Label(String(localized: "根拠を聞く"), systemImage: "play.circle.fill")
                            if locating { ProgressView().controlSize(.small) }
                            if let row, let times = model.times {
                                Text(ListeningTranscript.time(times[row])).monospacedDigit()
                            }
                        }
                        .font(.subheadline.weight(.medium)).foregroundStyle(StudyColors.accent)
                        .frame(minHeight: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain).disabled(locating)
                } else {
                    Button(String(localized: "音声スクリプトを見る"), systemImage: "text.alignleft") { presented = true }
                        .buttonStyle(StudySecondaryButtonStyle())
                }
            }
            .accessibilityIdentifier(question.map { "review.listen.\($0)" } ?? "review.transcript")
            .sheet(isPresented: $presented, onDismiss: { transcript = ListeningTranscript(part: part) }) {
                ListeningReviewSheet(transcript: model, title: part.id, question: question, evidenceRow: row)
            }
            .task(id: locating) {
                guard locating, let question else { return }
                do {
                    let index = question - part.firstQuestionNumber
                    let match = try await StudyClient.locateEvidence(for: part.questions[index], rows: model.rows)
                    try Task.checkCancellation()
                    resolvedRow = match
                    presented = true
                } catch {
                    if !Task.isCancelled { lookupError = error.localizedDescription }
                }
                locating = false
            }
            if let lookupError { Text(lookupError).font(.footnote).foregroundStyle(StudyColors.error) }
        }
    }
}

private struct ListeningReviewSheet: View {
    let transcript: ListeningTranscript
    let title: String
    let question: Int?
    @StateObject private var playback: ListeningPlayer
    private let localization = Bundle.main.preferredLocalizations.first ?? "en"
    let evidenceRow: Int?
    @Environment(\.dismiss) private var dismiss

    init(transcript: ListeningTranscript, title: String, question: Int?, evidenceRow: Int?) {
        self.transcript = transcript
        self.title = title
        self.question = question
        self.evidenceRow = evidenceRow
        _playback = StateObject(wrappedValue: ListeningPlayer(script: transcript.script))
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                TimelineView(.periodic(from: .now, by: 0.2)) { _ in
                    let player = playback.player
                    let times = playback.times ?? transcript.times
                    let playing = player?.isPlaying == true
                    let current = player?.currentTime ?? 0
                    let active = playing ? times?.lastIndex(where: { $0 <= current }) : nil
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(transcript.rows.indices, id: \.self) { index in
                                ListeningTranscriptRow(segment: transcript.rows[index], time: times.map { $0[index] },
                                                     active: active == index, question: evidenceRow == index ? question : nil,
                                                     localization: localization, index: index) {
                                    playback.play(script: transcript.script, row: index)
                                }.id(index)
                            }
                        }.padding(.horizontal)
                    }
                    .safeAreaInset(edge: .bottom) {
                        VStack {
                            if playback.generating { ProgressView(value: playback.generationFraction) }
                            if let error = playback.error { Text(error).font(.footnote).foregroundStyle(StudyColors.error) }
                            if let player {
                                Slider(value: Binding(get: { player.currentTime }, set: { playback.seek($0) }),
                                       in: 0...max(0.01, player.duration)).accessibilityLabel(String(localized: "再生位置"))
                                HStack {
                                    Text(ListeningTranscript.time(current))
                                    Spacer()
                                    Text(ListeningTranscript.time(player.duration))
                                }.font(.caption.monospacedDigit())
                            }
                            HStack(spacing: 32) {
                                Button { playback.seek(current - 5) } label: {
                                    Label("5秒戻る", systemImage: "gobackward.5")
                                }.labelStyle(.iconOnly).disabled(player == nil)
                                Button {
                                    if playing { playback.pause() }
                                    else { playback.play(script: transcript.script, row: player == nil ? evidenceRow ?? 0 : nil) }
                                } label: {
                                    Label(playing ? String(localized: "一時停止") : String(localized: "音声を再生"), systemImage: playing ? "pause.fill" : "play.fill")
                                }.labelStyle(.iconOnly).disabled(playback.generating)
                                Menu {
                                    ForEach([0.75, 1, 1.25, 1.5], id: \.self) { rate in
                                        Button("\(rate.formatted())×") { player?.rate = Float(rate) }
                                    }
                                } label: { Text("\((player?.rate ?? 1).formatted())×") }.disabled(player == nil)
                            }.font(.title3).frame(minHeight: 44)
                        }.padding(.horizontal).padding(.vertical, 8).background(.regularMaterial)
                    }
                }
                .onAppear {
                    if let row = evidenceRow {
                        proxy.scrollTo(row, anchor: .center)
                        playback.play(script: transcript.script, row: row)
                    }
                }
            }
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbar { Button(String(localized: "閉じる")) { dismiss() } }
        }
        .presentationDragIndicator(.visible)
        .onDisappear { playback.stop() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in playback.pause() }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { _ in playback.pause() }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { note in
            if note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue { playback.pause() }
        }
    }
}

private struct ListeningTranscriptRow: View {
    let segment: SpeechAudio.Segment
    let time: Double?
    let active: Bool
    let question: Int?
    let localization: String
    let index: Int
    let play: () -> Void
    @State private var expanded = false
    @State private var translation: String?
    @State private var error: String?

    var body: some View {
        let canTranslate = Locale.Language(identifier: localization).languageCode?.identifier != "en"
        VStack(alignment: .leading, spacing: 5) {
            ZStack(alignment: .topTrailing) {
                Button(action: play) {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Image(systemName: active ? "speaker.wave.2.fill" : "play.circle").frame(width: 22, height: 22)
                            if let time { Text(ListeningTranscript.time(time)).monospacedDigit() }
                            if let speaker = segment.speaker { Text(speaker) }
                        }
                        .font(.subheadline.bold()).foregroundStyle(StudyColors.accent)
                        .padding(.trailing, canTranslate ? 48 : 0)
                        .frame(minHeight: canTranslate ? 44 : 22)
                        if let question { Text(String(format: String(localized: "Q%lld の根拠"), question)).font(.caption.bold()) }
                        Text(segment.text)
                    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain)
                if canTranslate {
                    Button {
                        error = nil
                        expanded.toggle()
                    } label: {
                        Image(systemName: "translate")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(expanded ? StudyColors.accent : .secondary)
                            .frame(width: 44, height: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(expanded ? String(localized: "訳を隠す") : String(localized: "翻訳を表示"))
                    .accessibilityIdentifier("review.translation.\(index)")
                }
            }
            if expanded {
                if let translation { Text(translation).font(.subheadline).foregroundStyle(.secondary) }
                else { ProgressView().controlSize(.small) }
            }
            if let error { Text(error).font(.footnote).foregroundStyle(StudyColors.error) }
        }
        .padding(12)
        .background(active ? StudyColors.accent.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 12))
        .task(id: expanded) {
            guard expanded, translation == nil else { return }
            do {
                let value = try await StudyClient.translateUtterance(segment.text, localization: localization)
                try Task.checkCancellation()
                translation = value
            } catch {
                guard !Task.isCancelled else { return }
                self.error = error.localizedDescription
                expanded = false
            }
        }
    }
}
