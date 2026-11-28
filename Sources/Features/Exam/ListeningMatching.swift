import SwiftUI

struct ListeningMatchingGroup: Equatable {
    var indices: Range<Int>
    let instruction: String
    let options: [StudyQuestionLayout.Option]
}

extension ExamUnit {
    var listeningMatchingGroups: [ListeningMatchingGroup] {
        guard skill == "Listening" else { return [] }
        let banks = materialOptionBanks
        var groups: [ListeningMatchingGroup] = []
        for (index, question) in questions.enumerated() {
            guard StudyQuestionLayout(question.prompt).options.isEmpty else { continue }
            let instruction = StudyQuestionLayout(question.instruction)
            var options = instruction.options
            var heading = instruction.body
            if options.isEmpty {
                // Older generated papers stored the bank in directions or passages.
                guard question.instruction.localizedCaseInsensitiveContains("letter") else { continue }
                let number = firstQuestionNumber + index
                let candidates = banks.filter { $0.numbers?.contains(number) ?? (banks.count == 1) }
                guard candidates.count == 1, let bank = candidates.first else { continue }
                options = bank.options
                if !bank.heading.isEmpty { heading = bank.heading }
            }
            guard options.first?.label == "A" else { continue }
            if let last = groups.last, last.indices.upperBound == index,
               last.instruction == heading, last.options == options {
                groups[groups.count - 1].indices = last.indices.lowerBound..<(index + 1)
            } else {
                groups.append(.init(indices: index..<(index + 1), instruction: heading, options: options))
            }
        }
        return groups
    }

    private struct OptionBank {
        let numbers: ClosedRange<Int>?
        let heading: String
        let options: [StudyQuestionLayout.Option]
    }

    private var materialOptionBanks: [OptionBank] {
        let lines = ([directions] + passages).joined(separator: "\n")
            .components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        var banks: [OptionBank] = []
        var numbers: ClosedRange<Int>?
        var heading: [String] = []
        var index = 0
        while index < lines.count {
            let line = lines[index]
            index += 1
            if let range = line.firstMatch(of: #/(?i)^Questions?\s+(\d+)\s*[-–—]\s*(\d+)\b/#),
               let start = Int(range.1), let end = Int(range.2), start <= end {
                let offset = start < firstQuestionNumber && end <= questions.count ? firstQuestionNumber - 1 : 0
                numbers = (start + offset)...(end + offset)
                heading = []
            } else if line.firstMatch(of: #/^A[.)]?\s+/#) != nil {
                var optionLines = [line]
                var next = index
                while next < lines.count {
                    if !lines[next].isEmpty {
                        guard lines[next].firstMatch(of: #/^[B-Z][.)]?\s+/#) != nil else { break }
                        optionLines.append(lines[next])
                    }
                    next += 1
                }
                let options = StudyQuestionLayout(optionLines.joined(separator: "\n")).options
                if !options.isEmpty {
                    banks.append(.init(numbers: numbers, heading: numbers == nil ? "" : heading.joined(separator: "\n"), options: options))
                    index = next
                }
                heading = []
            } else if !line.isEmpty {
                heading.append(line)
            }
        }
        return banks
    }
}

struct ListeningMatchingView<Prompt: View>: View {
    let group: ListeningMatchingGroup
    let firstNumber: Int
    let answer: (Int) -> Binding<String>
    let prompt: (Int) -> Prompt
    let questionText: (Int) -> String
    let disabled: Bool

    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var wide = false
    @State private var selected: Int?
    @State private var choosing = false

    private var current: Int { selected.flatMap { group.indices.contains($0) ? $0 : nil } ?? group.indices.lowerBound }
    private var sideBySide: Bool { wide && !typeSize.isAccessibilitySize }
    private func number(_ index: Int) -> String {
        String(format: String(localized: "Question %@"), String(firstNumber + index))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: group.instruction).font(StudyTypography.subheadline).textSelection(.enabled)
            if sideBySide {
                HStack(alignment: .top, spacing: 16) {
                    rows.frame(maxWidth: .infinity, alignment: .leading)
                    options.frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                rows
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(StudyColors.mockCard, in: RoundedRectangle(cornerRadius: 16))
        .onGeometryChange(for: Bool.self) { $0.size.width >= 620 } action: { wide = $0 }
        .sheet(isPresented: $choosing) {
            VStack(alignment: .leading, spacing: 12) {
                Text(number(current)).font(StudyTypography.subheadline.bold()).foregroundStyle(StudyColors.accent)
                Text(verbatim: questionText(current)).font(StudyTypography.headline)
                ScrollView { options }
            }
            .padding(20).padding(.top, 12)
            .presentationDragIndicator(.visible)
        }
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(group.indices, id: \.self) { index in
                VStack(alignment: .leading, spacing: 4) {
                    Text(number(index)).font(StudyTypography.subheadline.bold())
                    prompt(index)
                    Button {
                        selected = index
                        if !sideBySide { choosing = true }
                    } label: {
                        HStack {
                            Text(answer(index).wrappedValue.isEmpty ? String(localized: "未回答") : answer(index).wrappedValue)
                            Spacer()
                            Image(systemName: sideBySide ? "arrow.right" : "chevron.up.chevron.down")
                        }.padding(.horizontal, 10).frame(minHeight: 44).contentShape(Rectangle())
                    }
                    .accessibilityLabel(number(index) + " " + questionText(index))
                    .accessibilityValue(answer(index).wrappedValue.isEmpty ? String(localized: "未回答") : answer(index).wrappedValue)
                    .accessibilityIdentifier("matching.question.\(index)")
                    .buttonStyle(.plain)
                    .disabled(disabled)
                    .background(StudyColors.reading.opacity(sideBySide && current == index ? 0.8 : 0.3), in: RoundedRectangle(cornerRadius: 8))
                }
                .id(ExamScreen.JumpTarget.question(index))
            }
        }
    }

    private var options: some View {
        VStack(alignment: .leading, spacing: 4) {
            if sideBySide && !choosing {
                Text(number(current)).font(StudyTypography.subheadline.bold()).foregroundStyle(StudyColors.accent)
            }
            ForEach(group.options, id: \.label) { option in
                let isSelected = answer(current).wrappedValue.caseInsensitiveCompare(option.label) == .orderedSame
                Button {
                    answer(current).wrappedValue = isSelected ? "" : option.label
                    if choosing { choosing = false }
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(verbatim: option.label).bold().foregroundStyle(StudyColors.accent)
                        Text(verbatim: option.text).frame(maxWidth: .infinity, alignment: .leading)
                        if isSelected { Image(systemName: "checkmark") }
                    }
                    .padding(8).frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(disabled)
                .background(StudyColors.reading.opacity(isSelected ? 0.7 : 0.18), in: RoundedRectangle(cornerRadius: 8))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityIdentifier("answer.choice.\(current).\(option.label)")
            }
        }
    }
}
