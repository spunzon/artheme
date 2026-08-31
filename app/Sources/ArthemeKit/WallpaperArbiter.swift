import Foundation

/// Decides who gets the desktop while a theme switch is in flight.
///
/// Two things race for the wallpaper: the apply pass, which puts up the
/// theme's flat colour, and the download, which puts up the first photograph
/// to arrive. Either can finish first, and a photograph must always win.
///
/// But claims also have to belong to a round, because a download outlives the
/// switch that started it. Without that, this happens: you apply a theme with
/// no wallpapers yet, it starts downloading, you pick another theme, and the
/// late download — arriving in the middle of the new switch, before the new
/// theme reaches the wallpaper step — takes the desktop. You end up with the
/// previous theme's picture under the new theme's colours.
public final class WallpaperArbiter: @unchecked Sendable {
    public static let shared = WallpaperArbiter()

    public enum Claim: Int, Sendable {
        case flatColour = 0
        case photograph = 1
    }

    private let lock = NSLock()
    private var round = 0
    private var winner = -1

    /// Starts a new switch and returns its token. Anything still holding an
    /// older token has already lost.
    @discardableResult
    public func newRound() -> Int {
        lock.lock(); defer { lock.unlock() }
        round += 1
        winner = -1
        return round
    }

    /// The switch currently in progress.
    public var currentRound: Int {
        lock.lock(); defer { lock.unlock() }
        return round
    }

    /// True if this claim should be applied: it belongs to the current round
    /// and nothing better has taken it yet.
    public func claim(_ claim: Claim, round claimed: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard claimed == round, claim.rawValue > winner else { return false }
        winner = claim.rawValue
        return true
    }
}
