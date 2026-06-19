import Foundation

/// 知识库训练服务 — 增量提取、合并、去重 + 问题重构
@Observable
@MainActor
final class KnowledgeTrainer {
    let store = KnowledgeStore()
    let questionStore = KnowledgeQuestionStore()

    private(set) var isTraining = false
    private(set) var isRebuilding = false
    private(set) var progress: TrainingProgress?
    private(set) var rebuildProgress: RebuildProgress?
    private(set) var rebuildStatus: String?   // nil=空闲, text=重构结果提示
    private(set) var lastError: String?

    struct RebuildProgress {
        var totalDepts: Int
        var processedDepts: Int
        var currentDeptName: String
        var collectedQuestions: Int
    }

    struct TrainingProgress {
        var totalFiles: Int
        var processedFiles: Int
        var skippedFiles: Int
        var newEntries: Int
        var updatedEntries: Int
        var currentFile: String
    }

    // MARK: - 训练文档

    /// 扫描文件列表，增量提取知识
    /// - Parameter forceRetrain: 忽略 hash 缓存，强制重新处理所有文件
    func train(fileURLs: [URL], settings: SettingsManager, forceRetrain: Bool = false) async {
        guard let provider = settings.llmProvider else {
            lastError = "请先在设置中配置 AI 服务"
            return
        }

        isTraining = true
        lastError = nil
        var manifest = store.loadManifest()
        var entries = forceRetrain ? [] : store.loadEntries()

        if forceRetrain {
            manifest = KnowledgeManifest(version: manifest.version, lastTrainedAt: nil, totalEntries: 0, processedFiles: [])
        }

        var prog = TrainingProgress(
            totalFiles: fileURLs.count,
            processedFiles: 0,
            skippedFiles: 0,
            newEntries: 0,
            updatedEntries: 0,
            currentFile: ""
        )
        progress = prog

        for url in fileURLs {
            guard !Task.isCancelled else {
                isTraining = false
                return
            }
            prog.currentFile = url.lastPathComponent
            progress = prog

            // 计算文件 hash
            guard let hash = KnowledgeStore.fileHash(url) else {
                prog.skippedFiles += 1
                prog.processedFiles += 1
                progress = prog
                continue
            }

            // 跳过已训练文件
            if !forceRetrain && store.isFileProcessed(hash, manifest: manifest) {
                prog.skippedFiles += 1
                prog.processedFiles += 1
                progress = prog
                continue
            }

            // 读取文件内容
            guard let content = readFileContent(url) else {
                prog.skippedFiles += 1
                prog.processedFiles += 1
                progress = prog
                continue
            }

            // AI 提取知识：nil = AI 失败（不记录到 manifest），[] = 成功但无内容
            guard let extracted = await extractKnowledge(from: content, fileName: url.lastPathComponent, provider: provider) else {
                // AI 调用失败，不标记为已处理，下次可以重试
                prog.skippedFiles += 1
                prog.processedFiles += 1
                progress = prog
                continue
            }

            // 增量合并
            let (newCount, updateCount) = mergeEntries(extracted: extracted, into: &entries)
            prog.newEntries += newCount
            prog.updatedEntries += updateCount

            // AI 成功（哪怕 0 条）才记录为已处理
            let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
            let processed = ProcessedFile(
                id: hash,
                fileName: url.lastPathComponent,
                fileSize: fileSize,
                processedAt: .now,
                entriesExtracted: extracted.count
            )
            manifest.processedFiles.append(processed)

            prog.processedFiles += 1
            progress = prog
        }

        // 保存
        manifest.version += 1
        manifest.lastTrainedAt = .now
        manifest.totalEntries = entries.count

        do {
            try store.save(manifest: manifest, entries: entries)
        } catch {
            lastError = "保存知识库失败: \(error.localizedDescription)"
        }

        isTraining = false
    }

    // MARK: - 重构问题库

