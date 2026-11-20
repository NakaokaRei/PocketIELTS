import SwiftUI
@preconcurrency import AVFoundation
import ComposableArchitecture

/// Original General Training learning material; groupings are not official band predictions.
struct StarterWord: Identifiable, Decodable {
    let expression: String
    let definition: String
    let example: String
    let topic: String
    let level: Int
    var id: String { expression }
    var context: String { expression + "\n" + definition + "\n" + example }
    static let levels = ["Foundation · 4–5", "Developing · 5.5–6.5", "Advanced · 7+"]
    static let topics = ["housing", "work", "training", "shopping", "travel", "health", "community", "money", "correspondence", "society"]
    static let all: [Self] = {
        guard let url = Bundle.main.url(forResource: "GeneralTrainingWords", withExtension: "json", subdirectory: "Vocabulary"),
              let data = try? Data(contentsOf: url),
              let words = try? JSONDecoder().decode([Self].self, from: data) else { return [] }
        return words
    }()
}

struct VocabularyLibraryScreen: View {
    let store: StoreOf<StudyFeature>
    @State private var level = 0
    @State private var selected: StarterWord?
    @State private var search = ""
    @StateObject private var pronunciation = WordPronouncer()
    private var filtered: [StarterWord] {
        StarterWord.all.filter { $0.level == level &&
            (search.isEmpty || $0.expression.localizedCaseInsensitiveContains(search) || $0.definition.localizedCaseInsensitiveContains(search)) }
    }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                Label(String(localized: "Available offline"), systemImage: "checkmark.circle.fill")
                    .font(StudyTypography.subheadline).foregroundStyle(StudyColors.accent)
                Text(String(localized: "Study levels are a guide, not official IELTS word lists."))
                    .font(StudyTypography.caption).foregroundStyle(StudyColors.secondaryText)
                ForEach(StarterWord.levels.indices, id: \.self) { index in
                    Button { level = index } label: {
                        HStack {
                            Text(StarterWord.levels[index]).font(StudyTypography.button)
                            Spacer()
                            Image(systemName: level == index ? "checkmark.circle.fill" : "circle")
                        }.padding(16).background(level == index ? StudyColors.reading : StudyColors.mockCard, in: RoundedRectangle(cornerRadius: 16))
                    }.buttonStyle(.plain).accessibilityIdentifier("library.level.\(index)")
                }
                if filtered.isEmpty { ContentUnavailableView.search(text: search) }
                ForEach(filtered) { word in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(word.expression).font(StudyTypography.heading).textSelection(.enabled)
                        WordPronunciationButton(word: word.expression, pronunciation: pronunciation)
                        Text(word.definition).font(StudyTypography.body).textSelection(.enabled)
                        if !word.example.isEmpty { Text(word.example).font(StudyTypography.subheadline).foregroundStyle(StudyColors.secondaryText).textSelection(.enabled) }
                        Button(String(localized: "AIに質問"), systemImage: "bubble.left.and.bubble.right") { pronunciation.stop(); selected = word }
                            .buttonStyle(StudySecondaryButtonStyle()).accessibilityIdentifier("library.ask.\(word.id)")
                    }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                        .background(StudyColors.mockCard, in: RoundedRectangle(cornerRadius: 20))
                }
            }.padding(20).frame(maxWidth: 800).frame(maxWidth: .infinity)
        }.navigationTitle(String(localized: "IELTS word library")).navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search)
            .onDisappear { pronunciation.stop() }
            .onChange(of: level) { _, _ in pronunciation.stop() }
            .sheet(item: $selected, onDismiss: { store.send(.closeQuestion) }) { word in
                TutorScreen(store: store, context: word.context, selectedText: word.expression, vocabularyMode: true)
            }
    }
}

