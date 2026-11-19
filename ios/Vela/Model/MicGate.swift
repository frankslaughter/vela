import Foundation
import LiveKit

/// Sits in the capture path after echo cancellation and noise suppression.
///
/// It does three jobs on every 10 ms of microphone audio:
/// - measures the level, for the meter, VOX, and the dead-microphone check;
/// - decides whether the gate is open for the current talk mode;
/// - replaces the audio with silence when the gate is closed, so nothing leaves the phone.
///
/// It runs on the audio thread, so it takes one short lock and allocates nothing.
final class MicGate: NSObject, AudioCustomProcessingDelegate, @unchecked Sendable {
    struct Settings {
        var mode: TalkMode = .open
        /// Closes the gate regardless of mode. Mute also mutes the track; this is the second lock on the door.
        var isMuted = false
        /// PTT only: the button is held, or the headset button latched it.
        var isTalking = false
        /// VOX opens at this level, in dB relative to full scale, measured after noise suppression.
        var voxThresholdDB: Float = -42
        /// VOX stays open this long after the level drops, so word endings are not clipped.
        var voxHangover: Double = 0.4
    }

    /// How many 10 ms blocks fell in each level band since the last report. For the log:
    /// it shows how far apart a muted headset and a quiet live one really are.
    struct Histogram: Sendable {
        /// Upper edges in dBFS of all bands but the last, which is everything louder.
        static let edges: [Float] = [-100, -95, -90, -85, -80, -75]
        var counts = (0, 0, 0, 0, 0, 0, 0)

        mutating func add(_ levelDB: Float) {
            if levelDB <= -100 { counts.0 += 1 }
            else if levelDB <= -95 { counts.1 += 1 }
            else if levelDB <= -90 { counts.2 += 1 }
            else if levelDB <= -85 { counts.3 += 1 }
            else if levelDB <= -80 { counts.4 += 1 }
            else if levelDB <= -75 { counts.5 += 1 }
            else { counts.6 += 1 }
        }

        mutating func add(_ other: Histogram) {
            counts.0 += other.counts.0; counts.1 += other.counts.1; counts.2 += other.counts.2
            counts.3 += other.counts.3; counts.4 += other.counts.4; counts.5 += other.counts.5
            counts.6 += other.counts.6
        }

        var text: String {
            "to -100: \(counts.0), to -95: \(counts.1), to -90: \(counts.2), to -85: \(counts.3), "
                + "to -80: \(counts.4), to -75: \(counts.5), louder: \(counts.6)"
        }
    }

    /// A headset muted on its own boom is not always perfectly silent: measured on the
    /// OpenComm2 on 2026-11-15, it usually leaves a hiss around -90 to -96 dB, while the same
    /// headset live in a quiet room never fell below about -81 dB. This level sits between.
    static let faintLevelDB: Float = -86

    struct Report: Sendable {
        /// Loudest 10 ms block since the last report, in dBFS. -120 is the floor.
        var levelDB: Float
        var isOpen: Bool
        /// How long the microphone has delivered nothing but digital silence.
        var silentSeconds: Double
        /// How long every block has been at or below `faintLevelDB`.
        var faintSeconds: Double
        var histogram: Histogram
        /// The longest wait for a block since the last report, beyond the block's own length.
        /// Blocks come every 10 ms; a wait of a tenth of a second or more is the audio standing still.
        var stallSeconds: Double
    }

    /// Called about five times a second, on the audio thread.
    var onReport: (@Sendable (Report) -> Void)?

    private let lock = NSLock()
    private var settings = Settings()
    private var sampleRate: Double = 48000
    private var hangoverLeft: Double = 0
    private var silentSeconds: Double = 0
    private var faintSeconds: Double = 0
    private var histogram = Histogram()
    private var windowPeakDB: Float = -120
    private var sinceReport: Double = 0
    private var lastBlockAt: Double = 0
    private var worstWait: Double = 0

    func update(_ change: (inout Settings) -> Void) {
        lock.lock()
        change(&settings)
        lock.unlock()
    }

    // MARK: AudioCustomProcessingDelegate

    func audioProcessingInitialize(sampleRate sampleRateHz: Int, channels _: Int) {
        lock.lock()
        sampleRate = Double(max(sampleRateHz, 8000))
        hangoverLeft = 0
        silentSeconds = 0
        faintSeconds = 0
        lastBlockAt = 0 // the audio is starting: the wait before the first block is not a stall
        lock.unlock()
    }

    func audioProcessingProcess(audioBuffer: LKAudioBuffer) {
        let frames = audioBuffer.frames
        let channels = audioBuffer.channels
        guard frames > 0, channels > 0 else { return }

        // WebRTC hands over floats in 16-bit range, -32768 to 32767.
        var sumSquares: Float = 0
        var peak: Float = 0
        for channel in 0 ..< channels {
            let samples = audioBuffer.rawBuffer(forChannel: channel)
            for i in 0 ..< frames {
                let value = samples[i]
                sumSquares += value * value
                peak = max(peak, abs(value))
            }
        }
        let rms = (sumSquares / Float(frames * channels)).squareRoot() / 32768
        let levelDB: Float = rms > 0 ? max(-120, 20 * log10(rms)) : -120

        let now = ProcessInfo.processInfo.systemUptime

        lock.lock()
        let duration = Double(frames) / sampleRate
        let current = settings

        // How late is this block? Waits of several seconds are the audio being stopped and
        // started, not a stall, and are left out.
        if lastBlockAt > 0 {
            let wait = now - lastBlockAt - duration
            if wait < 5 { worstWait = max(worstWait, wait) }
        }
        lastBlockAt = now

        // One count either way is the smallest step a 16-bit sample can take. Below two is silence.
        // Time spent muted in the app does not count: that silence is ours, not the microphone's.
        silentSeconds = (peak < 2 && !current.isMuted) ? silentSeconds + duration : 0
        faintSeconds = (levelDB <= Self.faintLevelDB && !current.isMuted) ? faintSeconds + duration : 0
        if !current.isMuted { histogram.add(levelDB) }

        let isOpen: Bool
        if current.isMuted {
            isOpen = false
            hangoverLeft = 0
        } else {
            switch current.mode {
            case .open:
                isOpen = true
            case .ptt:
                isOpen = current.isTalking
            case .vox:
                if levelDB >= current.voxThresholdDB {
                    hangoverLeft = current.voxHangover
                    isOpen = true
                } else if hangoverLeft > 0 {
                    hangoverLeft -= duration
                    isOpen = true
                } else {
                    isOpen = false
                }
            }
        }

        windowPeakDB = max(windowPeakDB, levelDB)
        sinceReport += duration
        var report: Report?
        if sinceReport >= 0.2 {
            report = Report(levelDB: windowPeakDB, isOpen: isOpen, silentSeconds: silentSeconds,
                            faintSeconds: faintSeconds, histogram: histogram, stallSeconds: max(worstWait, 0))
            histogram = Histogram()
            windowPeakDB = -120
            sinceReport = 0
            worstWait = 0
        }
        let callback = onReport
        lock.unlock()

        if !isOpen {
            for channel in 0 ..< channels {
                audioBuffer.rawBuffer(forChannel: channel).update(repeating: 0, count: frames)
            }
        }
        if let report { callback?(report) }
    }

    func audioProcessingRelease() {}
}
