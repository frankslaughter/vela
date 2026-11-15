import LiveKit
import SwiftUI

/// The screen the crew lives on. Three big buttons: mute in the middle, mode and channel below.
struct IntercomView: View {
    @EnvironmentObject private var intercom: Intercom
    @State private var isShowingSettings = false
    @State private var isConfirmingLeave = false

    private var isReconnecting: Bool { intercom.phase == .reconnecting }

    var body: some View {
        VStack(spacing: 14) {
            header
            TalkerStrip(talkers: intercom.talkers)
            if let notice = intercom.notice {
                NoticeBanner(text: notice.text)
            }
            MuteButton()
            MicMeterBar()
            HStack(spacing: 14) {
                ControlButton(title: "Mode", value: intercom.mode.label, systemImage: "waveform") {
                    intercom.cycleMode()
                }
                ControlButton(title: "Channel", value: intercom.channel, systemImage: "person.2.fill") {
                    intercom.cycleChannel()
                }
                .disabled(intercom.channels.count < 2 || isReconnecting)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .sheet(isPresented: $isShowingSettings) { SettingsView() }
        .animation(.easeOut(duration: 0.15), value: intercom.notice)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(intercom.boatName)
                    .font(.title2.bold())
                    .lineLimit(1)
                Text(statusText)
                    .font(.subheadline)
                    .foregroundStyle(isReconnecting ? Theme.warning : .white.opacity(0.7))
            }
            Spacer()
            BatteryLabel()
            Button { isConfirmingLeave = true } label: {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.title2)
                    .frame(width: 52, height: 52)
                    .background(Theme.card, in: Circle())
            }
            .tint(.white)
            .accessibilityLabel("Leave the boat")
            // Asking first means a wet thumb cannot drop someone off the intercom.
            .confirmationDialog("Leave \(intercom.boatName)?", isPresented: $isConfirmingLeave, titleVisibility: .visible) {
                Button("Leave", role: .destructive) { intercom.leave() }
                Button("Stay", role: .cancel) {}
            } message: {
                Text("You go off the intercom. Vela will not rejoin until you pick the boat again.")
            }
            Button { isShowingSettings = true } label: {
                Image(systemName: "gearshape.fill")
                    .font(.title2)
                    .frame(width: 52, height: 52)
                    .background(Theme.card, in: Circle())
            }
            .tint(.white)
            .accessibilityLabel("Settings")
        }
        .padding(.top, 8)
    }

    private var statusText: String {
        if isReconnecting { return "Reconnecting" }
        let count = intercom.talkers.count
        var text = count == 1 ? "Only you on \(intercom.channel)" : "\(count) on \(intercom.channel)"
        switch intercom.quality {
        case .poor: text += " · weak signal"
        case .lost: text += " · no signal"
        default: break
        }
        return text
    }
}

/// The mute toggle, or the talk button in PTT. It takes all the space it can get.
private struct MuteButton: View {
    @EnvironmentObject private var intercom: Intercom
    @EnvironmentObject private var meter: MicMeter

    private struct Look {
        var title: String
        var hint: String
        var symbol: String
        var color: Color
    }

    private var look: Look {
        if intercom.phase == .reconnecting {
            return Look(title: "OFFLINE", hint: "Getting the boat back", symbol: "wifi.slash", color: Theme.idle)
        }
        if intercom.isMicUnavailable {
            return Look(title: "MIC OFF", hint: "Listening only. Tap to try the microphone again", symbol: "mic.slash.fill", color: Theme.idle)
        }
        switch intercom.mode {
        case .ptt:
            return intercom.isTalking
                ? Look(title: "TALKING", hint: "Release to stop", symbol: "mic.fill", color: Theme.live)
                : Look(title: "HOLD TO TALK", hint: "Or press the headset button to latch", symbol: "mic.slash.fill", color: Theme.idle)
        case .vox:
            if intercom.isMuted { return Look(title: "MUTED", hint: "Tap to unmute", symbol: "mic.slash.fill", color: Theme.muted) }
            return Look(title: "LIVE", hint: meter.isGateOpen ? "VOX: sending" : "VOX: waiting for your voice", symbol: "mic.fill", color: Theme.live)
        case .open:
            return intercom.isMuted
                ? Look(title: "MUTED", hint: "Tap to unmute", symbol: "mic.slash.fill", color: Theme.muted)
                : Look(title: "LIVE", hint: "Tap to mute", symbol: "mic.fill", color: Theme.live)
        }
    }

