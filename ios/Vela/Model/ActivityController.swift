import ActivityKit
import Foundation

/// Owns the lock-screen Live Activity that shows mute state.
///
/// iOS only lets an app start a Live Activity while it is in the foreground, so a join
/// that happens with the phone in a pocket shows nothing until the app is next opened.
/// Updates and the mute button work from the background once it exists.
///
/// The card must never claim "Live" after the app has gone. Two things see to that:
/// it is removed when the app is closed, and every update carries an expiry, after which
/// the card shows "Not connected" until the running app refreshes it.
@MainActor
final class ActivityController {
    /// How long a card is trusted without a refresh. The app refreshes it every `refreshInterval`.
    static let trustedFor: TimeInterval = 90
    static let refreshInterval: TimeInterval = 45

    private var activity: Activity<MuteActivityAttributes>?

    /// Ends anything left over from a previous run of the app.
    func endAll() {
        activity = nil
        for stale in Activity<MuteActivityAttributes>.activities {
            Task { await stale.end(nil, dismissalPolicy: .immediate) }
        }
    }

    /// Removes every card and waits for it, for the moment the app is being closed.
    /// Safe to call from the main thread: the work runs elsewhere and this waits at most two seconds.
    nonisolated static func endAllBeforeExit(alsoRunning extra: @escaping @Sendable () async -> Void = {}) {
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            for card in Activity<MuteActivityAttributes>.activities {
                await card.end(nil, dismissalPolicy: .immediate)
            }
            await extra()
            done.signal()
        }
        _ = done.wait(timeout: .now() + 2)
    }

    func show(boat: String, state: MuteActivityAttributes.ContentState) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(Self.trustedFor))

        if let activity, activity.attributes.boat == boat, activity.activityState == .active {
            Task { await activity.update(content) }
            return
        }

        endAll()
        // Fails quietly in the background; the next foreground update tries again.
        activity = try? Activity.request(attributes: MuteActivityAttributes(boat: boat), content: content, pushType: nil)
    }
}
