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

    private let library = Library()
    private lazy var switcher = Switcher(library: library)

    init() {
        // A downloaded app starts with an empty ~/.config/artheme, so the
        // themes shipped in the bundle are copied in on first launch.
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("Themes") {
            library.seed(from: bundled)
        }
        reload()
    }

    func reload() {
        themes = library.themes()
        currentSlug = library.current?.slug
    }

    var current: Theme? { themes.first { $0.slug == currentSlug } }

    /// Wallpapers belonging to the active theme, for the picker.
    var wallpapers: [URL] { current?.wallpapers ?? [] }
    var activeWallpaper: URL? { current.flatMap { library.wallpaper(for: $0) } }

    func apply(_ theme: Theme) {
        guard busySlug == nil else { return }
        busySlug = theme.slug
        WallpaperArbiter.shared.newRound()
        // Started here, not after the switch finishes: the download and the
        // apply pass have nothing to say to each other, and running them in
        // parallel is the difference between the picture landing at 1.4s and
        // at 0.8s. The arbiter settles which of the two gets the desktop.
        fetchWallpapersIfMissing(theme)
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
    private func fetchWallpapersIfMissing(_ theme: Theme) {
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
                        shown = true
                        library.remember(wallpaper: url, for: theme)
                        // Beats the flat colour whichever finishes first.
                        if WallpaperArbiter.shared.claim(.photograph) {
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
        guard let theme = current else { return }
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
}
