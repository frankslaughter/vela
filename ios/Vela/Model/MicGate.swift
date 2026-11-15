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

    struct Report: Sendable {
        /// Loudest 10 ms block since the last report, in dBFS. -120 is the floor.
        var levelDB: Float
        var isOpen: Bool
        /// How long the microphone has delivered nothing but digital silence.
        var silentSeconds: Double
    }

    /// Called about five times a second, on the audio thread.
    var onReport: (@Sendable (Report) -> Void)?

    private let lock = NSLock()
    private var settings = Settings()
    private var sampleRate: Double = 48000
    private var hangoverLeft: Double = 0
    private var silentSeconds: Double = 0
    private var windowPeakDB: Float = -120
    private var sinceReport: Double = 0

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

        lock.lock()
        let duration = Double(frames) / sampleRate
        let current = settings

        // One count either way is the smallest step a 16-bit sample can take. Below two is silence.
        silentSeconds = peak < 2 ? silentSeconds + duration : 0

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
            report = Report(levelDB: windowPeakDB, isOpen: isOpen, silentSeconds: silentSeconds)
            windowPeakDB = -120
            sinceReport = 0
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
