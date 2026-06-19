import SwiftUI

/// 聚焦问题卡片的内容视图
/// 使用 @Bindable 直接绑定 Answer，避免自定义 Binding 导致 TextEditor 卡顿
struct FocusedCardContent: View {
    let question: QuestionTemplate
    let index: Int
    @Bindable var answer: Answer
    let project: Project
    let departments: [DepartmentTemplate]
    let selectedDepartmentId: String
    var aiOptions: [String]? = nil  // AI 增强的动态选项集

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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 问题序号 + 头部
            headerSection

            // 问题文本
            Text(question.question)
                .ahBody()
                .fontWeight(.medium)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, AHSpacing.l)
                .padding(.bottom, AHSpacing.s)

            // 蓝色强调线
            Rectangle()
                .fill(Color.ahAccentBorder)
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
                    .fill(.fill.tertiary)
                    .frame(width: 1)

                // 右：顾问笔记 + AI润色
                VStack(alignment: .leading, spacing: AHSpacing.xs) {
                    // 顾问记录
                    HStack {
                        Image(systemName: "pencil.line")
                            .ahCaption()
                            .foregroundStyle(Color.ahAccent)
                        Text("顾问记录")
                            .ahCaption()
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    TextEditor(text: $answer.noteText)
                        .ahCallout()
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 100, idealHeight: 140, maxHeight: 240)
                        .padding(AHSpacing.xs)
                        .background(Color.ahAccentBG, in: .rect(cornerRadius: AHRadius.sm))
                        .overlay(
                            RoundedRectangle(cornerRadius: AHRadius.sm)
                                .stroke(Color.ahAccentBorder, lineWidth: 0.5)
                        )
                        .onChange(of: answer.noteText) {
                            onNoteChanged()
                        }

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
                .background(Color.ahAccentBG)
            }

            if !followups.isEmpty {
                followupSection
            }

            // 快捷键提示
            HStack(spacing: AHSpacing.s) {
                Spacer()
                Text("⌘↑↓ 切题  ·  Tab 跳记录  ·  Enter 润色")
                    .ahCaption()
            }
            .foregroundStyle(.quaternary)
            .padding(.horizontal, AHSpacing.l)
            .padding(.vertical, AHSpacing.xxs)
        }
        .background(.background)
        .clipShape(.rect(cornerRadius: AHRadius.md))
        .shadow(color: (isFollowupQuestion ? Color.orange : Color.ahAccent).opacity(0.12), radius: 6, y: 2)
        .overlay(
            RoundedRectangle(cornerRadius: AHRadius.md)
                .stroke((isFollowupQuestion ? Color.orange : Color.ahAccent).opacity(0.35), lineWidth: 1.5)
        )
        .padding(.horizontal, AHSpacing.m)
        .padding(.vertical, AHSpacing.xxs)
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
                        .foregroundStyle(.orange)
                    Text("追问自:")
                        .ahCaption()
                        .foregroundStyle(.orange)
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
                    .ahCaption()
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(isFollowupQuestion ? Color.orange : Color.ahAccent, in: .circle)

                HStack(spacing: AHSpacing.xs) {
                    Text(question.topic)
                        .ahCaption()
                        .foregroundStyle(isFollowupQuestion ? .orange : Color.ahAccent)
                        .padding(.horizontal, AHSpacing.xs)
                        .padding(.vertical, 2)
                        .background((isFollowupQuestion ? Color.orange : Color.ahAccent).opacity(0.1), in: .capsule)
                    // 通用 / 行业标签
                    if question.industrySpecific == true {
                        Text(project.industryEnum.label)
                            .ahCaption()
                            .foregroundStyle(.blue)
                            .padding(.horizontal, AHSpacing.xxs)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.1), in: .capsule)
                    } else {
                        Text("通用")
                            .ahCaption()
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, AHSpacing.xxs)
                            .padding(.vertical, 2)
                            .background(Color.gray.opacity(0.1), in: .capsule)
                    }

                    if question.required {
                        Text("必答")
                            .ahCaption()
                            .foregroundStyle(.white)
                            .padding(.horizontal, AHSpacing.xxs)
                            .padding(.vertical, 2)
                            .background(.red, in: .capsule)
                    }
                    if answer.status == .ignored {
                        Text("已忽略")
                            .ahCaption()
                            .foregroundStyle(.white)
                            .padding(.horizontal, AHSpacing.xxs)
                            .padding(.vertical, 2)
                            .background(.gray, in: .capsule)
                    }
                    if answer.status == .transferred {
                        Text("已转移")
                            .ahCaption()
                            .foregroundStyle(.white)
                            .padding(.horizontal, AHSpacing.xxs)
                            .padding(.vertical, 2)
                            .background(.orange, in: .capsule)
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
                answer.selectedOptions = []
                answer.textValue = ""
                answer.otherText = ""
                answer.noteText = ""
                answer.polishedText = ""
                answer.voiceTranscript = ""
                answer.status = .unanswered
                onClear()
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

    /// 实际使用的选项：AI 动态选项 > 问题默认选项
    private var effectiveOptions: [String] {
        if let ai = aiOptions, !ai.isEmpty { return ai }
        return question.options ?? []
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
                            answer.otherText = newVal
                            syncTextValue()
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
                TextEditor(text: $answer.textValue)
                    .ahCallout()
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 80, maxHeight: 160)
                    .padding(AHSpacing.xs)
                    .background(.fill.quaternary, in: .rect(cornerRadius: AHRadius.sm))
                    .overlay(
                        RoundedRectangle(cornerRadius: AHRadius.sm)
                            .stroke(.fill.tertiary, lineWidth: 0.5)
                    )
                    .onChange(of: answer.textValue) {
                        markAnswered()
                        onAnswerChanged()
                    }
            }
        }
    }

    @ViewBuilder
    private func choiceRow(option: String) -> some View {
        let isSelected = isMultiChoice
            ? answer.selectedOptions.contains(option)
            : answer.selectedOptions.first == option

        HStack(spacing: AHSpacing.s) {
            Image(systemName: isMultiChoice
                  ? (isSelected ? "checkmark.square.fill" : "square")
                  : (isSelected ? "largecircle.fill.circle" : "circle"))
                .foregroundStyle(isSelected ? Color.ahAccent : .secondary)
                .ahCallout()
            Text(option)
                .ahCallout()
                .foregroundStyle(isSelected ? .primary : .secondary)
        }
        .padding(.vertical, AHSpacing.xxs)
        .padding(.horizontal, AHSpacing.xs)
        .background(isSelected ? Color.ahAccentBG : .clear, in: .rect(cornerRadius: AHRadius.xs))
        .contentShape(Rectangle())
        .onTapGesture {
            selectOption(option)
        }
    }

    @ViewBuilder
    private var otherOptionRow: some View {
        HStack(spacing: AHSpacing.s) {
            Image(systemName: isMultiChoice
                  ? (isOtherSelected ? "checkmark.square.fill" : "square")
                  : (isOtherSelected ? "largecircle.fill.circle" : "circle"))
                .foregroundStyle(isOtherSelected ? Color.ahAccent : .secondary)
                .ahCallout()
            Text("其他")
                .ahCallout()
                .foregroundStyle(isOtherSelected ? .primary : .secondary)
        }
        .padding(.vertical, AHSpacing.xxs)
        .padding(.horizontal, AHSpacing.xs)
        .background(isOtherSelected ? Color.ahAccentBG : .clear, in: .rect(cornerRadius: AHRadius.xs))
        .contentShape(Rectangle())
        .onTapGesture {
            selectOption("__other__")
        }
    }

    private func selectOption(_ option: String) {
        if isMultiChoice {
            if answer.selectedOptions.contains(option) {
                answer.selectedOptions.removeAll { $0 == option }
            } else {
                answer.selectedOptions.append(option)
            }
        } else {
            // 单选：如果选了"其他"，清掉之前的选项
            if option == "__other__" {
                answer.selectedOptions = ["__other__"]
            } else {
                answer.selectedOptions = [option]
                answer.otherText = ""
            }
        }
        syncTextValue()
        markAnswered()
        onAnswerChanged()
    }

    private func syncTextValue() {
        let display = answer.selectedOptions.map { opt in
            opt == "__other__" ? (answer.otherText.isEmpty ? "其他" : answer.otherText) : opt
        }
        answer.textValue = display.joined(separator: " | ")
    }

    // MARK: - AI Polish Section

    @ViewBuilder
    private var aiPolishSection: some View {
        VStack(alignment: .leading, spacing: AHSpacing.xxs) {
            HStack {
                Image(systemName: "wand.and.stars")
                    .ahCaption()
                    .foregroundStyle(.purple)
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
                        .foregroundStyle(.red)
                        .lineLimit(1)
                case .ready:
                    Text("已生成")
                        .ahCaption()
                        .foregroundStyle(.green)
                case .idle:
                    if isLLMConfigured {
                        Button {
                            onManualPolish()
                        } label: {
                            Text("手动润色")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }

            if polishStatus == .pending {
                Text("AI 润色生成中...")
                    .ahCaption()
                    .foregroundStyle(.tertiary)
                    .padding(AHSpacing.xs)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.ahAccentBG, in: .rect(cornerRadius: AHRadius.xs))
            } else if !answer.polishedText.isEmpty {
                TextEditor(text: $answer.polishedText)
                    .ahCaption()
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 60, idealHeight: 80, maxHeight: 140)
                    .padding(AHSpacing.xxs)
                    .background(Color.ahAccentBG, in: .rect(cornerRadius: AHRadius.xs))
                    .overlay(
                        RoundedRectangle(cornerRadius: AHRadius.xs)
                            .stroke(Color.purple.opacity(0.15), lineWidth: 0.5)
                    )
            } else if isLLMConfigured {
                Text("记录或转录后自动生成")
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
                    .foregroundStyle(Color.ahAccent)
                Text("AI 建议追问")
                    .ahCaption()
                    .fontWeight(.medium)
                    .foregroundStyle(Color.ahAccent)
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
                            .ahCaption()
                            .foregroundStyle(Color.ahAccent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(fq.question)
                                .ahCaption()
                                .fontWeight(.medium)
                            if !fq.method.isEmpty {
                                Text(fq.method)
                                    .ahCaption()
                                    .padding(.horizontal, AHSpacing.xxs)
                                    .padding(.vertical, 1)
                                    .background(Color.ahAccentBG, in: .capsule)
                                    .foregroundStyle(Color.ahAccent)
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
                .background(Color.ahAccentBG, in: .rect(cornerRadius: AHRadius.sm))
            }
        }
        .padding(.horizontal, AHSpacing.l)
        .padding(.vertical, AHSpacing.s)
        .background(Color.ahAccentBG.opacity(0.5))
    }

    // MARK: - Helpers

    private func markAnswered() {
        if answer.hasContent && answer.status == .unanswered {
            answer.status = .answered
        } else if !answer.hasContent {
            answer.status = .unanswered
        }
    }

}
