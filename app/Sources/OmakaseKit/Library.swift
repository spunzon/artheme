import Foundation

/// Where themes live and which one is active.
///
/// The layout is the same one the shell version used, so an existing
/// ~/.config/omakase keeps working: themes/<name>/colors.toml, generated/ for
/// derived files, and `current` as a symlink to the active theme.
public struct Library: Sendable {
    public let root: URL

    public init(root: URL? = nil) {
        if let root {
            self.root = root
        } else if let env = ProcessInfo.processInfo.environment["OMAKASE_HOME"], !env.isEmpty {
            self.root = URL(fileURLWithPath: (env as NSString).expandingTildeInPath)
        } else {
            self.root = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".config/omakase")
        }
    }

    public var themesDirectory: URL { root.appendingPathComponent("themes") }
    public var generated: URL { root.appendingPathComponent("generated") }
    public var currentLink: URL { root.appendingPathComponent("current") }

    public func ensureDirectories() throws {
        for d in [themesDirectory, generated] {
            try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        }
    }

    /// Every readable theme, sorted by name. Unreadable ones are skipped rather
    /// than fatal: one broken download must not hide the rest of the library.
    public func themes() -> [Theme] {
        let dirs = (try? FileManager.default.contentsOfDirectory(
            at: themesDirectory, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        return dirs.compactMap { try? Theme.load(directory: $0) }
                   .sorted { $0.slug < $1.slug }
    }

    public func theme(named slug: String) throws -> Theme {
        guard let safe = Paths.safeChild(of: themesDirectory, named: slug) else {
            throw OmakaseError.noSuchTheme(slug)
        }
        do { return try Theme.load(directory: safe) }
        catch { throw OmakaseError.noSuchTheme(slug) }
    }

    public var current: Theme? {
        guard let target = try? FileManager.default.destinationOfSymbolicLink(
            atPath: currentLink.path) else { return nil }
        let url = target.hasPrefix("/") ? URL(fileURLWithPath: target)
                                        : root.appendingPathComponent(target)
        return try? Theme.load(directory: url)
    }

    public func setCurrent(_ theme: Theme) throws {
        let fm = FileManager.default
        if (try? fm.destinationOfSymbolicLink(atPath: currentLink.path)) != nil
            || fm.fileExists(atPath: currentLink.path) {
            try? fm.removeItem(at: currentLink)
        }
        try fm.createSymbolicLink(at: currentLink, withDestinationURL: theme.directory)
    }

    /// The wallpaper chosen for a theme, remembered per theme.
    public func wallpaper(for theme: Theme) -> URL? {
        let all = theme.wallpapers
        guard !all.isEmpty else { return nil }
        let note = generated.appendingPathComponent("wallpaper-\(theme.slug).txt")
        if let want = try? String(contentsOf: note, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
           let match = all.first(where: { $0.lastPathComponent == want }) {
            return match
        }
        return all.first
    }

    public func remember(wallpaper: URL, for theme: Theme) {
        try? ensureDirectories()
        try? wallpaper.lastPathComponent.write(
            to: generated.appendingPathComponent("wallpaper-\(theme.slug).txt"),
            atomically: true, encoding: .utf8)
    }
}

public enum Paths {
    /// `parent/name`, refusing anything that could escape the directory.
    /// Names reach this from remote listings and from the command line.
    public static func safeChild(of parent: URL, named name: String) -> URL? {
        guard !name.isEmpty, !name.hasPrefix("."), !name.contains("/"),
              !name.contains("\\"), name != "..", name != "." else { return nil }
        let child = parent.appendingPathComponent(name)
        guard child.standardizedFileURL.path.hasPrefix(
            parent.standardizedFileURL.path + "/") else { return nil }
        return child
    }
}
