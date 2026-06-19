import Foundation
import SwiftUI

/// 平台设置管理器 — 统一管理所有服务配置
@Observable
final class SettingsManager {
    // MARK: - LLM 配置
    var llmConfig: LLMConfig {
        didSet { save() }
    }

    // MARK: - Obsidian 配置
    var obsidianConfig: ObsidianConfig {
        didSet { save() }
    }

    // MARK: - 金蝶云星空配置
    var kingdeeConfig: KingdeeConfig {
        didSet { save() }
    }

    // MARK: - LLM Provider（缓存实例，配置变更时重建）
    private var _cachedProvider: OpenAICompatibleProvider?
    private var _cachedProviderConfig: LLMConfig?

    // 防抖存储：0.5s 内多次配置变更只写一次 UserDefaults
    private var _pendingSave: DispatchWorkItem?

    var llmProvider: (any LLMProvider)? {
        guard !llmConfig.apiKey.isEmpty else { return nil }
        if let cached = _cachedProvider, _cachedProviderConfig == llmConfig {
            return cached
        }
        let provider = OpenAICompatibleProvider(config: llmConfig)
        _cachedProvider = provider
        _cachedProviderConfig = llmConfig
        return provider
    }

    var isLLMConfigured: Bool {
        !llmConfig.apiKey.isEmpty && !llmConfig.endpoint.isEmpty
    }

    // MARK: - 初始化

    private static let storageKey = "aham_settings"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let stored = try? JSONDecoder().decode(StoredSettings.self, from: data) {
            self.llmConfig      = stored.llm
            self.obsidianConfig = stored.obsidian
            self.kingdeeConfig  = stored.kingdee
        } else {
            self.llmConfig      = .default
            self.obsidianConfig = .default
            self.kingdeeConfig  = .default
        }
    }

    // MARK: - 持久化

    private func save() {
        _pendingSave?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let stored = StoredSettings(
                llm: self.llmConfig,
                obsidian: self.obsidianConfig,
                kingdee: self.kingdeeConfig
            )
            if let data = try? JSONEncoder().encode(stored) {
                UserDefaults.standard.set(data, forKey: Self.storageKey)
            }
        }
        _pendingSave = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: item)
    }

    /// 测试 LLM 连接
    func testLLMConnection() async -> Bool {
        guard let provider = llmProvider else { return false }
        return await provider.testConnection()
    }
}

// MARK: - 存储结构

private struct StoredSettings: Codable {
    let llm: LLMConfig
    let obsidian: ObsidianConfig
    var kingdee: KingdeeConfig
}

// MARK: - Obsidian 配置

struct ObsidianConfig: Codable, Equatable {
    var enabled: Bool
    var vaultPath: String
    var exportFolder: String
    var addFrontmatter: Bool
    var vaultBookmark: Data?

    static let `default` = ObsidianConfig(
        enabled: false,
        vaultPath: "",
        exportFolder: "Aham",
        addFrontmatter: true,
        vaultBookmark: nil
    )

    static func createBookmark(from url: URL) -> Data? {
        try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    var resolvedVaultURL: URL? {
        guard let data = vaultBookmark else { return nil }
        var stale = false
        return try? URL(resolvingBookmarkData: data,
                        options: .withSecurityScope,
                        relativeTo: nil,
                        bookmarkDataIsStale: &stale)
    }
}

// MARK: - 金蝶云星空配置

struct KingdeeConfig: Codable, Equatable {
    var serverURL: String
    var acctId: String
    var username: String
    var appId: String
    var appSecret: String
    var lcid: String

    var isConfigured: Bool {
        !serverURL.isEmpty && !acctId.isEmpty && !appId.isEmpty && !appSecret.isEmpty
    }

    static let `default` = KingdeeConfig(
        serverURL: "",
        acctId: "",
        username: "",
        appId: "",
        appSecret: "",
        lcid: "2052"
    )
}
