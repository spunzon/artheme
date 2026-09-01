import AppKit
import ArthemeKit
import SwiftUI
import UniformTypeIdentifiers

/// The "+" sheet: bring in a theme from a repo, or build one by hand.
struct AddThemeView: View {
    @EnvironmentObject private var store: ThemeStore
    @Environment(\.dismiss) private var dismiss
    @State private var mode: Mode = .repo

    enum Mode: String, CaseIterable, Identifiable {
        case repo = "Desde un repositorio"
        case manual = "A mano"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Picker("", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(14)

            switch mode {
            case .repo: RepoAddView()
            case .manual: ManualAddView()
            }
        }
        .frame(width: 560)
        .frame(minHeight: 260)
    }

    private var header: some View {
        HStack {
            Text("Añadir tema").font(.headline)
            Spacer()
            Button("Cerrar") { dismiss() }.buttonStyle(.borderless)
        }
        .padding(14)
    }
}

// MARK: - From a repo

private struct RepoAddView: View {
    @EnvironmentObject private var store: ThemeStore
    @Environment(\.dismiss) private var dismiss
    @State private var spec = ""
    @State private var alias = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Nombre del tema de Omarchy, o `usuario/repo` para un repositorio "
                 + "suelto (añade `#rama` si hace falta).")
                .font(.callout).foregroundStyle(.secondary)

            TextField("osaka-jade, o mattbbia/pissarro", text: $spec)
                .textFieldStyle(.roundedBorder)
                .onSubmit(submit)

            HStack {
                Text("Guardar como").foregroundStyle(.secondary)
                TextField("opcional, por defecto el nombre del repo", text: $alias)
                    .textFieldStyle(.roundedBorder)
            }

            if let error = store.addError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.red)
            }

            Spacer()

            HStack {
                Spacer()
                if store.addBusy {
                    ProgressView().controlSize(.small)
                    Text("descargando…").font(.callout).foregroundStyle(.secondary)
                }
                Button("Añadir") { submit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(spec.trimmingCharacters(in: .whitespaces).isEmpty || store.addBusy)
            }
        }
        .padding(14)
    }

    private func submit() {
        let trimmedSpec = spec.trimmingCharacters(in: .whitespaces)
        guard !trimmedSpec.isEmpty else { return }
        let trimmedAlias = alias.trimmingCharacters(in: .whitespaces)
        Task {
            await store.addFromRepo(trimmedSpec, as: trimmedAlias.isEmpty ? nil : trimmedAlias)
            if store.addError == nil { dismiss() }
        }
    }
}

// MARK: - By hand

private struct ManualAddView: View {
    @EnvironmentObject private var store: ThemeStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var baseSlug: String?
    @State private var background = SwiftUI.Color.black
    @State private var foreground = SwiftUI.Color.white
    @State private var accent = SwiftUI.Color.blue
    @State private var cursor = SwiftUI.Color.white
    @State private var selectionBackground = SwiftUI.Color.gray
    @State private var selectionForeground = SwiftUI.Color.white
    @State private var palette: [SwiftUI.Color] = Array(repeating: .gray, count: 16)
    @State private var wallpapers: [URL] = []

