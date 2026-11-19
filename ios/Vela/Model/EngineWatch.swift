import AVFAudio
import LiveKit

/// Says when the phone's audio engine stops.
///
/// It sits first in LiveKit's chain of engine observers and passes everything on unchanged.
/// The intercom needs to know because iOS will not start a stopped engine for an app that
/// is not on screen, and suspends an app whose engine stays stopped. See `Intercom.audioEngineStopped`.
final class EngineWatch: AudioEngineObserver, @unchecked Sendable {
    private let lock = NSLock()
    private var following: (any AudioEngineObserver)?
    private var stopped: (@Sendable () -> Void)?

    var next: (any AudioEngineObserver)? {
        get { lock.withLock { following } }
        set { lock.withLock { following = newValue } }
    }

    /// Called on one of WebRTC's own threads, while it is still changing the engine.
    /// Do nothing there but hand the news to another thread.
    var onStop: (@Sendable () -> Void)? {
        get { lock.withLock { stopped } }
        set { lock.withLock { stopped = newValue } }
    }

    func engineDidStop(_ engine: AVAudioEngine, isPlayoutEnabled: Bool, isRecordingEnabled: Bool) -> Int {
        let result = next?.engineDidStop(engine, isPlayoutEnabled: isPlayoutEnabled, isRecordingEnabled: isRecordingEnabled) ?? 0
        onStop?()
        return result
    }
}
