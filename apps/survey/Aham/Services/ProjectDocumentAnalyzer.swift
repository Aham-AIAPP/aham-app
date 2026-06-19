import Foundation

/// 项目文档分析器
/// - 支持多文件同时导入
/// - 分块（chunk）处理大文档，每块 3000 字
/// - 按部门分批生成补充问题，每批 3 个部门
/// - 所有进度通过 `progress`（0~1）和 `progressMessage` 暴露给 UI
@Observable
@MainActor
final class ProjectDocumentAnalyzer {

    // MARK: - 对外状态

    private(set) var isAnalyzing = false
    private(set) var isRebuildingQuestions = false
    /// 当前阶段进度 0.0 ~ 1.0（确定性）
    private(set) var progress: Double = 0
    /// 当前进度说明文字
    private(set) var progressMessage: String = ""
    var lastError: String?

    // MARK: - 数据结构

    struct DocumentAnalysisResult {
        let companyProfile: CompanyProfile
        let knownIssues: [String]
        let knownNeeds: [String]
        let keyFindings: [String]
        /// 所有文档合并后的摘要文本（5000字以内，供问题重构使用）
        let rawDocContent: String
        /// 成功处理的文件名列表
        let fileNames: [String]
    }

    struct CompanyProfile {
        var industry: String
        var scale: String
        var products: String
        var systems: [String]
        var certifications: [String]

        static let empty = CompanyProfile(industry: "", scale: "", products: "", systems: [], certifications: [])

        /// 用更丰富的画像数据合并（非空字段优先保留）
        mutating func merge(with other: CompanyProfile) {
            if industry.isEmpty  { industry  = other.industry  }
            if scale.isEmpty     { scale     = other.scale     }
            if products.isEmpty  { products  = other.products  }
            systems       = Array(Set(systems       + other.systems)).sorted()
            certifications = Array(Set(certifications + other.certifications)).sorted()
        }
    }

    // MARK: - 常量

    private let chunkSize   = 3000   // 每块字符数（约 1500 汉字）
    private let maxChunks   = 3      // 每个文档最多处理 3 块
    private let maxFiles    = 5      // 最多同时导入 5 个文件
    private let deptBatch   = 3      // 每批部门数

    // MARK: - 公开 API

    /// 分析多个文档，返回合并结果
    /// - Parameter fileURLs: 用户选择的文件 URL 列表（最多 maxFiles 个）
    func analyze(fileURLs: [URL], settings: SettingsManager) async -> DocumentAnalysisResult? {
        guard let provider = settings.llmProvider else {
            lastError = "请先在设置中配置 AI 服务"
            return nil
        }

        isAnalyzing = true
        progress = 0
        progressMessage = "正在读取文件..."
        lastError = nil
        defer { isAnalyzing = false; progress = 0; progressMessage = "" }

        let urls = Array(fileURLs.prefix(maxFiles))

        // 1. 读取所有文件内容并生成分块列表
        struct Chunk {
            let text: String
            let fileName: String
            let isFirstOfFile: Bool  // 决定是否提取 companyProfile
        }

        var allChunks: [Chunk] = []
        var successFileNames: [String] = []

        for url in urls {
            guard let content = readFileContent(url) else {
                print("[DocAnalyzer] 跳过无法读取的文件: \(url.lastPathComponent)")
                continue
            }
            successFileNames.append(url.lastPathComponent)
            let blocks = splitIntoChunks(content)
            for (i, block) in blocks.enumerated() {
                allChunks.append(Chunk(text: block, fileName: url.lastPathComponent, isFirstOfFile: i == 0))
            }
        }

        guard !allChunks.isEmpty else {
            lastError = "所有文件均无法读取，请检查文件格式"
            return nil
        }

        // 2. 逐块调用 LLM（确定性进度）
        var mergedProfile = CompanyProfile.empty
        var allIssues:   [String] = []
        var allNeeds:    [String] = []
        var allFindings: [String] = []
        var rawContentParts: [String] = []
        let totalChunks = allChunks.count

        for (i, chunk) in allChunks.enumerated() {
            let chunkLabel = totalChunks == 1
                ? chunk.fileName
                : "\(chunk.fileName)（\(i + 1)/\(totalChunks)）"
            progressMessage = "分析 \(chunkLabel)..."
            progress = Double(i) / Double(totalChunks)

            let messages = PromptTemplates.documentAnalysis(
                docContent: chunk.text,
                extractProfile: chunk.isFirstOfFile
            )
            do {
                let response = try await provider.chat(
                    messages: messages,
                    options: LLMOptions(maxTokens: 1000, temperature: 0.1, timeout: 45)
                )
                mergeChunkResult(response,
                                 extractProfile: chunk.isFirstOfFile,
                                 profile: &mergedProfile,
                                 issues: &allIssues,
                                 needs: &allNeeds,
                                 findings: &allFindings)
            } catch {
                let friendly = friendlyError(error)
                print("[DocAnalyzer] 块 \(i+1) 失败: \(friendly)")
                // 非关键错误：继续处理下一块，不终止整体流程
            }

            rawContentParts.append(chunk.text)
        }

        progress = 1.0
        progressMessage = "分析完成"

        // 合并 rawContent 用于后续问题重构（限 5000 字）
        let fullRaw = rawContentParts.joined(separator: "\n---\n")
        let rawDoc = String(fullRaw.prefix(5000))

        return DocumentAnalysisResult(
            companyProfile: mergedProfile,
            knownIssues:   Array(allIssues.prefix(6)),
            knownNeeds:    Array(allNeeds.prefix(6)),
            keyFindings:   Array(allFindings.prefix(6)),
            rawDocContent: rawDoc,
            fileNames:     successFileNames
        )
    }

