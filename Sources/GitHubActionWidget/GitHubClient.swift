import Foundation

/// GitHub REST 클라이언트. 토큰은 이 맥의 `gh` 로그인(`gh auth token`)을 그대로 쓴다.
/// 응답마다 ETag 를 기억했다가 If-None-Match 로 다시 물어본다 — 304 응답은 rate limit 을 소모하지 않는다.
actor GitHubClient {
    enum ClientError: LocalizedError {
        case noToken(String)
        case http(Int, String)

        var errorDescription: String? {
            switch self {
            case .noToken(let why):
                return L.t("GitHub 토큰 없음 — 터미널에서 `gh auth login` 필요 (\(why))",
                           "No GitHub token — run `gh auth login` in Terminal (\(why))")
            case .http(let code, let msg): return "GitHub API \(code): \(msg)"
            }
        }
    }

    private struct CacheEntry { let etag: String; let data: Data }

    private var cache: [URL: CacheEntry] = [:]
    private var token: String?
    private(set) var rateRemaining: Int?
    private let session: URLSession
    private let decoder: JSONDecoder

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 20
        session = URLSession(configuration: config)
        decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
    }

    func get<T: Decodable>(_ path: String, as type: T.Type) async throws -> T {
        let data = try await getData(path, retryAuth: true)
        return try decoder.decode(T.self, from: data)
    }

    private func getData(_ path: String, retryAuth: Bool) async throws -> Data {
        guard let url = URL(string: "https://api.github.com" + path) else {
            throw ClientError.http(0, "invalid path \(path)")
        }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(try currentToken())", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        req.setValue("GitHubActionWidget", forHTTPHeaderField: "User-Agent")
        if let cached = cache[url] { req.setValue(cached.etag, forHTTPHeaderField: "If-None-Match") }

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw ClientError.http(0, "no response") }
        if let r = http.value(forHTTPHeaderField: "X-RateLimit-Remaining").flatMap(Int.init) {
            rateRemaining = r
        }

        switch http.statusCode {
        case 304:
            if let cached = cache[url] { return cached.data }
            throw ClientError.http(304, "not cached")
        case 200..<300:
            if let etag = http.value(forHTTPHeaderField: "ETag") {
                cache[url] = CacheEntry(etag: etag, data: data)
            }
            return data
        case 401 where retryAuth:
            token = nil  // gh 가 토큰을 갱신했을 수 있으니 다시 읽는다
            return try await getData(path, retryAuth: false)
        default:
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["message"] as? String
            throw ClientError.http(http.statusCode, msg ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode))
        }
    }

    private func currentToken() throws -> String {
        if let token { return token }
        let candidates = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh"]
        guard let gh = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw ClientError.noToken(L.t("gh CLI 를 찾지 못함", "gh CLI not found"))
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: gh)
        p.arguments = ["auth", "token", "--hostname", "github.com"]
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        do { try p.run() } catch { throw ClientError.noToken(error.localizedDescription) }
        p.waitUntilExit()
        let value = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard p.terminationStatus == 0, !value.isEmpty else {
            let why = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw ClientError.noToken(why.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        token = value
        return value
    }
}
