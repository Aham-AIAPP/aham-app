import Foundation

/// 从知识库 AI 生成的补充调研问题集
struct KnowledgeQuestionSupplement: Codable {
    var version: Int
    var generatedAt: Date
    var totalQuestions: Int
    var supplements: [String: [QuestionTemplate]]   // deptId → questions
}

/// 持久化存储 AI 生成的补充问题
final class KnowledgeQuestionStore {

    private let fileURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = appSupport.appendingPathComponent("Aham/KnowledgeBase", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("question_supplements.json")
    }

    func load() -> KnowledgeQuestionSupplement? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(KnowledgeQuestionSupplement.self, from: data)
        } catch {
            print("[KnowledgeQuestionStore] decode error: \(error)")
            return nil
        }
    }

    func save(_ supplement: KnowledgeQuestionSupplement) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(supplement)
        try data.write(to: fileURL, options: .atomic)
    }

    func currentVersion() -> Int {
        load()?.version ?? 0
    }

    func questions(for departmentId: String) -> [QuestionTemplate] {
        load()?.supplements[departmentId] ?? []
    }
}