    /// 基于文档摘要，按部门分批生成补充问题
    func rebuildProjectQuestions(
        docContent: String,
        project: Project,
        departments: [DepartmentTemplate],
        settings: SettingsManager
    ) async -> [AIGeneratedQuestion]? {
        guard let provider = settings.llmProvider else {
            lastError = "请先在设置中配置 AI 服务"
            return nil
        }
        guard !departments.isEmpty else {
            lastError = "项目未选择任何调研部门"
            return nil
        }

        isRebuildingQuestions = true
        progress = 0
        progressMessage = ""
        lastError = nil
        defer { isRebuildingQuestions = false; progress = 0; progressMessage = "" }

        // 按 deptBatch 个部门为一批
        let batches = stride(from: 0, to: departments.count, by: deptBatch).map {
            Array(departments[$0..<min($0 + deptBatch, departments.count)])
        }
        let totalBatches = batches.count
        let customerName = project.customerName.isEmpty ? project.name : project.customerName
        var allQuestions: [AIGeneratedQuestion] = []

        for (i, batch) in batches.enumerated() {
            let batchLabel = batch.map(\.name).joined(separator: " / ")
            progressMessage = "生成问题（\(batchLabel)）\(i + 1)/\(totalBatches)"
            progress = Double(i) / Double(totalBatches)

            let messages = PromptTemplates.projectDocumentQuestionRebuild(
                docContent: docContent,
                customerName: customerName,
                departments: batch
            )
            do {
                let response = try await provider.chat(
                    messages: messages,
                    options: LLMOptions(maxTokens: 1500, temperature: 0.3, timeout: 45)
                )
                let questions = parseDocQuestions(from: response)
                allQuestions.append(contentsOf: questions)
            } catch {
                print("[DocAnalyzer] 批次 \(i+1) 失败: \(friendlyError(error))")
                // 单批失败继续处理其余批次
            }
        }

        progress = 1.0
        progressMessage = "生成完成"

        if allQuestions.isEmpty {
            lastError = "AI 未从文档中识别出可追加的调研问题"
            return nil
        }
        return allQuestions
    }

    /// 解析 LLM 返回的问题 JSON（暴露为 internal 供测试访问）
    func parseDocQuestions(from response: String) -> [AIGeneratedQuestion] {
        guard let json = LLMJSONParser.parse(response) as? [String: Any],
              let supplementsRaw = json["supplements"] as? [String: [[String: Any]]] else {
            return []
        }

        var result: [AIGeneratedQuestion] = []
        for (deptId, qList) in supplementsRaw {
            for item in qList {
                guard let id   = item["id"]   as? String,
                      let sect = item["section"] as? String,
                      let text = item["text"] as? String,
                      !text.isEmpty else { continue }

                result.append(AIGeneratedQuestion(
                    id: id,
                    departmentId: deptId,
                    section: sect,
                    text: text,
                    type: item["type"] as? String ?? "text",
                    options: item["options"] as? [String] ?? [],
                    reason: item["reason"] as? String ?? ""
                ))
            }
        }
        return result
    }

