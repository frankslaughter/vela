import ActivityKit
import Foundation

/// What the lock-screen Live Activity shows. Shared by the app and the widget extension.
struct MuteActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var isMuted: Bool
        var isConnected: Bool
        var channel: String
        /// "Open", "VOX" or "PTT".
        var mode: String
    }

    var boat: String
}
