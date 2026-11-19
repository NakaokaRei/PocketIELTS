import SwiftUI
import ComposableArchitecture

/// Original study material. The levels are learning guides, not official IELTS lists.
struct StarterWord: Identifiable {
    let expression: String
    let definition: String
    let example: String
    let level: Int
    var id: String { expression }
    var context: String { expression + "\n" + definition + "\n" + example }
    static let levels = ["Foundation · 4–5", "Developing · 5.5–6.5", "Advanced · 7+"]
    static let all: [Self] = groups.enumerated().flatMap { level, group in
        group.split(separator: "\n").map { line in
            let fields = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            return Self(expression: fields[0], definition: fields[1], example: fields[2], level: level)
        }
    }
    private static let groups = [
    """
    accommodation|A place where you live or stay.|The college offers affordable accommodation near the campus.
    appointment|An arrangement to meet someone at a particular time.|You need an appointment to speak to the adviser.
    available|Ready to be used or obtained.|Evening classes are available on Tuesdays.
    benefit|A useful or positive effect.|One benefit of cycling is improved health.
    borrow|To take something with permission and return it later.|Members can borrow up to six books.
    budget|The money available for a particular purpose.|We need to keep the project within our budget.
    community|People who live in the same area or share interests.|The new centre provides services for the local community.
    convenient|Easy to use or suitable for your needs.|Online booking is convenient for busy students.
    deadline|The latest time when something must be completed.|The application deadline is Friday at noon.
    equipment|The tools or items needed for an activity.|Safety equipment is provided during training.
    fee|An amount of money paid for a service.|There is a small fee for replacing a lost card.
    improve|To make or become better.|Regular practice can improve your confidence.
    increase|To become or make something greater.|The number of visitors increased last year.
    opportunity|A chance to do something useful or desirable.|Volunteering is an opportunity to learn new skills.
    permission|Approval to do something.|You need permission to park behind the building.
    provide|To give someone something they need.|The library provides free internet access.
    reduce|To make something smaller or less.|Taking the bus can reduce travel costs.
    reliable|Able to be trusted to work well.|A reliable train service helps people get to work.
    require|To need something or make it necessary.|Some courses require previous experience.
    resident|A person who lives in a particular place.|Local residents can use the garden throughout the year.
    """,
    """
    accessible|Easy to reach, enter or use.|Public buildings should be accessible to wheelchair users.
    allocate|To set aside resources for a particular purpose.|The council allocated more money to road repairs.
    alternative|Another possible choice.|Working from home is an alternative to commuting every day.
    approach|A way of dealing with a task or problem.|Schools need a flexible approach to teaching.
    assess|To judge the quality, value or importance of something.|The team will assess the impact of the changes.
    consequence|A result of an action or situation.|Poor planning can have serious consequences.
    contribute|To help produce a result or give something to a cause.|Public transport can contribute to cleaner air.
    decline|To become smaller, weaker or less common.|Sales declined during the winter months.
    efficient|Working well without wasting time or resources.|Modern heating systems are more efficient.
    evidence|Facts or information that support a belief.|There is clear evidence that exercise improves health.
    flexible|Able to change to suit different conditions.|Flexible hours can help parents manage childcare.
    maintain|To keep something in good condition or at the same level.|It is important to maintain public parks.
    priority|Something that is more important than other things.|Road safety should be a priority for local authorities.
    proportion|A part or share of a total.|A large proportion of students travel by bus.
    relevant|Directly connected with the subject being considered.|Applicants should describe their relevant experience.
    resource|Something useful that can help achieve a goal.|Clean water is a valuable resource.
    significant|Large or important enough to have an effect.|The scheme led to a significant reduction in waste.
    sustainable|Able to continue without using up resources or causing lasting harm.|Cities need more sustainable forms of transport.
    trend|A general direction in which something changes.|There is a growing trend towards online learning.
    voluntary|Done by choice rather than because it is required.|Participation in the survey is voluntary.
    """,
    """
    alleviate|To make a problem or suffering less severe.|Better bus services could alleviate traffic congestion.
    ambiguity|A lack of clarity that allows more than one interpretation.|The revised instructions remove the ambiguity.
    coherent|Logical and clearly connected.|A strong essay presents a coherent argument.
    compelling|Very convincing or persuasive.|The report offers compelling evidence for reform.
    detrimental|Causing harm or damage.|Long working hours can be detrimental to wellbeing.
    disparity|A noticeable difference, especially an unfair one.|There is a disparity in access to healthcare between regions.
    empirical|Based on observation or experiments rather than theory alone.|The claim needs empirical evidence.
    feasible|Possible and practical to carry out.|A pilot study will show whether the proposal is feasible.
    implication|A possible effect or result of a decision or situation.|The policy has important implications for small businesses.
    incentive|Something that encourages a person to take action.|Lower fares could provide an incentive to use public transport.
    inevitable|Certain to happen and unable to be avoided.|Some disruption is inevitable during construction.
    mitigate|To make the harmful effects of something less severe.|Planting trees can help mitigate urban heat.
    nuanced|Showing small but important differences.|The issue requires a nuanced discussion of costs and benefits.
    predominant|More common or influential than others.|Cars remain the predominant form of transport in the area.
    reconcile|To find a way for different needs or ideas to work together.|Planners must reconcile economic growth with environmental protection.
    resilience|The ability to recover or adapt after difficulties.|Diverse local businesses can strengthen economic resilience.
    substantial|Large in amount, value or importance.|The new system requires substantial investment.
    undermine|To gradually weaken or damage something.|Inconsistent rules can undermine public trust.
    viable|Able to work successfully in practice.|The project must be financially viable in the long term.
    outweigh|To be greater or more important than something else.|The long-term benefits may outweigh the initial costs.
    """
    ]
}

struct VocabularyLibraryScreen: View {
    let store: StoreOf<StudyFeature>
    @State private var level = 0
    @State private var selected: StarterWord?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
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
                ForEach(StarterWord.all.filter { $0.level == level }) { word in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(word.expression).font(StudyTypography.heading).textSelection(.enabled)
                        Text(word.definition).font(StudyTypography.body).textSelection(.enabled)
                        Text(word.example).font(StudyTypography.subheadline).foregroundStyle(StudyColors.secondaryText).textSelection(.enabled)
                        Button(String(localized: "AIに質問"), systemImage: "bubble.left.and.bubble.right") { selected = word }
                            .buttonStyle(StudySecondaryButtonStyle()).accessibilityIdentifier("library.ask.\(word.id)")
                    }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                        .background(StudyColors.mockCard, in: RoundedRectangle(cornerRadius: 20))
                }
            }.padding(20).frame(maxWidth: 800).frame(maxWidth: .infinity)
        }.navigationTitle(String(localized: "IELTS word library")).navigationBarTitleDisplayMode(.inline)
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
                        NavigationLink { ExamScreen(units: [unit], store: store) } label: {
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
