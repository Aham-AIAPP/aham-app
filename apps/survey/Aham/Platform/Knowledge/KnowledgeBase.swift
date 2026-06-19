import Foundation
import CryptoKit

/// 知识库模型 — 平台级，存储行业知识供 AI 调用
/// 增量更新：已有知识保留，新知识补充，冲突知识由 AI 判断更新

// MARK: - 知识条目

/// 单条知识
struct KnowledgeEntry: Codable, Identifiable, Hashable {
    let id: String                 // UUID
    var category: KnowledgeCategory
    var content: String            // 知识内容
    var source: String             // 来源文件/描述
    var confidence: Double         // 0~1 置信度
    var tags: [String]             // 关联标签（部门、主题等）
    var createdAt: Date
    var updatedAt: Date
}

/// 知识类别
enum KnowledgeCategory: String, Codable, CaseIterable {
    case industryTerm = "industry_term"         // 行业术语
    case bestPractice = "best_practice"         // 最佳实践
    case painPoint = "pain_point"               // 常见痛点
    case solution = "solution"                  // 解决方案
    case crossDeptRelation = "cross_dept"       // 跨部门关联
    case standard = "standard"                  // 体系标准
    case metric = "metric"                      // 关键指标
    case other = "other"

    var label: String {
        switch self {
        case .industryTerm: "行业术语"
        case .bestPractice: "最佳实践"
        case .painPoint: "常见痛点"
        case .solution: "解决方案"
        case .crossDeptRelation: "跨部门关联"
        case .standard: "体系标准"
        case .metric: "关键指标"
        case .other: "其他"
        }
    }

    var icon: String {
        switch self {
        case .industryTerm: "textbook.closed"
        case .bestPractice: "star"
        case .painPoint: "exclamationmark.triangle"
        case .solution: "lightbulb"
        case .crossDeptRelation: "arrow.triangle.branch"
        case .standard: "checkmark.seal"
        case .metric: "chart.bar"
        case .other: "doc.text"
        }
    }
}

// MARK: - 已处理文件记录

struct ProcessedFile: Codable, Identifiable, Hashable {
    let id: String            // 文件 SHA256 hash
    let fileName: String
    let fileSize: Int
    let processedAt: Date
    let entriesExtracted: Int // 提取了多少条知识
}

// MARK: - 知识库清单

struct KnowledgeManifest: Codable {
    var version: Int              // 版本号，每次训练 +1
    var lastTrainedAt: Date?      // 最后训练时间
    var totalEntries: Int         // 总知识条目数
    var processedFiles: [ProcessedFile]  // 已处理的文件列表
}

// MARK: - 知识库存储

/// 知识库持久化管理
final class KnowledgeStore {
    private let baseDir: URL

    init() {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            baseDir = FileManager.default.temporaryDirectory.appendingPathComponent("Aham/KnowledgeBase", isDirectory: true)
            try? FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
            return
        }
        baseDir = appSupport.appendingPathComponent("Aham/KnowledgeBase", isDirectory: true)
        try? FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
    }

    private var manifestURL: URL { baseDir.appendingPathComponent("manifest.json") }
    private var knowledgeURL: URL { baseDir.appendingPathComponent("knowledge.json") }

    // MARK: - 读取

    func loadManifest() -> KnowledgeManifest {
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder.withDateDecoding().decode(KnowledgeManifest.self, from: data)
        else {
            return KnowledgeManifest(version: 0, lastTrainedAt: nil, totalEntries: 0, processedFiles: [])
        }
        return manifest
    }

    func loadEntries() -> [KnowledgeEntry] {
        guard let data = try? Data(contentsOf: knowledgeURL),
              let entries = try? JSONDecoder.withDateDecoding().decode([KnowledgeEntry].self, from: data)
        else {
            return []
        }
        return entries
    }

    // MARK: - 保存

    func save(manifest: KnowledgeManifest, entries: [KnowledgeEntry]) throws {
        let encoder = JSONEncoder.withDateEncoding()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let manifestData = try encoder.encode(manifest)
        try manifestData.write(to: manifestURL, options: .atomic)

        let entriesData = try encoder.encode(entries)
        try entriesData.write(to: knowledgeURL, options: .atomic)
    }

    // MARK: - 文件 Hash

    static func fileHash(_ url: URL) -> String? {
        // 跳过超过 100MB 的文件
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = attrs?[.size] as? Int ?? 0
        guard size < 100_000_000 else { return nil }

        guard let data = try? Data(contentsOf: url) else { return nil }
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// 检查文件是否已经被训练过
    func isFileProcessed(_ hash: String, manifest: KnowledgeManifest) -> Bool {
        manifest.processedFiles.contains { $0.id == hash }
    }

    // MARK: - 知识库摘要（注入 Prompt 用）

    func knowledgeSummary(maxLength: Int = 3000) -> String {
        let entries = loadEntries()
        guard !entries.isEmpty else { return "" }

        var parts: [String] = []
        for category in KnowledgeCategory.allCases {
            let catEntries = entries.filter { $0.category == category }
            if catEntries.isEmpty { continue }
            let items = catEntries.prefix(10).map { "- \($0.content)" }.joined(separator: "\n")
            parts.append("【\(category.label)】\n\(items)")
        }

        let full = parts.joined(separator: "\n\n")
        if full.count > maxLength {
            return String(full.prefix(maxLength)) + "\n...(已截断)"
        }
        return full
    }
}

// MARK: - JSON Coding Helpers

private extension JSONDecoder {
    static func withDateDecoding() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private extension JSONEncoder {
    static func withDateEncoding() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
