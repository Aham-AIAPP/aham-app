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
                MainActor.assumeIsolated {
                    connection.start(queue: .main)
                    self?.receive(on: connection)
                }
            }
            listener.stateUpdateHandler = { [weak self] newState in
                MainActor.assumeIsolated {
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

    private func receive(on connection: NWConnection, buffer: Data = Data()) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            var nextBuffer = buffer
            if let data { nextBuffer.append(data) }

            MainActor.assumeIsolated {
                guard let self else { return }
                if error != nil {
                    connection.cancel()
                    return
                }

                switch HTTPRequestParser.parse(nextBuffer) {
                case .incomplete:
                    if isComplete {
                        self.send(
                            self.httpResponse(
                                status: "400 Bad Request",
                                json: self.errorJSON(code: "HTTP_REQUEST_INCOMPLETE", message: "HTTP 请求未完整接收")
                            ),
                            on: connection
                        )
                    } else {
                        self.receive(on: connection, buffer: nextBuffer)
                    }

                case .failure(let failure):
                    self.send(
                        self.httpResponse(
                            status: failure.status,
                            json: self.errorJSON(code: failure.code, message: failure.message)
                        ),
                        on: connection
                    )

                case .complete(let request):
                    self.send(self.handle(request: request), on: connection)
                }
            }
        }
    }

    private func send(_ response: Data, on connection: NWConnection) {
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    /// 处理一条已经完整解析的本机 HTTP 请求。
    private func handle(request: HTTPRPCRequest) -> Data {
        guard request.method == "POST", request.path == "/rpc" else {
            return httpResponse(
                status: "404 Not Found",
                json: errorJSON(code: "HTTP_ROUTE_NOT_FOUND", message: "仅支持 POST /rpc")
            )
        }
        guard request.version == "HTTP/1.1" || request.version == "HTTP/1.0" else {
            return httpResponse(
                status: "505 HTTP Version Not Supported",
                json: errorJSON(code: "HTTP_VERSION_UNSUPPORTED", message: "不支持该 HTTP 版本")
            )
        }
        guard let host = request.headers["host"], isLoopbackAuthority(host) else {
            return httpResponse(
                status: "403 Forbidden",
                json: errorJSON(code: "HTTP_HOST_FORBIDDEN", message: "只允许 localhost 请求")
            )
        }
        if let origin = request.headers["origin"], !isAllowedOrigin(origin) {
            return httpResponse(
                status: "403 Forbidden",
                json: errorJSON(code: "HTTP_ORIGIN_FORBIDDEN", message: "Origin 不被允许")
            )
        }
        guard request.headers["content-type"]?.lowercased().contains("application/json") == true else {
            return httpResponse(
                status: "415 Unsupported Media Type",
                json: errorJSON(code: "HTTP_CONTENT_TYPE_INVALID", message: "Content-Type 必须为 application/json")
            )
        }

        let expectedAuthorization = "Bearer \(settings.authorizationToken)"
        guard let authorization = request.headers["authorization"],
              secureEquals(authorization, expectedAuthorization) else {
            return httpResponse(
                status: "401 Unauthorized",
                json: errorJSON(code: "AUTH_TOKEN_INVALID", message: "MCP Token 无效")
            )
        }

        guard let payload = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any],
              let tool = payload["tool"] as? String else {
            return httpResponse(
                status: "400 Bad Request",
                json: errorJSON(code: "RPC_PAYLOAD_INVALID", message: "需要 {\"tool\":...,\"args\":{...}}")
            )
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
            return httpResponse(
                status: "200 OK",
                json: errorJSON(for: error)
            )
        }
    }

    private func isLoopbackAuthority(_ authority: String) -> Bool {
        let host = authority.split(separator: ":", maxSplits: 1).first.map(String.init)?.lowercased()
        return host == "127.0.0.1" || host == "localhost"
    }

    private func isAllowedOrigin(_ origin: String) -> Bool {
        guard let components = URLComponents(string: origin),
              let host = components.host?.lowercased() else { return false }
        return host == "127.0.0.1" || host == "localhost"
    }

    private func secureEquals(_ lhs: String, _ rhs: String) -> Bool {
        let left = Array(lhs.utf8)
        let right = Array(rhs.utf8)
        guard left.count == right.count else { return false }
        var difference: UInt8 = 0
        for index in left.indices { difference |= left[index] ^ right[index] }
        return difference == 0
    }

    private func errorJSON(code: String, message: String) -> [String: Any] {
        [
            "ok": false,
            "error": [
                "code": code,
                "message": message,
                "retryable": false
            ]
        ]
    }

    private func errorJSON(for error: Error) -> [String: Any] {
        if let structured = error as? MCPStructuredError {
            return ["ok": false, "error": structured.payload]
        }
        return errorJSON(code: "TOOL_CALL_FAILED", message: error.localizedDescription)
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
