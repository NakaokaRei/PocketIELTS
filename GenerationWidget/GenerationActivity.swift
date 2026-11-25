import ActivityKit

struct GenerationActivity: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var title: String
        var percent: Int
    }
}
