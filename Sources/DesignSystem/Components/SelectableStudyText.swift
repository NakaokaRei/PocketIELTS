import SwiftUI
import UIKit

/// Tap a word or long-press and adjust the selection to save an exact phrase.
struct SelectableStudyText: View {
    typealias Entry = StudyTextView.Entry
    let text: String
    let sourceID: String
    let onSave: (Entry) -> Void
    var onAsk: ((Entry) -> Void)? = nil
    var allowsAI = true
    var markdown = false
    @State private var saved = false

    var body: some View {
        StudyTextView(text: text, sourceID: sourceID, onSave: { entry in
            onSave(entry)
            saved = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            UIAccessibility.post(notification: .announcement, argument: String(localized: "単語帳に保存しました"))
        }, onAsk: allowsAI ? onAsk : nil, markdown: markdown)
        .overlay(alignment: .top) {
            if saved {
                Label(String(localized: "単語帳に保存しました"), systemImage: "checkmark.circle.fill")
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
    var markdown = false

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
        let rendered = markdown ? StudyMarkdown.render(text) : NSAttributedString(string: text, attributes: [.font: StudyTypography.bodyFont, .foregroundColor: StudyColors.bodyText])
        if changedSource || !view.attributedText.isEqual(to: rendered) {
            view.attributedText = rendered
            view.selectedRange = NSRange(location: 0, length: 0)
        }
    }

    static func dismantleUIView(_ view: UITextView, coordinator: Coordinator) {
        coordinator.stopPronunciation()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        return uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
    }

    final class Coordinator: NSObject, UITextViewDelegate, UIEditMenuInteractionDelegate, UIGestureRecognizerDelegate {
        private static let pronunciation = WordPronouncer()
        private static weak var speakingCoordinator: Coordinator?

        private func pronounce(_ expression: String) {
            Self.speakingCoordinator = self
            Self.pronunciation.toggle(expression)
        }

        func stopPronunciation() {
            guard Self.speakingCoordinator === self else { return }
            Self.pronunciation.stop()
            Self.speakingCoordinator = nil
        }

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
            let displayed = textView.text ?? ""
            guard range.length > 0, let selection = Range(range, in: displayed) else { return nil }
            let expression = String(displayed[selection])
            guard !expression.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            let entry = Entry(expression: expression, sourceText: displayed,
                              sourceID: current.sourceID, utf16Range: range)
            var actions: [UIMenuElement] = [
                UIAction(title: String(localized: "単語帳に追加"), image: UIImage(systemName: "text.badge.plus")) { _ in
                    StudySelectionDismissal.shared.clear()
                    current.onSave(entry)
                }
            ]
            if let ask = current.onAsk {
                actions.append(UIAction(title: String(localized: "AIに質問"), image: UIImage(systemName: "bubble.left")) { _ in
                    StudySelectionDismissal.shared.clear()
                    ask(entry)
                })
            }
            actions.append(UIAction(title: String(localized: "Hear pronunciation"), image: UIImage(systemName: "speaker.wave.2")) { [weak self] _ in
                StudySelectionDismissal.shared.clear()
                self?.pronounce(entry.expression)
            })
            actions.append(UIAction(title: String(localized: "コピー"), image: UIImage(systemName: "doc.on.doc")) { _ in
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


/// Foundation parses CommonMark; UIKit preserves native selection and word actions.
enum StudyMarkdown {
    static func render(_ source: String) -> NSAttributedString {
        guard let parsed = try? AttributedString(markdown: source, options: .init(interpretedSyntax: .full)) else {
            return NSAttributedString(string: source, attributes: [.font: StudyTypography.bodyFont, .foregroundColor: StudyColors.bodyText])
        }
        let output = NSMutableAttributedString(string: "")
        var previousBlock: Int?
        var previousRow: Int?
        for run in parsed.runs {
            let components = run.presentationIntent?.components ?? []
            let block = components.first?.identity
            var heading: Int?, ordinal: Int?, ordered = false, depth = 0, quote = false, code = false, rowID: Int?, tableHeader = false
            for component in components {
                switch component.kind {
                case .header(let level): heading = level
                case .listItem(let value): if ordinal == nil { ordinal = value }
                case .orderedList: if depth == 0 { ordered = true }; depth += 1
                case .unorderedList: depth += 1
                case .blockQuote: quote = true
                case .codeBlock: code = true
                case .tableHeaderRow: rowID = component.identity; tableHeader = true
                case .tableRow: rowID = component.identity
                default: break
                }
            }
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 4
            paragraph.paragraphSpacing = heading == nil ? 12 : 16
            paragraph.headIndent = CGFloat(max(0, depth - 1)) * 18 + (ordinal == nil ? 0 : 24) + (quote ? 14 : 0)
            paragraph.firstLineHeadIndent = CGFloat(max(0, depth - 1)) * 18 + (quote ? 14 : 0)
            var font = StudyTypography.bodyFont
            if let heading { font = UIFont.preferredFont(forTextStyle: heading == 1 ? .title2 : heading == 2 ? .title3 : .headline) }
            let inline = run.inlinePresentationIntent ?? []
            if code || inline.contains(.code) { font = .monospacedSystemFont(ofSize: font.pointSize * 0.92, weight: .regular) }
            var traits = font.fontDescriptor.symbolicTraits
            if heading != nil || tableHeader || inline.contains(.stronglyEmphasized) { traits.insert(.traitBold) }
            if inline.contains(.emphasized) { traits.insert(.traitItalic) }
            if let descriptor = font.fontDescriptor.withSymbolicTraits(traits) { font = UIFont(descriptor: descriptor, size: font.pointSize) }
            var attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: StudyColors.bodyText, .paragraphStyle: paragraph]
            if inline.contains(.strikethrough) { attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            if code || inline.contains(.code) { attrs[.backgroundColor] = UIColor.secondarySystemBackground }
            if let link = run.link, ["https", "http"].contains(link.scheme?.lowercased() ?? "") { attrs[.link] = link }
            if block != previousBlock {
                if output.length > 0 { output.append(NSAttributedString(string: rowID != nil && rowID == previousRow ? "  |  " : "\n", attributes: attrs)) }
                if let ordinal { output.append(NSAttributedString(string: ordered ? "\(ordinal).  " : "•  ", attributes: attrs)) }
                previousBlock = block; previousRow = rowID
            }
            output.append(NSAttributedString(string: String(parsed[run.range].characters), attributes: attrs))
        }
        return output
    }
}