    var body: some View {
        let look = look
        RoundedRectangle(cornerRadius: 32)
            .fill(look.color)
            .overlay {
                VStack(spacing: 14) {
                    Image(systemName: look.symbol)
                        .font(.system(size: 84, weight: .semibold))
                    Text(look.title)
                        .font(.system(size: 46, weight: .heavy, design: .rounded))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    Text(look.hint)
                        .font(.title3)
                        .opacity(0.85)
                        .multilineTextAlignment(.center)
                }
                .padding(20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(RoundedRectangle(cornerRadius: 32))
            .onTapGesture {
                if intercom.isMicUnavailable {
                    intercom.becameActive()
                } else if intercom.mode != .ptt {
                    intercom.toggleMute()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in intercom.setTalkHeld(true) }
                    .onEnded { _ in intercom.setTalkHeld(false) },
                isEnabled: intercom.mode == .ptt && !intercom.isMicUnavailable
            )
            .sensoryFeedback(.impact(weight: .heavy), trigger: intercom.isSilent)
            .animation(.easeOut(duration: 0.12), value: look.title)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(look.title.capitalized)
            .accessibilityHint(look.hint)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                if intercom.mode != .ptt { intercom.toggleMute() }
            }
    }
}

/// Who is on the channel, with whoever is speaking lit up.
private struct TalkerStrip: View {
    let talkers: [Talker]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(talkers) { talker in
                    HStack(spacing: 8) {
                        Image(systemName: talker.isMuted ? "mic.slash.fill" : (talker.isSpeaking ? "waveform" : "mic.fill"))
                            .font(.body.weight(.semibold))
                        Text(talker.isLocal ? "You" : talker.name)
                            .font(.title3.weight(.semibold))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 52)
                    .background(talker.isSpeaking ? Theme.live : Theme.card, in: Capsule())
                    .opacity(talker.isMuted ? 0.6 : 1)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(talker.isLocal ? "You" : talker.name), \(talker.isMuted ? "muted" : (talker.isSpeaking ? "speaking" : "live"))")
                }
            }
        }
        .frame(height: 52)
        .animation(.easeOut(duration: 0.1), value: talkers)
    }
}

private struct NoticeBanner: View {
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill").font(.title2)
            Text(text).font(.title3.weight(.semibold))
            Spacer(minLength: 0)
        }
        .foregroundStyle(.black)
        .padding(14)
        .background(Theme.warning, in: RoundedRectangle(cornerRadius: 16))
        .transition(.opacity)
    }
}

/// A thin level meter under the big button: proof the microphone hears something.
private struct MicMeterBar: View {
    @EnvironmentObject private var meter: MicMeter

    /// Maps -70 dBFS and below to empty, 0 dBFS to full.
    private var fraction: Double {
        Double(min(1, max(0, (meter.levelDB + 70) / 70)))
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.card)
                Capsule()
                    .fill(meter.isGateOpen ? Theme.live : Color.white.opacity(0.35))
                    .frame(width: max(6, proxy.size.width * fraction))
            }
        }
        .frame(height: 6)
        .animation(.linear(duration: 0.2), value: fraction)
        .accessibilityHidden(true)
    }
}

private struct ControlButton: View {
    let title: String
    let value: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Label(title.uppercased(), systemImage: systemImage)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
                Text(value)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .frame(maxWidth: .infinity, minHeight: 96)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 22))
        }
        .tint(.white)
        .sensoryFeedback(.selection, trigger: value)
        .accessibilityLabel("\(title): \(value)")
        .accessibilityHint("Changes the \(title.lowercased())")
    }
}

/// The phone's own battery, refreshed every half minute.
private struct BatteryLabel: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            let level = UIDevice.current.batteryLevel
            if level >= 0 {
                Label("\(Int((level * 100).rounded()))%", systemImage: symbol(for: level))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(level < 0.2 ? Theme.warning : .white.opacity(0.7))
            }
        }
        .onAppear { UIDevice.current.isBatteryMonitoringEnabled = true }
    }

    private func symbol(for level: Float) -> String {
        switch level {
        case ..<0.2: "battery.25percent"
        case ..<0.6: "battery.50percent"
        case ..<0.9: "battery.75percent"
        default: "battery.100percent"
        }
    }
}
