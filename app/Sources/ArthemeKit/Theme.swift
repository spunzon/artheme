import Foundation

public enum ArthemeError: LocalizedError {
    case missingColors(URL)
    case badValue(file: URL, key: String, value: String)
    case noSuchTheme(String)

    public var errorDescription: String? {
        switch self {
        case .missingColors(let u):
            return "\(u.path): no colors.toml, or it defines no background/foreground"
        case .badValue(let f, let k, let v):
            return "\(f.path): \(k) = \"\(v)\" is not a hex colour"
        case .noSuchTheme(let n):
            return "no theme named '\(n)'"
        }
    }
}

public enum Appearance: String, Sendable { case dark, light }

/// One theme: a directory with a colors.toml and, optionally, wallpapers.
public struct Theme: Identifiable, Sendable {
    public var id: String { slug }
    public let slug: String              // the directory name
    public let name: String              // the human-readable name
    public let directory: URL
    public let appearance: Appearance
    public let background, foreground, accent, cursor: Color
    public let selectionBackground, selectionForeground: Color
    public let palette: [Color]          // exactly 16

    /// Omarchy themes come in two schemes: the current one numbers the palette,
    /// the older one names it. Both are accepted; this maps one to the other.
    static let semantic: [String: String] = [
        "color0": "background", "color1": "red", "color2": "green",
        "color3": "yellow", "color4": "blue", "color5": "magenta",
        "color6": "cyan", "color7": "foreground", "color8": "muted",
        "color9": "bright_red", "color10": "bright_green",
        "color11": "bright_yellow", "color12": "bright_blue",
        "color13": "bright_magenta", "color14": "bright_cyan",
        "color15": "bright_foreground",
    ]

    static let colorKeys: Set<String> = {
        var k: Set<String> = ["background", "foreground", "accent", "cursor",
                              "selection", "selection_background", "selection_foreground"]
        for i in 0..<16 { k.insert("color\(i)") }
        for v in semantic.values { k.insert(v) }
        return k
    }()

    public static func load(directory: URL) throws -> Theme {
        let file = directory.appendingPathComponent("colors.toml")
        guard let text = try? String(contentsOf: file, encoding: .utf8) else {
            throw ArthemeError.missingColors(directory)
        }

        var colors: [String: Color] = [:]
        var strings: [String: String] = [:]
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            guard let (key, value) = Self.entry(in: String(line)) else { continue }
            if Self.colorKeys.contains(key) {
                guard let c = Color(value) else {
                    throw ArthemeError.badValue(file: file, key: key, value: value)
                }
                colors[key] = c
            } else {
                strings[key] = Self.sanitised(value)
            }
        }

        guard let bg = colors["background"], let fg = colors["foreground"] else {
            throw ArthemeError.missingColors(directory)
        }

        // Semantic scheme -> numbered palette.
        if colors["color0"] == nil {
            for (num, sem) in Self.semantic {
                if let c = colors[sem] { colors[num] = c }
            }
        }
        let palette = (0..<16).map { colors["color\($0)"] ?? fg }

        let appearance: Appearance = {
            if let m = strings["appearance"] ?? strings["mode"],
               let a = Appearance(rawValue: m) { return a }
            return bg.isDark ? .dark : .light
        }()

        return Theme(
            slug: directory.lastPathComponent,
            name: strings["name"].flatMap { $0.isEmpty ? nil : $0 } ?? directory.lastPathComponent,
            directory: directory,
            appearance: appearance,
            background: bg, foreground: fg,
            accent: colors["accent"] ?? colors["color4"] ?? fg,
            cursor: colors["cursor"] ?? fg,
            selectionBackground: colors["selection_background"] ?? colors["selection"] ?? fg,
            selectionForeground: colors["selection_foreground"] ?? bg,
            palette: palette)
    }

    /// `key = "value"` — the only shape these files actually use.
    static func entry(in line: String) -> (String, String)? {
        guard let eq = line.firstIndex(of: "=") else { return nil }
        let key = line[line.startIndex..<eq].trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty, !key.hasPrefix("#"), !key.hasPrefix("["),
              key.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else { return nil }
        let rest = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
        guard rest.hasPrefix("\""), let close = rest.dropFirst().firstIndex(of: "\"")
        else { return nil }
        return (key, String(rest[rest.index(after: rest.startIndex)..<close]))
    }

    /// Free text still reaches generated files, so strip anything a shell or
    /// AppleScript would read, and keep it short.
    static func sanitised(_ value: String, limit: Int = 64) -> String {
        String(value.filter { ch in
            !ch.isNewline && ch.asciiValue.map { $0 >= 32 } ?? true
                && !"\"\\`$".contains(ch)
        }.prefix(limit))
    }

    // MARK: - Assets

    public var wallpapers: [URL] {
        let dir = directory.appendingPathComponent("backgrounds")
        let images: Set<String> = ["jpg", "jpeg", "png", "heic", "webp"]
        let found = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil)) ?? []
        return found.filter { images.contains($0.pathExtension.lowercased()) }
                    .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// The theme's own cover image, if it has one.
    ///
    /// Omarchy themes publish a preview.png to show themselves off; artheme
    /// ships a 600px jpeg of it so the grid is full the moment the app opens,
    /// without carrying 100 MB of wallpapers. Themes with neither fall back to
    /// a cover drawn from their palette.
    public var preview: URL? {
        for name in ["preview.jpg", "preview.png"] {
            let p = directory.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: p.path) { return p }
        }
        return nil
    }

    /// The picture a card should show: its cover, or its first wallpaper.
    public var cover: URL? { preview ?? wallpapers.first }
}
