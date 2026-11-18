import SwiftUI
import UIKit

/// Tap a word or long-press and adjust the selection to save an exact phrase.
struct SelectableStudyText: View {
    typealias Entry = StudyTextView.Entry
    let text: String
    let sourceID: String
    let onSave: (Entry) -> Void
    var onAsk: ((Entry) -> Void)? = nil
    var onSavePaper: (() -> Void)? = nil
    var onVocabulary: (() -> Void)? = nil
    var allowsAI = true
    @State private var selected: Entry?
    @State private var afterDismiss: (() -> Void)?

    var body: some View {
        StudyTextView(text: text, sourceID: sourceID, onSave: { selected = $0 },
                      onAsk: onAsk, onSelect: { selected = $0 })
            .sheet(item: $selected, onDismiss: {
                let action = afterDismiss
                afterDismiss = nil
                action?()
            }) { entry in
                SelectionActionsScreen(entry: entry, allowsAI: allowsAI, onSave: onSave, onAsk: onAsk.map { action in
                    { value in afterDismiss = { action(value) }; selected = nil }
                }, onSavePaper: onSavePaper, onVocabulary: onVocabulary.map { action in
                    { afterDismiss = action; selected = nil }
                })
                .presentationDetents([.medium, .large])
            }
    }
}

private struct SelectionActionsScreen: View {
    let entry: SelectableStudyText.Entry
    let allowsAI: Bool
    let onSave: (SelectableStudyText.Entry) -> Void
    let onAsk: ((SelectableStudyText.Entry) -> Void)?
    let onSavePaper: (() -> Void)?
    let onVocabulary: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var meaning = ""
    @State private var saved = false
    @State private var paperSaved = false
    @State private var translating = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if saved {
                        Label("単語帳に保存しました", systemImage: "checkmark.circle.fill")
                            .font(.headline).foregroundStyle(StudyColors.accent)
                    }
                    Text(entry.expression).font(StudyTypography.roundedTitle(28)).textSelection(.enabled)
                    if saved {
                        if !meaning.isEmpty { Text(meaning) }
                        Button("学習を続ける") { dismiss() }.buttonStyle(.borderedProminent)
                        if let onVocabulary { Button("単語帳を見る", action: onVocabulary) }
                    } else {
                        Text(StudyTextSelection.excerpt(entry.sourceText, range: entry.utf16Range, expression: entry.expression)).font(.subheadline).foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        TextField("意味・メモ（任意）", text: $meaning, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                        if allowsAI {
                            Button("意味をAIで調べる") { translating = true; error = nil }.disabled(translating)
                        }
                        if translating { ProgressView("意味を確認中…") }
                        if let error { Text(error).font(.footnote).foregroundStyle(StudyColors.error) }
                        Button("選んだ表現を単語帳に追加", systemImage: "text.badge.plus") {
                            var value = entry; value.meaning = meaning
                            onSave(value); saved = true
                        }.buttonStyle(.borderedProminent).disabled(translating)
                        if let onAsk { Button("選んだ表現をAIに質問") { onAsk(entry) } }
                        if let onSavePaper {
                            Button(paperSaved ? "問題を保存しました" : "この問題を復習用に保存", systemImage: paperSaved ? "checkmark" : "bookmark") {
                                onSavePaper(); paperSaved = true
                            }.disabled(paperSaved)
                        }
                    }
                }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("テキスト選択").navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("閉じる") { dismiss() } }
            .task(id: translating) {
                guard translating else { return }
                do {
                    let result = try await StudyClient.liveValue.explain(entry.sourceText,
                        "選択した表現「\(entry.expression)」のこの文脈での意味を、単語帳用に短い日本語訳だけで答えてください。")
                    try Task.checkCancellation()
                    meaning = result
                } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
                translating = false
            }
        }.tint(StudyColors.accent)
    }
}

/// Use for passages, prompts, answer choices, explanations, and completed AI messages.
/// Persist the supplied entry in the same vocabulary store used by the vocabulary tab.
@available(iOS 16.0, *)
struct StudyTextView: UIViewRepresentable {
    struct Entry: Equatable, Identifiable {
        var id: String { sourceID + ":\(utf16Range.location):\(utf16Range.length)" }
        var meaning = ""
        let expression: String
        let sourceText: String
        let sourceID: String
        let utf16Range: NSRange
    }

    let text: String
    let sourceID: String
    let onSave: (Entry) -> Void
    var onAsk: ((Entry) -> Void)? = nil
    var onSelect: ((Entry) -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.selectWord(_:)))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
        view.accessibilityIdentifier = "study.text.\(sourceID)"
        view.isEditable = false
        view.isSelectable = true
        view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.textColor = StudyColors.bodyText
        view.font = StudyTypography.bodyFont
        view.adjustsFontForContentSizeCategory = true
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        let changedSource = context.coordinator.content.sourceID != sourceID
        context.coordinator.content = self
        if changedSource || view.text != text {
            view.text = text
            view.selectedRange = NSRange(location: 0, length: 0)
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        return uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var content: StudyTextView
        init(_ content: StudyTextView) { self.content = content }

        @objc func selectWord(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view as? UITextView,
                  let position = view.closestPosition(to: gesture.location(in: view)),
                  let word = view.tokenizer.rangeEnclosingPosition(position, with: .word, inDirection: UITextDirection(rawValue: UITextStorageDirection.forward.rawValue)),
                  let expression = view.text(in: word), !expression.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            let range = NSRange(location: view.offset(from: view.beginningOfDocument, to: word.start), length: view.offset(from: word.start, to: word.end))
            view.selectedTextRange = word
            content.onSelect?(Entry(expression: expression, sourceText: content.text, sourceID: content.sourceID, utf16Range: range))
        }

        func textView(_ textView: UITextView, editMenuForTextIn range: NSRange,
                      suggestedActions: [UIMenuElement]) -> UIMenu? {
            let current = content
            guard range.length > 0, textView.text == current.text,
                  let selection = Range(range, in: current.text) else { return nil }
            let expression = String(current.text[selection])
            guard !expression.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            let entry = Entry(expression: expression, sourceText: current.text,
                              sourceID: current.sourceID, utf16Range: range)
            var actions: [UIMenuElement] = [
                UIAction(title: "単語帳に追加", image: UIImage(systemName: "text.badge.plus")) { _ in
                    current.onSave(entry)
                }
            ]
            if let ask = current.onAsk {
                actions.append(UIAction(title: "AIに質問", image: UIImage(systemName: "bubble.left")) { _ in
                    ask(entry)
                })
            }
            return UIMenu(children: actions + suggestedActions)
        }
    }
}
