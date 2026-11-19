import Foundation

/// Adds up the speech iOS hears while the microphone is muted, to decide when to say "you're muted".
///
/// iOS reports speech in short stretches and ends one at every small pause. Someone talking
/// normally gives stretches of a second or so with gaps between them, so one stretch rarely
/// lasts two seconds (seen on an iPhone Air, 2026-11-18). The stretches are added up instead.
/// A pause longer than `longestPause` starts the count again.
struct MutedSpeechTally {
    /// How much speech earns a reminder.
    static let enough: TimeInterval = 2
    /// A silence longer than this means the person stopped talking, and the count starts again.
    static let longestPause: TimeInterval = 3

    private var finished: TimeInterval = 0
    private var began: Date?
    private var lastEnd: Date?

    /// iOS says speech began.
    mutating func started(at now: Date) {
        if began == nil, let lastEnd, now.timeIntervalSince(lastEnd) > Self.longestPause { finished = 0 }
        // iOS sometimes reports a start twice. The first one counts.
        if began == nil { began = now }
    }

    /// iOS says speech ended. An end with no start, as comes just after muting, counts for nothing.
    mutating func ended(at now: Date) {
        guard let began else { return }
        finished += max(now.timeIntervalSince(began), 0)
        self.began = nil
        lastEnd = now
    }

    /// Speech heard so far, counting the stretch still running.
    func spoken(at now: Date) -> TimeInterval {
        finished + (began.map { max(now.timeIntervalSince($0), 0) } ?? 0)
    }

    /// How much longer the running stretch has to last to earn a reminder.
    func remaining(at now: Date) -> TimeInterval {
        max(Self.enough - spoken(at: now), 0)
    }

    /// A twentieth of a second of slack, for a check that wakes a moment early.
    func isEnough(at now: Date) -> Bool {
        spoken(at: now) >= Self.enough - 0.05
    }

    /// The count starts again: after a reminder, and at every mute and unmute.
    mutating func reset() {
        self = MutedSpeechTally()
    }
}
