import SwiftUI

/// Present this view from the part picker using a sheet or fullScreenCover.
/// Replace the question inside its content to keep one session on the stack.
struct IELTSPracticeSession<Content: View>: View {
    let title: String
    let finish: () -> Void
    var saveBeforeFinish: (() -> Void)? = nil
    var savingDescription: String = ""
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
                            if saveBeforeFinish != nil { confirmSave = true }
                            else { finish(); dismiss() }
                        }
                    }
                }
        }
        .interactiveDismissDisabled(saveBeforeFinish != nil)
        .alert(String(localized: "練習を終了しますか？"), isPresented: $confirmSave) {
            Button(String(localized: "保存して終了")) { saveBeforeFinish?(); finish(); dismiss() }
            Button(String(localized: "保存せずに終了"), role: .destructive) { finish(); dismiss() }
            Button(String(localized: "続ける"), role: .cancel) {}
        } message: { Text(String(localized: "あとで復習できるように問題を保存しますか？") + "\n\n" + savingDescription) }
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
