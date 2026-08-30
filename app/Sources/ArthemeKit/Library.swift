import Foundation

/// Where themes live and which one is active.
///
/// The layout is the same one the shell version used, so an existing
/// ~/.config/artheme keeps working: themes/<name>/colors.toml, generated/ for
/// derived files, and `current` as a symlink to the active theme.
public struct Library: Sendable {
    public let root: URL

    public init(root: URL? = nil) {
        if let root {
            self.root = root
        } else if let env = ProcessInfo.processInfo.environment["ARTHEME_HOME"], !env.isEmpty {
            self.root = URL(fileURLWithPath: (env as NSString).expandingTildeInPath)
        } else {
            self.root = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".config/artheme")
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
            throw ArthemeError.noSuchTheme(slug)
        }
        do { return try Theme.load(directory: safe) }
        catch { throw ArthemeError.noSuchTheme(slug) }
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
    ///
    /// Names reach this from remote listings and from the command line, so the
    /// name itself is what is validated — no separators, no `..`, nothing
    /// hidden. That is the guarantee; the parent check below is defence in
    /// depth and deliberately does NOT touch the file system:
    /// `resolvingSymlinksInPath` strips a leading /private only when the path
    /// already exists, so an existing parent and a not-yet-created child
    /// resolve to different prefixes and every legitimate name gets rejected.
    public static func safeChild(of parent: URL, named name: String) -> URL? {
        guard !name.isEmpty, !name.hasPrefix("."), !name.contains("/"),
              !name.contains("\\"), name != "..", name != "." else { return nil }
        let child = parent.appendingPathComponent(name)
        // Compare normalised path strings, not URLs: deletingLastPathComponent
        // leaves a trailing slash and URL(fileURLWithPath:) only adds one when
        // the directory already exists, so == would depend on what is on disk.
        func normalised(_ url: URL) -> String {
            var path = url.standardizedFileURL.path
            while path.count > 1 && path.hasSuffix("/") { path.removeLast() }
            return path
        }
        guard normalised(child.deletingLastPathComponent()) == normalised(parent)
        else { return nil }
        return child
    }
}

public extension Library {
    /// Copy the themes bundled with the app into the user's library.
    ///
    /// A freshly downloaded app must not open on an empty grid, and the themes
    /// it ships are ~600 bytes each. Existing themes are never touched: this
    /// only fills in what is missing.
    @discardableResult
    func seed(from source: URL) -> Int {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: source, includingPropertiesForKeys: nil) else { return 0 }
        do { try ensureDirectories() } catch {
            // Never silent: a home that cannot be written to is worth saying.
            FileHandle.standardError.write(
                Data("artheme: cannot create \(themesDirectory.path): \(error.localizedDescription)\n".utf8))
            return 0
        }
        var copied = 0
        for entry in entries {
            guard FileManager.default.fileExists(
                atPath: entry.appendingPathComponent("colors.toml").path),
                  let destination = Paths.safeChild(of: themesDirectory,
                                                    named: entry.lastPathComponent),
                  !FileManager.default.fileExists(atPath: destination.path)
            else { continue }
            if (try? FileManager.default.copyItem(at: entry, to: destination)) != nil {
                copied += 1
            }
        }
        return copied
    }
}
