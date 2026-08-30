import Foundation
import OmakaseKit

let library = Library()
let switcher = Switcher(library: library)
var args = Array(CommandLine.arguments.dropFirst())

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data(("error: " + message + "\n").utf8))
    exit(1)
}

func flag(_ name: String) -> Bool {
    guard let i = args.firstIndex(of: name) else { return false }
    args.remove(at: i)
    return true
}

func value(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    let v = args[i + 1]
    args.removeSubrange(i...(i + 1))
    return v
}

func list() {
    let current = library.current?.slug
    for t in library.themes() { print("\(t.slug == current ? "*" : " ") \(t.slug)") }
}

func apply(_ name: String) {
    do {
        let theme = try library.theme(named: name)
        let notes = try switcher.apply(theme)
        print("→ \(theme.name)  (\(theme.appearance.rawValue), accent \(theme.accent.hex))")
        for n in notes { print("  ! \(n)") }
    } catch { fail(error.localizedDescription) }
}

/// The palette in truecolor.
///
/// Deliberately not the terminal's indexed colours: those repaint themselves
/// when the palette reloads, so every swatch already on screen would turn into
/// the newest theme — a demo where nothing appears to change.
func swatch(_ theme: Theme) {
    for row in [0..<8, 8..<16] {
        print(row.map { i -> String in
            let c = theme.palette[i]
            return "\u{1B}[48;2;\(c.r);\(c.g);\(c.b)m    \u{1B}[0m"
        }.joined())
    }
}

let usage = """
omakase — Omarchy-style themes for macOS

  omakase                       show the active theme and the list
  omakase <name>                switch to a theme
  omakase next                  rotate to the next theme
  omakase reload                re-apply the active theme
  omakase bg [n|next|name]      pick the wallpaper among the theme's own

  omakase fetch <name|owner/repo[#branch]> [--as <name>] [--no-wallpapers]
  omakase catalogue             list the themes upstream Omarchy publishes
  omakase install               wire up the apps present on this machine
  omakase install-cli [dir]     symlink omakase into your PATH
  omakase doctor                report which integrations are detected
  omakase restore [--yes]       put the files it touched back
  omakase swatch                print the active palette
  omakase demo [names...]       cycle themes on a timer, for screen recording
"""

