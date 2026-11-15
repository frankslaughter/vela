import AVFAudio
import Combine
import LiveKit
import OSLog
import UIKit

/// One person on the current channel, for the who-is-talking strip.
struct Talker: Identifiable, Equatable {
    let id: String
    var name: String
    var isSpeaking: Bool
    var isMuted: Bool
    var isLocal: Bool
}

/// Things the wearer needs to be told, in the ear and on the screen.
enum Notice: Equatable {
    case youreMuted
    case deadMic
    case headsetGone
    case micUnavailable

    var text: String {
        switch self {
        case .youreMuted: "You're muted"
        case .deadMic: "Your microphone is sending silence. Check the mute button on the headset boom."
        case .headsetGone: "Headset disconnected. You have been muted."
        case .micUnavailable: "Listening only. Your microphone has not started. Tap the big button to try again."
        }
    }
}

/// The microphone meter, kept apart from `Intercom` so five updates a second
/// redraw one small view and not the whole screen.
@MainActor
final class MicMeter: ObservableObject {
    @Published fileprivate(set) var levelDB: Float = -120
    @Published fileprivate(set) var isGateOpen = false
}

/// The intercom itself: finds the boat, joins it, and owns mute, talk mode and channel.
@MainActor
final class Intercom: NSObject, ObservableObject {
    static let shared = Intercom()

    enum Phase: Equatable {
        case needsName
        /// Browsing for boats, not on one.
        case looking
        case joining(String)
        case connected
        /// On a boat, but the link dropped and LiveKit is getting it back.
        case reconnecting

        var isAboard: Bool { self == .connected || self == .reconnecting }
    }

    @Published private(set) var phase: Phase = .looking
    @Published private(set) var boats: [Boat] = []
    @Published private(set) var boatName = ""
    @Published private(set) var channels: [String] = []
    @Published private(set) var channel = ""
    @Published private(set) var isMuted = Preferences.isMuted
    @Published private(set) var mode = Preferences.mode
    /// PTT only: the talk button is held, or the headset button latched it.
    @Published private(set) var isTalking = false
    /// On the boat and listening, but iOS would not start the microphone.
    /// It refuses when the app is not on screen and has no audio already running.
    @Published private(set) var isMicUnavailable = false
    @Published private(set) var talkers: [Talker] = []
    @Published private(set) var notice: Notice?
    /// Why the last join failed, or that the boat was lost.
    @Published private(set) var problem: String?
    /// Why the search for boats is not working.
    @Published private(set) var searchProblem: String?
    @Published private(set) var quality: ConnectionQuality = .unknown
    @Published private(set) var displayName = Preferences.displayName
    @Published private(set) var usesSpeakerWithoutHeadset = Preferences.usesSpeakerWithoutHeadset
    /// Experimental: register the session with iOS as a call, so a headset's button reaches us.
    @Published private(set) var usesCallKit = Preferences.usesCallKit
    /// The boat to be on. Set by choosing one, cleared by leaving.
    @Published private(set) var wantedBoat = Preferences.boatName

    let meter = MicMeter()

    /// True when nothing of yours can be heard: muted, or in PTT and not talking.
    var isSilent: Bool { isMicUnavailable || (mode == .ptt ? !isTalking : isMuted) }

    private let room = Room()
    private let browser = BoatBrowser()
    private let gate = MicGate()
    private let tones = Tones()
    private let headset = HeadsetButton()
    private let activity = ActivityController()
    private let call = CallSession()
    /// Read these in Console.app, filtered on the subsystem, when testing on a phone.
    private let log = Logger(subsystem: "com.tower3.vela", category: "intercom")

    private var hasStarted = false
    /// The app has been on screen at least once since it was started.
    private var hasBeenOnScreen = false
    private var currentBoat: Boat?
    private var joinTask: Task<Void, Never>?
    private var joinGeneration = 0
    private var retryTask: Task<Void, Never>?
    /// Seconds before the next join attempt. Doubles after each failure, so a boat that
    /// cannot be joined is not hammered; back to three seconds on any success or user action.
    private var retryDelay: Double = 3
    private var isRestartingCall = false
    private var isTalkHeld = false
    private var isTalkLatched = false
    private var mutedSpeechSince: Date?
    private var lastReminder = Date.distantPast
    private var mutedBeforeInterruption: Bool?
    private var noticeTask: Task<Void, Never>?
    private var cardRefreshTask: Task<Void, Never>?
    #if targetEnvironment(simulator)
    private var simulatedMicFailures = 0
    #endif

