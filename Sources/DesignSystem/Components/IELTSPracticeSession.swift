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
                        Button("終了") {
                            finish()
                            dismiss()
                        }
                    }
                }
        }
    }
}
