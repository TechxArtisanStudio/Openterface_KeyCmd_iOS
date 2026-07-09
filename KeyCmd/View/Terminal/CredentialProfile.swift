import Foundation

/// Represents a saved SSH credential profile.
/// Mirrors the Android CredentialProfile model.
struct CredentialProfile: Identifiable, Codable, Equatable {
    let id: String
    var name: String
    var host: String
    var port: Int
    var username: String
    /// Password is stored separately in Keychain (not in Codable data).
    var authType: AuthType
    var targetOs: String
    var notes: String
    var tags: [String]
    var isActive: Bool
    var createdAt: TimeInterval
    var updatedAt: TimeInterval

    enum AuthType: String, Codable {
        case password
        case sshKey = "ssh_key"
    }

    init(
        id: String = UUID().uuidString,
        name: String = "",
        host: String = "",
        port: Int = 22,
        username: String = "",
        authType: AuthType = .password,
        targetOs: String = "linux",
        notes: String = "",
        tags: [String] = [],
        isActive: Bool = false
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.username = username
        self.authType = authType
        self.targetOs = targetOs
        self.notes = notes
        self.tags = tags
        self.isActive = isActive
        let now = Date().timeIntervalSince1970
        self.createdAt = now
        self.updatedAt = now
    }

    /// Display label: profile name if present, otherwise "user@host -p port".
    var displayLabel: String {
        if !name.isEmpty { return name }
        return shortDescription
    }

    /// Compact display: "user@host -p port"
    var shortDescription: String {
        "\(username)@\(host) -p \(port)"
    }
}
