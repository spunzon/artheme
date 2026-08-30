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

    private var cover: URL? { theme.cover }

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
            if let cover, let image = Thumbnail.load(cover) {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                GeneratedCover(theme: theme)
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


/// A cover drawn from the theme itself, for themes that ship no picture.
///
/// A miniature of the desktop the theme produces — bar, window, prompt, accent
/// — which says more about what you are about to apply than a photograph does,
/// and costs nothing to ship.
struct GeneratedCover: View {
    let theme: Theme

    private var panel: OmakaseKit.Color { theme.background.mixed(with: theme.foreground, 0.08) }
    private var dim: OmakaseKit.Color { theme.background.mixed(with: theme.foreground, 0.45) }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                theme.background.swiftUI
                VStack(spacing: 0) {
                    bar
                    Spacer(minLength: 0)
                    window(width: geo.size.width)
                }
            }
        }
    }

    private var bar: some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(theme.accent.swiftUI)
                .frame(width: 14, height: 7)
            ForEach(1..<4) { i in
                RoundedRectangle(cornerRadius: 2).fill(dim.swiftUI)
                    .frame(width: 9, height: 7).opacity(Double(4 - i) / 4 + 0.3)
            }
            Spacer()
            ForEach([theme.palette[2], theme.palette[3], theme.palette[4]], id: \.hex) { c in
                Circle().fill(c.swiftUI).frame(width: 5, height: 5)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(panel.swiftUI)
    }

    private func window(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Circle().fill(theme.palette[1].swiftUI).frame(width: 5, height: 5)
                Circle().fill(theme.palette[3].swiftUI).frame(width: 5, height: 5)
                Circle().fill(theme.palette[2].swiftUI).frame(width: 5, height: 5)
            }
            ForEach([0.55, 0.8, 0.35], id: \.self) { factor in
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 1.5).fill(theme.accent.swiftUI)
                        .frame(width: 8, height: 4)
                    RoundedRectangle(cornerRadius: 1.5).fill(theme.foreground.swiftUI)
                        .frame(width: (width - 60) * factor, height: 4).opacity(0.75)
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(panel.swiftUI)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .padding(.horizontal, 10).padding(.bottom, 10)
    }
}
