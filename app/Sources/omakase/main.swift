import Foundation
import OmakaseKit

let library = Library()
let switcher = Switcher(library: library)
var args = Array(CommandLine.arguments.dropFirst())

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data(("error: " + message + "\n").utf8))
    exit(1)
}

func list() {
    let current = library.current?.slug
    for t in library.themes() {
        print("\(t.slug == current ? "*" : " ") \(t.slug)")
    }
}

func apply(_ name: String) {
    do {
        let theme = try library.theme(named: name)
        let notes = try switcher.apply(theme)
        print("→ \(theme.name)  (\(theme.appearance.rawValue), accent \(theme.accent.hex))")
        for n in notes { print("  ! \(n)") }
    } catch { fail(error.localizedDescription) }
}

let usage = """
omakase — Omarchy-style themes for macOS

  omakase                    show the active theme and the list
  omakase <name>             switch to a theme
  omakase next               rotate to the next theme
  omakase reload             re-apply the active theme
  omakase doctor             report which integrations are detected
  omakase install            wire up the apps present on this machine
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
    let themes = library.themes()
    print("themes    \(themes.count) installed")
    print("active    \(library.current?.slug ?? "(none)")\n")
    for i in Switcher.all {
        let wired = i.isWired(library)
        let mark = !i.isInstalled ? "–" : (wired ? "✓" : "!")
        let state = !i.isInstalled ? "not installed"
                                   : (wired ? "wired" : "installed but not wired")
        print("  \(mark)  \(i.name.padding(toLength: 18, withPad: " ", startingAt: 0)) \(state)")
    }
case "seed":
    // Themes bundled with the app, copied in on first run. Also useful on its
    // own: `omakase seed <dir>` adopts a directory of themes.
    let source = args.count > 1
        ? URL(fileURLWithPath: args[1])
        : Bundle.main.bundleURL.deletingLastPathComponent()
            .appendingPathComponent("Resources/Themes")
    let n = library.seed(from: source)
    print("seeded \(n) theme(s) from \(source.path)")
case "install":
    try switcher.install()
    print("wired up. Now pick a theme:  omakase <name>")
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
case let name?:
    apply(name)
}
