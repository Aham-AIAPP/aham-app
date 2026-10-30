import CryptoKit
import Foundation
import Security

/// MCP 服务的本机连接设置。
///
/// Token 持久化到 Keychain；供 stdio Adapter 使用的连接描述文件权限固定为 0600。
/// UI 和复制出的命令只包含描述文件路径，不再暴露 Token 或把它放进进程参数。
@Observable
final class MCPSettings {
    private static let storageKey = "aham_mcp"
    private static let keychainService = "com.lichengbao.Aham.mcp"
    private static let keychainAccount = "local-access-token"

    private let isEphemeral = ProcessInfo.processInfo.environment["AHAM_TEST_IN_MEMORY"] == "1"

    private(set) var port: UInt16
    private var token: String
    private(set) var lastPersistenceError: String?
    let connectionConfigURL: URL

    init() {
        // 隔离测试不能读取正式 Keychain、覆写连接文件或占用正式 MCP 端口。
        if isEphemeral {
            port = UInt16.random(in: 49_152...65_000)
            token = Self.makeToken()
            connectionConfigURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("AhamSurveyTests-" + UUID().uuidString, isDirectory: true)
                .appendingPathComponent("mcp-connection.json")
            persistTokenAndDescriptor()
            print("AHAM_TEST_CONFIG_PATH=\(connectionConfigURL.path)")
            return
        }
        let stored = UserDefaults.standard.data(forKey: Self.storageKey)
            .flatMap { try? JSONDecoder().decode(Stored.self, from: $0) }

        port = stored?.port ?? UInt16.random(in: 49_152...65_000)
        connectionConfigURL = Self.defaultConnectionConfigURL()

        let legacyToken = stored?.token
        token = Self.readTokenFromKeychain() ?? legacyToken ?? Self.makeToken()

        persistTokenAndDescriptor()
        savePortOnly()
    }

    var endpoint: String { "http://127.0.0.1:\(port)" }
    var authorizationToken: String { token }
    var connectionConfigPath: String { connectionConfigURL.path }

    var tokenFingerprint: String {
        let digest = SHA256.hash(data: Data(token.utf8))
        return digest.prefix(4).map { String(format: "%02x", $0) }.joined()
    }

    /// 重新生成令牌（端口保持不变，避免 endpoint 跟着变化）。
    func regenerateToken() {
        token = Self.makeToken()
        persistTokenAndDescriptor()
    }

    /// 供首页一键复制的接入命令。敏感信息只存在 0600 连接文件中。
    func claudeCodeCommand(adapterPath: String) -> String {
        "claude mcp add aham-survey -- node \(Self.shellQuote(adapterPath)) --config \(Self.shellQuote(connectionConfigPath))"
    }

    func codexConfigSnippet(adapterPath: String) -> String {
        """
        [mcp_servers.aham-survey]
        command = "node"
        args = ["\(Self.tomlEscape(adapterPath))", "--config", "\(Self.tomlEscape(connectionConfigPath))"]
        """
    }

    // MARK: - Persistence

    private struct Stored: Codable {
        let port: UInt16
        /// 仅用于从旧版本 UserDefaults 迁移，保存新值时始终为 nil。
        let token: String?
    }

    private struct ConnectionDescriptor: Codable {
        let version: Int
        let endpoint: String
        let port: UInt16
        let token: String
    }

    private func savePortOnly() {
        guard !isEphemeral else { return }
        guard let data = try? JSONEncoder().encode(Stored(port: port, token: nil)) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    private func persistTokenAndDescriptor() {
        do {
            if !isEphemeral { try Self.saveTokenToKeychain(token) }
            try writeConnectionDescriptor()
            lastPersistenceError = nil
        } catch {
            lastPersistenceError = error.localizedDescription
        }
    }

    private func writeConnectionDescriptor() throws {
        let directory = connectionConfigURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: NSNumber(value: 0o700)]
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o700)],
            ofItemAtPath: directory.path
        )

        let descriptor = ConnectionDescriptor(
            version: 1,
            endpoint: endpoint,
            port: port,
            token: token
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(descriptor)
        try data.write(to: connectionConfigURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o600)],
            ofItemAtPath: connectionConfigURL.path
        )
    }

    private static func defaultConnectionConfigURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base
            .appendingPathComponent("Aham Survey", isDirectory: true)
            .appendingPathComponent("mcp-connection.json", isDirectory: false)
    }

    // MARK: - Keychain

    private static func readTokenFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    private static func saveTokenToKeychain(_ token: String) throws {
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        let data = Data(token.utf8)
        let updateStatus = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw KeychainError(status: updateStatus)
        }

        var insert = baseQuery
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(insert as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw KeychainError(status: addStatus) }
    }

    private struct KeychainError: LocalizedError {
        let status: OSStatus
        var errorDescription: String? {
            SecCopyErrorMessageString(status, nil) as String? ?? "Keychain 错误 \(status)"
        }
    }

    // MARK: - Formatting

    private static func makeToken() -> String {
        let bytes = (0..<32).map { _ in UInt8.random(in: 0...255) }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func tomlEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