switch args.first {
case nil, "list", "ls":
    list()

case "-h", "--help", "help":
    print(usage)

case "current":
    print(library.current?.slug ?? "(none)")

case "doctor":
    print("root      \(library.root.path)")
    print("themes    \(library.themes().count) installed")
    print("active    \(library.current?.slug ?? "(none)")\n")
    for i in Switcher.all {
        let wired = i.isWired(library)
        let mark = !i.isInstalled ? "–" : (wired ? "✓" : "!")
        let state = !i.isInstalled ? "not installed"
                                   : (wired ? "wired" : "installed but not wired")
        print("  \(mark)  \(i.name.padding(toLength: 18, withPad: " ", startingAt: 0)) \(state)")
    }

case "install":
    try switcher.install()
    print("wired up. Now pick a theme:  omakase <name>")

case "install-cli":
    // The CLI lives inside the app bundle; this puts it on the PATH.
    let target = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
    let dir = URL(fileURLWithPath: args.count > 1 ? args[1]
                  : Files.home.appendingPathComponent(".local/bin").path)
    let link = dir.appendingPathComponent("omakase")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try? FileManager.default.removeItem(at: link)
    // A binary inside an .app keeps its path across updates, so link to it. One
    // sitting in .build does not survive the next compile, so copy it instead.
    if target.path.contains(".app/Contents/") {
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        print("→ \(link.path) → \(target.path)")
    } else {
        try FileManager.default.copyItem(at: target, to: link)
        print("→ \(link.path) (copied)")
    }
    if !(ProcessInfo.processInfo.environment["PATH"] ?? "").contains(dir.path) {
        print("  ! add it to your PATH:  export PATH=\"\(dir.path):$PATH\"")
    }

case "seed":
    let source = args.count > 1
        ? URL(fileURLWithPath: args[1])
        : Bundle.main.bundleURL.deletingLastPathComponent()
            .appendingPathComponent("Resources/Themes")
    print("seeded \(library.seed(from: source)) theme(s) from \(source.path)")

case "reload":
    guard let c = library.current else { fail("no active theme") }
    apply(c.slug)

case "next":
    let all = library.themes()
    guard !all.isEmpty else { fail("no themes installed") }
    let i = all.firstIndex { $0.slug == library.current?.slug }.map { ($0 + 1) % all.count } ?? 0
    apply(all[i].slug)

case "set":
    guard args.count > 1 else { fail("usage: omakase set <name>") }
    apply(args[1])

case "swatch":
    guard let theme = library.current else { fail("no active theme") }
    swatch(theme)

case "bg":
    guard let theme = library.current else { fail("no active theme") }
    let all = theme.wallpapers
    guard !all.isEmpty else { fail("theme '\(theme.slug)' ships no wallpapers (try: omakase fetch \(theme.slug))") }
    let active = library.wallpaper(for: theme)
    guard args.count > 1 else {
        for (i, url) in all.enumerated() {
            print("\(url == active ? "*" : " ") \(i + 1). \(url.lastPathComponent)")
        }
        exit(0)
    }
    let argument = args[1]
    let pick: URL
    if argument == "next" {
        let i = all.firstIndex(of: active ?? all[0]) ?? 0
        pick = all[(i + 1) % all.count]
    } else if let n = Int(argument), n >= 1, n <= all.count {
        pick = all[n - 1]
    } else {
        let matches = all.filter { $0.lastPathComponent.lowercased().contains(argument.lowercased()) }
        guard matches.count == 1 else { fail("'\(argument)' does not identify a single wallpaper. Try: omakase bg") }
        pick = matches[0]
    }
    library.remember(wallpaper: pick, for: theme)
    if let note = WallpaperIntegration().set(pick) { print("  ! \(note)") }
    print("→ \(pick.lastPathComponent)")

case "catalogue":
    do { print(try Fetcher(library: library).catalogue().joined(separator: "\n")) }
    catch { fail(error.localizedDescription) }

case "fetch":
    let wallpapers = !flag("--no-wallpapers")
    let alias = value("--as")
    guard args.count > 1 else { fail("usage: omakase fetch <name|owner/repo> [--as <name>] [--no-wallpapers]") }
    let spec = args[1]
    let fetcher = Fetcher(library: library)
    do {
        // An installed theme fetched by name just gets its wallpapers back —
        // unless --as was given, which always means "install a new theme".
        let known = alias == nil && !spec.contains("/")
            && Files.exists(library.themesDirectory.appendingPathComponent("\(spec)/source.json"))
        let result = known ? try fetcher.refetchWallpapers(spec)
                           : try fetcher.fetch(spec, as: alias, wallpapers: wallpapers)
        for s in result.skipped { print("    (skipped \(s))") }
        let theme = try library.theme(named: result.slug)
        print("→ \(result.slug): \(theme.appearance.rawValue), accent \(theme.accent.hex), "
              + "\(result.wallpapers) new wallpaper(s). Apply it with:  omakase \(result.slug)")
    } catch { fail(error.localizedDescription) }

case "restore":
    // Backups live next to the files they shadow, so find them where omakase
    // is allowed to write.
    var found: [URL] = []
    let roots = [Files.home.appendingPathComponent(".config"),
                 Files.home.appendingPathComponent("Library/Application Support"),
                 Files.home.appendingPathComponent(".vscode")]
    for root in roots {
        guard let walker = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
        for case let url as URL in walker where url.lastPathComponent.hasSuffix(".omakase-bak") {
            found.append(url)
        }
    }
    guard !found.isEmpty else { print("nothing to restore: no .omakase-bak files found"); exit(0) }
    for backup in found {
        let target = URL(fileURLWithPath: String(backup.path.dropLast(".omakase-bak".count)))
        print("  \(backup.path) → \(target.path)")
    }
    guard flag("--yes") else { print("\nre-run with --yes to actually restore"); exit(0) }
    for backup in found {
        let target = URL(fileURLWithPath: String(backup.path.dropLast(".omakase-bak".count)))
        try? FileManager.default.removeItem(at: target)
        try? FileManager.default.copyItem(at: backup, to: target)
    }
    Shell.run("/usr/bin/killall", ["WallpaperAgent"], timeout: 5)
    print("restored.")

case "demo":
    let hold = Double(value("--hold") ?? "") ?? 4
    let countdown = Int(value("--countdown") ?? "") ?? 3
    let names = args.count > 1 ? Array(args.dropFirst()) : library.themes().map(\.slug)
    for i in stride(from: countdown, to: 0, by: -1) {
        print("\rrecording in \(i)… ", terminator: "")
        fflush(stdout)
        Thread.sleep(forTimeInterval: 1)
    }
    print("\r" + String(repeating: " ", count: 24) + "\r", terminator: "")
    for name in names {
        guard let theme = try? library.theme(named: name) else { fail("unknown theme '\(name)'") }
        _ = try? switcher.apply(theme)
        print("\n  \u{1B}[1m\(theme.name)\u{1B}[0m  ·  \(theme.appearance.rawValue)  ·  \(theme.accent.hex)\n")
        swatch(theme)
        Thread.sleep(forTimeInterval: hold)
    }

case let name?:
    apply(name)
}
