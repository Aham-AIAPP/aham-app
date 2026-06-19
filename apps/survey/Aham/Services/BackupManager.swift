import Foundation
import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 应用数据备份与恢复管理器
@Observable
final class BackupManager {
    var isExporting = false
    var isImporting = false
    var exportMessage: String?
    var importMessage: String?
    var showImportConfirm = false
    var pendingImportURL: URL?

    // MARK: - 存储路径（沙盒内）

    private var appSupportDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    private var knowledgeBaseDir: URL {
        appSupportDir.appendingPathComponent("Aham/KnowledgeBase", isDirectory: true)
    }

    // MARK: - 导出

    func export() {
        // 先弹出保存面板（主线程同步）
        let panel = NSSavePanel()
        let dateStr = DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .none)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: " ", with: "")
        panel.nameFieldStringValue = "Aham备份_\(dateStr).zip"
        panel.allowedContentTypes = [UTType.zip]
        panel.title = "保存备份文件"
        panel.message = "选择备份文件的保存位置"

        guard panel.runModal() == .OK, let saveURL = panel.url else { return }

        isExporting = true
        exportMessage = nil

        Task {
            do {
                let zipURL = try await buildBackupZip()
                // 跨设备兼容：先 copy 再 remove
                if FileManager.default.fileExists(atPath: saveURL.path) {
                    try FileManager.default.removeItem(at: saveURL)
                }
                try FileManager.default.copyItem(at: zipURL, to: saveURL)
                try? FileManager.default.removeItem(at: zipURL)

                await MainActor.run {
                    self.isExporting = false
                    withAnimation { self.exportMessage = "✅ 备份已保存" }
                }
                try? await Task.sleep(for: .seconds(3))
                await MainActor.run {
                    withAnimation { if self.exportMessage?.hasPrefix("✅") == true { self.exportMessage = nil } }
                }
            } catch {
                await MainActor.run {
                    self.isExporting = false
                    self.exportMessage = "❌ 导出失败: \(error.localizedDescription)"
                }
            }
        }
    }

    private func buildBackupZip() async throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AhamBackup_\(Int(Date().timeIntervalSince1970))", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // 1. SwiftData
        let swiftDataDir = tempDir.appendingPathComponent("SwiftData", isDirectory: true)
        try FileManager.default.createDirectory(at: swiftDataDir, withIntermediateDirectories: true)
        for name in ["default.store", "default.store-shm", "default.store-wal"] {
            let src = appSupportDir.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: src.path) {
                try FileManager.default.copyItem(at: src, to: swiftDataDir.appendingPathComponent(name))
            }
        }

        // 2. 知识库
        let kbDir = tempDir.appendingPathComponent("KnowledgeBase", isDirectory: true)
        try FileManager.default.createDirectory(at: kbDir, withIntermediateDirectories: true)
        for name in ["knowledge.json", "manifest.json", "question_supplements.json", "question_exclusions.json"] {
            let src = knowledgeBaseDir.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: src.path) {
                try FileManager.default.copyItem(at: src, to: kbDir.appendingPathComponent(name))
            }
        }

        // 3. 设置（API Key、金蝶配置等）
        if let settingsData = UserDefaults.standard.data(forKey: "aham_settings") {
            try settingsData.write(to: tempDir.appendingPathComponent("settings.json"))
        }

        // 4. 备份信息
        let info: [String: String] = [
            "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.2",
            "date": ISO8601DateFormatter().string(from: Date()),
            "bundleId": Bundle.main.bundleIdentifier ?? "com.lichengbao.Aham"
        ]
        if let infoData = try? JSONEncoder().encode(info) {
            try infoData.write(to: tempDir.appendingPathComponent("backup_info.json"))
        }

        // 5. 压缩
        let zipURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AhamBackup_\(Int(Date().timeIntervalSince1970)).zip")

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
            process.arguments = ["-r", zipURL.path, "."]
            process.currentDirectoryURL = tempDir
            process.terminationHandler = { p in
                try? FileManager.default.removeItem(at: tempDir)
                if p.terminationStatus == 0 {
                    continuation.resume(returning: zipURL)
                } else {
                    continuation.resume(throwing: BackupError.zipFailed)
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    // MARK: - 导入

    func selectAndImport() {
        let panel = NSOpenPanel()
        panel.title = "选择备份文件"
        panel.allowedContentTypes = [UTType.zip]
        panel.allowsMultipleSelection = false
        panel.message = "选择 Aham 备份文件（.zip 格式）"

        if panel.runModal() == .OK, let url = panel.url {
            pendingImportURL = url
            showImportConfirm = true
        }
    }

    func confirmImport() {
        guard let url = pendingImportURL else { return }
        pendingImportURL = nil
        showImportConfirm = false
        isImporting = true
        importMessage = nil

        Task {
            do {
                try await performImport(from: url)
                await MainActor.run {
                    self.isImporting = false
                    withAnimation { self.importMessage = "✅ 导入成功，正在重启..." }
                }
                try? await Task.sleep(for: .seconds(1))
                await MainActor.run { self.relaunch() }
            } catch {
                await MainActor.run {
                    self.isImporting = false
                    self.importMessage = "❌ 导入失败: \(error.localizedDescription)"
                }
            }
        }
    }

    func cancelImport() {
        pendingImportURL = nil
        showImportConfirm = false
    }

    private func performImport(from zipURL: URL) async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AhamRestore_\(Int(Date().timeIntervalSince1970))", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // 解压
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            process.arguments = ["-o", zipURL.path, "-d", tempDir.path]
            process.terminationHandler = { p in
                if p.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: BackupError.unzipFailed)
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }

        // 校验：必须含有已知备份目录或文件
        let hasSwiftData = FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("SwiftData").path)
        let hasKB       = FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("KnowledgeBase").path)
        let hasSettings = FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("settings.json").path)
        guard hasSwiftData || hasKB || hasSettings else {
            throw BackupError.invalidBackup
        }

        // 恢复 SwiftData
        if hasSwiftData {
            let srcDir = tempDir.appendingPathComponent("SwiftData")
            for name in ["default.store", "default.store-shm", "default.store-wal"] {
                let src = srcDir.appendingPathComponent(name)
                guard FileManager.default.fileExists(atPath: src.path) else { continue }
                let dst = appSupportDir.appendingPathComponent(name)
                try? FileManager.default.removeItem(at: dst)
                try FileManager.default.copyItem(at: src, to: dst)
            }
        }

        // 恢复知识库
        if hasKB {
            try FileManager.default.createDirectory(at: knowledgeBaseDir, withIntermediateDirectories: true)
            let srcDir = tempDir.appendingPathComponent("KnowledgeBase")
            for name in ["knowledge.json", "manifest.json", "question_supplements.json", "question_exclusions.json"] {
                let src = srcDir.appendingPathComponent(name)
                guard FileManager.default.fileExists(atPath: src.path) else { continue }
                let dst = knowledgeBaseDir.appendingPathComponent(name)
                try? FileManager.default.removeItem(at: dst)
                try FileManager.default.copyItem(at: src, to: dst)
            }
        }

        // 恢复设置
        if hasSettings,
           let data = try? Data(contentsOf: tempDir.appendingPathComponent("settings.json")) {
            UserDefaults.standard.set(data, forKey: "aham_settings")
        }
    }

    // MARK: - 重启

    private func relaunch() {
        let path = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 0.8 && open \"\(path)\""]
        try? task.run()
        NSApplication.shared.terminate(nil)
    }
}

// MARK: - 错误

enum BackupError: LocalizedError {
    case zipFailed
    case unzipFailed
    case invalidBackup

    var errorDescription: String? {
        switch self {
        case .zipFailed:      "ZIP 压缩失败"
        case .unzipFailed:    "解压失败，文件可能已损坏"
        case .invalidBackup:  "无效的备份文件，不是 Aham 备份"
        }
    }
}