    // MARK: - Start-up

    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        room.delegates.add(delegate: self)

        #if targetEnvironment(simulator)
        // The simulator's audio device hangs on some Macs. Launching with `-noAudioDevice YES`
        // runs the audio engine without one, so everything except sound can still be exercised.
        if UserDefaults.standard.bool(forKey: "noAudioDevice") {
            try? AudioManager.shared.setManualRenderingMode(true)
        }
        #endif

        // Mute through Apple's voice processing. It is fast, iOS plays its own mute and
        // unmute tones in the ear, and it can still tell when a muted person is speaking.
        try? AudioManager.shared.set(microphoneMuteMode: .voiceProcessing)
        AudioManager.shared.capturePostProcessingDelegate = gate
        AudioManager.shared.onMutedSpeechActivity = { [weak self] _, event in
            Task { @MainActor in self?.mutedSpeech(event) }
        }
        applyAudioSessionPreference()

        // In PTT the talk button is the only gate. A mute saved from another mode would make it a dead button.
        if mode == .ptt, isMuted {
            isMuted = false
            Preferences.isMuted = false
        }

        gate.onReport = { [weak self] report in
            Task { @MainActor in self?.gateReported(report) }
        }
        syncGate()

        headset.onPress = { [weak self] in self?.buttonPressed() }
        headset.start()
        MuteIntentBridge.handler = { [weak self] in self?.buttonPressed() }
        call.onEnded = { [weak self] in self?.callEndedByPhone() }
        call.onMuteRequested = { [weak self] muted in
            guard let self, mode != .ptt else { return }
            setMuted(muted)
        }
        call.onHeld = { [weak self] held in self?.audioInterrupted(held ? .began : .ended) }
        activity.endAll()

