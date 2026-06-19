import Foundation
import AppKit

/// Markdown 导出引擎 — 将项目调研数据生成结构化 Markdown
struct MarkdownExporter {

    /// 将 Markdown 简单转换为 HTML 段落，封装成 Word 可识别的 HTML
    static func wrapInWordHTML(title: String, markdownBody: String) -> String {
        var html = """
        <!DOCTYPE html>
        <html xmlns:o='urn:schemas-microsoft-com:office:office'
              xmlns:w='urn:schemas-microsoft-com:office:word'
              xmlns='http://www.w3.org/TR/REC-html40'>
        <head>
        <meta charset='UTF-8'>
        <title>\(escapeHTML(title))</title>
        <style>
          body { font-family: -apple-system, "PingFang SC", "Microsoft YaHei", Arial, sans-serif;
                 font-size: 11pt; line-height: 1.6; margin: 2cm; color: #1a1a1a; }
          h1 { font-size: 18pt; color: #1a3557; border-bottom: 2px solid #1a3557; padding-bottom: 6pt; }
          h2 { font-size: 14pt; color: #2c5f8a; margin-top: 16pt; }
          h3 { font-size: 12pt; color: #3a3a3a; }
          table { border-collapse: collapse; width: 100%; margin: 8pt 0; }
          td, th { border: 1px solid #ccc; padding: 4pt 8pt; }
          th { background: #f0f4f8; }
          blockquote { border-left: 3px solid #aaa; margin-left: 0; padding-left: 12pt; color: #555; }
          em { color: #2c5f8a; }
          hr { border: none; border-top: 1px solid #ddd; margin: 12pt 0; }
          .note { background: #fffbe6; padding: 4pt 8pt; border-radius: 4pt; }
          .voice { background: #eef6ff; padding: 4pt 8pt; border-radius: 4pt; }
          .polish { background: #f0fff4; padding: 4pt 8pt; border-radius: 4pt; }
        </style>
        </head>
        <body>
        """

        // 逐行转换 Markdown → HTML
        let lines = markdownBody.components(separatedBy: "\n")
        var inTable = false
        var tableRowCount = 0

        for line in lines {
            if line.hasPrefix("# ") {
                html += "<h1>\(escapeHTML(String(line.dropFirst(2))))</h1>\n"
            } else if line.hasPrefix("## ") {
                html += "<h2>\(escapeHTML(String(line.dropFirst(3))))</h2>\n"
            } else if line.hasPrefix("### ") {
                html += "<h3>\(escapeHTML(String(line.dropFirst(4))))</h3>\n"
            } else if line.hasPrefix("> ") {
                html += "<blockquote><p>\(inlineMarkdown(String(line.dropFirst(2))))</p></blockquote>\n"
            } else if line.hasPrefix("- [x] ") {
                html += "<p>☑ \(escapeHTML(String(line.dropFirst(6))))</p>\n"
            } else if line.hasPrefix("- ") {
                html += "<p>• \(escapeHTML(String(line.dropFirst(2))))</p>\n"
            } else if line.hasPrefix("---") {
                if inTable { html += "</table>\n"; inTable = false; tableRowCount = 0 }
                html += "<hr>\n"
            } else if line.contains("|") && line.trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                let cells = line.split(separator: "|", omittingEmptySubsequences: false)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                if cells.allSatisfy({ $0.allSatisfy({ $0 == "-" || $0 == ":" }) }) {
                    // separator row — skip
                } else {
                    if !inTable { html += "<table>\n"; inTable = true; tableRowCount = 0 }
                    let tag = tableRowCount == 0 ? "th" : "td"
                    html += "<tr>" + cells.map { "<\(tag)>\(escapeHTML($0))</\(tag)>" }.joined() + "</tr>\n"
                    tableRowCount += 1
                }
            } else {
                if inTable { html += "</table>\n"; inTable = false; tableRowCount = 0 }
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty {
                    html += "<br>\n"
                } else {
                    html += "<p>\(inlineMarkdown(trimmed))</p>\n"
                }
            }
        }
        if inTable { html += "</table>\n" }

