import Foundation

/// MCP 服务的端口与访问令牌。
///
/// 刻意与 `aham_settings` 分开存放：备份恢复会整体覆盖 `aham_settings`，
/// 若把端口 / 令牌塞在一起，恢复一次旧配置就会让已接入的客户端永久连不上。
@Observable
final class MCPSettings {
    private static let storageKey = "aham_mcp"

    private(set) var port: UInt16
    private(set) var token: String

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let stored = try? JSONDecoder().decode(Stored.self, from: data) {
            port = stored.port
            token = stored.token
        } else {
            port = UInt16.random(in: 49_152...65_000)   // IANA 动态端口段
            token = Self.makeToken()
            save()
        }
    }

    /// 重新生成令牌（端口保持不变，避免已写好的客户端配置全部作废）
    func regenerateToken() {
        token = Self.makeToken()
        save()
    }

    var endpoint: String { "http://127.0.0.1:\(port)" }

    /// 供首页一键复制的接入命令
    func claudeCodeCommand(adapterPath: String) -> String {
        "claude mcp add aham-survey -- node \(adapterPath) --port \(port) --token \(token)"
    }

    func codexConfigSnippet(adapterPath: String) -> String {
        """
        [mcp_servers.aham-survey]
        command = "node"
        args = ["\(adapterPath)", "--port", "\(port)", "--token", "\(token)"]
        """
    }

    // MARK: - Private

    private struct Stored: Codable {
        let port: UInt16
        let token: String
    }

    private func save() {
        if let data = try? JSONEncoder().encode(Stored(port: port, token: token)) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    private static func makeToken() -> String {
        let bytes = (0..<24).map { _ in UInt8.random(in: 0...255) }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}
