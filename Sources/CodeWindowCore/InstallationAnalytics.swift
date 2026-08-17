import Foundation

public enum InstallationAnalyticsCaptureResult: Equatable, Sendable {
    case sent
    case alreadySent
    case failed
}

/// Records one anonymous event per installed CodeWindow lifetime. Uninstalling
/// removes the receipt and identifier with the rest of the app-owned support
/// directory, so a later clean reinstall counts as a new installation.
public enum InstallationAnalytics {
    public static let eventName = "installation_completed"

    private static let identifierFileName = ".installation-id"
    private static let receiptFileName = ".installation-analytics-sent"

    public static func captureIfNeeded(
        supportDirectory: URL,
        apiKey: String,
        apiHost: URL,
        releaseVersion: String,
        architecture: String,
        send: (_ endpoint: URL, _ body: Data) -> Bool
    ) throws -> InstallationAnalyticsCaptureResult {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty,
              key != "phc_your_project_token",
              apiHost.scheme?.lowercased() == "https",
              apiHost.host != nil
        else { return .failed }

        let receipt = supportDirectory.appendingPathComponent(receiptFileName)
        if FileManager.default.fileExists(atPath: receipt.path) {
            return .alreadySent
        }

        try FileManager.default.createDirectory(
            at: supportDirectory,
            withIntermediateDirectories: true
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: supportDirectory.path
        )

        let identifier = try installationIdentifier(in: supportDirectory)
        let endpoint = apiHost
            .appendingPathComponent("i", isDirectory: true)
            .appendingPathComponent("v0", isDirectory: true)
            .appendingPathComponent("e", isDirectory: true)
        let payload: [String: Any] = [
            "api_key": key,
            "distinct_id": identifier,
            "event": eventName,
            "properties": [
                "$lib": "codewindow-macos",
                "$process_person_profile": false,
                "architecture": architecture,
                "platform": "macOS",
                "release_version": releaseVersion,
            ],
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)
        guard send(endpoint, body) else { return .failed }

        try Data("sent\n".utf8).write(to: receipt, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: receipt.path)
        return .sent
    }

    private static func installationIdentifier(in supportDirectory: URL) throws -> String {
        let url = supportDirectory.appendingPathComponent(identifierFileName)
        if let stored = try? String(contentsOf: url, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
           UUID(uuidString: stored) != nil
        {
            return stored.lowercased()
        }

        let identifier = UUID().uuidString.lowercased()
        try Data("\(identifier)\n".utf8).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return identifier
    }
}
