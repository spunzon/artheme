import Foundation

/// Checks GitHub Releases for a newer build and installs it in place.
///
/// No appcast, no signing key, no framework: the release a person downloads
/// by hand is already ad-hoc signed by `bundle.sh`, so fetching that same
/// zip and swapping it in is enough. A zip pulled by `URLSession` also never
/// gets the `com.apple.quarantine` flag Safari or Chrome would attach, so
/// the replaced app opens without the "unidentified developer" prompt a
/// manual download shows every time.
public struct Updater: Sendable {
    public let repo: String
    public init(repo: String = "spunzon/artheme") { self.repo = repo }

    public struct Release: Sendable {
        public let version: String        // "0.1.1", tag's leading "v" stripped
        public let notes: String
        public let zipURL: URL
    }

    public enum UpdateError: LocalizedError {
        case http(Int), noZipAsset, badPayload, transport(String)
        case insecureURL(String), tooBig(String)
        case appNotBundled, installFailed(String), corruptDownload(String)

        public var errorDescription: String? {
            switch self {
            case .http(let code): return "GitHub returned \(code)"
            case .noZipAsset: return "the latest release has no .zip asset"
            case .badPayload: return "could not read the release info"
            case .transport(let m): return "could not reach GitHub (\(m))"
            case .insecureURL(let u): return "refusing a non-https download URL: \(u)"
            case .tooBig(let m): return "\(m) is larger than expected for a release download"
            case .appNotBundled: return "not running from an installed .app — nothing to replace"
            case .installFailed(let m): return "could not install the update: \(m)"
            case .corruptDownload(let m): return "the downloaded app failed verification: \(m)"
            }
        }
    }

    /// Nothing this project ships is anywhere near this size; a response
    /// claiming to be belongs to something other than a release zip.
    static let maxDownload = 100 * 1024 * 1024

    // MARK: - Checking

    /// `nil` if already on the latest version.
    public func checkForUpdate(current: String) throws -> Release? {
        let release = try latestRelease()
        return Self.isNewer(release.version, than: current) ? release : nil
    }

    func latestRelease() throws -> Release {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("artheme", forHTTPHeaderField: "User-Agent")

        let (data, response) = try send(request)
        guard response.statusCode == 200 else { throw UpdateError.http(response.statusCode) }
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let assets = json["assets"] as? [[String: Any]]
        else { throw UpdateError.badPayload }

        guard let zip = assets.first(where: {
            ($0["name"] as? String)?.hasSuffix(".zip") == true
        }), let urlString = zip["browser_download_url"] as? String, let url = URL(string: urlString)
        else { throw UpdateError.noZipAsset }

        let notes = (json["body"] as? String) ?? ""
        return Release(version: tag.hasPrefix("v") ? String(tag.dropFirst()) : tag,
                       notes: notes, zipURL: url)
    }

    /// Compares dot-separated numeric versions component by component;
    /// `"0.1.10"` is newer than `"0.1.9"`, unlike a plain string compare.
    /// Anything not numeric — a hand-edited build, `"dev"` — is never "newer".
    public static func isNewer(_ remote: String, than local: String) -> Bool {
        func parts(_ s: String) -> [Int]? {
            let p = s.split(separator: ".").map { Int($0) }
            return p.allSatisfy { $0 != nil } && !p.isEmpty ? p.map { $0! } : nil
        }
        guard let r = parts(remote), let l = parts(local) else { return false }
        for i in 0..<max(r.count, l.count) {
            let a = i < r.count ? r[i] : 0, b = i < l.count ? l[i] : 0
            if a != b { return a > b }
        }
        return false
    }

    // MARK: - Installing

