import SwiftUI
import UIKit

/// Use for passages, prompts, answer choices, explanations, and completed AI messages.
/// Persist the supplied entry in the same vocabulary store used by the vocabulary tab.
@available(iOS 16.0, *)
struct SelectableStudyText: UIViewRepresentable {
    struct Entry: Equatable {
        let expression: String
        let sourceText: String
        let sourceID: String
        let utf16Range: NSRange
    }

    let text: String
    let sourceID: String
    let onSave: (Entry) -> Void
    var onAsk: ((Entry) -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
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
        var content: SelectableStudyText
        init(_ content: SelectableStudyText) { self.content = content }

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
