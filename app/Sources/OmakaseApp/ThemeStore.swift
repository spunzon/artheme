import Foundation
import OmakaseKit
import SwiftUI

/// The app's single source of truth: what is installed, what is active, and
/// applying a theme without blocking the interface.
@MainActor
final class ThemeStore: ObservableObject {
    @Published private(set) var themes: [Theme] = []
    @Published private(set) var currentSlug: String?
    @Published private(set) var busySlug: String?
    @Published private(set) var fetching: String?
    @Published var notes: [String] = []

    private let library = Library()
    private lazy var switcher = Switcher(library: library)

    init() {
        // A downloaded app starts with an empty ~/.config/omakase, so the
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
        Task {
            let result: [String] = await Task.detached(priority: .userInitiated) { [switcher] in
                (try? switcher.apply(theme)) ?? ["could not apply \(theme.name)"]
            }.value
            notes = result
            currentSlug = theme.slug
            busySlug = nil
            fetchWallpapersIfMissing(theme)
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
        Task { [library] in
            let landed: Int = await Task.detached(priority: .background) {
                (try? Fetcher(library: library).refetchWallpapers(theme.slug))?.wallpapers ?? 0
            }.value
            if landed > 0, let updated = try? library.theme(named: theme.slug),
               let image = library.wallpaper(for: updated) {
                await Task.detached(priority: .userInitiated) {
                    WallpaperIntegration().set(image)
                }.value
            }
            fetching = nil
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
