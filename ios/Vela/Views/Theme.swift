import SwiftUI

/// Colours chosen to be told apart at a glance in sunlight: green is live, red is muted.
enum Theme {
    static let background = Color(red: 0.04, green: 0.08, blue: 0.11)
    static let card = Color.white.opacity(0.08)
    static let live = Color(red: 0.13, green: 0.62, blue: 0.33)
    static let muted = Color(red: 0.80, green: 0.20, blue: 0.18)
    static let idle = Color.white.opacity(0.16)
    static let warning = Color(red: 0.98, green: 0.78, blue: 0.25)
}
