import Foundation

/// The machine an integration writes to.
///
/// Everything that touches the file system goes through here, so tests can
/// point a whole run at a throwaway home directory instead of the real one —
/// and `appliesLive` keeps them from signalling processes or reloading bars
/// that belong to the person running the tests.
public struct Machine: Sendable {
    public let home: URL
    public let appliesLive: Bool

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                appliesLive: Bool = true) {
        self.home = home
        self.appliesLive = appliesLive
    }

    public static let current = Machine()

    /// `~/.config/<path>`
    public func config(_ path: String) -> URL {
        home.appendingPathComponent(".config").appendingPathComponent(path)
    }

    /// `~/Library/<path>`
    public func library(_ path: String) -> URL {
        home.appendingPathComponent("Library").appendingPathComponent(path)
    }
}

/// One application omakase can theme.
///
/// Every integration is optional and self-detecting: whatever is not installed
/// is skipped, so the same build works on any Mac without configuration.
public protocol Integration: Sendable {
    var id: String { get }
    var name: String { get }
    /// Is the application present on this machine?
    var isInstalled: Bool { get }
    /// Has omakase been wired into its configuration?
    func isWired(_ library: Library) -> Bool
    /// Take over the app's colours. Idempotent, keeps a backup.
    func install(_ library: Library) throws
    /// Apply a theme. Returns a note worth showing the user, or nil.
    @discardableResult
    func apply(_ theme: Theme, _ library: Library) throws -> String?
}

public extension Integration {
    func install(_ library: Library) throws {}
    func isWired(_ library: Library) -> Bool { true }
}

// MARK: - Shared helpers

public enum Shell {
    /// Run a command with a deadline. A helper that hangs must never stop a
    /// theme switch: the terminal repaint is what the user is looking at.
    @discardableResult
    public static func run(_ path: String, _ args: [String] = [],
                           timeout: TimeInterval = 8) -> (status: Int32, out: String) {
        guard FileManager.default.isExecutableFile(atPath: path) else { return (127, "") }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do { try p.run() } catch { return (127, "") }

        let deadline = Date().addingTimeInterval(timeout)
        while p.isRunning && Date() < deadline { usleep(20_000) }
        if p.isRunning { p.terminate(); return (124, "") }

        let data = (try? pipe.fileHandleForReading.readToEnd()) ?? Data()
        return (p.terminationStatus, String(data: data ?? Data(), encoding: .utf8) ?? "")
    }

    /// Look for an executable the way a login shell would, plus the usual
    /// Homebrew prefixes: a GUI app inherits none of the user's PATH.
    public static func which(_ name: String) -> String? {
        var dirs = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin",
                    "/opt/homebrew/sbin", "/usr/sbin"]
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            dirs = path.split(separator: ":").map(String.init) + dirs
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        dirs.append(contentsOf: ["\(home)/.local/bin", "\(home)/bin"])
        for d in dirs {
            let p = (d as NSString).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: p) { return p }
        }
        return nil
    }

    /// PIDs of a running process by executable name.
    ///
    /// Deliberately not `pgrep`: on macOS it hides its own ancestors, so a
    /// switch launched from inside a terminal cannot see that terminal and
    /// silently skips the reload — every app changes theme except the one you
    /// are looking at.
    public static func pids(of name: String) -> [Int32] {
        let (_, out) = run("/bin/ps", ["-Ao", "pid=,comm="], timeout: 5)
        return out.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
            guard parts.count == 2, let pid = Int32(parts[0].trimmingCharacters(in: .whitespaces))
            else { return nil }
            let comm = parts[1].trimmingCharacters(in: .whitespaces)
            return (comm as NSString).lastPathComponent == name ? pid : nil
        }
    }

    public static func isRunning(_ name: String) -> Bool { !pids(of: name).isEmpty }

    @discardableResult
    public static func osascript(_ source: String, timeout: TimeInterval = 10) -> Int32 {
        run("/usr/bin/osascript", ["-e", source], timeout: timeout).status
    }

    /// Quote a value for embedding in AppleScript source.
    public static func applescriptString(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}

public enum Files {
    public static var home: URL { FileManager.default.homeDirectoryForCurrentUser }
    public static func config(_ path: String) -> URL {
        home.appendingPathComponent(".config").appendingPathComponent(path)
    }
    public static func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    public static func write(_ text: String, to url: URL, executable: Bool = false) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
        if executable {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }
    }

    public static func read(_ url: URL) -> String? {
        try? String(contentsOf: url, encoding: .utf8)
    }

    /// Keep the version of a file omakase is about to take over.
    ///
    /// The first backup is the pre-omakase original and is never overwritten,
    /// but a later install must not silently discard edits made since then, so
    /// anything different gets its own timestamped copy.
    @discardableResult
    public static func backup(_ url: URL) -> URL? {
        guard exists(url) else { return nil }
        let bak = URL(fileURLWithPath: url.path + ".omakase-bak")
        if !exists(bak) {
            try? FileManager.default.copyItem(at: url, to: bak)
            return bak
        }
        if (try? Data(contentsOf: bak)) == (try? Data(contentsOf: url)) { return bak }
        let stamp = ISO8601DateFormatter.stamp()
        let dated = URL(fileURLWithPath: "\(url.path).omakase-bak.\(stamp)")
        try? FileManager.default.copyItem(at: url, to: dated)
        return dated
    }

    /// Does this config already point at the file omakase generates? Accepts
    /// the path written absolutely, via $HOME or via ~.
    public static func references(_ target: URL, in file: URL) -> Bool {
        guard let body = read(file) else { return false }
        let abs = target.path
        let rel = abs.replacingOccurrences(of: home.path, with: "")
        return body.contains(abs) || body.contains("$HOME" + rel)
            || body.contains("${HOME}" + rel) || body.contains("~" + rel)
    }
}

extension ISO8601DateFormatter {
    static func stamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: Date())
    }
}