    /// Downloads the release zip, extracts it, moves the current app to the
    /// Trash and puts the new one in its place, then relaunches. Returns
    /// only on failure — success ends the process.
    public func install(_ release: Release, relaunch: Bool = true) throws {
        guard let appURL = Bundle.main.bundleURL as URL?,
              appURL.pathExtension == "app" else { throw UpdateError.appNotBundled }

        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("artheme-update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }

        let zip = scratch.appendingPathComponent("update.zip")
        try download(release.zipURL, to: zip)

        let unpacked = scratch.appendingPathComponent("unpacked")
        try FileManager.default.createDirectory(at: unpacked, withIntermediateDirectories: true)
        try run("/usr/bin/ditto", ["-x", "-k", zip.path, unpacked.path])

        guard let newApp = (try? FileManager.default.contentsOfDirectory(
            at: unpacked, includingPropertiesForKeys: nil))?.first(where: { $0.pathExtension == "app" })
        else { throw UpdateError.installFailed("the download did not contain an .app") }

        try verify(newApp)

        // Never sit on the file the running process is executing from.
        let staged = scratch.appendingPathComponent(appURL.lastPathComponent)
        try FileManager.default.moveItem(at: newApp, to: staged)

        var trashed: NSURL?
        do {
            try FileManager.default.trashItem(at: appURL, resultingItemURL: &trashed)
        } catch {
            throw UpdateError.installFailed("could not move the running app aside: \(error.localizedDescription)")
        }
        do {
            try FileManager.default.moveItem(at: staged, to: appURL)
        } catch {
            // Put the original back rather than leaving nothing installed.
            if let trashed = trashed as URL? { try? FileManager.default.moveItem(at: trashed, to: appURL) }
            throw UpdateError.installFailed(error.localizedDescription)
        }

        // Defence in depth: URLSession downloads do not pick up the
        // quarantine flag Safari/Chrome/Mail attach, but strip it explicitly
        // in case a future macOS starts tagging them too.
        _ = try? run("/usr/bin/xattr", ["-cr", appURL.path])

        guard relaunch else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = [appURL.path]
        try? p.run()
        exit(0)
    }

    /// Catches a corrupted or tampered download before it replaces a working
    /// install: the signature must still be intact — ad-hoc or not, that
    /// detects any change to the bundle since `bundle.sh` signed it — and the
    /// bundle identifier must be the app this process actually is, so a zip
    /// that happens to contain some other `.app` can't get installed in its
    /// place.
    private func verify(_ app: URL) throws {
        do {
            try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
        } catch {
            throw UpdateError.corruptDownload("signature check failed — \(error.localizedDescription)")
        }
        guard let plist = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")),
              let downloadedID = plist["CFBundleIdentifier"] as? String
        else { throw UpdateError.corruptDownload("no Info.plist in the downloaded app") }
        let ownID = Bundle.main.bundleIdentifier
        guard ownID == nil || downloadedID == ownID else {
            throw UpdateError.corruptDownload(
                "bundle id \(downloadedID) does not match the running app (\(ownID ?? "?"))")
        }
    }

    // MARK: - Plumbing

    @discardableResult
    private func run(_ path: String, _ args: [String]) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            throw UpdateError.installFailed("\(path) exited \(p.terminationStatus)")
        }
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }

    private func download(_ url: URL, to destination: URL) throws {
        guard url.scheme == "https" else { throw UpdateError.insecureURL(url.absoluteString) }
        let (data, response) = try send(URLRequest(url: url))
        guard response.statusCode == 200 else { throw UpdateError.http(response.statusCode) }
        // Checked after the fact, not via a Content-Length header: a server
        // is free to omit or lie about it, so the actual byte count is the
        // only number worth trusting.
        guard data.count <= Self.maxDownload else {
            throw UpdateError.tooBig("\(url.lastPathComponent) (\(data.count / 1024 / 1024) MB)")
        }
        try data.write(to: destination)
    }

    private func send(_ request: URLRequest) throws -> (Data, HTTPURLResponse) {
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        var result: (Data, HTTPURLResponse)?
        var failure: String?
        let waiter = DispatchSemaphore(value: 0)
        session.dataTask(with: request) { data, response, error in
            if let error { failure = error.localizedDescription }
            else if let http = response as? HTTPURLResponse { result = (data ?? Data(), http) }
            else { failure = "no response" }
            waiter.signal()
        }.resume()
        if waiter.wait(timeout: .now() + 120) == .timedOut { throw UpdateError.transport("timed out") }
        if let result { return result }
        throw UpdateError.transport(failure ?? "unknown")
    }
}
