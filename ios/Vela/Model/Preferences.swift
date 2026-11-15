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
}
