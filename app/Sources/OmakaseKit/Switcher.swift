import Foundation

/// Applies a theme across every integration present on this machine.
public struct Switcher: Sendable {
    public let library: Library
    public let integrations: [any Integration]

    public init(library: Library = Library(), machine: Machine = .current,
                integrations: [any Integration]? = nil) {
        self.library = library
        self.integrations = integrations ?? Switcher.all(machine: machine)
    }

    /// Ghostty comes first on purpose: it is the surface the user is looking at
    /// and the cheapest to poke, so it must not wait behind the wallpaper or a
    /// helper that might hang.
    public static var all: [any Integration] { all() }

    public static func all(machine: Machine = .current) -> [any Integration] {
        [
            // Terminals first: they are what the user is looking at.
            GhosttyIntegration(machine: machine), KittyIntegration(machine: machine), AlacrittyIntegration(machine: machine),
            WezTermIntegration(machine: machine), ITerm2Integration(machine: machine),
            // Desktop furniture.
            SketchyBarIntegration(machine: machine), BordersIntegration(machine: machine), HerdrIntegration(machine: machine),
            AppearanceIntegration(machine: machine), WallpaperIntegration(machine: machine),
            // Editors and the rest.
            VSCodeIntegration(machine: machine), NeovimIntegration(machine: machine), ZedIntegration(machine: machine),
            BtopIntegration(machine: machine), TmuxIntegration(machine: machine),
        ]
    }

    public var installed: [any Integration] { integrations.filter(\.isInstalled) }

    public func isWired(_ integration: any Integration) -> Bool {
        integration.isWired(library)
    }

    @discardableResult
    public func apply(_ theme: Theme) throws -> [String] {
        try library.ensureDirectories()
        var notes: [String] = []
        for integration in integrations where integration.isInstalled {
            do {
                if let note = try integration.apply(theme, library) { notes.append(note) }
            } catch {
                // One failing integration must never abort the rest.
                notes.append("\(integration.name): \(error.localizedDescription)")
            }
        }
        try library.setCurrent(theme)
        return notes
    }

    public func install() throws {
        try library.ensureDirectories()
        for integration in integrations where integration.isInstalled {
            try? integration.install(library)
        }
    }
}
