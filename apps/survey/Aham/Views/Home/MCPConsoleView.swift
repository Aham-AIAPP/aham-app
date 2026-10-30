import SwiftUI
import AppKit

/// 首页 —— MCP 控制台。
///
/// App 内已无「新建项目」入口：项目、题库、答案回写全部由 Claude / Codex 通过
/// MCP 驱动。所以首页要一次讲清三件事：服务是否在跑、怎么接、能让 AI 做什么。
struct MCPConsoleView: View {
    @Environment(MCPServer.self) private var server
    @Environment(MCPSettings.self) private var mcpSettings

    @State private var client: ClientKind = .claudeCode
    @State private var copiedHint: String?
    @State private var copiedExample: String?
    @State private var showTokenResetConfirm = false

    enum ClientKind: String, Hashable {
        case claudeCode = "Claude Code", codex = "Codex"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AHSpacing.xl) {
                hero
                serviceStatus
                setupCard
                toolsCard
                examplesCard
            }
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, AHSpacing.xxl)
            .padding(.vertical, AHSpacing.xxxl)
        }
        .background(Color.ahPaper)
        .onChange(of: client) { _, _ in copiedHint = nil; copiedExample = nil }
        .alert("重新生成 MCP Token？", isPresented: $showTokenResetConfirm) {
            Button("取消", role: .cancel) {}
            Button("重新生成", role: .destructive) {
                mcpSettings.regenerateToken()
                copiedHint = mcpSettings.lastPersistenceError == nil ? "Token 已更新，请重连 AI 客户端" : nil
            }
        } message: {
            Text("现有 AI 客户端连接会失效。配置路径不变，重新连接客户端以读取新 Token。")
        }
    }

    // MARK: - Hero

    @ViewBuilder
    private var hero: some View {
        VStack(alignment: .leading, spacing: AHSpacing.s) {
            AHIconTile(symbol: "doc.text.magnifyingglass", size: AHIconBox.hero, tint: .ahAccent)
                .padding(.bottom, AHSpacing.m)

            Text("Aham Survey").ahTitle()
            Text("调研数据的本地终端 · 项目与问卷由 MCP 驱动")
                .ahBody()
                .foregroundStyle(Color.ahInk60)
        }
    }

    // MARK: - 服务状态

    @ViewBuilder
    private var serviceStatus: some View {
        AHCard {
            AHSection("MCP 服务") {
                EmptyView()
            } trailing: {
                HStack(spacing: AHSpacing.s) {
                    if server.isRunning {
                        Button("停止") { server.stop() }
                            .buttonStyle(.ahGhost)
                    } else {
                        Button("启动服务") { server.start() }
                            .buttonStyle(.ahSecondary)
                    }
                }
            }

            VStack(alignment: .leading, spacing: AHSpacing.s) {
                HStack(spacing: AHSpacing.m) {
                    AHStatus(text: statusText, color: statusColor)
                    Text(mcpSettings.endpoint)
                        .ahMono(12)
                        .foregroundStyle(Color.ahInk60)
                        .textSelection(.enabled)
                }

                Text("Token ····\(mcpSettings.tokenFingerprint)")
                    .ahMono(11)
                    .foregroundStyle(Color.ahInk40)

                if case .failed(let message) = server.state {
                    Text(message)
                        .ahCaption()
                        .foregroundStyle(Color.ahDanger)
                }

                HStack(spacing: AHSpacing.m) {
                    Text("已处理 \(server.callCount) 次调用")
                        .ahCaption()
                        .foregroundStyle(Color.ahInk60)
                    if let summary = server.lastCallSummary {
                        Text("最近：\(summary)")
                            .ahCaption()
                            .foregroundStyle(Color.ahInk60)
                    }
                }

                Text("服务随 App 运行；关掉 App，Claude / Codex 就调不到了。")
                    .ahCaption()
                    .foregroundStyle(Color.ahInk40)
            }
            .padding(.top, AHSpacing.s)
        }
    }

    private var statusText: String {
        switch server.state {
        case .running:  "运行中"
        case .stopped:  "未启动"
        case .failed:   "启动失败"
        }
    }

    private var statusColor: Color {
        switch server.state {
        case .running:  .ahSuccess
        case .stopped:  .ahInk40
        case .failed:   .ahDanger
        }
    }

    // MARK: - 怎么接入

    @ViewBuilder
    private var setupCard: some View {
        AHCard {
            AHSection("怎么接入") {
                EmptyView()
            } trailing: {
                AHSegmentedTab(
                    selection: $client,
                    items: [
                        (ClientKind.claudeCode, "Claude Code", nil),
                        (ClientKind.codex, "Codex", nil)
                    ]
                )
            }

            VStack(alignment: .leading, spacing: AHSpacing.s) {
                if adapterPath == nil {
                    Text("未在 App 包内找到适配器脚本 aham-survey-mcp.mjs，请确认构建时已作为资源打包。")
                        .ahCaption()
                        .foregroundStyle(Color.ahDanger)
                }

                codeBlock(setupSnippet)

                HStack(spacing: AHSpacing.s) {
                    Button("复制配置") { copy(setupSnippet) }
                        .buttonStyle(.ahPrimary)
                        .disabled(adapterPath == nil)
                    Button("重新生成 Token") {
                        showTokenResetConfirm = true
                    }
                    .buttonStyle(.ahGhost)
                    Spacer(minLength: 0)
                    Text(copiedHint ?? "")
                        .ahMeta().foregroundStyle(Color.ahInk60)
                        .frame(width: 180, alignment: .trailing)
                        .lineLimit(2)
                        .accessibilityHidden(copiedHint == nil)
                }

                if let error = mcpSettings.lastPersistenceError {
                    Text(error).ahCallout().foregroundStyle(Color.ahDanger)
                }
                Text("需要 Node 18+。Token 保存在本机受限连接文件中，不会出现在复制命令里。")
                    .ahCaption()
                    .foregroundStyle(Color.ahInk40)
            }
            .padding(.top, AHSpacing.s)
        }
    }

    private var adapterPath: String? {
        Bundle.main.url(forResource: "aham-survey-mcp", withExtension: "mjs")?.path
    }

    private var setupSnippet: String {
        let path = adapterPath ?? "<App 包内 aham-survey-mcp.mjs 的路径>"
        return switch client {
        case .claudeCode: mcpSettings.claudeCodeCommand(adapterPath: path)
        case .codex:      mcpSettings.codexConfigSnippet(adapterPath: path)
        }
    }

    // MARK: - 能做什么

    @ViewBuilder
    private var toolsCard: some View {
        AHCard {
            AHSection("\(client.rawValue) 能做什么") {
                EmptyView()
            }

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(MCPTools.catalog.enumerated()), id: \.element.id) { index, tool in
                    if index > 0 { AHDivider() }
                    HStack(alignment: .top, spacing: AHSpacing.m) {
                        Text(tool.name)
                            .ahMono(12)
                            .foregroundStyle(Color.ahInk)
                            .frame(width: 150, alignment: .leading)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(tool.summary)
                                .ahCallout()
                                .foregroundStyle(Color.ahInk)
                            Text("参数：\(tool.arguments)")
                                .ahCaption()
                                .foregroundStyle(Color.ahInk40)
                        }

                        Spacer(minLength: 0)

                        if tool.isWrite {
                            AHPill(text: "写入")
                        }
                    }
                    .padding(.vertical, AHSpacing.s)
                }
            }
            .padding(.top, AHSpacing.xs)
        }
    }

    // MARK: - 开始使用

    private let examples = [
        "帮我给「苏州精越机械」建一个调研项目，范围 MES，行业装备制造，顾问写李成宝",
        "读一下这份访谈记录，按采购部的题目把答案回写进「苏州精越机械」的调研",
        "把「苏州精越机械」的调研报告导出成 Markdown 给我"
    ]

    @ViewBuilder
    private var examplesCard: some View {
        AHCard {
            AHSection("开始使用") {
                EmptyView()
            }

            VStack(alignment: .leading, spacing: AHSpacing.s) {
                Text("接好之后，可以这样向 \(client.rawValue) 描述任务：")
                    .ahCaption()
                    .foregroundStyle(Color.ahInk60)

                ForEach(examples, id: \.self) { example in
                    HStack(alignment: .top, spacing: AHSpacing.s) {
                        Text("•")
                            .ahCallout()
                            .foregroundStyle(Color.ahInk40)
                        Text(example)
                            .ahCallout()
                            .foregroundStyle(Color.ahInk)
                            .textSelection(.enabled)
                        Spacer(minLength: 0)
                        Button {
                            copy(example, example: example)
                        } label: {
                            Image(systemName: copiedExample == example ? "checkmark" : "doc.on.doc")
                                .frame(width: AHLayout.control, height: AHLayout.control)
                                .ahCaption()
                                .foregroundStyle(Color.ahInk40)
                        }
                        .buttonStyle(.ahInline)
                        .help(copiedExample == example ? "已复制" : "复制这句话")
                        .accessibilityLabel(copiedExample == example ? "这句话已复制" : "复制这句话")
                    }
                }
            }
            .padding(.top, AHSpacing.s)
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func codeBlock(_ text: String) -> some View {
        Text(text)
            .ahMono(12)
            .foregroundStyle(Color.ahInk)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AHSpacing.m)
            .background(Color.ahPaper, in: .rect(cornerRadius: AHRadius.md))
    }

    private func copy(_ text: String, example: String? = nil) {
        NSPasteboard.general.clearContents()
        let success = NSPasteboard.general.setString(text, forType: .string)
        if let example {
            copiedExample = success ? example : nil
        } else {
            copiedHint = success ? "配置已复制" : "无法写入剪贴板，请重试"
        }
    }
}
