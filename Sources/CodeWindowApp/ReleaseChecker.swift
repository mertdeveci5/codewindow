import CodeWindowCore
import Foundation

enum ReleaseCheckResult: Sendable {
    case current
    case available(version: String, pageURL: URL)
    case failed
}

enum ReleaseChecker {
    private static let repositoryPath = "/mertdeveci5/codewindow/releases/"

    static func check(currentVersion: String) async -> ReleaseCheckResult {
        guard let current = AppVersion(currentVersion),
              let endpoint = URL(string: "https://api.github.com/repos/mertdeveci5/codewindow/releases/latest")
        else { return .failed }

        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 10
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2026-03-10", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("CodeWindow/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse, response.statusCode == 200,
                  let release = try? JSONDecoder().decode(GitHubRelease.self, from: data),
                  let candidate = AppVersion(release.tagName),
                  let pageURL = URL(string: release.htmlURL),
                  pageURL.scheme == "https",
                  pageURL.host == "github.com",
                  pageURL.path.hasPrefix(repositoryPath)
            else { return .failed }

            let displayVersion = release.tagName.first?.lowercased() == "v"
                ? String(release.tagName.dropFirst())
                : release.tagName
            return candidate > current
                ? .available(version: displayVersion, pageURL: pageURL)
                : .current
        } catch {
            return .failed
        }
    }
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: String

    private enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
    }
}
