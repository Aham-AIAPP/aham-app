import Foundation
import Network
import SwiftData

/// 绑定 127.0.0.1 的极简 HTTP 服务，供 stdio 适配器转发 MCP 调用。
///
/// 只实现一条路由：`POST /rpc`，body `{"tool":"...","args":{...}}`。
/// MCP 协议本身由外部的 `aham-survey-mcp` 适配器承担 —— Claude Code 与 Codex
/// 都以 stdio 接入，App 这边不必啃 Streamable HTTP + SSE 的完整规范。
///
/// 沙盒：`ENABLE_INCOMING_NETWORK_CONNECTIONS` 已在工程配置中开启，无需额外授权。
@Observable
@MainActor
final class MCPServer {

    enum State: Equatable {
        case stopped
        case running(port: UInt16)
        case failed(String)
    }

    private(set) var state: State = .stopped
    private(set) var lastCallSummary: String?
    private(set) var callCount: Int = 0

    private var listener: NWListener?
    private let settings: MCPSettings
    private let container: ModelContainer
    private let pluginLoader: PluginLoader

    init(settings: MCPSettings, container: ModelContainer, pluginLoader: PluginLoader) {
        self.settings = settings
        self.container = container
        self.pluginLoader = pluginLoader
    }

    var isRunning: Bool {
        if case .running = state { return true }
        return false
    }

    // MARK: - 生命周期

    func start() {
        guard listener == nil else { return }
        do {
            let params = NWParameters.tcp
            params.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback),
                                                     port: NWEndpoint.Port(rawValue: settings.port)!)
            params.allowLocalEndpointReuse = true

            let listener = try NWListener(using: params)
            listener.newConnectionHandler = { [weak self] connection in
                connection.start(queue: .main)
                Task { @MainActor in self?.receive(on: connection) }
            }
            listener.stateUpdateHandler = { [weak self] newState in
                Task { @MainActor in
                    switch newState {
                    case .ready:            self?.state = .running(port: self?.settings.port ?? 0)
                    case .failed(let err):  self?.state = .failed(err.localizedDescription)
                    case .cancelled:        self?.state = .stopped
                    default:                break
                    }
                }
            }
            listener.start(queue: .main)
            self.listener = listener
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        state = .stopped
    }

    func restart() {
        stop()
        start()
    }

    // MARK: - 收发

    private func receive(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            guard let data, error == nil else {
                connection.cancel()
                return
            }
            Task { @MainActor in
                let response = self.handle(rawRequest: data)
                connection.send(content: response, completion: .contentProcessed { _ in
                    connection.cancel()
                })
            }
            _ = isComplete
        }
    }

    /// 解析一个极简 HTTP 请求并返回完整响应字节
    private func handle(rawRequest: Data) -> Data {
        guard let text = String(data: rawRequest, encoding: .utf8),
              let headerEnd = text.range(of: "\r\n\r\n") else {
            return httpResponse(status: "400 Bad Request", json: ["error": "malformed request"])
        }

        let head = String(text[text.startIndex..<headerEnd.lowerBound])
        let body = String(text[headerEnd.upperBound...])
        let lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.first ?? ""

        guard requestLine.hasPrefix("POST /rpc") else {
            return httpResponse(status: "404 Not Found", json: ["error": "only POST /rpc is supported"])
        }

        // 令牌校验：本机自用，仅防止其他进程误撞
        let authorized = lines.contains {
            $0.lowercased().hasPrefix("authorization:") &&
            $0.contains(settings.token)
        }
        guard authorized else {
            return httpResponse(status: "401 Unauthorized", json: ["error": "invalid token"])
        }

        guard let bodyData = body.data(using: .utf8),
              let payload = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
              let tool = payload["tool"] as? String else {
            return httpResponse(status: "400 Bad Request", json: ["error": "expected {\"tool\":...,\"args\":{...}}"])
        }
        let args = payload["args"] as? [String: Any] ?? [:]

        // 必须用 mainContext：视图的 @Query 观察的就是它。
        // 另开 ModelContext 会让 Claude 建的项目不出现在侧栏，直到重启 App。
        let tools = MCPTools(
            context: container.mainContext,
            pluginLoader: pluginLoader
        )
        callCount += 1
        do {
            let result = try tools.call(tool, args: args)
            lastCallSummary = "\(tool) ✓"
            return httpResponse(status: "200 OK", json: ["ok": true, "data": result])
        } catch {
            lastCallSummary = "\(tool) ✗ \(error.localizedDescription)"
            return httpResponse(status: "200 OK",
                                json: ["ok": false, "error": error.localizedDescription])
        }
    }

    private func httpResponse(status: String, json: [String: Any]) -> Data {
        let body = (try? JSONSerialization.data(withJSONObject: json, options: [.withoutEscapingSlashes]))
            ?? Data("{\"ok\":false}".utf8)
        var head = "HTTP/1.1 \(status)\r\n"
        head += "Content-Type: application/json; charset=utf-8\r\n"
        head += "Content-Length: \(body.count)\r\n"
        head += "Connection: close\r\n\r\n"
        return Data(head.utf8) + body
    }
}
