import SwiftUI

/// Present this view from the part picker using a sheet or fullScreenCover.
/// Replace the question inside its content to keep one session on the stack.
struct IELTSPracticeSession<Content: View>: View {
    let title: String
    let finish: () -> Void
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
                            finish()
                            dismiss()
                        }
                    }
                }
        }
    }
}

/// A visible, full-hit-area action for supporting study tasks.
struct StudySecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
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
