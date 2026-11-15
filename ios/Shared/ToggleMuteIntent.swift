import AppIntents

/// The mute button on the lock-screen Live Activity.
///
/// A `LiveActivityIntent` runs inside the app's process, not the widget's, so it can
/// reach the live intercom through `MuteIntentBridge`.
struct ToggleMuteIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Toggle mute"
    static var description = IntentDescription("Mutes or unmutes your microphone on the boat intercom.")

    func perform() async throws -> some IntentResult {
        await MuteIntentBridge.toggle()
        return .result()
    }
}

/// Set by the app at launch. Empty in the widget extension, where the intent never runs.
enum MuteIntentBridge {
    @MainActor static var handler: (() -> Void)?

    @MainActor static func toggle() {
        handler?()
    }
}
