import ArthemeKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: ThemeStore
    @State private var query = ""
    @State private var onlyLight = false
    @State private var onlyDark = false
    @State private var showingAdd = false

    private var visible: [Theme] {
        store.themes.filter { theme in
            let matches = query.isEmpty
                || theme.displayName.localizedCaseInsensitiveContains(query)
                || theme.slug.localizedCaseInsensitiveContains(query)
            let appearance = (!onlyLight && !onlyDark)
                || (onlyLight && theme.appearance == .light)
                || (onlyDark && theme.appearance == .dark)
            return matches && appearance
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            grid
            if !store.notes.isEmpty { notes }
            Divider()
            statusBar
        }
        .frame(minWidth: 560, minHeight: 420)
        // The CLI, the menu bar item and this window all change the same
        // thing, so the grid re-reads the active theme whenever it comes back
        // to the front instead of showing whatever it saw when it opened.
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification)) { _ in
            store.reload()
        }
        .sheet(isPresented: $showingAdd) {
            AddThemeView().environmentObject(store)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search themes", text: $query)
                .textFieldStyle(.plain)
                .frame(maxWidth: 220)
            Spacer()
            Toggle("Light", isOn: $onlyLight).toggleStyle(.button).controlSize(.small)
            Toggle("Dark", isOn: $onlyDark).toggleStyle(.button).controlSize(.small)
            Button { store.reload() } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless)
                .help("Reload the list from disk")
            Button { showingAdd = true } label: { Image(systemName: "plus") }
                .buttonStyle(.borderless)
                .help("Add a theme")
            Button { store.revealLog() } label: { Image(systemName: "doc.text.magnifyingglass") }
                .buttonStyle(.borderless)
                .help("Open the switch log — what each app did on the last theme change")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 190, maximum: 260), spacing: 14)],
                      spacing: 14) {
                ForEach(visible) { theme in
                    ThemeCard(theme: theme,
                              isCurrent: theme.slug == store.currentSlug,
                              isBusy: theme.slug == store.busySlug)
                        .onTapGesture { store.apply(theme) }
                }
            }
            .padding(14)
        }
        .overlay {
            if visible.isEmpty { empty }
        }
    }

    /// Hand-rolled rather than ContentUnavailableView, which is macOS 14+:
    /// the deployment target stays at 13 so more people can run this.
    private var empty: some View {
        VStack(spacing: 6) {
            Image(systemName: "paintpalette").font(.largeTitle).foregroundStyle(.tertiary)
            Text(store.themes.isEmpty ? "No themes yet" : "Nothing matches")
                .font(.headline)
            Text(store.themes.isEmpty
                 ? "Add one to ~/.config/artheme/themes"
                 : "No theme matches “\(query)”")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var notes: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(store.notes, id: \.self) { note in
                Label(note, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14).padding(.vertical, 6)
    }

    /// The active theme's own wallpapers, so switching picture never leaves the
    /// palette behind.
    private var statusBar: some View {
        HStack(spacing: 10) {
            if let current = store.current {
                Circle().fill(current.accent.swiftUI).frame(width: 9, height: 9)
                Text(current.displayName).font(.system(size: 12, weight: .medium))
                Text(current.appearance.rawValue).font(.caption).foregroundStyle(.secondary)
            } else {
                Text("No theme applied").font(.caption).foregroundStyle(.secondary)
            }
            if store.showsProgress, let fetching = store.fetching {
                ProgressView().controlSize(.small).scaleEffect(0.7)
                Text("fetching \(fetching) wallpapers…")
                    .font(.caption).foregroundStyle(.secondary)
            } else if let failed = store.failed {
                // Silence here is the worst outcome: without this the user
                // cannot tell "no wallpapers", "still downloading" and "no
                // internet" apart.
                Label("couldn't fetch \(failed) wallpapers — check your connection",
                      systemImage: "wifi.exclamationmark")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if store.wallpapers.count > 1 {
                Text("Wallpaper").font(.caption).foregroundStyle(.secondary)
                ForEach(store.wallpapers, id: \.self) { url in
                    Button { store.chooseWallpaper(url) } label: {
                        thumbnail(url, active: url == store.activeWallpaper)
                    }
                    .buttonStyle(.plain)
                    .help(url.lastPathComponent)
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }

    private func thumbnail(_ url: URL, active: Bool) -> some View {
        Group {
            if let image = Thumbnail.load(url, maxPixel: 120) {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(.quaternary)
            }
        }
        .frame(width: 34, height: 22)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4)
            .strokeBorder(active ? SwiftUI.Color.primary : SwiftUI.Color.clear, lineWidth: 2))
    }
}
