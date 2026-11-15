import MediaPlayer
import UIKit

/// Maps the headset's play/pause button to one action.
///
/// A single press on an AirPods stem or a headset's multifunction button arrives as a
/// play, pause, or toggle command. All three mean the same thing here.
///
/// Whether iOS delivers these while a voice-chat audio session is active depends on the
/// headset and has to be checked on real hardware. That is exit criterion 3 of the plan.
@MainActor
final class HeadsetButton {
    var onPress: (() -> Void)?

    func start() {
        let center = MPRemoteCommandCenter.shared()
        for command in [center.togglePlayPauseCommand, center.playCommand, center.pauseCommand] {
            command.isEnabled = true
            command.addTarget { [weak self] _ in
                Task { @MainActor in self?.onPress?() }
                return .success
            }
        }
        for command in [center.nextTrackCommand, center.previousTrackCommand, center.skipForwardCommand,
                        center.skipBackwardCommand, center.changePlaybackPositionCommand]
        {
            command.isEnabled = false
        }
        UIApplication.shared.beginReceivingRemoteControlEvents()
    }

    /// Keeps the lock screen's Now Playing card honest about the intercom's state.
    func show(title: String, subtitle: String) {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: subtitle,
            MPNowPlayingInfoPropertyIsLiveStream: true,
            MPNowPlayingInfoPropertyPlaybackRate: 1.0,
        ]
    }

    func clear() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }
}
