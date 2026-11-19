import AVFAudio
import LiveKit
import UIKit

/// Test mode: lets one person test several phones.
///
/// Every two seconds the phone tells the base station's test bench what it is sending and
/// hearing, and the reply carries any commands waiting for it. The log goes along every ten
/// seconds. Nobody has to listen at this phone, or touch it, for the bench to know how it is doing.
extension Intercom {
    func startTestReports() {
        testTask?.cancel()
        testTask = nil
        guard isTestMode else { return }
        testTask = Task { [weak self] in
            var tick = 0
            while !Task.isCancelled {
                await self?.sendTestReport(withLog: tick % 5 == 0)
                tick += 1
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func sendTestReport(withLog: Bool) async {
        // Report to the boat we are on, or the one we are trying to get back to.
        guard let boat = currentBoat ?? boats.first(where: { $0.name == wantedBoat }) else { return }
        do {
            let reply = try await ControlClient.post(boat: boat, path: "api/report", body: testReport())
            for command in reply["commands"] as? [[String: Any]] ?? [] {
                if let action = command["action"] as? String { runTestCommand(action) }
            }
        } catch {
            return // the base station is out of reach; the next report will try again
        }
        guard withLog else { return }
        let lines = await LogFile.shared.takePending()
        guard !lines.isEmpty else { return }
        do {
            _ = try await ControlClient.post(boat: boat, path: "api/log",
                                             body: ["device_id": Preferences.deviceID, "name": displayName, "lines": lines])
        } catch {
            LogFile.shared.putBack(lines)
        }
    }

    private func runTestCommand(_ action: String) {
        log.info("Test bench command: \(action)")
        switch action {
        case "mute": setMuted(true)
        case "unmute": setMuted(false)
        case "mode": cycleMode()
        case "channel": cycleChannel()
        default: log.error("Unknown test bench command: \(action)")
        }
    }

    private func testReport() -> [String: Any] {
        let session = AVAudioSession.sharedInstance()
        let app = UIApplication.shared
        let device = UIDevice.current

        var report: [String: Any] = [
            "device_id": Preferences.deviceID,
            "name": displayName,
            "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
            "phase": phaseName,
            "channel": channel,
            "mode": mode.label,
            "muted": isMuted,
            "headset_muted": isHeadsetMuted,
            "mic_unavailable": isMicUnavailable,
            "silence_suppression": suppressesSilence,
            "redundancy": sendsRedundancy,
            "app_state": app.applicationState == .active ? "active" : (app.applicationState == .background ? "background" : "inactive"),
            // True a few seconds after the phone locks, on a phone with a passcode.
            "locked": !app.isProtectedDataAvailable,
            "charging": device.batteryState == .charging || device.batteryState == .full,
            "route_in": session.currentRoute.inputs.map(\.portType.rawValue).joined(separator: "+"),
            "route_out": session.currentRoute.outputs.map(\.portType.rawValue).joined(separator: "+"),
            "quality": qualityName,
            "mic_level_db": Double(testMicPeakDB),
            "audio_stall_ms": Int(testAudioStall * 1000),
            "joins": joinCount,
            "drops": dropCount,
        ]
        if device.batteryLevel >= 0 { report["battery"] = Double(device.batteryLevel) }
        testMicPeakDB = -120
        testAudioStall = 0

        // What this phone's own microphone track has put on the wire, and how much of it the
        // audio server says never arrived. Both counts start again with each join.
        let statistics = room.localParticipant.audioTracks.first?.track?.statistics
        if let packets = statistics?.outboundRtpStream.first?.packetsSent {
            var sent: [String: Any] = ["packets": packets]
            if let lost = statistics?.remoteInboundRtpStream.first?.packetsLost { sent["lost"] = lost }
            report["sent"] = sent
        }

        // What has arrived from each person this phone is listening to. The counts only ever grow;
        // the test bench works out the change between reports.
        var hearing: [[String: Any]] = []
        for person in room.remoteParticipants.values {
            guard let identity = person.identity?.stringValue else { continue }
            var entry: [String: Any] = ["identity": identity, "name": person.name ?? identity]
            if let stats = person.audioTracks.first?.track?.statistics?.inboundRtpStream.first {
                if let value = stats.packetsReceived { entry["packets"] = value }
                if let value = stats.packetsLost { entry["lost"] = value }
                if let value = stats.totalSamplesReceived { entry["samples"] = value }
                if let value = stats.concealedSamples { entry["concealed"] = value }
                if let value = stats.totalAudioEnergy { entry["energy"] = value }
                if let value = stats.totalSamplesDuration { entry["duration"] = value }
                if let value = stats.jitter { entry["jitter"] = value }
                // How long audio waits in the player before it is heard: a total, and how many
                // samples it is the total for. The bench divides one by the other.
                if let value = stats.jitterBufferDelay { entry["buffer_delay"] = value }
                if let value = stats.jitterBufferEmittedCount { entry["buffer_count"] = value }
                // Samples the player added to fall behind, and dropped to catch up.
                if let value = stats.insertedSamplesForDeceleration { entry["stretched"] = value }
                if let value = stats.removedSamplesForAcceleration { entry["squeezed"] = value }
                // Packets that arrived too late to be played.
                if let value = stats.packetsDiscarded { entry["discarded"] = value }
            }
            hearing.append(entry)
        }
        report["hearing"] = hearing
        return report
    }

    private var phaseName: String {
        switch phase {
        case .needsName: "needsName"
        case .looking: "looking"
        case .joining: "joining"
        case .connected: "connected"
        case .reconnecting: "reconnecting"
        }
    }

    private var qualityName: String {
        switch quality {
        case .excellent: "excellent"
        case .good: "good"
        case .poor: "poor"
        case .lost: "lost"
        default: "unknown"
        }
    }
}
