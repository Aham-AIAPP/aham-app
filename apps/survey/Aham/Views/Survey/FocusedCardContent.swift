import SwiftUI
import SwiftData

/// 聚焦问题卡片的内容视图
/// 输入经服务层保存；草稿和已完成答案共享归档、修订与进度规则。
struct FocusedCardContent: View {
    let question: QuestionTemplate
    let index: Int
    let answer: Answer
    @Environment(AppStore.self) private var appStore
    @Environment(PluginLoader.self) private var pluginLoader
    @Environment(\.modelContext) private var modelContext
    let project: Project
    let departments: [DepartmentTemplate]
    let selectedDepartmentId: String

    // AI 回调
    var onIgnoreToggle: () -> Void = {}
    var onTransfer: (String) -> Void = { _ in }
    var onClear: () -> Void = {}
    var onAnswerChanged: () -> Void = {}
    var onNoteChanged: () -> Void = {}

    // AI 状态（从父视图传入）
    var polishStatus: PolishStatus = .idle
    var isLLMConfigured: Bool = false
    var onManualPolish: () -> Void = {}
    var followups: [AISurveyEnhancer.FollowupQuestion] = []
    var isLoadingFollowups: Bool = false
    var onDismissFollowups: () -> Void = {}
    var onAdoptFollowup: (Int) -> Void = { _ in }
    var onIgnoreFollowup: (Int) -> Void = { _ in }
    var triggerResults: [TriggerEngine.TriggerResult] = []

    // 追问关联
    var parentQuestionText: String? = nil
    var isFollowupQuestion: Bool = false

    @State private var confirmClear = false
    @State private var clearRevision = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if appStore.answerTextDrafts[answer.id] != nil {
                VStack(alignment: .leading, spacing: AHSpacing.s) {
                    Text("这条输入尚未保存，已保留在当前会话。请重试；如内容已被外部更新，可复制输入后放弃草稿查看最新值。")
                        .ahCallout().foregroundStyle(Color.ahDanger)
                    HStack {
                        Button("重试保存") { retryTextDraft() }.buttonStyle(.ahSecondary)
                        Button("放弃未保存输入") { appStore.answerTextDrafts[answer.id] = nil }.buttonStyle(.ahGhost)
                    }
                }.padding(AHSpacing.l)
            }
            // 问题序号 + 头部
            headerSection