struct AddVocabularyScreen: View {
    let store: StoreOf<StudyFeature>
    @Environment(\.dismiss) private var dismiss
    @FocusState private var editing: Bool
    @State private var expression = ""
    @State private var example = ""
    @State private var tutor = false
    private var trimmed: String { expression.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var duplicate: Bool { store.vocabulary.contains { $0.sourceID == "manual" && $0.expression.caseInsensitiveCompare(trimmed) == .orderedSame } }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(String(localized: "Add a word or phrase")).font(StudyTypography.title)
                    TextField(String(localized: "Word or phrase"), text: $expression, axis: .vertical)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().font(StudyTypography.heading).focused($editing)
                        .padding(16).background(StudyColors.mockCard, in: RoundedRectangle(cornerRadius: 16))
                        .accessibilityIdentifier("vocabulary.expression")
                    TextField(String(localized: "Example sentence (optional)"), text: $example, axis: .vertical)
                        .lineLimit(3...6).font(StudyTypography.body).focused($editing)
                        .padding(16).background(StudyColors.mockCard, in: RoundedRectangle(cornerRadius: 16))
                    Button(String(localized: "AIに質問"), systemImage: "bubble.left.and.bubble.right") { tutor = true }
                        .buttonStyle(StudySecondaryButtonStyle()).disabled(trimmed.isEmpty)
                        .accessibilityIdentifier("vocabulary.composeAI")
                    Button(duplicate ? String(localized: "Already in your vocabulary") : String(localized: "Save to my vocabulary"), systemImage: "plus.circle.fill") {
                        store.send(.saveExpression(SavedExpression(expression: trimmed, source: "My vocabulary", sourceText: example.trimmingCharacters(in: .whitespacesAndNewlines), sourceID: "manual")))
                        dismiss()
                    }.buttonStyle(StudyPrimaryButtonStyle()).disabled(trimmed.isEmpty || duplicate)
                        .accessibilityIdentifier("vocabulary.saveManual")
                }.padding(24).frame(maxWidth: 650).frame(maxWidth: .infinity)
            }.navigationTitle(String(localized: "Add vocabulary")).navigationBarTitleDisplayMode(.inline)
                .scrollDismissesKeyboard(.interactively)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(String(localized: "キャンセル")) { dismiss() } }
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button(String(localized: "入力を完了")) { editing = false }
                    }
                }
                .sheet(isPresented: $tutor, onDismiss: { store.send(.closeQuestion) }) {
                    TutorScreen(store: store, context: trimmed + "\n" + example, selectedText: trimmed, vocabularyMode: true)
                }
        }
    }
}

struct OfflineLibraryScreen: View {
    let units: [ExamUnit]
    let store: StoreOf<StudyFeature>
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Label(String(localized: "Available offline"), systemImage: "checkmark.circle.fill")
                    .font(StudyTypography.heading).foregroundStyle(StudyColors.accent)
                Text(String(localized: "12 included parts. Reading answers and explanations work offline. AI feedback, conversations and new audio need internet."))
                    .font(StudyTypography.subheadline).foregroundStyle(StudyColors.secondaryText)
                ForEach(["Reading", "Listening", "Writing", "Speaking"], id: \.self) { skill in
                    Text(skill).font(StudyTypography.heading)
                    ForEach(units.filter { $0.skill == skill }) { unit in
                        StudyLink { ExamScreen(units: [unit], store: store) } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(unit.id).font(StudyTypography.caption).foregroundStyle(StudyColors.accent)
                                    Text(unit.title).font(StudyTypography.heading)
                                }
                                Spacer(); Image(systemName: "chevron.right")
                            }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                                .background(StudyColors.mockCard, in: RoundedRectangle(cornerRadius: 20))
                        }.buttonStyle(.plain).accessibilityIdentifier("offline.open.\(unit.id)")
                    }
                }
            }.padding(20).frame(maxWidth: 800).frame(maxWidth: .infinity)
        }.navigationTitle(String(localized: "Offline practice")).navigationBarTitleDisplayMode(.inline)
    }
}

struct VocabularyCard: Identifiable, Equatable {
    let id: String
    let word: String
    let meaning: String
    let example: String
    let personal: Bool
    var context: String { [word, meaning, example].filter { !$0.isEmpty }.joined(separator: "\n") }
    init(_ entry: StarterWord) {
        id = entry.id; word = entry.expression; meaning = entry.definition; example = entry.example; personal = false
    }
    init?(_ entry: SavedExpression) {
        let value = entry.expression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        let match = StarterWord.all.first { $0.expression.caseInsensitiveCompare(value) == .orderedSame }
        id = entry.id.uuidString; word = value; personal = true
        let savedMeaning = entry.meaning.trimmingCharacters(in: .whitespacesAndNewlines)
        meaning = savedMeaning.isEmpty ? match?.definition ?? "" : savedMeaning
        example = entry.contextExcerpt.isEmpty ? match?.example ?? "" : entry.contextExcerpt
    }
    static func waitingDeck(_ saved: [SavedExpression]) -> [Self] {
        // Keep every saved expression, including ones without a definition. A one-word
        // personal deck must continue into the bundled collection rather than loop forever.
        var seen = Set<String>()
        let personal = saved.compactMap(Self.init).filter { seen.insert($0.word.lowercased()).inserted }
        let bundled = StarterWord.all.map(Self.init).filter { seen.insert($0.word.lowercased()).inserted }
        return personal.shuffled() + bundled.shuffled()
    }
}