    /// 基于知识库为各部门生成 AI 补充问题，分批调用以避免超出 token 限制
    /// 返回待确认的结果（不自动保存），调用方展示确认界面后调用 confirmRebuild(_:) 写入
    func rebuildQuestions(departments: [DepartmentTemplate], settings: SettingsManager) async -> KnowledgeQuestionSupplement? {
        guard let provider = settings.llmProvider else {
            lastError = "请先在设置中配置 AI 服务"
            return nil
        }

        let entries = store.loadEntries()
        guard !entries.isEmpty else {
            lastError = "知识库为空，请先训练文档"
            return nil
        }

        isRebuilding = true
        rebuildStatus = nil
        lastError = nil

        let knowledgeSummary = buildKnowledgeSummaryForPrompt(entries: entries)

        // 每批最多 3 个部门，避免单次响应超出 token 限制
        let batchSize = 3
        let batches = stride(from: 0, to: departments.count, by: batchSize).map {
            Array(departments[$0..<min($0 + batchSize, departments.count)])
        }

        var rebuildProg = RebuildProgress(
            totalDepts: departments.count,
            processedDepts: 0,
            currentDeptName: "",
            collectedQuestions: 0
        )
        rebuildProgress = rebuildProg

        var supplements: [String: [QuestionTemplate]] = [:]
        var failedBatches = 0

        for batch in batches {
            guard !Task.isCancelled else { break }

            rebuildProg.currentDeptName = batch.map(\.name).joined(separator: "、")
            rebuildProgress = rebuildProg

            let deptList = batch.map { "- \($0.id): \($0.name)" }.joined(separator: "\n")
            let messages = questionRebuildPrompt(knowledgeSummary: knowledgeSummary, deptList: deptList)

            do {
                let response = try await provider.chat(messages: messages, options: .knowledge)
                if let json = LLMJSONParser.parse(response) as? [String: Any],
                   let supplementsRaw = json["supplements"] as? [String: [[String: Any]]] {
                    for (deptId, qList) in supplementsRaw {
                        let questions = qList.compactMap { parseQuestion($0) }
                        if !questions.isEmpty {
                            supplements[deptId] = questions
                            rebuildProg.collectedQuestions += questions.count
                        }
                    }
                }
                // 即使某批解析为空，也记为已处理（AI 判断该批无相关知识）
            } catch {
                failedBatches += 1
                // 单批失败不中断，继续处理其余批次
            }

            rebuildProg.processedDepts += batch.count
            rebuildProgress = rebuildProg
        }

        isRebuilding = false
        rebuildProgress = nil

        // 全部批次失败才视为整体失败
        if failedBatches == batches.count && batches.count > 0 {
            lastError = "问题重构失败，请检查 AI 服务配置后重试"
            return nil
        }

        guard !supplements.isEmpty else {
            lastError = "AI 未能为任何部门生成补充问题，知识库内容可能与问题模板相关性不足"
            return nil
        }

        let totalCount = supplements.values.reduce(0) { $0 + $1.count }
        return KnowledgeQuestionSupplement(
            version: questionStore.currentVersion() + 1,
            generatedAt: .now,
            totalQuestions: totalCount,
            supplements: supplements
        )
    }

    /// 确认并保存重构结果
    func confirmRebuild(_ supplement: KnowledgeQuestionSupplement) {
        do {
            try questionStore.save(supplement)
            rebuildStatus = "已应用 \(supplement.totalQuestions) 条补充问题（V\(supplement.version)），新建项目将自动加载"
        } catch {
            lastError = "保存失败: \(error.localizedDescription)"
        }
    }

    // MARK: - AI 知识提取

    /// 返回 nil 表示 AI 调用失败（文件不应标记为已处理）
    /// 返回 [] 表示 AI 成功但文档无可提取知识（文件应标记为已处理）
    private func extractKnowledge(from content: String, fileName: String, provider: any LLMProvider) async -> [KnowledgeEntry]? {
        let messages = knowledgeExtractionPrompt(content: String(content.prefix(6000)))

        do {
            let response = try await provider.chat(messages: messages, options: .knowledge)
            guard let json = LLMJSONParser.parse(response) as? [String: Any],
                  let items = json["entries"] as? [[String: Any]] else {
                return []   // 有效响应但无条目
            }

            return items.compactMap { item -> KnowledgeEntry? in
                guard let cat = item["category"] as? String,
                      let content = item["content"] as? String,
                      !content.isEmpty else { return nil }

                return KnowledgeEntry(
                    id: UUID().uuidString,
                    category: KnowledgeCategory(rawValue: cat) ?? .other,
                    content: content,
                    source: fileName,
                    confidence: item["confidence"] as? Double ?? 0.7,
                    tags: item["tags"] as? [String] ?? [],
                    createdAt: .now,
                    updatedAt: .now
                )
            }
        } catch {
            let isTimeout = error.localizedDescription.contains("timed out") ||
                            (error as NSError).code == NSURLErrorTimedOut
            lastError = isTimeout
                ? "AI 提取超时（文件较大，已自动截断至6000字，请重试）"
                : "AI 提取失败: \(error.localizedDescription)"
            return nil   // AI 调用失败
        }
    }

    // MARK: - Prompts

    private func knowledgeExtractionPrompt(content: String) -> [LLMMessage] {
        let system = """
        你是行业知识提取专家。从文档中提取结构化的行业知识条目。

        知识类别：
        - industry_term: 行业术语和定义
        - best_practice: 最佳实践和经验
        - pain_point: 常见痛点和挑战
        - solution: 解决方案和建议
        - cross_dept: 跨部门协作关联
        - standard: 体系标准和合规要求
        - metric: 关键指标和KPI
        - other: 其他有价值的知识

        提取规则：
        - 每条知识应独立、完整、有价值
        - content 要简洁精炼（50-200字）
        - confidence: 0.9(明确陈述) / 0.7(可推断) / 0.5(模糊)
        - tags 标注关联的部门或主题

        输出 JSON：
        {
          "entries": [
            {"category": "类别", "content": "知识内容", "confidence": 0.9, "tags": ["标签"]}
          ]
        }
        """

        let user = "请从以下文档中提取行业知识：\n\n\(content)"

        return [
            LLMMessage(role: .system, content: system),
            LLMMessage(role: .user, content: user)
        ]
    }