            // 问题文本
            Text(question.question)
                .ahBody()
                .fontWeight(.medium)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, AHSpacing.l)
                .padding(.bottom, AHSpacing.s)

            // 分隔线（中性）
            Rectangle()
                .fill(Color.ahDivider)
                .frame(height: 1)
                .padding(.horizontal, AHSpacing.l)

            // 主体：左边问题输入 + 右边顾问笔记 + AI润色
            HStack(alignment: .top, spacing: 0) {
                // 左：答案输入
                VStack(alignment: .leading, spacing: AHSpacing.s) {
                    answerInputSection
                }
                .padding(AHSpacing.m)
                .frame(maxWidth: .infinity, alignment: .leading)

                Rectangle()
                    .fill(Color.ahDivider)
                    .frame(width: 1)

                // 右：顾问笔记 + AI润色
                VStack(alignment: .leading, spacing: AHSpacing.xs) {
                    // 顾问记录
                    HStack {
                        Image(systemName: "pencil.line")
                            .ahCaption()
                            .foregroundStyle(Color.ahInk60)
                        Text("顾问记录")
                            .ahCaption()
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    TextEditor(text: answerBinding(\.noteText))
                        .accessibilityLabel("顾问记录")
                        .ahCallout()
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 100, idealHeight: 140, maxHeight: 240)
                        .padding(AHSpacing.xs)
                        .background(Color.ahPaperAlt, in: .rect(cornerRadius: AHRadius.sm))
                        .overlay(
                            RoundedRectangle(cornerRadius: AHRadius.sm)
                                .stroke(Color.ahBorder, lineWidth: 1)
                        )


                    // AI 润色区域
                    aiPolishSection
                }
                .padding(AHSpacing.m)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 240)
            .opacity(answer.status == .ignored ? 0.4 : 1)

            // 底部：触发提示 + AI 追问
            if !triggerResults.isEmpty {
                VStack(alignment: .leading, spacing: AHSpacing.xxs) {
                    ForEach(triggerResults) { result in
                        HStack(alignment: .top, spacing: AHSpacing.xs) {
                            Image(systemName: triggerIcon(for: result.type))
                                .ahCaption()
                                .foregroundStyle(triggerColor(for: result.type))
                            Text(result.content)
                                .ahCaption()
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, AHSpacing.l)
                .padding(.vertical, AHSpacing.xs)
                .background(Color.ahPaperAlt)
            }

            if !followups.isEmpty {
                followupSection
            }

            // 快捷键提示
            HStack(spacing: AHSpacing.s) {
                Spacer()
                Text("⌘↑↓ 切题  ·  Tab 移动焦点  ·  ⌘⇧P 润色")
                    .ahCaption()
            }
            .foregroundStyle(.quaternary)
            .padding(.horizontal, AHSpacing.l)
            .padding(.vertical, AHSpacing.xxs)
        }
        .clipShape(.rect(cornerRadius: AHRadius.md))
        .overlay(alignment: .leading) {
            // 追问卡用左侧细 warning 条标识（非阴影、非整框）
            if isFollowupQuestion {
                Rectangle().fill(Color.ahWarning).frame(width: 2)
            }
        }
        .padding(.horizontal, AHSpacing.m)
        .padding(.vertical, AHSpacing.xxs)
        .confirmationDialog("清除当前题的答案、笔记和来源证据？", isPresented: $confirmClear) {
            Button("清除当前题", role: .destructive) {
                guard appStore.performWrite({
                    try SurveyService(context: modelContext, pluginLoader: pluginLoader)
                        .editAnswer(answer, in: project, expectedRevision: clearRevision) {
                            $0.selectedOptions = []; $0.textValue = ""; $0.otherText = ""
                            $0.noteText = ""; $0.polishedText = ""; $0.voiceTranscript = ""
                            $0.evidence = ""; $0.status = .unanswered
                        }
                }) else { return }
                appStore.answerTextDrafts[answer.id] = nil
                onClear()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作无法撤销。其他题目不受影响；如 MCP 已更新本题，将阻止清除。")
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: AHSpacing.xxs) {
            // 追问关联指示
            if isFollowupQuestion, let parent = parentQuestionText {
                HStack(spacing: AHSpacing.xxs) {
                    Image(systemName: "arrow.turn.down.right")
                        .ahCaption()
                        .foregroundStyle(Color.ahWarning)
                    Text("追问自:")
                        .ahCaption()
                        .foregroundStyle(Color.ahWarning)
                    Text(parent)
                        .ahCaption()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, AHSpacing.l)
                .padding(.top, AHSpacing.s)
            }

            HStack {
                Text("\(index + 1)")
                    .ahMono(12, weight: .bold)
                    .foregroundStyle(Color.ahOnAccent)
                    .frame(width: 22, height: 22)
                    .background(isFollowupQuestion ? Color.ahWarning : Color.ahAccent, in: .circle)

                HStack(spacing: AHSpacing.xs) {
                    // 主题 tag（中性）
                    neutralTag(question.topic)

                    // 通用 / 行业标签（中性 —— 靠文字区分）
                    neutralTag(question.industrySpecific == true ? project.industryEnum.label : "通用")

                    // 必答：文字 + 极弱 danger，不用色块（铁规）
                    if question.required {
                        Text("· 必答")
                            .ahCaption()
                            .foregroundStyle(Color.ahDanger)
                    }
                    // 状态：6px 点 + 文字（铁规）
                    if answer.status == .ignored {
                        AHStatus(text: "已忽略", color: .ahInk40)
                    }
                    if answer.status == .transferred {
                        AHStatus(text: "已转移", color: .ahWarning)
                    }
                }
                Spacer()
                actionButtons
            }
            .padding(.horizontal, AHSpacing.l)
            .padding(.top, isFollowupQuestion ? AHSpacing.xxs : AHSpacing.m)
            .padding(.bottom, AHSpacing.xs)
        }
    }

    // MARK: - Action Buttons

    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: AHSpacing.xs) {
            Button(role: .destructive) {
                clearRevision = answer.revision
                confirmClear = true
            } label: {
                Label("清除", systemImage: "trash")
            }
            .buttonStyle(.ahGhost)

            Button {
                onIgnoreToggle()
            } label: {
                Label(answer.status == .ignored ? "恢复" : "忽略",
                      systemImage: answer.status == .ignored ? "eye" : "eye.slash")
            }
            .buttonStyle(.ahGhost)

            Menu {
                ForEach(departments) { dept in
                    if dept.id != selectedDepartmentId {
                        Button {
                            onTransfer(dept.id)
                        } label: {
                            Label(dept.name, systemImage: dept.sfSymbol)
                        }
                    }
                }
            } label: {
                Label("转移", systemImage: "arrow.uturn.right")
            }
            .menuStyle(.button)
            .buttonStyle(.ahGhost)
            .fixedSize()
        }
    }

    // MARK: - Answer Input

    /// 实际使用的选项
    private var effectiveOptions: [String] {
        question.options ?? []
    }

    /// 是否为多选模式
    private var isMultiChoice: Bool {
        question.type == .multiChoice
    }

    /// "其他" 是否被选中
    private var isOtherSelected: Bool {
        answer.selectedOptions.contains("__other__")
    }

    @ViewBuilder
    private var answerInputSection: some View {
        let options = effectiveOptions

        if !options.isEmpty {
            // 统一选择题 UI
            VStack(alignment: .leading, spacing: AHSpacing.xxs) {
                ForEach(options, id: \.self) { option in
                    choiceRow(option: option)
                }

                // "其他" 选项（始终显示在最后）
                if !options.contains("其他") {
                    otherOptionRow
                }

                // "其他" 文本输入
                if isOtherSelected {
                    TextField("请补充...", text: Binding(
                        get: { answer.otherText },
                        set: { newVal in
                            if editAnswer({ record in
                                record.otherText = newVal
                                syncTextValue(record)
                            }) { onAnswerChanged() }
                        }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .ahCallout()
                    .padding(.leading, AHSpacing.xxxl)
                }
            }
        } else {
            // 无选项时退回文本输入
            VStack(alignment: .leading, spacing: AHSpacing.xxs) {
                Text("回答")
                    .ahCaption()
                TextEditor(text: answerBinding(\.textValue))
                    .accessibilityLabel("回答")
                    .ahCallout()
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 80, maxHeight: 160)
                    .padding(AHSpacing.xs)
                    .background(Color.ahPaperAlt, in: .rect(cornerRadius: AHRadius.sm))
                    .overlay(
                        RoundedRectangle(cornerRadius: AHRadius.sm)
                            .stroke(Color.ahBorder, lineWidth: 1)
                    )

            }
        }
    }

    @ViewBuilder
    private func choiceRow(option: String) -> some View {
        let isSelected = isMultiChoice
            ? answer.selectedOptions.contains(option)
            : answer.selectedOptions.first == option

        Button { selectOption(option) } label: {
        HStack(spacing: AHSpacing.s) {
            Image(systemName: isMultiChoice
                  ? (isSelected ? "checkmark.square.fill" : "square")
                  : (isSelected ? "largecircle.fill.circle" : "circle"))
                .foregroundStyle(isSelected ? Color.ahInk : .ahInk60)
                .ahCallout()
            Text(option)
                .ahCallout()
                .foregroundStyle(Color.ahInk)
        }
        .padding(.vertical, AHSpacing.xxs)
        .padding(.horizontal, AHSpacing.xs)
        .background(isSelected ? Color.ahSelected : .clear, in: .rect(cornerRadius: AHRadius.xs))
        .contentShape(Rectangle())
        .frame(maxWidth: .infinity, minHeight: AHLayout.control, alignment: .leading)
        }
        .buttonStyle(.ahGhost)
        .accessibilityLabel(option)
        .accessibilityValue(isSelected ? "已选中" : "未选中")

    }

    @ViewBuilder
    private var otherOptionRow: some View {
        Button { selectOption("__other__") } label: {
        HStack(spacing: AHSpacing.s) {
            Image(systemName: isMultiChoice
                  ? (isOtherSelected ? "checkmark.square.fill" : "square")
                  : (isOtherSelected ? "largecircle.fill.circle" : "circle"))
                .foregroundStyle(isOtherSelected ? Color.ahInk : .ahInk60)
                .ahCallout()
            Text("其他")
                .ahCallout()
                .foregroundStyle(Color.ahInk)
        }
        .padding(.vertical, AHSpacing.xxs)
        .padding(.horizontal, AHSpacing.xs)
        .background(isOtherSelected ? Color.ahSelected : .clear, in: .rect(cornerRadius: AHRadius.xs))
        .contentShape(Rectangle())
        .frame(maxWidth: .infinity, minHeight: AHLayout.control, alignment: .leading)
        }
        .buttonStyle(.ahGhost)
        .accessibilityLabel("其他")
        .accessibilityValue(isOtherSelected ? "已选中" : "未选中")

    }

    private func selectOption(_ option: String) {
        if editAnswer({ record in
            if isMultiChoice {
                if record.selectedOptions.contains(option) {
                    record.selectedOptions.removeAll { $0 == option }
                } else { record.selectedOptions.append(option) }
            } else { record.selectedOptions = [option] }
            if !record.selectedOptions.contains("__other__") { record.otherText = "" }
            syncTextValue(record)
        }) { onAnswerChanged() }
    }

    private func syncTextValue(_ record: Answer) {
        record.textValue = record.selectedOptions.map {
            $0 == "__other__" ? (record.otherText.isEmpty ? "其他" : record.otherText) : $0
        }.joined(separator: " | ")
    }

    // MARK: - AI Polish Section

    @ViewBuilder
    private var aiPolishSection: some View {
        VStack(alignment: .leading, spacing: AHSpacing.xxs) {
            HStack {
                Image(systemName: "wand.and.stars")
                    .ahCaption()
                    .foregroundStyle(Color.ahInk60)
                Text("AI 润色")
                    .ahCaption()
                    .foregroundStyle(.secondary)
                Spacer()

                switch polishStatus {
                case .pending:
                    HStack(spacing: AHSpacing.xxs) {
                        ProgressView()
                            .controlSize(.mini)
                        Text("生成中...")
                            .ahCaption()
                            .foregroundStyle(Color.ahAccent)
                    }
                case .error(let msg):
                    Text("失败: \(msg)")
                        .ahCaption()
                        .foregroundStyle(Color.ahDanger)
                        .help(msg)
                case .ready:
                    Text("已生成")
                        .ahCaption()
                        .foregroundStyle(Color.ahSuccess)
                case .idle:
                    EmptyView()
                }

                // 润色改为手动触发后，按钮在生成中之外的所有状态都要在
                // —— 否则答案改完就再也无法重新润色
                Group {
                    Button {
                        onManualPolish()
                    } label: {
                        Text(polishStatus == .idle ? "润色 ⌘⇧P" : "重新润色")
                    }
                    .buttonStyle(.ahSecondary)
                    .keyboardShortcut("p", modifiers: [.command, .shift])
                    .disabled(!isLLMConfigured || polishStatus == .pending || (!answer.hasContent && answer.noteText.isEmpty && answer.voiceTranscript.isEmpty))
                    .help(isLLMConfigured ? "用 AI 整理这条记录（⌘⇧P）" : "请先在设置中配置 API Key")
                }
            }

            if polishStatus == .pending {
                Text("AI 润色生成中...")
                    .ahCaption()
                    .foregroundStyle(.tertiary)
                    .padding(AHSpacing.xs)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.ahPaperAlt, in: .rect(cornerRadius: AHRadius.xs))
            }
            if !answer.polishedText.isEmpty {
                TextEditor(text: answerBinding(\.polishedText))
                    .accessibilityLabel("AI 润色结果")
                    .ahCaption()
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 60, idealHeight: 80, maxHeight: 140)
                    .padding(AHSpacing.xxs)
                    .background(Color.ahPaperAlt, in: .rect(cornerRadius: AHRadius.xs))
                    .overlay(
                        RoundedRectangle(cornerRadius: AHRadius.xs)
                            .stroke(Color.ahBorder, lineWidth: 1)
                    )
            } else if isLLMConfigured {
                Text("点击润色生成建议，原始记录仍会保留。")
                    .ahCaption()
                    .padding(AHSpacing.xxs)
            }
        }
    }

    // MARK: - AI Followup Section

    @ViewBuilder
    private var followupSection: some View {
        VStack(alignment: .leading, spacing: AHSpacing.xs) {
            HStack(spacing: AHSpacing.xxs) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .ahCaption()
                    .foregroundStyle(Color.ahInk60)
                Text("AI 建议追问")
                    .ahCaption()
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.ahInk)
                if isLoadingFollowups {
                    ProgressView()
                        .controlSize(.mini)
                }
                Spacer()
                Button {
                    onDismissFollowups()
                } label: {
                    Image(systemName: "xmark")
                        .ahCaption()
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }

            ForEach(Array(followups.enumerated()), id: \.offset) { idx, fq in
                VStack(alignment: .leading, spacing: AHSpacing.xxs) {
                    HStack(alignment: .top, spacing: AHSpacing.xs) {
                        Text("\(idx + 1).")
                            .ahMono(12)
                            .foregroundStyle(Color.ahInk40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(fq.question)
                                .ahCaption()
                                .fontWeight(.medium)
                            if !fq.method.isEmpty {
                                Text(fq.method)
                                    .ahCaption()
                                    .padding(.horizontal, AHSpacing.xxs)
                                    .padding(.vertical, 1)
                                    .background(Color.ahPaperAlt, in: .capsule)
                                    .foregroundStyle(Color.ahInk60)
                            }
                            if !fq.reason.isEmpty {
                                Text(fq.reason)
                                    .ahCaption()
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        Spacer()
                    }

                    // 采纳 / 忽略按钮
                    HStack(spacing: AHSpacing.s) {
                        Spacer()
                        Button {
                            onIgnoreFollowup(idx)
                        } label: {
                            Label("忽略", systemImage: "xmark")
                        }
                        .buttonStyle(.ahSecondary)

                        Button {
                            onAdoptFollowup(idx)
                        } label: {
                            Label("采纳", systemImage: "checkmark")
                        }
                        .buttonStyle(.ahPrimary)
                    }
                }
                .padding(AHSpacing.s)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.ahPaper, in: .rect(cornerRadius: AHRadius.sm))
            }
        }
        .padding(.horizontal, AHSpacing.l)
        .padding(.vertical, AHSpacing.s)
        .background(Color.ahPaperAlt)
    }

    // MARK: - Helpers

    /// 中性标签（铁规：tag 无色相，靠文字区分）。
    private func neutralTag(_ text: String) -> some View {
        Text(text)
            .ahCaption()
            .foregroundStyle(Color.ahInk60)
            .padding(.horizontal, AHSpacing.xs)
            .padding(.vertical, 2)
            .background(Color.ahPaperAlt, in: .capsule)
    }

    @discardableResult
    private func editAnswer(_ apply: (Answer) -> Void) -> Bool {
        appStore.performWrite {
            try SurveyService(context: modelContext, pluginLoader: pluginLoader)
                .editAnswer(answer, in: project, apply: apply)
        }
    }

    private func retryTextDraft() {
        guard let draft = appStore.answerTextDrafts[answer.id] else { return }
        if appStore.performWrite({
            try SurveyService(context: modelContext, pluginLoader: pluginLoader)
                .editAnswer(answer, in: project, expectedRevision: draft.revision) { record in
                    for (key, value) in draft.fields { record[keyPath: key] = value }
                }
        }) {
            appStore.answerTextDrafts[answer.id] = nil
            onAnswerChanged()
        }
    }

    private func answerBinding(_ keyPath: ReferenceWritableKeyPath<Answer, String>) -> Binding<String> {
        Binding(get: { appStore.answerTextDrafts[answer.id]?.fields[keyPath] ?? answer[keyPath: keyPath] }, set: { value in
            var draft = appStore.answerTextDrafts[answer.id] ?? .init(revision: answer.revision)
            draft.fields[keyPath] = value
            appStore.answerTextDrafts[answer.id] = draft
            retryTextDraft()
            if keyPath == \Answer.noteText { onNoteChanged() }
        })
    }
}
