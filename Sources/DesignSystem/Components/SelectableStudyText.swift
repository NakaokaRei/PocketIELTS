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
    var allowsAI = true
    @State private var saved = false

    var body: some View {
        StudyTextView(text: text, sourceID: sourceID, onSave: { entry in
            onSave(entry)
            saved = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            UIAccessibility.post(notification: .announcement, argument: "単語帳に保存しました")
        }, onAsk: allowsAI ? onAsk : nil, onSavePaper: onSavePaper)
        .overlay(alignment: .top) {
            if saved {
                Label("単語帳に保存しました", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.bold()).padding(12)
                    .background(.regularMaterial, in: Capsule())
                    .allowsHitTesting(false).accessibilityIdentifier("selection.saved")
            }
        }
        .task(id: saved) {
            guard saved else { return }
            try? await Task.sleep(for: .seconds(2))
            saved = false
        }
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
    var onSavePaper: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        let menu = UIEditMenuInteraction(delegate: context.coordinator)
        view.addInteraction(menu)
        context.coordinator.menu = menu
        view.delegate = context.coordinator
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.selectWord(_:)))
        tap.cancelsTouchesInView = false
        tap.delegate = context.coordinator
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

    final class Coordinator: NSObject, UITextViewDelegate, UIEditMenuInteractionDelegate, UIGestureRecognizerDelegate {
        var selectionAtTouch = false
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            selectionAtTouch = (gestureRecognizer.view as? UITextView)?.selectedRange.length ?? 0 > 0
            return true
        }
        weak var menu: UIEditMenuInteraction?
        var content: StudyTextView
        init(_ content: StudyTextView) { self.content = content }

        @objc func selectWord(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view as? UITextView else { return }
            if selectionAtTouch {
                StudySelectionDismissal.shared.clear()
                return
            }
            guard
                  let position = view.closestPosition(to: gesture.location(in: view)),
                  let word = view.tokenizer.rangeEnclosingPosition(position, with: .word, inDirection: UITextDirection(rawValue: UITextStorageDirection.forward.rawValue)),
                  let expression = view.text(in: word), !expression.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            DispatchQueue.main.async { [weak self, weak view] in
                guard let self, let view else { return }
                StudySelectionDismissal.shared.activate(view, menu: self.menu)
                view.becomeFirstResponder()
                view.selectedTextRange = word
                self.menu?.presentEditMenu(with: UIEditMenuConfiguration(identifier: nil,
                    sourcePoint: CGPoint(x: view.firstRect(for: word).midX, y: view.firstRect(for: word).maxY)))
            }
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            if textView.selectedRange.length > 0 { StudySelectionDismissal.shared.activate(textView, menu: menu) }
        }

        func editMenuInteraction(_ interaction: UIEditMenuInteraction,
                                 menuFor configuration: UIEditMenuConfiguration,
                                 suggestedActions: [UIMenuElement]) -> UIMenu? {
            guard let view = interaction.view as? UITextView else { return nil }
            return textView(view, editMenuForTextIn: view.selectedRange, suggestedActions: suggestedActions)
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
                    StudySelectionDismissal.shared.clear()
                    current.onSave(entry)
                }
            ]
            if let ask = current.onAsk {
                actions.append(UIAction(title: "AIに質問", image: UIImage(systemName: "bubble.left")) { _ in
                    StudySelectionDismissal.shared.clear()
                    ask(entry)
                })
            }
            if let savePaper = current.onSavePaper {
                actions.append(UIAction(title: "問題を保存", image: UIImage(systemName: "bookmark")) { _ in
                    StudySelectionDismissal.shared.clear()
                    savePaper()
                })
            }
            actions.append(UIAction(title: "コピー", image: UIImage(systemName: "doc.on.doc")) { _ in
                UIPasteboard.general.string = entry.expression
                StudySelectionDismissal.shared.clear()
            })
            return UIMenu(children: actions)
        }
    }
}

/// One non-consuming recognizer per active window; taps outside the text end selection.
@MainActor
private final class StudySelectionDismissal: NSObject, UIGestureRecognizerDelegate {
    static let shared = StudySelectionDismissal()
    private weak var active: UITextView?
    private weak var menu: UIEditMenuInteraction?
    private weak var window: UIWindow?
    private lazy var tap = UITapGestureRecognizer(target: self, action: #selector(outsideTap(_:)))

    func activate(_ view: UITextView, menu: UIEditMenuInteraction?) {
        if active !== view { clear() }
        active = view
        self.menu = menu
        if let nextWindow = view.window, window !== nextWindow {
            window?.removeGestureRecognizer(tap)
            tap.cancelsTouchesInView = false
            tap.delegate = self
            nextWindow.addGestureRecognizer(tap)
            window = nextWindow
        }
    }

    func clear() {
        let previous = active
        active = nil
        menu?.dismissMenu()
        menu = nil
        previous?.selectedRange = NSRange(location: 0, length: 0)
        previous?.resignFirstResponder()
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard let active else { return false }
        guard !(touch.view?.isDescendant(of: active) ?? false) else { return false }
        // The edit menu is presented above the content. Never consume its taps:
        // dismissing it here would prevent the chosen UIAction from executing.
        var ancestor = active.superview
        while let view = ancestor {
            if view is UIScrollView {
                return touch.view?.isDescendant(of: view) ?? false
            }
            ancestor = view.superview
        }
        return false
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

    @objc private func outsideTap(_ gesture: UITapGestureRecognizer) { clear() }
}
