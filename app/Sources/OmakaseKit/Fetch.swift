import Foundation

/// Downloading themes from GitHub.
///
/// Upstream Omarchy moved to omacom/omarchy on the `quattro` branch, and old
/// raw.githubusercontent URLs 404 on binaries even while still serving text, so
/// everything goes through the contents API and the `download_url` it hands
/// back.
public struct Fetcher: Sendable {
    public let library: Library
    public init(library: Library) { self.library = library }

    public static let upstreamRepo = "omacom/omarchy"
    public static let upstreamBranch = "quattro"

    static let maxWallpaper = 12 * 1024 * 1024   // skip the odd 20 MB "test" image
    static let maxDownload = 32 * 1024 * 1024    // nothing a theme ships is bigger

    public struct Result: Sendable {
        public let slug: String
        public let wallpapers: Int
        public let skipped: [String]
    }

    public enum FetchError: LocalizedError {
        case notFound(String), rateLimited, http(Int, String)
        case unsafeName(String), tooBig(String), transport(String)

        public var errorDescription: String? {
            switch self {
            case .notFound(let what): return "\(what) not found on GitHub"
            case .rateLimited:
                return "GitHub rate limit reached (60 requests/hour unauthenticated). "
                     + "Wait, or set GITHUB_TOKEN."
            case .http(let code, let url): return "GitHub returned \(code) for \(url)"
            case .unsafeName(let n): return "refusing unsafe name '\(n)'"
            case .tooBig(let n): return "\(n) is larger than 32 MB"
            case .transport(let m): return "could not reach GitHub (\(m))"
            }
        }
    }

    // MARK: - Public API

    /// `fetch("nord")` takes it from upstream Omarchy;
    /// `fetch("owner/repo")` or `fetch("owner/repo#branch")` from a theme repo.
    @discardableResult
    public func fetch(_ spec: String, as alias: String? = nil,
                      wallpapers wantWallpapers: Bool = true,
                      onImage: ((URL, Int) -> Void)? = nil) throws -> Result {
        let repo: String, ref: String, base: String, derived: String
        if spec.contains("/") {
            let parts = spec.split(separator: "#", maxSplits: 1).map(String.init)
            repo = parts[0]
            ref = parts.count > 1 ? parts[1] : "HEAD"
            base = ""
            derived = (repo.split(separator: "/").last.map(String.init) ?? repo)
                .replacingOccurrences(of: "omarchy-", with: "")
                .replacingOccurrences(of: "-theme", with: "")
        } else {
            repo = Self.upstreamRepo; ref = Self.upstreamBranch
            base = "themes/\(spec)"; derived = spec
        }

        let slug = alias ?? derived
        guard let destination = Paths.safeChild(of: library.themesDirectory, named: slug) else {
            throw FetchError.unsafeName(slug)
        }

        let listing = try contents(repo: repo, path: base, ref: ref)
        guard let colors = listing.first(where: { $0.name == "colors.toml" && $0.type == "file" })
        else { throw FetchError.notFound("colors.toml in \(repo)/\(base)") }

        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try download(colors.downloadURL, to: destination.appendingPathComponent("colors.toml"))
        // Whatever the theme says about its own licence travels with it.
        for extra in ["LICENSE", "LICENSE.md", "README.md"] {
            if let item = listing.first(where: { $0.name == extra && $0.type == "file" }) {
                try? download(item.downloadURL, to: destination.appendingPathComponent(extra))
            }
        }

        var count = 0, skipped: [String] = []
        if wantWallpapers {
            let dirs = Set(listing.filter { $0.type == "dir" }.map(\.name))
            if dirs.contains("backgrounds") {
                let (n, s) = try wallpaperSet(repo: repo, ref: ref,
                                              path: join(base, "backgrounds"),
                                              into: destination.appendingPathComponent("backgrounds"),
                                              onImage: onImage)
                count += n; skipped += s
            }
            // Some themes ship a second set; prefix it so both can coexist.
            if dirs.contains("backgrounds-alt") {
                let (n, s) = try wallpaperSet(repo: repo, ref: ref,
                                              path: join(base, "backgrounds-alt"),
                                              into: destination.appendingPathComponent("backgrounds"),
                                              prefix: "alt-")
                count += n; skipped += s
            }
        }

        // Remember where it came from, so wallpapers can be re-fetched after a
        // clone that carries only the colours.
        let source = ["repo": repo, "ref": ref, "path": base]
        try JSONSerialization.data(withJSONObject: source, options: [.prettyPrinted, .sortedKeys])
            .write(to: destination.appendingPathComponent("source.json"))

        return Result(slug: slug, wallpapers: count, skipped: skipped)
    }

    /// Re-download the wallpapers of a theme that is already installed.
    /// `onImage` fires as each wallpaper lands, so a caller can put the first
    /// one up without waiting for the rest — a theme with nine wallpapers took
    /// 7.6 seconds to finish, and the first one arrives in about one.
    @discardableResult
    public func refetchWallpapers(_ slug: String,
                                  onImage: ((URL, Int) -> Void)? = nil) throws -> Result {
        guard let dir = Paths.safeChild(of: library.themesDirectory, named: slug) else {
            throw FetchError.unsafeName(slug)
        }
        let file = dir.appendingPathComponent("source.json")
        guard let data = try? Data(contentsOf: file),
              let source = (try? JSONSerialization.jsonObject(with: data)) as? [String: String],
              let repo = source["repo"], let ref = source["ref"], let base = source["path"]
        else { throw FetchError.notFound("source.json for '\(slug)'") }

        var count = 0, skipped: [String] = []
        for (path, prefix) in [("backgrounds", ""), ("backgrounds-alt", "alt-")] {
            if let (n, s) = try? wallpaperSet(repo: repo, ref: ref, path: join(base, path),
                                              into: dir.appendingPathComponent("backgrounds"),
                                              prefix: prefix, onImage: onImage) {
                count += n; skipped += s
            }
        }
        return Result(slug: slug, wallpapers: count, skipped: skipped)
    }

