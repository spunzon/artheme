import Foundation

// MARK: - Visual Studio Code

/// A local theme extension, regenerated on every switch.
///
/// Omarchy's vscode.json only names a marketplace extension to install; this
/// derives the theme from the palette instead, so it works for every theme and
/// never installs anything behind the user's back.
public struct VSCodeIntegration: Integration {
    public let id = "vscode", name = "Visual Studio Code"
    public init() {}

    var extensionDir: URL {
        Files.home.appendingPathComponent(".vscode/extensions/omakase-theme")
    }
    var themeFile: URL { extensionDir.appendingPathComponent("themes/omakase-color-theme.json") }

    public var isInstalled: Bool {
        Files.exists(URL(fileURLWithPath: "/Applications/Visual Studio Code.app"))
            || Shell.which("code") != nil
    }
    public var isWired: Bool { Files.exists(themeFile) }

    public func apply(_ theme: Theme, _ l: Library) throws -> String? {
        let bg = theme.background, fg = theme.foreground, accent = theme.accent
        let dim = bg.mixed(with: fg, 0.55)
        let panel = bg.mixed(with: fg, 0.06)
        let border = bg.mixed(with: fg, 0.14)
        let names = ["Black", "Red", "Green", "Yellow", "Blue", "Magenta", "Cyan", "White"]

        var colors: [String: String] = [
            "editor.background": bg.hex, "editor.foreground": fg.hex,
            "editorLineNumber.foreground": dim.hex,
            "editorLineNumber.activeForeground": accent.hex,
            "editorCursor.foreground": theme.cursor.hex,
            "editor.selectionBackground": theme.selectionBackground.hex,
            "editor.lineHighlightBackground": panel.hex,
            "sideBar.background": panel.hex, "sideBar.foreground": fg.hex,
            "sideBar.border": border.hex,
            "activityBar.background": panel.hex, "activityBar.foreground": fg.hex,
            "activityBar.activeBorder": accent.hex,
            "statusBar.background": accent.hex,
            "statusBar.foreground": (accent.luma > 0.55 ? "#111111" : "#ffffff"),
            "titleBar.activeBackground": panel.hex, "titleBar.activeForeground": fg.hex,
            "tab.activeBackground": bg.hex, "tab.inactiveBackground": panel.hex,
            "tab.activeBorderTop": accent.hex,
            "panel.background": bg.hex, "panel.border": border.hex,
            "terminal.background": bg.hex, "terminal.foreground": fg.hex,
            "focusBorder": accent.hex,
        ]
        for (i, label) in names.enumerated() {
            colors["terminal.ansi\(label)"] = theme.palette[i].hex
            colors["terminal.ansiBright\(label)"] = theme.palette[i + 8].hex
        }

        let themeJSON: [String: Any] = [
            "name": "Omakase",
            "type": theme.appearance == .dark ? "dark" : "light",
            "colors": colors,
            "tokenColors": [
                ["scope": ["comment"], "settings": ["foreground": dim.hex]],
                ["scope": ["string"], "settings": ["foreground": theme.palette[2].hex]],
                ["scope": ["keyword", "storage"], "settings": ["foreground": theme.palette[5].hex]],
                ["scope": ["constant", "number"], "settings": ["foreground": theme.palette[3].hex]],
                ["scope": ["entity.name.function"], "settings": ["foreground": theme.palette[4].hex]],
                ["scope": ["variable"], "settings": ["foreground": fg.hex]],
                ["scope": ["entity.name.type", "support.type"],
                 "settings": ["foreground": theme.palette[6].hex]],
            ],
        ]
        let manifest: [String: Any] = [
            "name": "omakase-theme", "displayName": "Omakase",
            "description": "The active omakase theme.",
            "publisher": "omakase", "version": "0.0.1",
            "engines": ["vscode": "^1.60.0"], "categories": ["Themes"],
            "contributes": ["themes": [[
                "label": "Omakase",
                "uiTheme": theme.appearance == .dark ? "vs-dark" : "vs",
                "path": "./themes/omakase-color-theme.json",
            ]]],
        ]

        try FileManager.default.createDirectory(
            at: themeFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: manifest,
                                   options: [.prettyPrinted, .sortedKeys])
            .write(to: extensionDir.appendingPathComponent("package.json"))
        try JSONSerialization.data(withJSONObject: themeJSON,
                                   options: [.prettyPrinted, .sortedKeys])
            .write(to: themeFile)

        // VS Code loads a colour theme once per window.
        return "VS Code: pick “Omakase” once (⇧⌘P → Color Theme); reload the window to see later switches"
    }
}

// MARK: - Neovim

/// A colorscheme in ~/.config/nvim/colors, which Neovim finds on its own.
/// Nothing in the user's init is touched: they run `:colorscheme omakase`.
public struct NeovimIntegration: Integration {
    public let id = "neovim", name = "Neovim"
    public init() {}

    var colorscheme: URL { Files.config("nvim/colors/omakase.lua") }

    public var isInstalled: Bool {
        Shell.which("nvim") != nil || Files.exists(Files.config("nvim"))
    }
    public var isWired: Bool { Files.exists(colorscheme) }

