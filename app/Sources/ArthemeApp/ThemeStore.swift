import AppKit
import Foundation
import ArthemeKit
import SwiftUI

/// The app's single source of truth: what is installed, what is active, and
/// applying a theme without blocking the interface.
@MainActor
final class ThemeStore: ObservableObject {
    @Published private(set) var themes: [Theme] = []
    @Published private(set) var currentSlug: String?
    @Published private(set) var busySlug: String?
    @Published private(set) var fetching: String?
    @Published private(set) var failed: String?
    @Published private(set) var showsProgress = false
    @Published var notes: [String] = []

    /// State for the "add a theme" sheet — kept separate from `busySlug`
    /// because adding and switching can legitimately overlap.
    @Published var addBusy = false
    @Published var addError: String?

    /// State for self-updating.
    @Published private(set) var availableUpdate: Updater.Release?
    @Published var updateBusy = false
    @Published var updateError: String?

    private let library = Library()
    private lazy var switcher = Switcher(library: library)
    private lazy var fetcher = Fetcher(library: library)
    private let updater = Updater()

    init() {
        // A downloaded app starts with an empty ~/.config/artheme, so the
        // themes shipped in the bundle are copied in on first launch.
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("Themes") {
            library.seed(from: bundled)
        }
        reload()
        checkForUpdatesIfDue()
    }

    func reload() {
        themes = library.themes()
        currentSlug = library.current?.slug
    }

    var current: Theme? { themes.first { $0.slug == currentSlug } }

    /// One line per switch, one indented line per integration — the first
    /// thing to ask someone for when "it applied but nothing changed".
    var logURL: URL { library.lastApplyLog }

    /// Opens the log in whatever handles `.log` (Console, TextEdit…), or
    /// reveals it in Finder if nothing has run yet to create the file.
    func revealLog() {
        if FileManager.default.fileExists(atPath: logURL.path) {
            NSWorkspace.shared.open(logURL)
        } else {
            try? library.ensureDirectories()
            NSWorkspace.shared.activateFileViewerSelecting([library.generated])
        }
    }

    /// Wallpapers belonging to the active theme, for the picker.
    var wallpapers: [URL] { current?.wallpapers ?? [] }
    var activeWallpaper: URL? { current.flatMap { library.wallpaper(for: $0) } }

    func apply(_ theme: Theme) {
        guard busySlug == nil else { return }
        busySlug = theme.slug
        let round = WallpaperArbiter.shared.newRound()
        // Started here, not after the switch finishes: the download and the
        // apply pass have nothing to say to each other, and running them in
        // parallel is the difference between the picture landing at 1.4s and
        // at 0.8s. The arbiter settles which of the two gets the desktop.
        fetchWallpapersIfMissing(theme, round: round)
        Task {
            let result: [String] = await Task.detached(priority: .userInitiated) { [switcher] in
                (try? switcher.apply(theme)) ?? ["could not apply \(theme.name)"]
            }.value
            notes = result
            currentSlug = theme.slug
            busySlug = nil
        }
    }

    /// Wallpapers are not shipped with the app — 100 MB of other people's work
    /// — so the first time a theme is actually applied its pictures are pulled
    /// in the background and the desktop updates when they land.
    private func fetchWallpapersIfMissing(_ theme: Theme, round: Int) {
        let source = theme.directory.appendingPathComponent("source.json")
        guard theme.wallpapers.isEmpty, FileManager.default.fileExists(atPath: source.path)
        else { return }
        fetching = theme.slug
        failed = nil
        // Held back on purpose: an indicator that shows and hides within half a
        // second is worse than none, and most downloads finish inside it.
        Task {
            try? await Task.sleep(nanoseconds: 700_000_000)
            if fetching == theme.slug { showsProgress = true }
        }
        Task { [library] in
            let landed: Int = await Task.detached(priority: .background) {
                // The first picture to arrive goes up straight away; the rest
                // keep downloading behind it for the wallpaper picker.
                var shown = false
                let result = try? Fetcher(library: library)
                    .refetchWallpapers(theme.slug) { url, _ in
                        guard !shown else { return }
                        // The arbiter only knows about this process; the CLI
                        // and a second window are other processes entirely. So
                        // check on disk that this theme is still the active one
                        // before painting its picture.
                        guard library.current?.slug == theme.slug else { return }
                        shown = true
                        library.remember(wallpaper: url, for: theme)
                        // Beats the flat colour whichever finishes first, and
                        // loses outright if the user has moved on since.
                        if WallpaperArbiter.shared.claim(.photograph, round: round) {
                            WallpaperIntegration().set(url)
                        }
                    }
                return result?.wallpapers ?? 0
            }.value
            fetching = nil
            showsProgress = false
            failed = landed == 0 ? theme.slug : nil
            reload()
        }
    }

    func chooseWallpaper(_ url: URL) {
        // Re-read from disk: the theme may have changed from the CLI or the
        // menu bar since this window last looked, and remembering a wallpaper
        // against the wrong theme is how they drift apart.
        guard let theme = library.current else { return }
        library.remember(wallpaper: url, for: theme)
        Task.detached(priority: .userInitiated) {
            WallpaperIntegration().set(url)
        }
        objectWillChange.send()
    }

    func next() {
        guard !themes.isEmpty else { return }
        let i = themes.firstIndex { $0.slug == currentSlug }.map { ($0 + 1) % themes.count } ?? 0
        apply(themes[i])
    }

