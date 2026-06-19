import Foundation

/// 保存用户排除的内置问题 ID（影响新建项目的问题集）
final class QuestionExclusionStore {
    private let fileURL: URL

    init() {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Aham/KnowledgeBase", isDirectory: true)
        fileURL = dir.appendingPathComponent("question_exclusions.json")
    }

    func load() -> Set<String> {
        guard let data = try? Data(contentsOf: fileURL),
              let ids = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return Set(ids)
    }

    func save(_ ids: Set<String>) throws {
        let dir = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(Array(ids).sorted())
        try data.write(to: fileURL, options: .atomic)
    }
}
