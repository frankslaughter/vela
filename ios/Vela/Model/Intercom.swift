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
        case .deadMic: "Your microphone is sending silence. Check that it is working."
        case .headsetGone: "Headset disconnected. You have been muted."
        case .micUnavailable: "Listening only. Your microphone is not working. Tap the big button to try again."
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
    /// PTT only: the talk button is held, or a button press latched it.
    @Published private(set) var isTalking = false
    /// On the boat and listening, but the microphone is not delivering audio. iOS refuses to
    /// start it for an app that is not on screen, and takes it away for a phone call, or when
    /// an iPad's case is closed.
    @Published private(set) var isMicUnavailable = false
    /// The headset is sending pure silence, which is what a mute button on its boom does.
    /// The phone is never told about that mute, so it is inferred, and treated as a real one.
    @Published private(set) var isHeadsetMuted = false
    @Published private(set) var talkers: [Talker] = []
    @Published private(set) var notice: Notice?
    /// Why the last join failed, or that the boat was lost.
    @Published private(set) var problem: String?
    /// Why the search for boats is not working.
    @Published private(set) var searchProblem: String?
    @Published private(set) var quality: ConnectionQuality = .unknown
    @Published private(set) var displayName = Preferences.displayName
    @Published private(set) var usesSpeakerWithoutHeadset = Preferences.usesSpeakerWithoutHeadset
    /// Reporting to the base station's test bench and taking its commands. See `Intercom+Testing.swift`.
    @Published private(set) var isTestMode = Preferences.isTestMode
    /// How the microphone's audio is sent. Both are on for normal use; the switches are for finding lost packets.
    @Published private(set) var suppressesSilence = Preferences.suppressesSilence
    @Published private(set) var sendsRedundancy = Preferences.sendsRedundancy
    /// The boat to be on. Set by choosing one, cleared by leaving.
    @Published private(set) var wantedBoat = Preferences.boatName

    let meter = MicMeter()

    /// True when nothing of yours can be heard: muted, or in PTT and not talking.
    var isSilent: Bool { isMicUnavailable || isHeadsetMuted || (mode == .ptt ? !isTalking : isMuted) }

    let room = Room()
    private let browser = BoatBrowser()
    private let gate = MicGate()
    private let tones = Tones()
    private let activity = ActivityController()
    /// Also written to Documents/vela-log.txt on the phone; see EventLog.
    let log = EventLog(category: "intercom")

    private var hasStarted = false
    /// The app has been on screen at least once since it was started.
    private var hasBeenOnScreen = false
    private(set) var currentBoat: Boat?
    private var joinTask: Task<Void, Never>?
    private var joinGeneration = 0
    private var retryTask: Task<Void, Never>?
    /// Seconds before the next join attempt. Doubles after each failure, so a boat that
    /// cannot be joined is not hammered; back to three seconds on any success or user action.
    private var retryDelay: Double = 3
    private var isTalkHeld = false
    private var isTalkLatched = false
    private var mutedSpeechSince: Date?
    /// When the microphone last delivered audio. It does so five times a second while live.
    private var lastGateReport = Date()
    private var micWatchTask: Task<Void, Never>?
    private var lastMicRecovery = Date.distantPast
    /// Seconds between attempts to get a stopped microphone back. Doubles after each, up to a minute.
    private var micRecoveryDelay: Double = 10
    /// Recovery normally waits for the app to be on screen, where iOS allows a microphone to
    /// start. Just after an interruption ends, or a microphone reappears, it may try unseen.
    private var mayRecoverUnseenUntil = Date.distantPast
    var testTask: Task<Void, Never>?
    /// For the test bench: how often this phone has joined, and lost the boat without being asked.
    private(set) var joinCount = 0
    private(set) var dropCount = 0
    /// Loudest microphone level since the last test report.
    var testMicPeakDB: Float = -120
    /// Microphone level over the last half minute, for the log.
    private var levelFloorDB: Float = 0
    private var levelPeakDB: Float = -120
    private var levelLongestSilence: Double = 0
    private var levelHistogram = MicGate.Histogram()
    private var levelMutedReports = 0
    private var levelWindowStart = Date()
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

        MuteIntentBridge.handler = { [weak self] in self?.buttonPressed() }
        activity.endAll()

        let center = NotificationCenter.default
        center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let reason = note.userInfo?[AVAudioSessionInterruptionReasonKey] as? UInt
            let options = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt
            Task { @MainActor in
                self?.log.info("Interruption notice: reason \(reason.map(String.init) ?? "none"), options \(options.map(String.init) ?? "none")")
                self?.audioInterrupted(raw.flatMap(AVAudioSession.InterruptionType.init))
            }
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
        UIDevice.current.isBatteryMonitoringEnabled = true
        micWatchTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                self?.checkMicrophone()
            }
        }
        startTestReports()
    }

    /// The app is being closed, for example swiped away in the app switcher.
    /// Take the card off the lock screen and tell the server, so neither claims we are still here.
    func willTerminate() {
        log.info("Closing: leaving the boat")
        let room = room
        ActivityController.endAllBeforeExit { await room.disconnect() }
    }

    /// The app came to the foreground.
    func becameActive() {
        guard hasStarted else { return }
        hasBeenOnScreen = true
        publishState() // a Live Activity can only be started from the foreground
        retryDelay = 3
        // Being opened is proof that whatever interrupted the audio is over, told or not.
        if mutedBeforeInterruption != nil { audioInterrupted(.ended) }
        recoverMicrophone("the app came on screen", force: true) // only here will iOS start a microphone
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
        isHeadsetMuted = false
        Task {
            await room.disconnect()
            try? await AudioManager.shared.setRecordingAlwaysPreparedMode(false)
        }
        publishState()
    }

    func toggleMute() {
        // Nothing the app does can unmute a headset. Say so, and do not stack a second mute on top.
        if isHeadsetMuted, !isMuted {
            tones.say("Muted on the headset", after: .reminder)
            return
        }
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
        stateChanged()
    }

    func cycleMode() {
        mode = mode.next
        Preferences.mode = mode
        log.info("Mode \(self.mode.label)")
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

    /// Takes effect by rejoining, because listening statistics are switched on when the room is joined.
    func setTestMode(_ on: Bool) {
        guard on != isTestMode else { return }
        isTestMode = on
        Preferences.isTestMode = on
        log.info("Test mode \(on)")
        startTestReports()
        if phase.isAboard, let boat = currentBoat { join(boat, channel: channel) }
    }

    /// Takes effect by rejoining, because the microphone's track is published with these settings.
    func setSuppressesSilence(_ on: Bool) {
        guard on != suppressesSilence else { return }
        suppressesSilence = on
        Preferences.suppressesSilence = on
        if phase.isAboard, let boat = currentBoat { join(boat, channel: channel) }
    }

    func setSendsRedundancy(_ on: Bool) {
        guard on != sendsRedundancy else { return }
        sendsRedundancy = on
        Preferences.sendsRedundancy = on
        if phase.isAboard, let boat = currentBoat { join(boat, channel: channel) }
    }

    func setUsesSpeakerWithoutHeadset(_ on: Bool) {
        usesSpeakerWithoutHeadset = on
        Preferences.usesSpeakerWithoutHeadset = on
        applyAudioSessionPreference()
    }

    /// The lock-screen button: one press, no looking.
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
        // iOS can start the app unseen, for example from the lock-screen button after
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

    /// `restartingAudio` also stops the microphone pipeline that is otherwise kept warm between
    /// connections, so the audio engine and session start again from nothing.
    private func join(_ boat: Boat, channel requested: String? = nil, restartingAudio: Bool = false) {
        joinGeneration += 1
        let generation = joinGeneration
        joinTask?.cancel()
        retryTask?.cancel()
        phase = .joining(boat.name)
        problem = nil
        log.info("Joining \(boat.name) at \(boat.host)")

        joinTask = Task { [weak self] in
            guard let self else { return }
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
                if restartingAudio { try? await AudioManager.shared.setRecordingAlwaysPreparedMode(false) }
                guard generation == joinGeneration else { return }

                let connect = ConnectOptions(reconnectAttempts: 60, isDscpEnabled: true)
                let options = RoomOptions(
                    defaultAudioCaptureOptions: AudioCaptureOptions(echoCancellation: true, autoGainControl: true, noiseSuppression: true),
                    defaultAudioPublishOptions: micPublishOptions,
                    reportRemoteTrackStatistics: isTestMode // what this phone hears, for the test bench
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
                joinCount += 1
                lastGateReport = Date()
                phase = .connected
                publishMicState()
                log.info("Joined \(ticket.boat) on \(ticket.channel), muted \(self.isMuted), microphone \(micStarted)")
                log.info("Audio after joining: \(audioSummary)")
                log.info("Sending with silence suppression \(suppressesSilence ? "on" : "off"), redundancy \(sendsRedundancy ? "on" : "off")")
                tones.play(.joined)
                stateChanged()
            } catch {
                guard generation == joinGeneration else { return }
                log.error("Join failed: \(String(describing: error))")
                joinTask = nil
                await room.disconnect()
                guard generation == joinGeneration else { return }
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
            // The options are passed here as well as in the room's defaults. Left to the defaults,
            // the SDK (2.19.0) follows up with a list of the track's features that leaves them out,
            // and the audio server then switches silence suppression back on.
            try await room.localParticipant.setMicrophone(enabled: true, publishOptions: micPublishOptions)
            if isMuted { try await room.localParticipant.setMicrophone(enabled: false) }
            // Keeps the microphone pipeline warm between connections, which also keeps
            // the app alive in a pocket while it waits for the boat to come back.
            try? await AudioManager.shared.setRecordingAlwaysPreparedMode(true)
            if isTestMode { await room.localParticipant.audioTracks.first?.track?.set(reportStatistics: true) }
            return true
        } catch {
            log.error("Microphone did not start: \(String(describing: error))")
            return false
        }
    }

    // MARK: - Watching the microphone

    /// Every two seconds: is the microphone still delivering audio? Nothing else says so reliably.
    /// An interruption or a lost input stops it without an error, and the screen would go on saying LIVE.
    private func checkMicrophone() {
        guard phase == .connected else {
            lastGateReport = Date()
            return
        }
        let isOnScreen = UIApplication.shared.applicationState == .active
        if isMicUnavailable {
            if isOnScreen || Date() < mayRecoverUnseenUntil { recoverMicrophone("it is still off") }
            return
        }
        // A muted microphone delivers nothing, so there is nothing to watch.
        guard !isMuted else {
            lastGateReport = Date()
            return
        }
        guard Date().timeIntervalSince(lastGateReport) > 5 else { return }

        log.error("The microphone stopped delivering audio: \(audioSummary)")
        isMicUnavailable = true
        isHeadsetMuted = false
        notice = .micUnavailable
        tones.play(.warning)
        publishMicState()
        stateChanged()
        if isOnScreen || Date() < mayRecoverUnseenUntil { recoverMicrophone("it stopped") }
    }

    /// Gets a stopped microphone back by leaving and rejoining with the audio started from nothing.
    /// Nothing gentler is known to work after an interruption.
    private func recoverMicrophone(_ why: String, force: Bool = false) {
        guard isMicUnavailable, phase == .connected, let boat = currentBoat else { return }
        guard force || Date().timeIntervalSince(lastMicRecovery) >= micRecoveryDelay else { return }
        lastMicRecovery = Date()
        micRecoveryDelay = min(micRecoveryDelay * 2, 60)
        log.info("Restarting the audio to get the microphone back: \(why)")
        join(boat, channel: channel, restartingAudio: true)
    }

    /// Tells the boat what state the microphone is in, without touching the audio.
    /// The roster and the other phones show anything but "live" as muted.
    private func publishMicState() {
        guard room.connectionState == .connected else { return }
        let value = isMicUnavailable ? "off" : (isHeadsetMuted ? "headset-muted" : "live")
        let room = room, log = log
        Task {
            do {
                try await room.localParticipant.set(attributes: ["mic": value])
            } catch {
                log.error("The boat was not told the microphone is \(value): \(String(describing: error))")
            }
        }
    }

    /// How the microphone's audio is encoded and sent.
    private var micPublishOptions: AudioPublishOptions {
        AudioPublishOptions(encoding: AudioEncoding(maxBitrate: 32000), dtx: suppressesSilence, red: sendsRedundancy)
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
        Task { try? await room.localParticipant.setMicrophone(enabled: !self.isMuted, publishOptions: self.micPublishOptions) }
    }

    private func gateReported(_ report: MicGate.Report) {
        meter.levelDB = report.levelDB
        meter.isGateOpen = report.isOpen

        lastGateReport = Date()
        if !isMicUnavailable { micRecoveryDelay = 10 }
        logLevels(report)
        testMicPeakDB = max(testMicPeakDB, report.levelDB)

        // A headset muted on its own boom sends next to nothing, and the phone is never told.
        // A second and a half below the faint level on a headset microphone is taken as that
        // mute. It ends at the first block clearly above it; the gap between the two levels
        // keeps a stray click from flipping the state. On any other microphone, pure silence
        // is a fault to warn about.
        let isLive = !isMuted && !isMicUnavailable && phase == .connected
        if isHeadsetMuted {
            if !isLive || report.levelDB > MicGate.faintLevelDB + 6 { setHeadsetMuted(false) }
        } else if isLive, report.faintSeconds >= 1.5, isOnHeadsetMicrophone {
            setHeadsetMuted(true)
        }

        let looksDead = isLive && !isHeadsetMuted && report.silentSeconds >= 5
        if looksDead, notice == nil {
            notice = .deadMic
            tones.play(.warning)
        } else if !looksDead, notice == .deadMic {
            notice = nil
        }
    }

    private var isOnHeadsetMicrophone: Bool {
        #if targetEnvironment(simulator)
        // `-pretendHeadset YES` rehearses a muted headset: with no audio device, every microphone is silent.
        if UserDefaults.standard.bool(forKey: "pretendHeadset") { return true }
        #endif
        return AVAudioSession.sharedInstance().currentRoute.inputs.contains { $0.portType == .bluetoothHFP }
    }

    private func setHeadsetMuted(_ muted: Bool) {
        guard muted != isHeadsetMuted else { return }
        isHeadsetMuted = muted
        log.info("Headset mute \(muted ? "on" : "off")")
        // The audio track is left alone: muting it would blind the check that notices the headset coming back.
        publishMicState()
        stateChanged()
    }

    /// Every half minute, what the microphone has been delivering. It shows whether a quiet
    /// room ever reads as pure silence, which is what would make the headset check wrong.
    private func logLevels(_ report: MicGate.Report) {
        guard phase == .connected else {
            levelWindowStart = Date()
            return
        }
        levelFloorDB = min(levelFloorDB, report.levelDB)
        levelPeakDB = max(levelPeakDB, report.levelDB)
        levelLongestSilence = max(levelLongestSilence, report.silentSeconds)
        levelHistogram.add(report.histogram)
        if isHeadsetMuted { levelMutedReports += 1 }
        guard Date().timeIntervalSince(levelWindowStart) >= 30 else { return }
        log.info("Microphone over 30 s: quietest \(Int(levelFloorDB)) dB, loudest \(Int(levelPeakDB)) dB, "
            + "longest pure silence \(String(format: "%.1f", levelLongestSilence)) s, muted \(isMuted), "
            + "headset mute for \(String(format: "%.0f", Double(levelMutedReports) * 0.2)) s. Blocks by dB, \(levelHistogram.text)")
        levelHistogram = MicGate.Histogram()
        levelMutedReports = 0
        levelFloorDB = 0
        levelPeakDB = -120
        levelLongestSilence = 0
        levelWindowStart = Date()
    }

    /// iOS noticed speech while the microphone is muted.
    private func mutedSpeech(_ event: SpeechActivityEvent) {
        log.info("Speech while muted: \(String(describing: event))")
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
        log.info("Audio interrupted: \(type == .began ? "began" : "ended")")
        guard phase.isAboard else { return }
        switch type {
        case .began:
            // Two reports of the same interruption must not overwrite what to come back to.
            if mutedBeforeInterruption == nil { mutedBeforeInterruption = isMuted }
            setMuted(true)
        case .ended:
            if mutedBeforeInterruption == false { setMuted(false) }
            mutedBeforeInterruption = nil
            // The microphone may not have come back with it. The watch finds out within seconds.
            lastGateReport = Date()
            mayRecoverUnseenUntil = Date().addingTimeInterval(25)
        default:
            break
        }
    }

    /// The state of the phone's audio, for the log.
    private var audioSummary: String {
        let session = AVAudioSession.sharedInstance()
        let inputs = session.currentRoute.inputs.map(\.portType.rawValue).joined(separator: "+")
        let outputs = session.currentRoute.outputs.map(\.portType.rawValue).joined(separator: "+")
        return "engine \(AudioManager.shared.isEngineRunning ? "running" : "stopped"), "
            + "\(session.category.rawValue)/\(session.mode.rawValue), \(Int(session.sampleRate)) Hz, "
            + "in \(inputs.isEmpty ? "none" : inputs), out \(outputs.isEmpty ? "none" : outputs)"
    }

    private func routeChanged(_ reason: AVAudioSession.RouteChangeReason?) {
        log.info("Audio route changed, reason \(reason?.rawValue ?? 0): \(audioSummary)")
        if !AVAudioSession.sharedInstance().currentRoute.inputs.isEmpty {
            // A microphone is there. If an interruption took it away and iOS never said it was
            // over, as happens when an iPad's case is closed and opened, this is the sign that it is.
            if mutedBeforeInterruption != nil, phase.isAboard { audioInterrupted(.ended) }
            if isMicUnavailable { mayRecoverUnseenUntil = Date().addingTimeInterval(25) }
        }
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
                               isMuted: !person.isMicrophoneEnabled() || ["headset-muted", "off"].contains(person.attributes["mic"] ?? ""),
                               isLocal: false))
        }
        talkers = list
    }

    /// The lock-screen Live Activity.
    private func publishState() {
        guard wantedBoat != nil, !boatName.isEmpty else {
            cardRefreshTask?.cancel()
            cardRefreshTask = nil
            activity.endAll()
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
    }

    // MARK: - Connection events

    private func connectionChanged(to state: ConnectionState) {
        switch state {
        case .disconnected:
            // Only react when we did not ask for it: joins and leaves change the phase first.
            guard phase.isAboard else { return }
            log.error("Lost the boat: \(String(describing: self.room.disconnectError))")
            dropCount += 1
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
            log.error("The link dropped; reconnecting. Link quality was \(String(describing: quality))")
            phase = .reconnecting
            stateChanged()
        } else if !isReconnecting, phase == .reconnecting {
            log.info("The link is back")
            phase = .connected
            lastGateReport = Date()
            applyMicState()
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

    nonisolated func room(_: Room, participant _: Participant, didUpdateAttributes _: [String: String]) {
        Task { @MainActor in self.refreshTalkers() }
    }

    nonisolated func room(_: Room, participant _: RemoteParticipant, didPublishTrack _: RemoteTrackPublication) {
        Task { @MainActor in self.refreshTalkers() }
    }

    nonisolated func room(_: Room, participant: Participant, didUpdateConnectionQuality quality: ConnectionQuality) {
        guard participant is LocalParticipant else { return }
        Task { @MainActor in
            if quality != self.quality { self.log.info("Connection quality \(String(describing: quality)): \(self.audioSummary)") }
            self.quality = quality
        }
    }
}
