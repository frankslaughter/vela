import ActivityKit
import SwiftUI
import WidgetKit

/// Lock-screen and Dynamic Island view of "am I live?", with a mute toggle
/// that works without unlocking the phone.
struct MuteLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MuteActivityAttributes.self) { context in
            LockScreenView(boat: context.attributes.boat, state: trusted(context))
                .activityBackgroundTint(Color.black.opacity(0.55))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    StateGlyph(state: trusted(context)).font(.title2)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(statusText(trusted(context))).font(.headline)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.channel).font(.subheadline).foregroundStyle(.secondary)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    MuteButton(state: trusted(context))
                }
            } compactLeading: {
                StateGlyph(state: trusted(context))
            } compactTrailing: {
                Text(shortText(trusted(context))).font(.caption.weight(.semibold))
            } minimal: {
                StateGlyph(state: trusted(context))
            }
        }
    }
}

/// The state to draw. A card the app has stopped refreshing cannot be believed,
/// so it is drawn as not connected, whatever it last said.
private func trusted(_ context: ActivityViewContext<MuteActivityAttributes>) -> MuteActivityAttributes.ContentState {
    var state = context.state
    if context.isStale { state.isConnected = false }
    return state
}

private func statusText(_ state: MuteActivityAttributes.ContentState) -> String {
    if !state.isConnected { return "Not connected" }
    return state.isMuted ? "Muted" : "Live"
}

private func shortText(_ state: MuteActivityAttributes.ContentState) -> String {
    if !state.isConnected { return "Off" }
    return state.isMuted ? "Muted" : "Live"
}

private func stateColor(_ state: MuteActivityAttributes.ContentState) -> Color {
    if !state.isConnected { return .gray }
    return state.isMuted ? .red : .green
}

private struct StateGlyph: View {
    let state: MuteActivityAttributes.ContentState

    var body: some View {
        Image(systemName: !state.isConnected ? "wifi.slash" : (state.isMuted ? "mic.slash.fill" : "mic.fill"))
            .foregroundStyle(stateColor(state))
    }
}

private struct MuteButton: View {
    let state: MuteActivityAttributes.ContentState

    var body: some View {
        Button(intent: ToggleMuteIntent()) {
            Label(state.isMuted ? "Unmute" : "Mute", systemImage: state.isMuted ? "mic.fill" : "mic.slash.fill")
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .tint(state.isMuted ? .green : .red)
        .disabled(!state.isConnected)
    }
}

private struct LockScreenView: View {
    let boat: String
    let state: MuteActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 14) {
            StateGlyph(state: state)
                .font(.system(size: 34))
                .frame(width: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(statusText(state))
                    .font(.title2.weight(.bold))
                    .foregroundStyle(stateColor(state))
                Text("\(state.channel) · \(state.mode)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                Text(boat)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            MuteButton(state: state)
                .frame(width: 130)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}
