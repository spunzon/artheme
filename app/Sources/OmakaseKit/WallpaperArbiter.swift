import Foundation

/// Decides who gets the desktop while a theme switch is in flight.
///
/// The download now starts the moment a theme is picked, in parallel with
/// applying it, so the two race: the flat colour is written by the apply pass
/// and the photograph by the download, and either can finish first. Within a
/// round a photograph always wins, whatever the order — otherwise a fast
/// download would be overwritten by the placeholder that was meant to cover it.
public final class WallpaperArbiter: @unchecked Sendable {
    public static let shared = WallpaperArbiter()

    public enum Claim: Int, Sendable {
        case flatColour = 0
        case photograph = 1
    }

    private let lock = NSLock()
    private var winner = -1

    /// A new theme switch. Everything from the previous one loses.
    public func newRound() {
        lock.lock(); winner = -1; lock.unlock()
    }

    /// True if this claim should be applied — that is, if nothing better has
    /// already taken this round.
    public func claim(_ claim: Claim) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard claim.rawValue > winner else { return false }
        winner = claim.rawValue
        return true
    }
}