    public func apply(_ theme: Theme, _ l: Library) throws -> String? {
        let bg = theme.background, fg = theme.foreground
        let dim = bg.mixed(with: fg, 0.55)
        let panel = bg.mixed(with: fg, 0.08)
        let p = theme.palette
        let terminals = (0..<16)
            .map { "vim.g.terminal_color_\($0) = \"\(p[$0].hex)\"" }
            .joined(separator: "\n")

        try Files.write("""
        -- Generated by omakase — do not edit by hand.
        -- Theme: \(theme.name)
        -- Use it with:  :colorscheme omakase

        vim.cmd("highlight clear")
        if vim.fn.exists("syntax_on") == 1 then vim.cmd("syntax reset") end
        vim.o.background = "\(theme.appearance.rawValue)"
        vim.g.colors_name = "omakase"

        \(terminals)

        local hl = vim.api.nvim_set_hl
        hl(0, "Normal",       { fg = "\(fg.hex)", bg = "\(bg.hex)" })
        hl(0, "NormalFloat",  { fg = "\(fg.hex)", bg = "\(panel.hex)" })
        hl(0, "Comment",      { fg = "\(dim.hex)", italic = true })
        hl(0, "Constant",     { fg = "\(p[3].hex)" })
        hl(0, "String",       { fg = "\(p[2].hex)" })
        hl(0, "Identifier",   { fg = "\(p[4].hex)" })
        hl(0, "Function",     { fg = "\(p[12].hex)" })
        hl(0, "Statement",    { fg = "\(p[5].hex)" })
        hl(0, "Keyword",      { fg = "\(p[5].hex)" })
        hl(0, "Type",         { fg = "\(p[6].hex)" })
        hl(0, "Special",      { fg = "\(p[13].hex)" })
        hl(0, "Error",        { fg = "\(p[1].hex)" })
        hl(0, "CursorLine",   { bg = "\(panel.hex)" })
        hl(0, "LineNr",       { fg = "\(dim.hex)" })
        hl(0, "CursorLineNr", { fg = "\(theme.accent.hex)", bold = true })
        hl(0, "Visual",       { bg = "\(theme.selectionBackground.hex)",
                                fg = "\(theme.selectionForeground.hex)" })
        hl(0, "StatusLine",   { fg = "\(fg.hex)", bg = "\(panel.hex)" })
        hl(0, "VertSplit",    { fg = "\(bg.mixed(with: fg, 0.14).hex)" })
        hl(0, "Pmenu",        { fg = "\(fg.hex)", bg = "\(panel.hex)" })
        hl(0, "PmenuSel",     { fg = "\(bg.hex)", bg = "\(theme.accent.hex)" })
        hl(0, "Search",       { fg = "\(bg.hex)", bg = "\(theme.accent.hex)" })
        hl(0, "Title",        { fg = "\(theme.accent.hex)", bold = true })
        hl(0, "Directory",    { fg = "\(p[4].hex)" })

        """, to: colorscheme)
        return nil
    }
}

// MARK: - Zed

public struct ZedIntegration: Integration {
    public let id = "zed", name = "Zed"
    public init() {}

    var themeFile: URL { Files.config("zed/themes/omakase.json") }

    public var isInstalled: Bool {
        Files.exists(URL(fileURLWithPath: "/Applications/Zed.app"))
            || Shell.which("zed") != nil || Files.exists(Files.config("zed"))
    }
    public var isWired: Bool { Files.exists(themeFile) }

    public func apply(_ theme: Theme, _ l: Library) throws -> String? {
        let bg = theme.background, fg = theme.foreground, p = theme.palette
        let panel = bg.mixed(with: fg, 0.06)
        let border = bg.mixed(with: fg, 0.16)
        let dim = bg.mixed(with: fg, 0.55)
        let ansi = ["black", "red", "green", "yellow", "blue", "magenta", "cyan", "white"]

        var style: [String: Any] = [
            "background": bg.hex, "text": fg.hex, "text.muted": dim.hex,
            "border": border.hex, "border.variant": border.hex,
            "elevated_surface.background": panel.hex,
            "surface.background": panel.hex,
            "element.background": panel.hex,
            "element.selected": theme.selectionBackground.hex,
            "editor.background": bg.hex, "editor.foreground": fg.hex,
            "editor.gutter.background": bg.hex,
            "editor.line_number": dim.hex,
            "editor.active_line_number": theme.accent.hex,
            "editor.active_line.background": panel.hex,
            "terminal.background": bg.hex, "terminal.foreground": fg.hex,
            "status_bar.background": panel.hex,
            "title_bar.background": panel.hex,
            "tab_bar.background": panel.hex,
            "tab.active_background": bg.hex, "tab.inactive_background": panel.hex,
            "panel.background": panel.hex,
            "scrollbar.thumb.background": border.hex,
        ]
        for (i, label) in ansi.enumerated() {
            style["terminal.ansi.\(label)"] = p[i].hex
            style["terminal.ansi.bright_\(label)"] = p[i + 8].hex
        }

        let family: [String: Any] = [
            "$schema": "https://zed.dev/schema/themes/v0.2.0.json",
            "name": "Omakase",
            "author": "omakase",
            "themes": [[
                "name": "Omakase",
                "appearance": theme.appearance.rawValue,
                "style": style,
            ]],
        ]
        try FileManager.default.createDirectory(
            at: themeFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: family,
                                   options: [.prettyPrinted, .sortedKeys]).write(to: themeFile)
        return nil
    }
}