    /// The themes upstream Omarchy publishes.
    public func catalogue() throws -> [String] {
        try contents(repo: Self.upstreamRepo, path: "themes", ref: Self.upstreamBranch)
            .filter { $0.type == "dir" }.map(\.name).sorted()
    }

    // MARK: - GitHub

    struct Item { let name: String, type: String, downloadURL: String, size: Int }

    private func join(_ base: String, _ path: String) -> String {
        base.isEmpty ? path : "\(base)/\(path)"
    }

    private func contents(repo: String, path: String, ref: String) throws -> [Item] {
        var components = URLComponents(string: "https://api.github.com/repos/\(repo)/contents/\(path)")
        components?.queryItems = [URLQueryItem(name: "ref", value: ref)]
        guard let url = components?.url else { throw FetchError.notFound(repo) }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("omakase", forHTTPHeaderField: "User-Agent")
        // Optional, and only ever sent to the API host — the redirect handler
        // below strips it if a hop leaves that host.
        if let token = ProcessInfo.processInfo.environment["GITHUB_TOKEN"], !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try send(request)
        switch response.statusCode {
        case 200: break
        case 403, 429: throw FetchError.rateLimited
        case 404: throw FetchError.notFound("\(repo)/\(path) on \(ref)")
        default: throw FetchError.http(response.statusCode, url.absoluteString)
        }
        guard let array = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else {
            throw FetchError.notFound("a directory listing at \(repo)/\(path)")
        }
        return array.compactMap {
            guard let name = $0["name"] as? String, let type = $0["type"] as? String
            else { return nil }
            return Item(name: name, type: type,
                        downloadURL: $0["download_url"] as? String ?? "",
                        size: $0["size"] as? Int ?? 0)
        }
    }

    private func wallpaperSet(repo: String, ref: String, path: String,
                              into directory: URL, prefix: String = "",
                              onImage: ((URL, Int) -> Void)? = nil)
        throws -> (Int, [String]) {
        let images: Set<String> = ["jpg", "jpeg", "png", "heic", "webp"]
        let listing = try contents(repo: repo, path: path, ref: ref)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var count = 0, skipped: [String] = []
        for item in listing where item.type == "file" {
            guard images.contains((item.name as NSString).pathExtension.lowercased()) else { continue }
            guard item.size <= Self.maxWallpaper else {
                skipped.append("\(item.name) (\(item.size / 1024 / 1024) MB)"); continue
            }
            guard let out = Paths.safeChild(of: directory, named: prefix + item.name) else {
                throw FetchError.unsafeName(prefix + item.name)
            }
            if Files.exists(out) { continue }
            try download(item.downloadURL, to: out)
            count += 1
            onImage?(out, count)
        }
        return (count, skipped)
    }

    /// No credentials are attached here, and the response is capped: `size` in a
    /// listing is what the server claims, not what it sends.
    private func download(_ urlString: String, to destination: URL) throws {
        guard let url = URL(string: urlString), url.scheme == "https" else {
            throw FetchError.http(0, urlString)
        }
        var request = URLRequest(url: url)
        request.setValue("omakase", forHTTPHeaderField: "User-Agent")
        let (data, response) = try send(request)
        guard response.statusCode == 200 else {
            throw FetchError.http(response.statusCode, urlString)
        }
        guard data.count <= Self.maxDownload else {
            throw FetchError.tooBig(destination.lastPathComponent)
        }
        try data.write(to: destination)
    }

    /// Synchronous on purpose: this serves a CLI and a background task in the
    /// app, and neither wants an async boundary here.
    private func send(_ request: URLRequest) throws -> (Data, HTTPURLResponse) {
        let session = URLSession(configuration: .ephemeral,
                                 delegate: RedirectGuard(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        var result: Result2 = .none
        let waiter = DispatchSemaphore(value: 0)
        session.dataTask(with: request) { data, response, error in
            if let error { result = .failure(error.localizedDescription) }
            else if let http = response as? HTTPURLResponse { result = .success(data ?? Data(), http) }
            else { result = .failure("no response") }
            waiter.signal()
        }.resume()

        if waiter.wait(timeout: .now() + 120) == .timedOut { throw FetchError.transport("timed out") }
        switch result {
        case .success(let data, let http): return (data, http)
        case .failure(let message): throw FetchError.transport(message)
        case .none: throw FetchError.transport("no response")
        }
    }

    private enum Result2 { case none, success(Data, HTTPURLResponse), failure(String) }
}

/// Drops the Authorization header if a redirect leaves the host it was meant for.
final class RedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        var forwarded = request
        if request.url?.host != task.originalRequest?.url?.host {
            forwarded.setValue(nil, forHTTPHeaderField: "Authorization")
        }
        completionHandler(forwarded)
    }
}
