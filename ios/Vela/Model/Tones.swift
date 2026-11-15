import AVFoundation

/// Short cues played in the wearer's own ear. Nobody else hears them:
/// they go to this phone's output, not into the microphone path.
@MainActor
final class Tones {
    enum Tone: CaseIterable {
        /// Talk latch off, in PTT mode.
        case low
        /// Talk latch on, in PTT mode.
        case rising
        /// "You're muted": you have been talking to nobody.
        case reminder
        /// Joined the boat.
        case joined
        /// Lost the boat.
        case lost
        /// Something needs a look: dead microphone, headset gone.
        case warning
    }

    private var players: [Tone: AVAudioPlayer] = [:]
    /// Speaks through the intercom's own audio session, so it comes out of the headset.
    private let synthesizer = AVSpeechSynthesizer()

    init() {
        for tone in Tone.allCases {
            guard let player = try? AVAudioPlayer(data: Self.wav(Self.notes(for: tone)), fileTypeHint: AVFileType.wav.rawValue) else { continue }
            player.volume = 0.6
            players[tone] = player
        }
    }

    func play(_ tone: Tone) {
        guard let player = players[tone] else { return }
        player.currentTime = 0
        player.play()
    }

    /// Says a few words in the wearer's ear, after a cue so the words are not a surprise.
    func say(_ words: String, after tone: Tone) {
        play(tone)
        let utterance = AVSpeechUtterance(string: words)
        utterance.preUtteranceDelay = 0.4 // lets the cue finish
        synthesizer.stopSpeaking(at: .immediate)
        synthesizer.speak(utterance)
    }

    /// Frequency in hertz and length in seconds. Zero hertz is a gap.
    private static func notes(for tone: Tone) -> [(hz: Double, seconds: Double)] {
        switch tone {
        case .low: [(330, 0.12)]
        case .rising: [(440, 0.07), (660, 0.09)]
        case .reminder: [(330, 0.10), (0, 0.08), (330, 0.10)]
        case .joined: [(523, 0.08), (659, 0.08), (784, 0.12)]
        case .lost: [(784, 0.08), (659, 0.08), (523, 0.14)]
        case .warning: [(880, 0.07), (0, 0.05), (880, 0.07), (0, 0.05), (880, 0.07)]
        }
    }

    /// Builds a 16-bit mono WAV in memory, with a short fade on each note so it does not click.
    private static func wav(_ notes: [(hz: Double, seconds: Double)]) -> Data {
        let rate = 44100.0
        var samples: [Int16] = []
        for note in notes {
            let count = Int(note.seconds * rate)
            let fade = min(count / 2, Int(0.006 * rate))
            for i in 0 ..< count {
                guard note.hz > 0 else { samples.append(0); continue }
                var gain = 0.5
                if i < fade { gain *= Double(i) / Double(fade) }
                if i >= count - fade { gain *= Double(count - 1 - i) / Double(fade) }
                samples.append(Int16(gain * 32767 * sin(2 * .pi * note.hz * Double(i) / rate)))
            }
        }

        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        let byteCount = UInt32(samples.count * 2)
        data.append(contentsOf: Array("RIFF".utf8)); append(36 + byteCount)
        data.append(contentsOf: Array("WAVEfmt ".utf8)); append(UInt32(16))
        append(UInt16(1)); append(UInt16(1)); append(UInt32(rate)); append(UInt32(rate) * 2)
        append(UInt16(2)); append(UInt16(16))
        data.append(contentsOf: Array("data".utf8)); append(byteCount)
        for sample in samples { append(sample) }
        return data
    }
}