    /// 将分析结果写入项目（画像信息 + documentContext）
    func applyToProject(_ result: DocumentAnalysisResult, project: Project) {
        let p = result.companyProfile
        if project.companyScale.isEmpty && !p.scale.isEmpty    { project.companyScale = p.scale }
        if project.existingSystems.isEmpty && !p.systems.isEmpty {
            project.existingSystems = p.systems.joined(separator: "、")
        }

        var parts: [String] = []
        if !p.industry.isEmpty       { parts.append("行业：\(p.industry)") }
        if !p.products.isEmpty       { parts.append("产品：\(p.products)") }
        if !p.certifications.isEmpty { parts.append("认证：\(p.certifications.joined(separator: "、"))") }
        if !result.knownIssues.isEmpty  { parts.append("已知问题：\(result.knownIssues.joined(separator: "；"))") }
        if !result.knownNeeds.isEmpty   { parts.append("已知需求：\(result.knownNeeds.joined(separator: "；"))") }
        if !result.keyFindings.isEmpty  { parts.append("关键发现：\(result.keyFindings.joined(separator: "；"))") }

        if !parts.isEmpty {
            var enhancement = project.aiEnhancement ?? AIProjectEnhancement()
            enhancement.documentContext = parts.joined(separator: "\n")
            project.aiEnhancement = enhancement
        }
        project.updatedAt = .now
    }

    // MARK: - 私有辅助

    /// 在段落/句子边界切分文本，每块不超过 chunkSize 字符，最多 maxChunks 块
    private func splitIntoChunks(_ text: String) -> [String] {
        guard text.count > chunkSize else { return [text] }

        var chunks: [String] = []
        var remaining = text.trimmingCharacters(in: .whitespacesAndNewlines)

        while !remaining.isEmpty && chunks.count < maxChunks {
            if remaining.count <= chunkSize {
                chunks.append(remaining)
                break
            }

            // 在 chunkSize 之前寻找最近的换行 / 句号 / 分号作为切割点
            let endIdx = remaining.index(remaining.startIndex, offsetBy: chunkSize)
            let searchRange = remaining.startIndex..<endIdx
            var splitIdx = endIdx

            let separators = ["\n\n", "\n", "。", "；", "！", "？", ". ", "; "]
            for sep in separators {
                if let r = remaining.range(of: sep, options: .backwards, range: searchRange) {
                    splitIdx = r.upperBound
                    break
                }
            }

            chunks.append(String(remaining[..<splitIdx]))
            remaining = String(remaining[splitIdx...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return chunks
    }

    /// 合并单块 LLM 返回结果到累积变量
    private func mergeChunkResult(
        _ response: String,
        extractProfile: Bool,
        profile: inout CompanyProfile,
        issues: inout [String],
        needs: inout [String],
        findings: inout [String]
    ) {
        guard let json = LLMJSONParser.parse(response) as? [String: Any] else { return }

        if extractProfile, let pd = json["companyProfile"] as? [String: Any] {
            let parsed = CompanyProfile(
                industry:      pd["industry"]      as? String   ?? "",
                scale:         pd["scale"]         as? String   ?? "",
                products:      pd["products"]      as? String   ?? "",
                systems:       pd["systems"]       as? [String] ?? [],
                certifications: pd["certifications"] as? [String] ?? []
            )
            profile.merge(with: parsed)
        }

        appendDeduped(json["knownIssues"]  as? [String] ?? [], into: &issues)
        appendDeduped(json["knownNeeds"]   as? [String] ?? [], into: &needs)
        appendDeduped(json["keyFindings"]  as? [String] ?? [], into: &findings)
    }

    /// 将新条目追加到数组，跳过与已有项相似的条目
    private func appendDeduped(_ items: [String], into array: inout [String]) {
        for item in items where !item.isEmpty {
            let isDuplicate = array.contains { isSimilar($0, item) }
            if !isDuplicate { array.append(item) }
        }
    }

    /// 简单相似度判断：其中一方包含另一方（长度 >= 4 的字符串才做子串匹配，更短的直接比较）
    private func isSimilar(_ a: String, _ b: String) -> Bool {
        guard a.count >= 4, b.count >= 4 else { return a == b }
        return a.localizedCaseInsensitiveContains(b) || b.localizedCaseInsensitiveContains(a)
    }

    /// 将系统错误转为用户友好的中文提示
    private func friendlyError(_ error: Error) -> String {
        if let urlErr = error as? URLError {
            switch urlErr.code {
            case .timedOut:             return "请求超时，文档内容过长或网络较慢"
            case .notConnectedToInternet: return "网络未连接"
            case .cannotConnectToHost:  return "无法连接到 AI 服务，请检查配置"
            default: break
            }
        }
        return error.localizedDescription
    }

    private func readFileContent(_ url: URL) -> String? {
        FileTextExtractor.extractText(from: url)
    }
}
