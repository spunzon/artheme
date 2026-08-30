import Foundation

/// An RGB colour parsed from a theme file.
///
/// Values arrive from other people's repositories and end up inside files that
/// get executed — a window manager runs `bordersrc`, a shell sources the
/// SketchyBar palette — so nothing becomes a `Color` until it has been proven
/// to be hex digits and nothing else.
public struct Color: Equatable, Hashable, Sendable {
    public let r: Int, g: Int, b: Int

    public init(r: Int, g: Int, b: Int) {
        self.r = min(max(r, 0), 255)
        self.g = min(max(g, 0), 255)
        self.b = min(max(b, 0), 255)
    }

    /// Parses `#rgb`, `#rrggbb` or `#rrggbbaa` (alpha is dropped). Returns nil
    /// for anything else — including anything a shell would find interesting.
    public init?(_ text: String) {
        var s = text.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.allSatisfy(\.isHexDigit) else { return nil }
        switch s.count {
        case 3: s = s.map { "\($0)\($0)" }.joined()
        case 6, 8: s = String(s.prefix(6))
        default: return nil
        }
        let n = Int(s, radix: 16)!
        self.init(r: n >> 16 & 0xff, g: n >> 8 & 0xff, b: n & 0xff)
    }

    public var hex: String { String(format: "#%02x%02x%02x", r, g, b) }
    public var bare: String { String(format: "%02x%02x%02x", r, g, b) }

    /// `0xAARRGGBB` — SketchyBar's format, alpha first.
    public func sketchybar(alpha: Int = 0xff) -> String {
        String(format: "0x%02x%02x%02x%02x", alpha, r, g, b)
    }

    /// Blend towards another colour. `t == 0` is self, `t == 1` is `other`.
    public func mixed(with other: Color, _ t: Double) -> Color {
        func f(_ a: Int, _ b: Int) -> Int { Int((Double(a) + (Double(b) - Double(a)) * t).rounded()) }
        return Color(r: f(r, other.r), g: f(g, other.g), b: f(b, other.b))
    }

    /// Relative luminance, for deciding what reads on top of this colour.
    public var luma: Double {
        0.2126 * Double(r) / 255 + 0.7152 * Double(g) / 255 + 0.0722 * Double(b) / 255
    }

    public var isDark: Bool { luma < 0.5 }
}
