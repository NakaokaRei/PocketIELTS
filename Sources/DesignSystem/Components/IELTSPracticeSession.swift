import SwiftUI

/// Present this view from the part picker using a sheet or fullScreenCover.
/// Replace the question inside its content to keep one session on the stack.
struct IELTSPracticeSession<Content: View>: View {
    let title: String
    let finish: () -> Void
    var save: (() -> Void)?
    @State private var confirmSave = false
    @ViewBuilder let content: () -> Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            content()
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(String(localized: "終了")) {
                            confirmSave = true
                        }
                    }
                    if let save {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(String(localized: "この問題を保存"), systemImage: "bookmark", action: save).labelStyle(.iconOnly)
                        }
                    }
                }
        }
        .interactiveDismissDisabled()
        .alert(String(localized: "練習を終了しますか？"), isPresented: $confirmSave) {
            Button(String(localized: "練習を終了"), role: .destructive) { finish(); dismiss() }
            Button(String(localized: "続ける"), role: .cancel) {}
        }
    }
}

struct ShortAnswerField: View {
    @Binding var text: String
    @State private var selection: TextSelection?

    var body: some View {
        HStack(spacing: 8) {
            TextField(String(localized: "解答"), text: $text, selection: $selection)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            AnswerPasteControl(insert: insert)
                .frame(width: 44, height: 44)
        }
    }

    private func insert(_ pasted: String) {
        let range: Range<String.Index>
        if let selection, case .selection(let selectedRange) = selection.indices {
            range = selectedRange
        } else {
            range = text.endIndex..<text.endIndex
        }
        let prefix = text[..<range.lowerBound] + pasted
        text = String(prefix) + text[range.upperBound...]
        selection = TextSelection(insertionPoint: String.Index(utf16Offset: prefix.utf16.count, in: text))
    }
}

private struct AnswerPasteControl: UIViewRepresentable {
    let insert: (String) -> Void

    final class Target: UIResponder {
        var insert: ((String) -> Void)?

        override init() {
            super.init()
            pasteConfiguration = UIPasteConfiguration(forAccepting: NSString.self)
        }

        override func paste(itemProviders: [NSItemProvider]) {
            guard let provider = itemProviders.first(where: { $0.canLoadObject(ofClass: NSString.self) }) else { return }
            provider.loadObject(ofClass: NSString.self) { [weak self] value, _ in
                guard let text = value as? String, !text.isEmpty else { return }
                Task { @MainActor in self?.insert?(text) }
            }
        }
    }

    func makeCoordinator() -> Target { Target() }

    func makeUIView(context: Context) -> UIPasteControl {
        let configuration = UIPasteControl.Configuration()
        configuration.displayMode = .iconOnly
        configuration.baseForegroundColor = UIColor(StudyColors.accent)
        configuration.baseBackgroundColor = .secondarySystemGroupedBackground
        let control = UIPasteControl(configuration: configuration)
        control.accessibilityIdentifier = "answer.paste"
        control.accessibilityLabel = String(localized: "Paste")
        return control
    }

    func updateUIView(_ control: UIPasteControl, context: Context) {
        context.coordinator.insert = insert
        control.target = context.environment.isEnabled ? context.coordinator : nil
    }
}

/// A visible, full-hit-area action for supporting study tasks.
struct StudySecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(StudyTypography.button)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .foregroundStyle(.tint)
            .background(.tint.opacity(configuration.isPressed ? 0.20 : 0.08), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.tint.opacity(0.35), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 16))
            .opacity(isEnabled ? 1 : 0.45)
    }
}

/// Keeps study actions stable when their title or the surrounding content changes.
struct StudyPrimaryButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(StudyTypography.headline)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.horizontal, 16).padding(.vertical, 8)
            .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
            .background(StudyColors.accent, in: RoundedRectangle(cornerRadius: 18))
            .opacity(!isEnabled ? 0.45 : configuration.isPressed ? 0.8 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 18))
    }
}
