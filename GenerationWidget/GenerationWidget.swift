import ActivityKit
import SwiftUI
import WidgetKit

@main
struct GenerationWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: GenerationActivity.self) { context in
            VStack(alignment: .leading, spacing: 8) {
                Label(context.state.title, systemImage: "arrow.down.circle")
                ProgressView(value: Double(context.state.percent), total: 100)
                Text(context.state.percent, format: .percent.scale(1))
                    .font(.caption.monospacedDigit())
            }
            .padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Text(verbatim: context.state.title) }
                DynamicIslandExpandedRegion(.trailing) { percentage(context) }
                DynamicIslandExpandedRegion(.bottom) {
                    ProgressView(value: Double(context.state.percent), total: 100)
                }
            } compactLeading: {
                Image(systemName: "arrow.down.circle")
            } compactTrailing: {
                percentage(context)
            } minimal: {
                Image(systemName: "arrow.down.circle")
            }
        }
    }

    private func percentage(_ context: ActivityViewContext<GenerationActivity>) -> some View {
        Text(context.state.percent, format: .percent.scale(1)).monospacedDigit()
    }
}