        let center = NotificationCenter.default
        center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            Task { @MainActor in self?.audioInterrupted(raw.flatMap(AVAudioSession.InterruptionType.init)) }
        }
        center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.hasBeenOnScreen = true
                self?.tryAutoJoin()
            }
        }
        center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            Task { @MainActor in self?.routeChanged(raw.flatMap(AVAudioSession.RouteChangeReason.init)) }
        }

        browser.onChange = { [weak self] boats in
            self?.boats = boats
            self?.tryAutoJoin()
        }
        browser.onProblem = { [weak self] message in self?.searchProblem = message }
        browser.start()

        phase = displayName.isEmpty ? .needsName : .looking
    }

    /// The app is being closed, for example swiped away in the app switcher.
    /// Take the card off the lock screen and tell the server, so neither claims we are still here.
    func willTerminate() {
        log.info("Closing: leaving the boat")
        call.end()
        let room = room
        ActivityController.endAllBeforeExit { await room.disconnect() }
    }

    /// The app came to the foreground.
    func becameActive() {
        guard hasStarted else { return }
        hasBeenOnScreen = true
        publishState() // a Live Activity can only be started from the foreground
        retryDelay = 3
        retryMicrophone() // and so can the microphone
        tryAutoJoin()
    }

    // MARK: - Things the person does

    func setDisplayName(_ name: String) {
        let trimmed = name.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !trimmed.isEmpty, trimmed != displayName else { return }
        displayName = trimmed
        Preferences.displayName = trimmed
        if phase == .needsName {
            phase = .looking
            tryAutoJoin()
        } else if phase.isAboard, let boat = currentBoat {
            join(boat, channel: channel) // a new token carries the new name
        }
    }

    /// Pick a boat from the list. It becomes the boat to join on sight from now on.
    func choose(_ boat: Boat) {
        wantedBoat = boat.name
        Preferences.boatName = boat.name
        retryDelay = 3
        join(boat)
    }

    /// Leave the boat and stop joining it on sight.
    func leave() {
        wantedBoat = nil
        Preferences.boatName = nil
        joinGeneration += 1
        joinTask?.cancel()
        joinTask = nil
        retryTask?.cancel()
        phase = .looking
        problem = nil
        notice = nil
        boatName = ""
        currentBoat = nil
        talkers = []
        isMicUnavailable = false
        Task {
            await room.disconnect()
            try? await AudioManager.shared.setRecordingAlwaysPreparedMode(false)
            // Unless a new join began meanwhile, which now owns the call.
            if joinTask == nil { call.end() }
        }
        publishState()
    }

    func toggleMute() {
        setMuted(!isMuted)
    }

    func setMuted(_ muted: Bool) {
        guard muted != isMuted else { return }
        isMuted = muted
        Preferences.isMuted = muted
        log.info("Muted \(muted)")
        mutedSpeechSince = nil
        lastReminder = .distantPast // each new mute earns its own reminder
        if !muted, notice == .youreMuted { notice = nil }
        syncGate()
        applyMicState()
        call.showMuted(muted)
        stateChanged()
    }

    func cycleMode() {
        mode = mode.next
        Preferences.mode = mode
        log.info("Mode \(self.mode.label, privacy: .public)")
        isTalkHeld = false
        isTalkLatched = false
        isTalking = false
        // In PTT the talk button is the only gate, so a leftover mute would make it a dead button.
        if mode == .ptt, isMuted { setMuted(false) }
        syncGate()
        stateChanged()
    }

    func cycleChannel() {
        guard phase == .connected, channels.count > 1, let boat = currentBoat,
              let index = channels.firstIndex(of: channel)
        else { return }
        join(boat, channel: channels[(index + 1) % channels.count])
    }

    /// PTT: the on-screen talk button went down or came up.
    func setTalkHeld(_ held: Bool) {
        guard mode == .ptt, held != isTalkHeld else { return }
        isTalkHeld = held
        if held { isTalkLatched = false } // holding takes over from a latch
        updateTalking()
    }

    func setUsesSpeakerWithoutHeadset(_ on: Bool) {
        usesSpeakerWithoutHeadset = on
        Preferences.usesSpeakerWithoutHeadset = on
        applyAudioSessionPreference()
    }

    /// Experimental. Takes effect by rejoining, because it changes who owns the audio session.
    func setUsesCallKit(_ on: Bool) {
        guard on != usesCallKit else { return }
        usesCallKit = on
        Preferences.usesCallKit = on
        if phase.isAboard, let boat = currentBoat { join(boat, channel: channel) }
    }

    /// iOS ended the call. Nearly always that is the headset's button, which can only say
    /// "hang up". Get a new call up first, so the audio is running again, then count the press.
    private func callEndedByPhone() {
        guard usesCallKit, phase.isAboard, !isRestartingCall, let boat = currentBoat else { return }
        isRestartingCall = true
        let generation = joinGeneration
        let began = Date()
        Task {
            defer { isRestartingCall = false }
            do {
                try await call.begin(boat: boatName, options: sessionOptions)
                guard generation == joinGeneration else { return }
                log.info("Call restarted in \(Int(Date().timeIntervalSince(began) * 1000)) ms")
                buttonPressed()
            } catch {
                guard generation == joinGeneration else { return }
                log.error("Call not restarted: \(String(describing: error), privacy: .public)")
                join(boat, channel: channel) // tries the call once more, then falls back to plain audio
            }
        }
    }

    /// The headset button or the lock-screen button: one press, no looking.
    private func buttonPressed() {
        guard phase.isAboard else { return }
        if mode == .ptt {
            isTalkLatched.toggle()
            tones.play(isTalkLatched ? .rising : .low)
            updateTalking()
        } else {
            toggleMute()
        }
    }

    private func updateTalking() {
        let talking = isTalkHeld || isTalkLatched
        guard talking != isTalking else { return }
        isTalking = talking
        log.info("Talking \(talking)")
        syncGate()
        stateChanged()
    }

    // MARK: - Joining

    private func tryAutoJoin() {
        // iOS can start the app unseen, for example when a headset button is pressed after
        // the app was closed. It will not give that app a microphone, and it suspends it
        // within a minute, so joining would only put a ghost on the roster. Wait to be opened.
        if !hasBeenOnScreen { hasBeenOnScreen = UIApplication.shared.applicationState == .active }
        guard hasBeenOnScreen else { return }
        guard phase == .looking, joinTask == nil, let wantedBoat,
              let boat = boats.first(where: { $0.name == wantedBoat })
        else { return }
        join(boat)
    }

    private func scheduleRetry() {
        retryTask?.cancel()
        let delay = retryDelay
        retryDelay = min(retryDelay * 2, 30)
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.tryAutoJoin()
        }
    }

    private func join(_ boat: Boat, channel requested: String? = nil) {
        joinGeneration += 1
        let generation = joinGeneration
        joinTask?.cancel()
        retryTask?.cancel()
        phase = .joining(boat.name)
        problem = nil
        log.info("Joining \(boat.name, privacy: .public) at \(boat.host, privacy: .public)")

        joinTask = Task { [weak self] in
            guard let self else { return }
            var beganCall = false
            do {
                guard await LiveKitSDK.ensureDeviceAccess(for: [.audio]) else {
                    throw ControlError(message: "Vela needs the microphone. Allow it in Settings.")
                }
                let ticket = try await ControlClient.join(boat: boat,
                                                          deviceID: Preferences.deviceID,
                                                          name: displayName,
                                                          channel: requested ?? Preferences.channel)
                guard generation == joinGeneration else { return }

                if room.connectionState != .disconnected { await room.disconnect() }
                guard generation == joinGeneration else { return }

                // With the call switch on, iOS owns the audio session and it must be
                // running before LiveKit touches the microphone.
                if usesCallKit != call.isEnabled {
                    try? await AudioManager.shared.setRecordingAlwaysPreparedMode(false)
                    call.setEnabled(usesCallKit)
                }
                if usesCallKit {
                    beganCall = !call.hasCall
                    do {
                        try await call.begin(boat: ticket.boat, options: sessionOptions)
                    } catch {
                        // Carry on as a plain audio app: sound matters more than the button.
                        log.error("Call not started: \(String(describing: error), privacy: .public)")
                        beganCall = false
                        call.setEnabled(false)
                    }
                    guard generation == joinGeneration else { return }
                }

                let connect = ConnectOptions(reconnectAttempts: 60, isDscpEnabled: true)
                let options = RoomOptions(
                    defaultAudioCaptureOptions: AudioCaptureOptions(echoCancellation: true, autoGainControl: true, noiseSuppression: true),
                    defaultAudioPublishOptions: AudioPublishOptions(encoding: AudioEncoding(maxBitrate: 32000), dtx: true, red: true)
                )
                try await room.connect(url: ticket.livekitURL, token: ticket.token, connectOptions: connect, roomOptions: options)
                guard generation == joinGeneration else { return }

                // A microphone that will not start is not a reason to leave: stay and listen.
                // Leaving and rejoining would only fail the same way, over and over.
                let micStarted = await startMicrophone()
                guard generation == joinGeneration else { return }
                isMicUnavailable = !micStarted
                if micStarted {
                    if notice == .micUnavailable { notice = nil }
                } else {
                    notice = .micUnavailable
                    tones.play(.warning)
                }
                retryDelay = 3

                currentBoat = boat
                boatName = ticket.boat
                channels = ticket.channels
                channel = ticket.channel
                Preferences.channel = ticket.channel
                joinTask = nil
                phase = .connected
                log.info("Joined \(ticket.boat, privacy: .public) on \(ticket.channel, privacy: .public), muted \(self.isMuted), microphone \(micStarted)")
                tones.play(.joined)
                call.showMuted(isMuted)
                stateChanged()
            } catch {
                guard generation == joinGeneration else { return }
                log.error("Join failed: \(String(describing: error), privacy: .public)")
                joinTask = nil
                await room.disconnect()
                guard generation == joinGeneration else { return }
                // A call kept from before a lost link stays up: it keeps the app alive to rejoin.
                if beganCall { call.end() }
                phase = .looking
                problem = "Could not join \(boat.name). \(error.localizedDescription)"
                stateChanged()
                scheduleRetry()
            }
        }
    }

    // MARK: - Audio

    /// Publishes the microphone, muted if that is the saved state. False if iOS refused.
    private func startMicrophone() async -> Bool {
        #if targetEnvironment(simulator)
        // `-micFailures 2` makes the first two starts fail, to rehearse a phone that joins while locked.
        let failuresLeft = UserDefaults.standard.integer(forKey: "micFailures") - simulatedMicFailures
        if failuresLeft > 0 {
            simulatedMicFailures += 1
            log.error("Microphone did not start: simulated failure")
            return false
        }
        #endif
        do {
            // The gate is already closed if muted, so nothing leaks between publishing and muting.
            try await room.localParticipant.setMicrophone(enabled: true)
            if isMuted { try await room.localParticipant.setMicrophone(enabled: false) }
            // Keeps the microphone pipeline warm between connections, which also keeps
            // the app alive in a pocket while it waits for the boat to come back.
            try? await AudioManager.shared.setRecordingAlwaysPreparedMode(true)
            return true
        } catch {
            log.error("Microphone did not start: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    /// Tries again for a microphone that would not start. Called when the app comes on screen.
    private func retryMicrophone() {
        guard isMicUnavailable, phase == .connected else { return }
        let generation = joinGeneration
        Task {
            guard await startMicrophone(), generation == joinGeneration else { return }
            log.info("Microphone started")
            isMicUnavailable = false
            if notice == .micUnavailable { notice = nil }
            syncGate()
            stateChanged()
        }
    }

    /// Hands-free profile only: it is what gives us the headset's microphone.
    private var sessionOptions: AVAudioSession.CategoryOptions {
        var options: AVAudioSession.CategoryOptions = [.allowBluetoothHFP]
        if usesSpeakerWithoutHeadset { options.insert(.defaultToSpeaker) }
        return options
    }

    private func applyAudioSessionPreference() {
        AudioManager.shared.sessionConfiguration = AudioSessionConfiguration(category: .playAndRecord,
                                                                             categoryOptions: sessionOptions,
                                                                             mode: .voiceChat)
    }

    private func syncGate() {
        let mode = mode, isMuted = isMuted, isTalking = isTalking
        gate.update {
            $0.mode = mode
            $0.isMuted = isMuted
            $0.isTalking = isTalking
        }
    }

    /// Pushes the wanted mute state to the published track. Always applies the latest
    /// value, so quick presses settle on the right answer.
    private func applyMicState() {
        guard room.connectionState == .connected, !isMicUnavailable else { return }
        Task { try? await room.localParticipant.setMicrophone(enabled: !self.isMuted) }
    }

    private func gateReported(_ report: MicGate.Report) {
        meter.levelDB = report.levelDB
        meter.isGateOpen = report.isOpen

        // A headset muted on its own boom sends pure silence, and the phone is never told.
        let looksDead = report.silentSeconds >= 5 && !isMuted && phase == .connected
        if looksDead, notice == nil {
            notice = .deadMic
            tones.play(.warning)
        } else if !looksDead, notice == .deadMic {
            notice = nil
        }
    }

    /// iOS noticed speech while the microphone is muted.
    private func mutedSpeech(_ event: SpeechActivityEvent) {
        log.info("Speech while muted: \(String(describing: event), privacy: .public)")
        switch event {
        case .started:
            mutedSpeechSince = Date()
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(2))
                self?.remindIfStillTalking()
            }
        case .ended:
            mutedSpeechSince = nil
        }
    }

    private func remindIfStillTalking() {
        guard isMuted, phase.isAboard, let since = mutedSpeechSince,
              Date().timeIntervalSince(since) >= 1.9,
              Date().timeIntervalSince(lastReminder) >= 60 // once, then quiet for a minute or until the next mute
        else { return }
        lastReminder = Date()
        log.info("Reminding: you're muted")
        show(.youreMuted, for: 6)
        tones.say("You're muted", after: .reminder)
    }

    private func show(_ notice: Notice, for seconds: Double) {
        self.notice = notice
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, self?.notice == notice else { return }
            self?.notice = nil
        }
    }

    /// A phone call or Siri took the audio: mute, and come back the way we were.
    private func audioInterrupted(_ type: AVAudioSession.InterruptionType?) {
        guard phase.isAboard else { return }
        switch type {
        case .began:
            // A held call and an audio interruption can both report the same phone call.
            if mutedBeforeInterruption == nil { mutedBeforeInterruption = isMuted }
            setMuted(true)
        case .ended:
            if mutedBeforeInterruption == false { setMuted(false) }
            mutedBeforeInterruption = nil
        default:
            break
        }
    }

    private func routeChanged(_ reason: AVAudioSession.RouteChangeReason?) {
        guard reason == .oldDeviceUnavailable, phase.isAboard, !isMuted else { return }
        setMuted(true)
        show(.headsetGone, for: 10)
        tones.play(.warning)
    }

    // MARK: - State out to the rest of the phone

    private func stateChanged() {
        refreshTalkers()
        publishState()
    }

    private func refreshTalkers() {
        guard phase.isAboard else {
            talkers = []
            return
        }
        let me = room.localParticipant
        var list = [Talker(id: "me", name: displayName, isSpeaking: me.isSpeaking && !isSilent, isMuted: isSilent, isLocal: true)]
        let others = room.remoteParticipants.values.sorted {
            ($0.name ?? "").localizedCaseInsensitiveCompare($1.name ?? "") == .orderedAscending
        }
        for person in others {
            list.append(Talker(id: person.identity?.stringValue ?? UUID().uuidString,
                               name: person.name?.isEmpty == false ? person.name! : "Someone",
                               isSpeaking: person.isSpeaking,
                               isMuted: !person.isMicrophoneEnabled(),
                               isLocal: false))
        }
        talkers = list
    }

    /// Lock-screen Live Activity and the Now Playing card.
    private func publishState() {
        guard wantedBoat != nil, !boatName.isEmpty else {
            cardRefreshTask?.cancel()
            cardRefreshTask = nil
            activity.endAll()
            headset.clear()
            return
        }
        // The card expires unless refreshed, so a crashed app cannot leave "Live" on the lock screen.
        if cardRefreshTask == nil {
            cardRefreshTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(ActivityController.refreshInterval))
                    guard !Task.isCancelled else { return }
                    self?.publishState()
                }
            }
        }
        let connected = phase == .connected
        activity.show(boat: boatName,
                      state: .init(isMuted: isSilent, isConnected: connected, channel: channel, mode: mode.label))
        headset.show(title: !connected ? "Not connected" : (isSilent ? "Muted" : "Live"),
                     subtitle: "\(boatName) · \(channel)")
    }

    // MARK: - Connection events

    private func connectionChanged(to state: ConnectionState) {
        switch state {
        case .disconnected:
            // Only react when we did not ask for it: joins and leaves change the phase first.
            guard phase.isAboard else { return }
            log.error("Lost the boat: \(String(describing: self.room.disconnectError), privacy: .public)")
            phase = .looking
            problem = "Lost \(boatName). Rejoining when it is back in range."
            tones.play(.lost)
            stateChanged()
            scheduleRetry()
        case .reconnecting:
            reconnecting(true)
        case .connected:
            reconnecting(false)
        default:
            break
        }
    }

    private func reconnecting(_ isReconnecting: Bool) {
        if isReconnecting, phase == .connected {
            phase = .reconnecting
            stateChanged()
        } else if !isReconnecting, phase == .reconnecting {
            phase = .connected
            applyMicState()
            retryMicrophone()
            stateChanged()
        }
    }
}

