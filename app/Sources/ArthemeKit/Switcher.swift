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
        var log: [String] = []
        for integration in integrations {
            guard integration.isInstalled else {
                log.append("\(integration.id): not installed")
                continue
            }
            let started = Date()
            do {
                let outcome = try integration.apply(theme, library)
                let ms = Int(Date().timeIntervalSince(started) * 1000)
                let said = [outcome.detail, outcome.note].compactMap { $0 }.joined(separator: " · ")
                log.append("\(integration.id): ok \(ms)ms" + (said.isEmpty ? "" : " — \(said)"))
                if let note = outcome.note { notes.append(note) }
            } catch {
                // One failing integration must never abort the rest.
                log.append("\(integration.id): FAILED \(error.localizedDescription)")
                notes.append("\(integration.name): \(error.localizedDescription)")
            }
        }
        try library.setCurrent(theme)
        record(theme, log)
        return notes
    }

    /// A line per switch in generated/last-apply.log: which integrations ran,
    /// how long each took and what it said. Without it a theme that changes the
    /// wallpaper but not the terminal is impossible to tell apart from one that
    /// never reached the terminal at all.
    private func record(_ theme: Theme, _ log: [String]) {
        let stamp = DateFormatter()
        stamp.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let line = "\(stamp.string(from: Date())) \(theme.slug)\n"
            + log.map { "    \($0)" }.joined(separator: "\n") + "\n"
        let file = library.generated.appendingPathComponent("last-apply.log")
        if let handle = try? FileHandle(forWritingTo: file) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? line.write(to: file, atomically: true, encoding: .utf8)
        }
    }

    public func install() throws {
        try library.ensureDirectories()
        for integration in integrations where integration.isInstalled {
            try? integration.install(library)
        }
    }
}