    // MARK: - Adding themes

    /// Whether a theme with this slug already exists — for validating the
    /// "add" sheet as the user types, before they hit the button and get a
    /// generic file-system error back.
    func isSlugTaken(_ slug: String) -> Bool {
        themes.contains { $0.slug == slug }
    }

    /// Downloads a theme from Omarchy (`"osaka-jade"`) or a standalone repo
    /// (`"owner/repo"`, `"owner/repo#branch"`). Runs off the main actor
    /// because it hits the network; `addBusy`/`addError` drive the sheet.
    func addFromRepo(_ spec: String, as alias: String?) async {
        guard !addBusy else { return }
        addBusy = true
        addError = nil
        do {
            let slug = try await Task.detached(priority: .userInitiated) { [fetcher] in
                try fetcher.fetch(spec, as: alias).slug
            }.value
            reload()
            currentSlug = currentSlug ?? slug
        } catch {
            addError = error.localizedDescription
        }
        addBusy = false
    }

    static let maxWallpaperImport = 12 * 1024 * 1024   // matches Fetcher's own cap
    static let importableImages: Set<String> = ["jpg", "jpeg", "png", "heic", "webp"]

    /// Writes a hand-built `colors.toml` under a new slug, copies in any
    /// chosen wallpapers, and reloads. `entries` is ordered so the file reads
    /// the way a person would write it; duplicate keys are the caller's
    /// mistake, not something to guard here.
    @discardableResult
    func addManualTheme(name: String, slug: String,
                        entries: [(String, String)],
                        wallpapers: [URL] = []) -> Bool {
        guard let destination = Paths.safeChild(of: library.themesDirectory, named: slug) else {
            addError = "'\(slug)' is not a valid theme name"
            return false
        }
        guard !isSlugTaken(slug), !FileManager.default.fileExists(atPath: destination.path) else {
            addError = "a theme named '\(slug)' already exists"
            return false
        }
        // The name reaches a `key = "value"` line verbatim, so strip whatever
        // would break out of the quotes — Theme.load does the same on read,
        // but a broken write is still a broken file.
        let safeName = name.filter { $0 != "\"" && $0 != "\\" && !$0.isNewline }
        do {
            try library.ensureDirectories()
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            var lines = ["name = \"\(safeName)\""]
            lines += entries.map { "\($0.0) = \"\($0.1)\"" }
            try (lines.joined(separator: "\n") + "\n")
                .write(to: destination.appendingPathComponent("colors.toml"),
                       atomically: true, encoding: .utf8)
            try copyWallpapers(wallpapers, into: destination)
        } catch {
            addError = error.localizedDescription
            try? FileManager.default.removeItem(at: destination)
            return false
        }
        addError = nil
        reload()
        return true
    }

    /// Copies picked images into `<theme>/backgrounds/`, skipping anything
    /// that is not a recognised image type or is over the size cap other
    /// downloads use — the file panel lets you pick a video by mistake, this
    /// is where that gets caught.
    private func copyWallpapers(_ urls: [URL], into destination: URL) throws {
        guard !urls.isEmpty else { return }
        let backgrounds = destination.appendingPathComponent("backgrounds")
        try FileManager.default.createDirectory(at: backgrounds, withIntermediateDirectories: true)
        for url in urls {
            guard Self.importableImages.contains(url.pathExtension.lowercased()) else { continue }
            guard let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int,
                  size <= Self.maxWallpaperImport else { continue }
            guard let out = Paths.safeChild(of: backgrounds, named: url.lastPathComponent) else { continue }
            var candidate = out
            var n = 1
            while FileManager.default.fileExists(atPath: candidate.path) {
                candidate = backgrounds.appendingPathComponent(
                    "\(out.deletingPathExtension().lastPathComponent)-\(n).\(out.pathExtension)")
                n += 1
            }
            try? FileManager.default.copyItem(at: url, to: candidate)
        }
    }

    // MARK: - Self-update

    var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    private static let lastCheckKey = "artheme.lastUpdateCheck"

    /// Silent, and at most once a day — a GUI app that pings GitHub on every
    /// launch is how you get personally rate-limited by your own project.
    private func checkForUpdatesIfDue() {
        let last = UserDefaults.standard.double(forKey: Self.lastCheckKey)
        guard Date().timeIntervalSince1970 - last > 86400 else { return }
        Task { await checkForUpdates(silent: true) }
    }

    /// `silent: true` never surfaces a network error — used for the automatic
    /// daily check, where "GitHub was unreachable" is not worth interrupting
    /// anyone over. The menu's "Check for Updates…" passes `false`.
    func checkForUpdates(silent: Bool = false) async {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastCheckKey)
        let version = appVersion
        do {
            let release = try await Task.detached(priority: .background) { [updater] in
                try updater.checkForUpdate(current: version)
            }.value
            availableUpdate = release
            if !silent { updateError = nil }
        } catch {
            if !silent { updateError = error.localizedDescription }
        }
    }

    /// Downloads and installs `availableUpdate`, then relaunches — this call
    /// does not return on success.
    func installUpdate() async {
        guard let release = availableUpdate, !updateBusy else { return }
        updateBusy = true
        updateError = nil
        do {
            try await Task.detached(priority: .userInitiated) { [updater] in
                try updater.install(release)
            }.value
        } catch {
            updateError = error.localizedDescription
        }
        updateBusy = false
    }
}