// MARK: - RoomDelegate

// LiveKit calls these off the main thread. Each one hops to the main actor and re-reads the room.
extension Intercom: RoomDelegate {
    nonisolated func room(_: Room, didUpdateConnectionState connectionState: ConnectionState, from _: ConnectionState) {
        Task { @MainActor in self.connectionChanged(to: connectionState) }
    }

    nonisolated func room(_: Room, didStartReconnectWithMode _: ReconnectMode) {
        Task { @MainActor in self.reconnecting(true) }
    }

    nonisolated func room(_: Room, didCompleteReconnectWithMode _: ReconnectMode) {
        Task { @MainActor in self.reconnecting(false) }
    }

    nonisolated func room(_: Room, participantDidConnect _: RemoteParticipant) {
        Task { @MainActor in self.refreshTalkers() }
    }

    nonisolated func room(_: Room, participantDidDisconnect _: RemoteParticipant) {
        Task { @MainActor in self.refreshTalkers() }
    }

    nonisolated func room(_: Room, didUpdateSpeakingParticipants _: [Participant]) {
        Task { @MainActor in self.refreshTalkers() }
    }

    nonisolated func room(_: Room, participant _: Participant, didUpdateName _: String) {
        Task { @MainActor in self.refreshTalkers() }
    }

    nonisolated func room(_: Room, participant _: Participant, trackPublication _: TrackPublication, didUpdateIsMuted _: Bool) {
        Task { @MainActor in self.refreshTalkers() }
    }

    nonisolated func room(_: Room, participant _: RemoteParticipant, didPublishTrack _: RemoteTrackPublication) {
        Task { @MainActor in self.refreshTalkers() }
    }

    nonisolated func room(_: Room, participant: Participant, didUpdateConnectionQuality quality: ConnectionQuality) {
        guard participant is LocalParticipant else { return }
        Task { @MainActor in self.quality = quality }
    }
}