    private var base: Theme? { store.themes.first { $0.slug == baseSlug } }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }
    private var slug: String { Self.slugify(trimmedName) }
    private var collision: Bool { !slug.isEmpty && store.isSlugTaken(slug) }
    private var canSubmit: Bool { !trimmedName.isEmpty && !collision }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("Nombre del tema", text: $name)
                            .textFieldStyle(.roundedBorder)
                        if collision {
                            Label("ya existe un tema llamado “\(slug)”",
                                  systemImage: "exclamationmark.triangle")
                                .font(.caption).foregroundStyle(.red)
                        } else if !trimmedName.isEmpty {
                            Text("se guardará como “\(slug)”")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        basePicker
                    }
                    ManualThemePreview(name: trimmedName.isEmpty ? "Vista previa" : trimmedName,
                                       background: background, foreground: foreground,
                                       accent: accent, palette: palette)
                        .frame(width: 170, height: 130)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Colores base").font(.subheadline).foregroundStyle(.secondary)
                    swatchGrid([
                        ("Fondo", $background), ("Texto", $foreground),
                        ("Acento", $accent), ("Cursor", $cursor),
                        ("Selección — fondo", $selectionBackground),
                        ("Selección — texto", $selectionForeground),
                    ])
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Paleta").font(.subheadline).foregroundStyle(.secondary)
                    Text("16 colores, como los que usa una terminal — los ocho "
                         + "primeros son los primarios, los ocho siguientes sus variantes.")
                        .font(.caption).foregroundStyle(.secondary)
                    paletteGrid
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Imágenes de fondo").font(.subheadline).foregroundStyle(.secondary)
                    Text("Opcional — se muestran en el selector de fondo de escritorio una vez aplicado el tema.")
                        .font(.caption).foregroundStyle(.secondary)
                    wallpaperPicker
                }

                if let error = store.addError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.callout).foregroundStyle(.red)
                }
            }
            .padding(14)
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Spacer()
                Button("Añadir") { submit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSubmit)
            }
            .padding(14)
            .background(.bar)
        }
        .task { applyBase(store.themes.first { $0.slug == "osaka-jade" } ?? store.themes.first) }
    }

    private var basePicker: some View {
        HStack {
            Text("Partir de").foregroundStyle(.secondary)
            Picker("", selection: $baseSlug) {
                Text("En blanco").tag(String?.none)
                ForEach(store.themes) { theme in
                    Text(theme.displayName).tag(String?.some(theme.slug))
                }
            }
            .labelsHidden()
            .onChange(of: baseSlug) { _ in applyBase(base) }
        }
    }

    private func swatchGrid(_ items: [(String, Binding<SwiftUI.Color>)]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 10)], spacing: 10) {
            ForEach(items, id: \.0) { label, binding in
                ColorPicker(label, selection: binding, supportsOpacity: false)
                    .font(.callout)
            }
        }
    }

    private var paletteGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], spacing: 8) {
            ForEach(0..<16, id: \.self) { i in
                ColorPicker(paletteLabel(i), selection: $palette[i], supportsOpacity: false)
                    .font(.caption)
            }
        }
    }

    private func paletteLabel(_ i: Int) -> String {
        i < 8 ? "Primario \(i + 1)" : "Secundario \(i - 7)"
    }

    private var wallpaperPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !wallpapers.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(wallpapers, id: \.self) { url in
                            wallpaperThumbnail(url)
                        }
                    }
                }
            }
            Button { pickWallpapers() } label: {
                Label("Añadir imágenes…", systemImage: "photo.badge.plus")
            }
        }
    }

    private func wallpaperThumbnail(_ url: URL) -> some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let image = Thumbnail.load(url, maxPixel: 160) {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Rectangle().fill(.quaternary)
                }
            }
            .frame(width: 80, height: 54)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            Button {
                wallpapers.removeAll { $0 == url }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.white, .black.opacity(0.6))
            }
            .buttonStyle(.plain)
            .padding(2)
        }
        .help(url.lastPathComponent)
    }

    /// Opens a standard file panel filtered to the image types the library
    /// already knows how to show, same list `Theme.wallpapers` accepts.
    private func pickWallpapers() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = ThemeStore.importableImages
            .compactMap { UTType(filenameExtension: $0) }
        guard panel.runModal() == .OK else { return }
        for url in panel.urls where !wallpapers.contains(url) {
            wallpapers.append(url)
        }
    }

    /// Fills every field from an existing theme, so starting from one is a
    /// single click rather than sixteen colour pickers from scratch.
    private func applyBase(_ theme: Theme?) {
        baseSlug = theme?.slug
        guard let theme else { return }
        background = theme.background.swiftUI
        foreground = theme.foreground.swiftUI
        accent = theme.accent.swiftUI
        cursor = theme.cursor.swiftUI
        selectionBackground = theme.selectionBackground.swiftUI
        selectionForeground = theme.selectionForeground.swiftUI
        palette = theme.palette.map(\.swiftUI)
    }

    private func submit() {
        guard canSubmit else { return }
        var entries: [(String, String)] = [
            ("appearance", background.artheme.isDark ? "dark" : "light"),
            ("background", background.artheme.hex),
            ("foreground", foreground.artheme.hex),
            ("accent", accent.artheme.hex),
            ("cursor", cursor.artheme.hex),
            ("selection_background", selectionBackground.artheme.hex),
            ("selection_foreground", selectionForeground.artheme.hex),
        ]
        entries += palette.enumerated().map { ("color\($0.offset)", $0.element.artheme.hex) }

        if store.addManualTheme(name: trimmedName, slug: slug, entries: entries, wallpapers: wallpapers) {
            dismiss()
        }
    }

    /// `my Theme!` -> `my-theme`, matching the directory names every other
    /// theme already uses.
    static func slugify(_ text: String) -> String {
        var out = ""
        var lastWasDash = false
        for scalar in text.lowercased().unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                out.unicodeScalars.append(scalar)
                lastWasDash = false
            } else if !lastWasDash {
                out.append("-")
                lastWasDash = true
            }
        }
        return out.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}

/// A miniature of the theme being built, in the same style as the grid's own
/// cards — the only way to tell whether an accent actually reads against a
/// background before committing to sixteen colour pickers.
private struct ManualThemePreview: View {
    let name: String
    let background, foreground, accent: SwiftUI.Color
    let palette: [SwiftUI.Color]

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                background
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 3) {
                        ForEach(0..<3) { i in
                            Circle().fill(palette[i + 1]).frame(width: 5, height: 5)
                        }
                        Spacer()
                    }
                    RoundedRectangle(cornerRadius: 1.5).fill(accent).frame(width: 30, height: 4)
                    RoundedRectangle(cornerRadius: 1.5).fill(foreground).opacity(0.75)
                        .frame(width: 70, height: 4)
                    RoundedRectangle(cornerRadius: 1.5).fill(foreground).opacity(0.5)
                        .frame(width: 50, height: 4)
                }
                .padding(10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(height: 84)
            HStack(spacing: 6) {
                Text(name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(foreground)
                    .lineLimit(1)
                Spacer(minLength: 4)
                HStack(spacing: 2) {
                    ForEach(1..<6) { i in
                        Circle().fill(palette[i]).frame(width: 5, height: 5)
                    }
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(background)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(.black.opacity(0.15), lineWidth: 1))
    }
}