    private func questionRebuildPrompt(knowledgeSummary: String, deptList: String) -> [LLMMessage] {
        let system = """
        你是企业调研问题设计专家。根据行业知识库，为各业务部门生成补充调研问题。

        规则：
        - 仅为知识库有明确相关内容的部门生成问题
        - 每个部门最多 3-4 道补充问题
        - 问题应直接揭露知识库中提到的痛点、衡量关键指标或验证最佳实践
        - 问题 id 格式：kb_{dept_id}_{3位序号}（如 kb_production_001）
        - section 必须是：opening / process / painpoint / expectation / compliance 之一
        - type 必须是：text / single_choice / multi_choice / number / boolean 之一
        - 选择题需提供 options 数组；开放题 options 为 null

        输出 JSON：
        {
          "supplements": {
            "dept_id": [
              {
                "id": "kb_dept_001",
                "section": "painpoint",
                "topic": "主题",
                "question": "问题内容",
                "type": "text",
                "options": null,
                "hints": ["调查提示"],
                "order": 100
              }
            ]
          }
        }
        """

        let user = "知识库内容：\n\(knowledgeSummary)\n\n部门列表：\n\(deptList)"

        return [
            LLMMessage(role: .system, content: system),
            LLMMessage(role: .user, content: user)
        ]
    }

    // MARK: - 辅助

    private func buildKnowledgeSummaryForPrompt(entries: [KnowledgeEntry]) -> String {
        var parts: [String] = []
        for category in KnowledgeCategory.allCases {
            let catEntries = entries.filter { $0.category == category }.prefix(8)
            if catEntries.isEmpty { continue }
            let items = catEntries.map { "- \($0.content)" }.joined(separator: "\n")
            parts.append("【\(category.label)】\n\(items)")
        }
        let full = parts.joined(separator: "\n\n")
        return full.count > 4000 ? String(full.prefix(4000)) + "\n...(已截断)" : full
    }

    private func parseQuestion(_ dict: [String: Any]) -> QuestionTemplate? {
        guard let id = dict["id"] as? String,
              let sectionStr = dict["section"] as? String,
              let section = QuestionSection(rawValue: sectionStr),
              let topic = dict["topic"] as? String,
              let question = dict["question"] as? String else { return nil }

        let typeStr = dict["type"] as? String ?? "text"
        let type_ = QuestionType(rawValue: typeStr) ?? .text
        let options = (dict["options"] as? [String])?.isEmpty == false ? dict["options"] as? [String] : nil
        let hints = dict["hints"] as? [String]
        let order = dict["order"] as? Int ?? 100

        return QuestionTemplate(
            id: id,
            section: section,
            topic: topic,
            question: question,
            type: type_,
            options: options,
            required: false,
            hints: hints,
            triggers: nil,
            meceGroup: nil,
            knowledgeRef: "knowledge_base",
            industrySpecific: nil,
            order: order
        )
    }

    // MARK: - 增量合并

    private func mergeEntries(extracted: [KnowledgeEntry], into existing: inout [KnowledgeEntry]) -> (Int, Int) {
        var newCount = 0
        var updateCount = 0

        for entry in extracted {
            if let matchIndex = existing.firstIndex(where: { isSimilar($0, entry) }) {
                if entry.confidence > existing[matchIndex].confidence ||
                   entry.content.count > existing[matchIndex].content.count {
                    existing[matchIndex].content = entry.content
                    existing[matchIndex].confidence = max(existing[matchIndex].confidence, entry.confidence)
                    existing[matchIndex].updatedAt = .now
                    let newTags = Set(existing[matchIndex].tags).union(entry.tags)
                    existing[matchIndex].tags = Array(newTags)
                    updateCount += 1
                }
            } else {
                existing.append(entry)
                newCount += 1
            }
        }

        return (newCount, updateCount)
    }

    private func isSimilar(_ a: KnowledgeEntry, _ b: KnowledgeEntry) -> Bool {
        guard a.category == b.category else { return false }

        let tokensA = tokenize(a.content)
        let tokensB = tokenize(b.content)

        guard !tokensA.isEmpty, !tokensB.isEmpty else { return false }

        let overlap = tokensA.intersection(tokensB).count
        let similarity = Double(overlap) / Double(min(tokensA.count, tokensB.count))
        return similarity > 0.6
    }

    private func tokenize(_ text: String) -> Set<String> {
        var tokens = Set<String>()
        let words = text.components(separatedBy: .whitespacesAndNewlines).filter { $0.count > 1 }
        tokens.formUnion(words)
        let chars = Array(text.filter { !$0.isWhitespace })
        for i in 0..<max(0, chars.count - 1) {
            tokens.insert(String(chars[i]) + String(chars[i + 1]))
        }
        return tokens
    }

    // MARK: - 文件读取

    private func readFileContent(_ url: URL) -> String? {
        FileTextExtractor.extractText(from: url)
    }
}
