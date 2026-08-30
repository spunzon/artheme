import AppKit
import ImageIO

/// Downsampled wallpaper previews.
///
/// Some themes ship 7680×4320 wallpapers; decoding those at full size to draw a
/// 240pt card would cost hundreds of megabytes. ImageIO decodes straight to the
/// size we need, and results are cached per URL and size.
enum Thumbnail {
    private static let cache = NSCache<NSString, NSImage>()

    static func load(_ url: URL, maxPixel: Int = 480) -> NSImage? {
        let key = "\(url.path)@\(maxPixel)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }
        let image = NSImage(cgImage: cg, size: .init(width: cg.width, height: cg.height))
        cache.setObject(image, forKey: key)
        return image
    }
}
