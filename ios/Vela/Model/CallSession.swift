import AVFAudio
import CallKit
import LiveKit
import OSLog

/// Registers the intercom session with iOS as a phone call. Experimental, behind a switch in Settings.
///
/// Why: while the intercom holds a Bluetooth headset in its hands-free profile, the headset's
/// button sends "hang up", and iOS passes that only to an app that has a call registered here.
/// The press arrives as a request to end the call. iOS ends the call whether or not the app
/// agrees (refusing was tried on 2026-11-14 and the call went away regardless), so the app
/// agrees, starts a new call at once, and treats the whole thing as one button press.
///
/// A registered call also changes who owns the audio: iOS switches the audio session on and off,
/// and LiveKit's audio engine may only run in between.
@MainActor
final class CallSession: NSObject {
    /// iOS ended the call: the headset button, the End button in the system's call display,
    /// or a phone call accepted with End & Accept. There is no call any more.
    var onEnded: (() -> Void)?
    /// The mute button in the system's call display.
    var onMuteRequested: ((Bool) -> Void)?
    /// A phone call took over (true) or gave the audio back (false).
    var onHeld: ((Bool) -> Void)?

    /// iOS owns the audio session, not LiveKit.
    private(set) var isEnabled = false
    var hasCall: Bool { callID != nil }

    private let provider: CXProvider
    private let controller = CXCallController()
    private let log = Logger(subsystem: "com.tower3.vela", category: "call")
    private var callID: UUID?
    private var callName = ""
    private var isAudioActive = false
    private var activations = 0
    private var deactivations = 0
    private var sessionOptions: AVAudioSession.CategoryOptions = [.allowBluetoothHFP]

    override init() {
        let configuration = CXProviderConfiguration()
        configuration.supportsVideo = false
        configuration.maximumCallGroups = 1
        configuration.maximumCallsPerCallGroup = 1
        configuration.supportedHandleTypes = [.generic]
        configuration.includesCallsInRecents = false
        provider = CXProvider(configuration: configuration)
        super.init()
        provider.setDelegate(self, queue: .main)
    }

    /// Hands the audio session to iOS (on) or back to LiveKit (off).
    /// Call it with the room disconnected and the microphone pipeline stopped.
    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        log.info("Call mode \(enabled)")
        if enabled {
            AudioManager.shared.audioSession.isAutomaticConfigurationEnabled = false
            if !isAudioActive { try? AudioManager.shared.setEngineAvailability(.none) }
        } else {
            end()
            AudioManager.shared.audioSession.isAutomaticConfigurationEnabled = true
            try? AudioManager.shared.setEngineAvailability(.default)
        }
    }

    /// Starts the call if there is none, and waits until iOS has switched the audio on.
    func begin(boat: String, options: AVAudioSession.CategoryOptions) async throws {
        sessionOptions = options
        callName = boat
        let isNewCall = callID == nil
        let seenOn = activations, seenOff = deactivations
        if let callID {
            provider.reportCall(with: callID, updated: update())
        } else {
            let id = UUID()
            callID = id
            let action = CXStartCallAction(call: id, handle: CXHandle(type: .generic, value: boat))
            action.isVideo = false
            do {
                try await controller.request(CXTransaction(action: action))
            } catch {
                callID = nil
                throw error
            }
        }
        if !isNewCall, isAudioActive { return } // the call from before, still running

        // Wait for iOS to switch the audio on for this call. When a call replaces one that
        // just ended, the audio may never have been switched off; a second and a half
        // without that happening is taken as proof.
        for tick in 0 ..< 50 {
            if activations > seenOn { break }
            if tick >= 15, isAudioActive, deactivations == seenOff { break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard isAudioActive else {
            end()
            throw ControlError(message: "iOS did not start the call's audio.")
        }
    }

    /// Ends the call from our side. Safe to call with no call.
    func end() {
        guard let id = callID else { return }
        log.info("Ending the call")
        callID = nil
        provider.reportCall(with: id, endedAt: nil, reason: .remoteEnded)
    }

    /// Keeps the system's call display in step with the app's own mute.
    func showMuted(_ muted: Bool) {
        guard let callID else { return }
        controller.request(CXTransaction(action: CXSetMutedCallAction(call: callID, muted: muted))) { _ in }
    }

    private func update() -> CXCallUpdate {
        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .generic, value: callName)
        update.localizedCallerName = callName
        update.hasVideo = false
        update.supportsHolding = true // lets a phone call be taken without ending the intercom
        update.supportsGrouping = false
        update.supportsUngrouping = false
        update.supportsDTMF = false
        return update
    }

    private func configureSession(_ session: AVAudioSession) {
        do {
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: sessionOptions)
        } catch {
            log.error("Audio session not configured: \(String(describing: error), privacy: .public)")
        }
    }

    // The delegate queue is the main queue, so each callback below is already on the main actor.

    private func started(_ action: CXStartCallAction) {
        configureSession(AVAudioSession.sharedInstance())
        action.fulfill()
        provider.reportOutgoingCall(with: action.callUUID, startedConnectingAt: nil)
        provider.reportOutgoingCall(with: action.callUUID, connectedAt: nil)
        provider.reportCall(with: action.callUUID, updated: update())
        log.info("Call started")
    }

    private func endRequested(_ action: CXEndCallAction) {
        action.fulfill()
        guard action.callUUID == callID else { return }
        log.info("iOS ended the call: headset button, call display, or a phone call")
        callID = nil
        onEnded?()
    }

    private func audioChanged(active: Bool, session: AVAudioSession) {
        log.info("Call audio active \(active)")
        isAudioActive = active
        if active { activations += 1 } else { deactivations += 1 }
        guard isEnabled else { return }
        if active { configureSession(session) }
        do {
            try AudioManager.shared.setEngineAvailability(active ? .default : .none)
        } catch {
            log.error("Audio engine availability not set: \(String(describing: error), privacy: .public)")
        }
    }

    private func reset() {
        log.error("iOS reset the call provider")
        callID = nil
        audioChanged(active: false, session: .sharedInstance())
    }
}

extension CallSession: CXProviderDelegate {
    nonisolated func providerDidReset(_: CXProvider) {
        MainActor.assumeIsolated { reset() }
    }

    nonisolated func provider(_: CXProvider, perform action: CXStartCallAction) {
        MainActor.assumeIsolated { started(action) }
    }

    nonisolated func provider(_: CXProvider, perform action: CXEndCallAction) {
        MainActor.assumeIsolated { endRequested(action) }
    }

    nonisolated func provider(_: CXProvider, perform action: CXSetMutedCallAction) {
        MainActor.assumeIsolated {
            onMuteRequested?(action.isMuted)
            action.fulfill()
        }
    }

    nonisolated func provider(_: CXProvider, perform action: CXSetHeldCallAction) {
        MainActor.assumeIsolated {
            onHeld?(action.isOnHold)
            action.fulfill()
        }
    }

    nonisolated func provider(_: CXProvider, didActivate audioSession: AVAudioSession) {
        MainActor.assumeIsolated { audioChanged(active: true, session: audioSession) }
    }

    nonisolated func provider(_: CXProvider, didDeactivate audioSession: AVAudioSession) {
        MainActor.assumeIsolated { audioChanged(active: false, session: audioSession) }
    }
}
