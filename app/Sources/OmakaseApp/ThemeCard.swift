import OmakaseKit
import SwiftUI

extension OmakaseKit.Color {
    var swiftUI: SwiftUI.Color {
        SwiftUI.Color(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
    }
}

/// One theme in the grid: its own wallpaper as the picture, its palette as the
/// caption. Both are what the theme will actually look like, not a swatch of
/// something approximate.
struct ThemeCard: View {
    let theme: Theme
    let isCurrent: Bool
    let isBusy: Bool
    @State private var hovering = false

    private var wallpaper: URL? { theme.wallpapers.first }

    var body: some View {
        VStack(spacing: 0) {
            preview
            caption
        }
        .background(theme.background.swiftUI)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isCurrent ? theme.accent.swiftUI : .black.opacity(0.15),
                              lineWidth: isCurrent ? 3 : 1)
        )
        .shadow(color: .black.opacity(hovering ? 0.25 : 0.10),
                radius: hovering ? 10 : 4, y: hovering ? 4 : 2)
        .scaleEffect(hovering && !isBusy ? 1.02 : 1)
        .animation(.easeOut(duration: 0.15), value: hovering)
        .onHover { hovering = $0 }
        .accessibilityLabel("\(theme.name), \(theme.appearance.rawValue)"
                            + (isCurrent ? ", active" : ""))
    }

    private var preview: some View {
        ZStack {
            if let wallpaper, let image = Thumbnail.load(wallpaper) {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                // No wallpaper: show the palette itself rather than an empty box.
                theme.background.swiftUI
                VStack(spacing: 4) {
                    ForEach(0..<2) { row in
                        HStack(spacing: 4) {
                            ForEach(0..<8) { i in
                                theme.palette[row * 8 + i].swiftUI
                                    .frame(width: 14, height: 14).cornerRadius(3)
                            }
                        }
                    }
                }
            }
            if isBusy {
                Rectangle().fill(.black.opacity(0.35))
                ProgressView().controlSize(.small).tint(.white)
            }
        }
        .frame(height: 118)
        .frame(maxWidth: .infinity)
        .clipped()
    }

    private var caption: some View {
        HStack(spacing: 8) {
            if isCurrent {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(theme.accent.swiftUI)
            }
            Text(theme.name)
                .font(.system(size: 12, weight: isCurrent ? .semibold : .regular))
                .foregroundStyle(theme.foreground.swiftUI)
                .lineLimit(1)
            Spacer(minLength: 4)
            HStack(spacing: 3) {
                ForEach([1, 2, 3, 4, 5], id: \.self) { i in
                    Circle().fill(theme.palette[i].swiftUI).frame(width: 7, height: 7)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
}
