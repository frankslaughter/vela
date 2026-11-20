import Foundation

/// How the microphone is keyed.
enum TalkMode: String, CaseIterable {
    /// Mic always on, like the Eartec.
    case open
    /// Mic opens when you speak.
    case vox
    /// Mic opens while you hold the button, or after a headset-button press latches it.
    case ptt

    var label: String {
        switch self {
        case .open: "Open"
        case .vox: "VOX"
        case .ptt: "PTT"
        }
    }

    var next: TalkMode {
        let all = Self.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
}

/// Small things the app remembers between launches.
enum Preferences {
    private static let store = UserDefaults.standard

    static var displayName: String {
        get { store.string(forKey: "displayName") ?? "" }
        set { store.set(newValue, forKey: "displayName") }
    }

    /// A stable identifier for this install. It is this phone's identity on the intercom.
    static var deviceID: String {
        if let id = store.string(forKey: "deviceID") { return id }
        let id = UUID().uuidString.lowercased()
        store.set(id, forKey: "deviceID")
        return id
    }

    /// The boat to join on sight. Nil until one is chosen, and again after leaving.
    static var boatName: String? {
        get { store.string(forKey: "boatName") }
        set { store.set(newValue, forKey: "boatName") }
    }

    static var channel: String? {
        get { store.string(forKey: "channel") }
        set { store.set(newValue, forKey: "channel") }
    }

    static var mode: TalkMode {
        get { TalkMode(rawValue: store.string(forKey: "mode") ?? "") ?? .open }
        set { store.set(newValue.rawValue, forKey: "mode") }
    }

    static var isMuted: Bool {
        get { store.bool(forKey: "isMuted") }
        set { store.set(newValue, forKey: "isMuted") }
    }

    /// Play through the phone's loudspeaker when no headset is connected. Off by default:
    /// on the boat a lost headset should not turn the phone into a speaker.
    static var usesSpeakerWithoutHeadset: Bool {
        get { store.bool(forKey: "usesSpeakerWithoutHeadset") }
        set { store.set(newValue, forKey: "usesSpeakerWithoutHeadset") }
    }

    /// Test mode: report to the base station's test bench, send it the log, and take its commands.
    static var isTestMode: Bool {
        get { store.bool(forKey: "isTestMode") }
        set { store.set(newValue, forKey: "isTestMode") }
    }

    /// Silence suppression (DTX): send almost nothing while the microphone is quiet. Off unless switched on.
    /// With it on, the first words after a silence reach the listener about 50 ms later, because
    /// the listener's player waits longer when packets come only five times a second: 290 ms
    /// against 240 ms with Bluetooth at both ends, measured 2026-11-19 (docs/stage-2-log.md).
    /// A locked phone that sends without a break also keeps its radio awake (docs/stage-1-log.md).
    /// Until 2026-11-19 it was on unless switched off, under the key "noSilenceSuppression",
    /// which is no longer read, so every phone starts from off.
    static var suppressesSilence: Bool {
        get { store.bool(forKey: "silenceSuppression") }
        set { store.set(newValue, forKey: "silenceSuppression") }
    }

    /// Redundancy (RED): each packet repeats the one before, to cover a lost packet. On unless switched off for a test.
    static var sendsRedundancy: Bool {
        get { !store.bool(forKey: "noRedundancy") }
        set { store.set(!newValue, forKey: "noRedundancy") }
    }

    /// Voice marking (DSCP): packets are marked as voice, which puts them in the Wi-Fi's voice queue. On unless switched off for a test.
    static var marksVoice: Bool {
        get { !store.bool(forKey: "noVoiceMarking") }
        set { store.set(!newValue, forKey: "noVoiceMarking") }
    }
}