struct WaitingVocabularyView: View {
    let words: [SavedExpression]
    @State private var cards: [VocabularyCard] = []
    @State private var index = 0
    @StateObject private var pronunciation = WordPronouncer()
    init(words: [SavedExpression]) {
        self.words = words
        _cards = State(initialValue: VocabularyCard.waitingDeck(words))
    }
    var body: some View {
        Group {
            if let card = cards.isEmpty ? nil : cards[index % cards.count] {
                VStack(alignment: .leading, spacing: 12) {
                    Label(String(localized: "Vocabulary while you wait"), systemImage: "book")
                        .font(StudyTypography.headline).foregroundStyle(StudyColors.accent)
                    Text(String(localized: card.personal ? "From your saved words" : "From the word library"))
                        .accessibilityIdentifier(card.personal ? "generation.source.personal" : "generation.source.bundled")
                        .font(StudyTypography.caption).foregroundStyle(StudyColors.secondaryText)
                    Text(card.word).font(StudyTypography.heading).accessibilityIdentifier("generation.word")
                    Text(card.meaning.isEmpty ? String(localized: "No saved meaning") : card.meaning)
                        .font(StudyTypography.body).accessibilityIdentifier("generation.meaning")
                    Text(card.example).font(StudyTypography.subheadline).foregroundStyle(StudyColors.secondaryText)
                    WordPronunciationButton(word: card.word, pronunciation: pronunciation)
                    Button(String(localized: "Next word"), systemImage: "arrow.right") { pronunciation.stop(); index = (index + 1) % cards.count }
                        .buttonStyle(StudySecondaryButtonStyle()).accessibilityIdentifier("generation.nextWord")
                    Text(String(localized: "Your practice opens automatically when ready."))
                        .font(StudyTypography.caption).foregroundStyle(StudyColors.secondaryText)
                }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                    .background(StudyColors.mockCard, in: RoundedRectangle(cornerRadius: 20))
            }
        }.onDisappear { pronunciation.stop() }
    }
}

@MainActor
final class WordPronouncer: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published private(set) var activeWord: String?
    @Published private(set) var error: String?
    private let synthesizer = AVSpeechSynthesizer()
    private var utteranceID: ObjectIdentifier?
    override init() { super.init(); synthesizer.delegate = self }
    static func utterance(for word: String) -> AVSpeechUtterance {
        let utterance = AVSpeechUtterance(string: word)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-GB") ?? AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.85
        return utterance
    }
    func toggle(_ word: String) {
        if activeWord == word { stop(); return }
        stop(); error = nil
        guard !word.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: .duckOthers)
            try session.setActive(true)
            let utterance = Self.utterance(for: word)
            utteranceID = ObjectIdentifier(utterance); activeWord = word
            synthesizer.speak(utterance)
        } catch { self.error = error.localizedDescription }
    }
    func stop() {
        let wasActive = activeWord != nil
        utteranceID = nil; activeWord = nil
        synthesizer.stopSpeaking(at: .immediate)
        if wasActive { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            guard self?.utteranceID == id else { return }
            self?.stop()
        }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            guard self?.utteranceID == id else { return }
            self?.stop()
        }
    }
}

struct WordPronunciationButton: View {
    let word: String
    @ObservedObject var pronunciation: WordPronouncer
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                pronunciation.toggle(word)
            } label: {
                Label(String(localized: pronunciation.activeWord == word ? "Stop pronunciation" : "Hear pronunciation"),
                      systemImage: pronunciation.activeWord == word ? "stop.fill" : "speaker.wave.2.fill")
            }.buttonStyle(StudySecondaryButtonStyle()).accessibilityIdentifier("vocabulary.pronounce.\(word)")
            if let error = pronunciation.error { Text(error).font(StudyTypography.caption).foregroundStyle(StudyColors.error) }
        }.onChange(of: scenePhase) { _, phase in if phase != .active { pronunciation.stop() } }
    }
}
