import Foundation
import PDFKit
import AppKit

/// 共享文件文本提取工具 — 支持纯文本、PDF、Word、Excel、PPT
enum FileTextExtractor {
    private static let textExts: Set<String> = ["txt", "md", "markdown", "json", "csv", "log", "xml", "html"]
    // NSAttributedString 可处理的 Office/富文本格式
    private static let attrStrExts: Set<String> = ["docx", "doc", "rtf", "odt", "xlsx", "xls", "pptx", "ppt"]

    /// 所有支持的文件扩展名（供文件夹扫描使用）
    static let supportedExtensions: Set<String> = textExts.union(attrStrExts).union(["pdf"])

    /// 从文件提取文本内容，不支持的格式返回 nil
    static func extractText(from url: URL) -> String? {
        let ext = url.pathExtension.lowercased()

        if textExts.contains(ext) {
            return try? String(contentsOf: url, encoding: .utf8)
        }

        if ext == "pdf" {
            return extractPDFText(url)
        }

        if attrStrExts.contains(ext) {
            return extractAttributedStringText(url)
        }

        return nil
    }

    private static func extractPDFText(_ url: URL) -> String? {
        guard let doc = PDFDocument(url: url) else { return nil }
        var text = ""
        for i in 0..<doc.pageCount {
            if let page = doc.page(at: i), let pageText = page.string {
                text += pageText + "\n"
            }
        }
        return text.isEmpty ? nil : text
    }

    /// 使用 NSAttributedString 提取 Word/RTF/ODT 文档文本
    private static func extractAttributedStringText(_ url: URL) -> String? {
        guard let attrStr = try? NSAttributedString(url: url, options: [:], documentAttributes: nil) else {
            return nil
        }
        let text = attrStr.string
        return text.isEmpty ? nil : text
    }
}
