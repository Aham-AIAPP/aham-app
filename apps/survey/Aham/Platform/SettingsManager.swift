import Foundation
import SwiftUI

/// 平台设置管理器 — 统一管理所有服务配置
@Observable
final class SettingsManager {
    // MARK: - LLM 配置
    var llmConfig: LLMConfig {
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
            self.llmConfig = stored.llm
        } else {
            self.llmConfig = .default
        }
    }

    // MARK: - 持久化

    private func save() {
        _pendingSave?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let stored = StoredSettings(llm: self.llmConfig)
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
}
