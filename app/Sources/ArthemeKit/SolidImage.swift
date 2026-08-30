import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A flat PNG in a single colour, cached per colour.
///
/// It exists so the desktop can answer immediately. Applying a theme whose
/// wallpapers have not been downloaded yet used to leave the old picture up for
/// seconds while everything else had already changed, which reads as broken
/// rather than as loading. Now the background becomes the theme's own colour at
/// once and the photograph replaces it when it lands.
public enum SolidImage {
    public static func url(for color: Color, in library: Library) -> URL? {
        let file = library.generated.appendingPathComponent("solid-\(color.bare).png")
        if FileManager.default.fileExists(atPath: file.path) { return file }
        try? FileManager.default.createDirectory(at: library.generated,
                                                 withIntermediateDirectories: true)
        guard write(color, to: file) else { return nil }
        return file
    }

    /// 1920×1080 rather than a single pixel: macOS scales wallpapers, and a
    /// 1×1 source can end up blurred or letterboxed depending on the fill mode.
    /// A flat PNG of this size is a few kilobytes.
    private static func write(_ color: Color, to file: URL) -> Bool {
        let width = 1920, height = 1080
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
        context.setFillColor(red: CGFloat(color.r) / 255, green: CGFloat(color.g) / 255,
                             blue: CGFloat(color.b) / 255, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(
                file as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { return false }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination)
    }
}
