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

/// One application artheme can theme.
///
/// Every integration is optional and self-detecting: whatever is not installed
/// is skipped, so the same build works on any Mac without configuration.
public protocol Integration: Sendable {
    var id: String { get }
    var name: String { get }
    /// Is the application present on this machine?
    var isInstalled: Bool { get }
    /// Has artheme been wired into its configuration?
    func isWired(_ library: Library) -> Bool
    /// Take over the app's colours. Idempotent, keeps a backup.
    func install(_ library: Library) throws
    /// Apply a theme.
    @discardableResult
    func apply(_ theme: Theme, _ library: Library) throws -> Outcome
}

public extension Integration {
    func install(_ library: Library) throws {}
    func isWired(_ library: Library) -> Bool { true }
}

/// What an integration has to say when it finishes.
///
/// `note` is shown to the person switching themes and should be rare and
/// actionable; `detail` only reaches generated/last-apply.log. Mixing the two
/// is how "signalled 3 ghostty processes" ended up as a warning on every
/// single switch.
public struct Outcome: Sendable {
    public var note: String?
    public var detail: String?

    public init(note: String? = nil, detail: String? = nil) {
        self.note = note
        self.detail = detail
    }

    public static let done = Outcome()
    public static func note(_ text: String) -> Outcome { Outcome(note: text) }
    public static func detail(_ text: String) -> Outcome { Outcome(detail: text) }
}

// MARK: - Shared helpers

public enum Shell {
    /// Run a command with a deadline, returning its standard output.
    ///
    /// The pipe is drained WHILE the process runs. Reading it only after
    /// waiting for exit deadlocks as soon as the output fills the 64 KB pipe
    /// buffer: the child blocks writing, never exits, the deadline expires and
    /// the caller gets nothing back. `ps -Ao pid=,comm=` on a busy Mac is about
    /// 77 KB — which is exactly how a theme switch ended up finding no
    /// terminal to reload, and changing the wallpaper but nothing else.
    @discardableResult
    public static func run(_ path: String, _ args: [String] = [],
                           timeout: TimeInterval = 8) -> (status: Int32, out: String) {
        guard FileManager.default.isExecutableFile(atPath: path) else { return (127, "") }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        // Never read, so never allowed to fill a buffer of its own.
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return (127, "") }

        let lock = NSLock()
        var output = Data()
        let drained = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            lock.lock(); output = data; lock.unlock()
            drained.signal()
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline { usleep(20_000) }
        if process.isRunning {
            process.terminate()
            _ = drained.wait(timeout: .now() + 1)
            return (124, "")
        }
        _ = drained.wait(timeout: .now() + 2)
        lock.lock(); defer { lock.unlock() }
        return (process.terminationStatus, String(data: output, encoding: .utf8) ?? "")
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

    /// Keep the version of a file artheme is about to take over.
    ///
    /// The first backup is the pre-artheme original and is never overwritten,
    /// but a later install must not silently discard edits made since then, so
    /// anything different gets its own timestamped copy.
    @discardableResult
    public static func backup(_ url: URL) -> URL? {
        guard exists(url) else { return nil }
        let bak = URL(fileURLWithPath: url.path + ".artheme-bak")
        if !exists(bak) {
            try? FileManager.default.copyItem(at: url, to: bak)
            return bak
        }
        if (try? Data(contentsOf: bak)) == (try? Data(contentsOf: url)) { return bak }
        let stamp = ISO8601DateFormatter.stamp()
        let dated = URL(fileURLWithPath: "\(url.path).artheme-bak.\(stamp)")
        try? FileManager.default.copyItem(at: url, to: dated)
        return dated
    }

    /// Does this config already point at the file artheme generates? Accepts
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