        html += "</body></html>"
        return html
    }

    private static func escapeHTML(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func inlineMarkdown(_ s: String) -> String {
        // HTML 转义后再做 inline 标记替换，避免 index 越界
        var result = escapeHTML(s)
        // 粗体 **text** → <strong>text</strong>（先处理，防止与斜体规则冲突）
        result = result.replacingOccurrences(of: #"\*\*([^*\n]+?)\*\*"#,
                                             with: "<strong>$1</strong>",
                                             options: .regularExpression)
        // 斜体 *text* → <em>text</em>
        result = result.replacingOccurrences(of: #"(?<![*])\*([^*\n]+?)\*(?![*])"#,
                                             with: "<em>$1</em>",
                                             options: .regularExpression)
        return result
    }

    // MARK: - Private

    private static func aiEnhancementSection(enhancement: AIProjectEnhancement) -> String {
        var md = "\n---\n\n## AI 项目分析\n\n"
        if !enhancement.industryContext.isEmpty {
            md += "### 行业上下文\n\n\(enhancement.industryContext)\n\n"
        }
        if !enhancement.documentContext.isEmpty {
            md += "### 文档摘要\n\n\(enhancement.documentContext)\n\n"
        }
        if !enhancement.additionalQuestions.isEmpty {
            md += "### AI 补充问题建议\n\n"
            for q in enhancement.additionalQuestions {
                md += "- **[\(q.departmentId)]** \(q.text)\n"
                if !q.reason.isEmpty { md += "  > \(q.reason)\n" }
            }
            md += "\n"
        }
        return md
    }

    private static func frontmatter(project: Project) -> String {
        var yaml: [String] = ["---"]
        yaml.append("title: \"\(yamlEscape(project.displayName + " 调研报告"))\"")
        yaml.append("customer: \"\(yamlEscape(project.customerName))\"")
        if !project.consultant.isEmpty {
            yaml.append("consultant: \"\(yamlEscape(project.consultant))\"")
        }
        yaml.append("date: \(project.surveyDate.formatted(.iso8601.year().month().day()))")
        yaml.append("status: \(project.status.label)")
        yaml.append("industry: \(project.industryEnum.label)")
        yaml.append("progress: \(Int(project.progress * 100))%")
        yaml.append("tags:")
        yaml.append("  - 调研报告")
        yaml.append("  - \"\(yamlEscape(project.customerName))\"")
        yaml.append("---\n\n")
        return yaml.joined(separator: "\n")
    }

    private static func yamlEscape(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
             .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func projectOverview(project: Project, config: ExportConfig) -> String {
        var md = "## 项目概况\n\n"
        md += "| 项目 | 信息 |\n|------|------|\n"
        md += "| 客户 | \(project.customerName) |\n"
        if !project.consultant.isEmpty {
            md += "| 顾问 | \(project.consultant) |\n"
        }
        md += "| 调研日期 | \(project.surveyDate.formatted(.dateTime.year().month().day())) |\n"
        md += "| 状态 | \(project.status.label) |\n"
        if !project.companyScale.isEmpty {
            md += "| 企业规模 | \(project.companyScale) |\n"
        }
        if !project.headcount.isEmpty {
            md += "| 人数 | \(project.headcount) |\n"
        }
        if !project.revenue.isEmpty {
            md += "| 营收 | \(project.revenue) |\n"
        }
        if !project.existingSystems.isEmpty {
            md += "| 已有系统 | \(project.existingSystems) |\n"
        }
        md += "\n"

        if !project.surveyGoal.isEmpty {
            md += "> **调研目标**: \(project.surveyGoal)\n\n"
        }

        return md
    }

    private static func questionBlock(
        question: QuestionTemplate,
        answer: Answer,
        config: ExportConfig
    ) -> String {
        var md = ""

        // 问题
        md += "**\(question.topic)** — \(question.question)\n\n"

        // 回答
        if !answer.selectedOptions.isEmpty && answer.selectedOptions != [answer.textValue] {
            for opt in answer.selectedOptions {
                md += "- [x] \(opt)\n"
            }
            md += "\n"
        } else if !answer.textValue.isEmpty {
            md += "> \(answer.textValue.replacingOccurrences(of: "\n", with: "\n> "))\n\n"
        }

        // AI 润色
        if config.includeAIPolish && !answer.polishedText.isEmpty {
            md += "*AI 润色:* \(answer.polishedText)\n\n"
        }

        // 顾问笔记
        if config.includeNotes && !answer.noteText.isEmpty {
            md += "*笔记:* \(answer.noteText)\n\n"
        }

        // 语音转写
        if config.includeVoice && !answer.voiceTranscript.isEmpty {
            md += "*语音记录:* \(answer.voiceTranscript)\n\n"
        }

        return md
    }
}

/// 导出格式
enum ExportFormat: String, CaseIterable {
    case markdown = "Markdown (.md)"
    case word     = "Word (.docx)"
}

/// 导出配置
struct ExportConfig {
    var format: ExportFormat
    var addFrontmatter: Bool
    var includeNotes: Bool
    var includeAIPolish: Bool
    var includeVoice: Bool
    var includeAIEnhancement: Bool
    /// nil 表示导出全部部门
    var departmentFilter: [String]?

    static let `default` = ExportConfig(
        format: .markdown,
        addFrontmatter: true,
        includeNotes: true,
        includeAIPolish: true,
        includeVoice: true,
        includeAIEnhancement: true,
        departmentFilter: nil
    )
}

// MARK: - ExportSnapshot（纯值类型，无 SwiftData / @Observable 依赖）

/// 导出快照：在 MainActor 上从 @Model 对象提取的纯 Swift 值类型副本
struct ExportSnapshot {
    var displayName: String
    var customerName: String
    var consultant: String
    var surveyDate: Date
    var statusLabel: String
    var industryLabel: String
    var companyScale: String
    var headcount: String
    var revenue: String
    var existingSystems: String
    var surveyGoal: String
    var totalQuestions: Int
    var answeredQuestions: Int
    var progress: Double
    var aiEnhancement: AIProjectEnhancement?
    var selectedDepartmentIds: [String]
    var departmentNames: [String: String]   // deptId → 显示名称
    var departmentSections: [String: [ExportSectionData]]  // deptId → sections

    struct ExportSectionData {
        var label: String
        var items: [ExportItem]
    }

    struct ExportItem {
        var topic: String
        var question: String
        var selectedOptions: [String]
        var textValue: String
        var noteText: String
        var polishedText: String
        var voiceTranscript: String
        var hasContent: Bool
    }

    var answeredDeptIds: [String] {
        selectedDepartmentIds.filter { deptId in
            departmentSections[deptId]?.flatMap(\.items).contains(where: \.hasContent) == true
        }
    }
}

// MARK: - MarkdownExporter Snapshot 版本

extension MarkdownExporter {
    /// 从 ExportSnapshot 生成 Markdown（全程无 @Model 访问）
    static func exportProject(snapshot: ExportSnapshot, config: ExportConfig) -> String {
        var md = ""

        if config.addFrontmatter {
            md += snapshotFrontmatter(snapshot)
        }

        md += "# \(snapshot.displayName) — 调研报告\n\n"
        md += snapshotOverview(snapshot)

        if config.includeAIEnhancement, let enhancement = snapshot.aiEnhancement {
            md += aiEnhancementSection(enhancement: enhancement)
        }

        let deptIds = config.departmentFilter ?? snapshot.selectedDepartmentIds
        for deptId in deptIds {
            let name = snapshot.departmentNames[deptId] ?? deptId
            guard let sections = snapshot.departmentSections[deptId] else { continue }

            md += "\n---\n\n## \(name)\n\n"

            for section in sections {
                let visibleItems = section.items.filter(\.hasContent)
                if visibleItems.isEmpty { continue }

                md += "### \(section.label)\n\n"
                for item in visibleItems {
                    md += snapshotQuestionBlock(item: item, config: config)
                }
            }
        }

        md += "\n---\n\n## 调研统计\n\n"
        md += "- 总问题数: \(snapshot.totalQuestions)\n"
        md += "- 已回答: \(snapshot.answeredQuestions)\n"
        md += "- 完成率: \(Int(snapshot.progress * 100))%\n"
        md += "- 调研部门: \(snapshot.selectedDepartmentIds.count) 个\n"
        md += "- 导出时间: \(Date.now.formatted(.dateTime.year().month().day().hour().minute()))\n"

        return md
    }

    static func exportProjectAsHTML(snapshot: ExportSnapshot, config: ExportConfig) -> String {
        let md = exportProject(snapshot: snapshot, config: config)
        return wrapInWordHTML(title: "\(snapshot.displayName) 调研报告", markdownBody: md)
    }

    /// 生成真正的 .docx（Office Open XML）— 需主线程，用 MainActor.run 包裹 WebKit 调用
    static func exportProjectAsDOCX(snapshot: ExportSnapshot, config: ExportConfig) async -> Data? {
        // YAML frontmatter 对 Word 无意义，关闭
        var cfg = config
        cfg.addFrontmatter = false
        let html = exportProjectAsHTML(snapshot: snapshot, config: cfg)
        return await MainActor.run {
            guard let htmlData = html.data(using: .utf8),
                  let attrStr = try? NSAttributedString(
                      data: htmlData,
                      options: [
                          .documentType: NSAttributedString.DocumentType.html,
                          .characterEncoding: String.Encoding.utf8.rawValue
                      ],
                      documentAttributes: nil
                  ) else { return nil }
            return try? attrStr.data(
                from: NSRange(location: 0, length: attrStr.length),
                documentAttributes: [.documentType: NSAttributedString.DocumentType.officeOpenXML]
            )
        }
    }

    private static func snapshotFrontmatter(_ s: ExportSnapshot) -> String {
        var yaml: [String] = ["---"]
        yaml.append("title: \"\(yamlEscape(s.displayName + " 调研报告"))\"")
        yaml.append("customer: \"\(yamlEscape(s.customerName))\"")
        if !s.consultant.isEmpty { yaml.append("consultant: \"\(yamlEscape(s.consultant))\"") }
        yaml.append("date: \(s.surveyDate.formatted(.iso8601.year().month().day()))")
        yaml.append("status: \(s.statusLabel)")
        yaml.append("industry: \(s.industryLabel)")
        yaml.append("progress: \(Int(s.progress * 100))%")
        yaml.append("tags:\n  - 调研报告\n  - \"\(yamlEscape(s.customerName))\"")
        yaml.append("---\n\n")
        return yaml.joined(separator: "\n")
    }

    private static func snapshotOverview(_ s: ExportSnapshot) -> String {
        var md = "## 项目概况\n\n| 项目 | 信息 |\n|------|------|\n"
        md += "| 客户 | \(s.customerName) |\n"
        if !s.consultant.isEmpty { md += "| 顾问 | \(s.consultant) |\n" }
        md += "| 调研日期 | \(s.surveyDate.formatted(.dateTime.year().month().day())) |\n"
        md += "| 状态 | \(s.statusLabel) |\n"
        if !s.companyScale.isEmpty { md += "| 企业规模 | \(s.companyScale) |\n" }
        if !s.headcount.isEmpty    { md += "| 人数 | \(s.headcount) |\n" }
        if !s.revenue.isEmpty      { md += "| 营收 | \(s.revenue) |\n" }
        if !s.existingSystems.isEmpty { md += "| 已有系统 | \(s.existingSystems) |\n" }
        md += "\n"
        if !s.surveyGoal.isEmpty { md += "> **调研目标**: \(s.surveyGoal)\n\n" }
        return md
    }

    private static func snapshotQuestionBlock(item: ExportSnapshot.ExportItem, config: ExportConfig) -> String {
        var md = "**\(item.topic)** — \(item.question)\n\n"

        if !item.selectedOptions.isEmpty {
            for opt in item.selectedOptions { md += "- [x] \(opt)\n" }
            md += "\n"
        } else if !item.textValue.isEmpty {
            md += "> \(item.textValue.replacingOccurrences(of: "\n", with: "\n> "))\n\n"
        }

        if config.includeAIPolish  && !item.polishedText.isEmpty    { md += "*AI 润色:* \(item.polishedText)\n\n" }
        if config.includeNotes     && !item.noteText.isEmpty         { md += "*笔记:* \(item.noteText)\n\n" }
        if config.includeVoice     && !item.voiceTranscript.isEmpty  { md += "*语音记录:* \(item.voiceTranscript)\n\n" }

        return md
    }
}
