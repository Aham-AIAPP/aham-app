import Foundation

struct MCPContract {
    struct Tool: Decodable {
        let name: String
        let description: String
        let summary: String
        let arguments: String
        let isWrite: Bool
    }

    let version: Int
    let tools: [Tool]

    static let current: MCPContract = load()

    private struct FilePayload: Decodable {
        let version: Int
        let tools: [Tool]
    }

    private static func load() -> MCPContract {
        guard let url = Bundle.main.url(forResource: "mcp-contract", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(FilePayload.self, from: data) else {
            return MCPContract(version: 1, tools: [])
        }
        return MCPContract(version: payload.version, tools: payload.tools)
    }
}
