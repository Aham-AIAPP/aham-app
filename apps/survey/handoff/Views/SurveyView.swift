import SwiftUI
import SwiftData

// SurveyView V3
// ────────────────────────────────────────────────────────────────────────
// V3 重构要点（vs V2）：
//
//   1. 顶部部门 Tab 栏：
//      - V2：Tab 下方 2pt 强调线 + 数字大小只有 caption2
//      - V3：整个 tab 做成"胶囊选中"，保留数字但用 AHPill 独立显示进度
//      - 去掉 Tab 栏底部的 Divider，改为 ahPaperBar 背景分区
//
//   2. AI / 麦克风状态指示器：
//      - 迁移到 AHPill（更小，颜色更节制）
//      - 录音时红色胶囊带微微呼吸动画
//
//   3. 左侧问题侧边栏：
//      - 改用 AHCard 分组 Section 头
//      - 问题行用 AHStatusDot + 文本，焦点态用 ahAccentBG 背景
//      - 追问缩进 + 橙色 turn-down 图标保持
//
//   4. 中间聚焦区：
//      - 三卡片布局保留（相邻上/下预览 + 中间焦点）
//      - 焦点卡用 AHCard 容器（更强的视觉权重）
//      - 相邻卡片 ghost 状态 —— 半透明 + 更小字号
//
//   5. 进度条：
//      - 顶部胶囊化进度条，左右侧信息更紧凑
//
//   6. 底部导航：
//      - 跳转圆点行改为 horizontal scroll，超过 20 个时不截断
//      - 改用 AHGhost 按钮样式
//
// ⚠️ 所有状态管理、AI 调度、录音逻辑、追问采纳等代码保持 V2 不变。
//    V3 只改装饰层。

struct SurveyView: View {
    @Bindable var project: Project
    @Environment(PluginLoader.self) var pluginLoader
    @Environment(\.modelContext) var modelContext
    @Query var allAnswers: [Answer]
    @Environment(SpeechRecognitionService.self) var speechService
    @Environment(SettingsManager.self) var settings

    @State var selectedDepartmentId: String?
    @State var focusedQuestionIndex: Int = 0

    // AI 润色 / 追问
    @State var enhancer: AISurveyEnhancer?
    @State var polishStatus: PolishStatus = .idle
    @State var polishTask: Task<Void, Never>?
    @State var followups: [AISurveyEnhancer.FollowupQuestion] = []
    @State var isLoadingFollowups = false
    @State var followupTask: Task<Void, Never>?

    // 备忘录
    @State var memoExpanded = false
    @State var memoItems: [MemoCategory: [String]] = [
        .forms: [], .metrics: [], .approvals: [], .needs: []
    ]
    @State var newMemoText = ""
    @State var activeMemoCategory: MemoCategory = .forms

    @State var adoptedFollowups: [AdoptedFollowup] = []
    @State var answerLookup: [String: Answer] = [:]
    @State var cachedDisplayQuestions: [QuestionTemplate] = []
    @State var cachedFollowupIds: Set<String> = []
    @State private var cachedExclusionIds: Set<String> = []

    // MARK: - 业务方法（V2 原样保留）

    func baseQuestions(for deptId: String) -> [QuestionTemplate] {
        var base = pluginLoader.questions(for: deptId, scopes: project.surveyScopes, industry: project.industryEnum)
        let extra = KnowledgeQuestionStore().questions(for: deptId)
        if !extra.isEmpty { base.append(contentsOf: extra) }
        if !cachedExclusionIds.isEmpty {
            base = base.filter { !cachedExclusionIds.contains($0.id) }
        }
        if let skips = project.aiEnhancement?.skipSuggestions {
            base = base.filter { !skips.contains($0.id) }
        }
        return base
    }

    private var currentSections: [(section: QuestionSection, questions: [QuestionTemplate])] {
        let questions = cachedDisplayQuestions.filter { !cachedFollowupIds.contains($0.id) }
        guard !questions.isEmpty else { return [] }
        var result: [(QuestionSection, [QuestionTemplate])] = []
        for section in QuestionSection.allCases {
            let sectionQuestions = questions.filter { $0.section == section }
            if !sectionQuestions.isEmpty {
                result.append((section, sectionQuestions))
            }
        }
        return result
    }

    var isAIAvailable: Bool { settings.isLLMConfigured }
    var isRecordingAvailable: Bool {
        speechService.micPermissionGranted && speechService.speechPermissionGranted
    }

    private func parentQuestionText(for questionId: String) -> String? {
        guard let fu = adoptedFollowups.first(where: { $0.template.id == questionId }) else { return nil }
        return cachedDisplayQuestions.first(where: { $0.id == fu.parentQuestionId })?.question
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            departmentTabBar
            questionProgressBar

            HStack(spacing: 0) {
                questionNavSidebar.frame(width: 220)
                Divider().overlay(Color.ahDivider)
                questionFocusArea.frame(maxWidth: .infinity)
                Divider().overlay(Color.ahDivider)
                surveyRightPanel.frame(width: 300)
            }
        }
        .background(Color.ahPaper)
        .onAppear { initialLoad() }
        .onDisappear {
            polishTask?.cancel()
            followupTask?.cancel()
        }
        .onChange(of: selectedDepartmentId) {
            focusedQuestionIndex = 0
            resetAIState()
            ensureAnswersExist()
            rebuildDisplayQuestions()
        }
        .onChange(of: allAnswers.count) { rebuildAnswerLookup() }
        .onChange(of: focusedQuestionIndex) { _, _ in resetAIState() }
        .onChange(of: speechService.latestConfirmedText) { _, newText in
            guard !newText.isEmpty else { return }
            autoFillConfirmedSegment(newText)
        }
    }

    private func initialLoad() {
        if selectedDepartmentId == nil,
           let first = project.selectedDepartmentIds.first {
            selectedDepartmentId = first
        }
        cachedExclusionIds = project.usesQuestionExclusions ? QuestionExclusionStore().load() : []
        rebuildAnswerLookup()
        ensureAnswersExist()
        rebuildDisplayQuestions()
        Task { await speechService.checkPermissions() }
    }

    // MARK: - 顶部部门 Tab（V3）

    @ViewBuilder
    private var departmentTabBar: some View {
        let departments = pluginLoader.selectedDepartments(ids: project.selectedDepartmentIds)
        HStack(spacing: AHSpacing.s) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AHSpacing.xs) {
                    ForEach(departments) { dept in
                        departmentTabButton(for: dept)
                    }
                }
                .padding(.horizontal, AHSpacing.m)
            }

            Spacer(minLength: AHSpacing.s)

            // AI / 麦克风 状态
            HStack(spacing: AHSpacing.xs) {
                AHPill(
                    text: "AI",
                    icon: isAIAvailable ? "checkmark.circle.fill" : "xmark.circle",
                    style: isAIAvailable ? .success : .neutral
                )
                .help(isAIAvailable ? "AI 已连接" : "请在设置中配置 API Key")

                AHPill(
                    text: speechService.isRecording ? "录音中" : "麦克风",
                    icon: speechService.isRecording ? "mic.fill" : "mic",
                    style: speechService.isRecording ? .danger : (isRecordingAvailable ? .success : .neutral)
                )
                .help(speechService.isRecording ? "正在录音"
                      : isRecordingAvailable ? "可用"
                      : "请授予麦克风与语音识别权限")
            }
            .padding(.trailing, AHSpacing.m)
        }
        .padding(.vertical, AHSpacing.s)
        .background(Color.ahPaperBar)
    }

    @ViewBuilder
    private func departmentTabButton(for dept: DepartmentTemplate) -> some View {
        let isSelected = selectedDepartmentId == dept.id
        let deptTotal  = baseQuestions(for: dept.id).count
        let deptDone   = answeredCount(for: dept.id)
        let completed  = deptDone == deptTotal && deptTotal > 0

        Button {
            withAnimation(AHAnimation.quick) { selectedDepartmentId = dept.id }
        } label: {
            HStack(spacing: AHSpacing.xs) {
                Image(systemName: dept.sfSymbol)
                    .font(.system(size: 11, weight: .semibold))
                Text(dept.name)
                    .font(.callout.weight(isSelected ? .semibold : .regular))
                Text("\(deptDone)/\(deptTotal)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(completed ? Color.ahSuccess : .secondary)
            }
            .foregroundStyle(isSelected ? Color.ahInk : Color.ahInk60)
            .padding(.horizontal, AHSpacing.m)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: AHRadius.md, style: .continuous)
                    .fill(isSelected ? Color.ahPaperAlt : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AHRadius.md, style: .continuous)
                    .strokeBorder(isSelected ? Color.ahBorder : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 顶部进度条

    @ViewBuilder
    private var questionProgressBar: some View {
        let total = cachedDisplayQuestions.count
        let answered = answeredCount(for: selectedDepartmentId ?? "")
        let progress = total > 0 ? Double(answered) / Double(total) : 0

        HStack(spacing: AHSpacing.m) {
            HStack(spacing: AHSpacing.xxs) {
                Text("\(answered)").ahMono(13, weight: .semibold).foregroundStyle(.primary)
                Text("/").ahMono(13).foregroundStyle(.tertiary)
                Text("\(total)").ahMono(13).foregroundStyle(.secondary)
                Text("完成").font(.caption).foregroundStyle(.secondary)
            }
            .frame(width: 100, alignment: .leading)

            ProgressView(value: progress)
                .tint(progress >= 1 ? Color.ahSuccess : Color.ahAccent)

            Text("第 \(focusedQuestionIndex + 1) / \(total) 题")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .fixedSize()
        }
        .padding(.horizontal, AHSpacing.l)
        .padding(.vertical, AHSpacing.xs)
        .background(Color.ahPaper)
        .overlay(
            Rectangle().fill(Color.ahDivider).frame(height: 1),
            alignment: .bottom
        )
    }

    // MARK: - 左侧问题侧边栏

    @ViewBuilder
    private var questionNavSidebar: some View {
        VStack(spacing: 0) {
            if let deptId = selectedDepartmentId,
               let dept = pluginLoader.departments.first(where: { $0.id == deptId }) {
                HStack(spacing: AHSpacing.xs) {
                    AHIconTile(symbol: dept.sfSymbol, size: AHIconBox.xs, tint: Color.ahAccent)
                    Text(dept.name).font(.callout.weight(.semibold))
                    Spacer()
                }
                .padding(.horizontal, AHSpacing.m)
                .padding(.vertical, AHSpacing.s)
                .background(Color.ahPaperBar)
                Divider().overlay(Color.ahDivider)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: AHSpacing.s, pinnedViews: []) {
                        ForEach(currentSections, id: \.section) { section, questions in
                            sectionHeader(section, questions: questions)
                            ForEach(questions) { question in
                                sidebarQuestionRow(question: question)
                                let deptId = selectedDepartmentId ?? ""
                                let childFollowups = adoptedFollowups.filter {
                                    $0.parentQuestionId == question.id && $0.departmentId == deptId
                                }
                                ForEach(childFollowups) { fu in
                                    sidebarQuestionRow(question: fu.template, isFollowup: true)
                                }
                            }
                        }
                    }
                    .padding(AHSpacing.s)
                }
                .onChange(of: focusedQuestionIndex) {
                    if focusedQuestionIndex < cachedDisplayQuestions.count {
                        let q = cachedDisplayQuestions[focusedQuestionIndex]
                        withAnimation(AHAnimation.standard) {
                            proxy.scrollTo(q.id, anchor: .center)
                        }
                    }
                }
            }
        }
        .background(Color.ahPaper)
    }

    private func sectionHeader(_ section: QuestionSection, questions: [QuestionTemplate]) -> some View {
        let sectionDone = questions.filter { q in
            let a = findAnswer(for: q.id, departmentId: selectedDepartmentId ?? "")
            return a?.hasContent ?? false
        }.count

        return HStack(spacing: AHSpacing.xxs) {
            Image(systemName: section.icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(section == .painpoint ? Color.ahDanger : Color.ahAccent)
            Text(section.label).ahSectionLabel()
            Spacer()
            if sectionDone > 0 {
                Text("\(sectionDone)/\(questions.count)")
                    .ahMono(10)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, AHSpacing.xs)
        .padding(.top, AHSpacing.xs)
    }

    @ViewBuilder
    private func sidebarQuestionRow(question: QuestionTemplate, isFollowup: Bool = false) -> some View {
        let globalIndex = globalQuestionIndex(for: question)
        let answer = findAnswer(for: question.id, departmentId: selectedDepartmentId ?? "")
        let isFocused = focusedQuestionIndex == globalIndex

        Button {
            withAnimation(AHAnimation.quick) { focusedQuestionIndex = globalIndex }
        } label: {
            HStack(spacing: AHSpacing.xs) {
                if isFollowup {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.ahWarning)
                }
                AHStatusDot(color: statusColor(for: answer))
                Text(question.question)
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(isFocused ? Color.ahInk : Color.ahInk60)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 5)
            .padding(.horizontal, AHSpacing.xs)
            .padding(.leading, isFollowup ? AHSpacing.m : 0)
            .background(
                RoundedRectangle(cornerRadius: AHRadius.sm)
                    .fill(isFocused
                          ? (isFollowup ? Color.ahWarning.opacity(0.12) : Color.ahAccentBG)
                          : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .id(question.id)
    }

    // MARK: - 中间聚焦区

    @ViewBuilder
    private var questionFocusArea: some View {
        if cachedDisplayQuestions.isEmpty {
            AHEmptyState(
                symbol: "building.2",
                title: "选择部门",
                message: "从顶部选择一个部门开始调研"
            )
        } else {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: AHSpacing.xs) {
                        let questions = cachedDisplayQuestions
                        let fi = focusedQuestionIndex
                        let count = questions.count

                        let indices: (prev: Int?, next: Int?) = {
                            if count <= 1 { return (nil, nil) }
                            if fi == 0 { return (nil, 1) }
                            if fi >= count - 1 { return (fi - 1, nil) }
                            return (fi - 1, fi + 1)
                        }()

                        if fi == 0, count > 2 {
                            // 先走到正式卡片
                        } else if fi >= count - 1, fi - 2 >= 0 {
                            adjacentCard(question: questions[fi - 2], index: fi - 2)
                        }
                        if let prev = indices.prev {
                            adjacentCard(question: questions[prev], index: prev)
                        }
                        if fi < count {
                            focusedCardWrapper(fi: fi, questions: questions)
                        }
                        if let next = indices.next {
                            adjacentCard(question: questions[next], index: next)
                        }
                        if fi == 0, count > 2 {
                            adjacentCard(question: questions[2], index: 2)
                        }
                    }
                    .padding(.vertical, AHSpacing.m)
                    .padding(.horizontal, AHSpacing.m)
                }

                memoBar
                questionNavigationBar
            }
        }
    }

    @ViewBuilder
    private func focusedCardWrapper(fi: Int, questions: [QuestionTemplate]) -> some View {
        let question = questions[fi]
        if let answer = findAnswer(for: question.id, departmentId: selectedDepartmentId ?? "") {
            let triggerResults: [TriggerEngine.TriggerResult] = {
                guard let triggers = question.triggers, !triggers.isEmpty, answer.hasContent else { return [] }
                return TriggerEngine.evaluate(
                    triggers: triggers,
                    answer: answer.textValue,
                    selectedOptions: answer.selectedOptions
                )
            }()

            FocusedCardContent(
                question: question, index: fi, answer: answer,
                project: project,
                departments: pluginLoader.selectedDepartments(ids: project.selectedDepartmentIds),
                selectedDepartmentId: selectedDepartmentId ?? "",
                aiOptions: project.aiEnhancement?.optionSets[question.id],
                onIgnoreToggle: {
                    answer.status = answer.status == .ignored ? .unanswered : .ignored
                },
                onTransfer: { deptId in
                    answer.status = .transferred
                    if let dept = pluginLoader.departments.first(where: { $0.id == deptId }) {
                        answer.noteText += "\n[转移至: \(dept.name)]"
                    }
                },
                onClear: { resetAIState() },
                onAnswerChanged: {
                    scheduleFollowups(question: question, answer: answer)
                    scheduleAIPolish(question: question, answer: answer)
                },
                onNoteChanged: { scheduleAIPolish(question: question, answer: answer) },
                polishStatus: polishStatus,
                isLLMConfigured: settings.isLLMConfigured,
                onManualPolish: { scheduleAIPolish(question: question, answer: answer) },
                followups: followups,
                isLoadingFollowups: isLoadingFollowups,
                onDismissFollowups: { followups = [] },
                onAdoptFollowup: { idx in adoptFollowup(at: idx, parentQuestion: question) },
                onIgnoreFollowup: { idx in ignoreFollowup(at: idx) },
                triggerResults: triggerResults,
                parentQuestionText: parentQuestionText(for: question.id),
                isFollowupQuestion: cachedFollowupIds.contains(question.id)
            )
            .padding(AHSpacing.s)
            .background(
                RoundedRectangle(cornerRadius: AHRadius.xl, style: .continuous)
                    .fill(Color.ahPaperAlt)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AHRadius.xl, style: .continuous)
                    .strokeBorder(Color.ahAccentBorder, lineWidth: 1.5)
            )
            .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
        }
    }

    @ViewBuilder
    private func adjacentCard(question: QuestionTemplate, index: Int) -> some View {
        let answer = findAnswer(for: question.id, departmentId: selectedDepartmentId ?? "")
        let isFollowup = cachedFollowupIds.contains(question.id)

        Button {
            withAnimation(AHAnimation.standard) { focusedQuestionIndex = index }
        } label: {
            HStack(spacing: AHSpacing.s) {
                if isFollowup {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.ahWarning)
                }
                Text("\(index + 1)")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(isFollowup ? Color.ahWarning : .secondary)
                    .frame(width: 18, height: 18)
                    .background(
                        Circle().fill(isFollowup ? Color.ahWarning.opacity(0.15) : Color.ahPaper)
                    )
                AHStatusDot(color: statusColor(for: answer))
                VStack(alignment: .leading, spacing: 2) {
                    Text(question.topic).ahCaption().foregroundStyle(Color.ahAccent.opacity(0.7))
                    Text(question.question).font(.callout).lineLimit(2).foregroundStyle(.secondary)
                }
                Spacer()
                if let ans = answer, ans.hasContent {
                    Text(String(ans.textValue.prefix(30)) + (ans.textValue.count > 30 ? "..." : ""))
                        .font(.caption).foregroundStyle(.tertiary).lineLimit(1)
                        .frame(maxWidth: 150, alignment: .trailing)
                }
                Image(systemName: index < focusedQuestionIndex ? "chevron.down" : "chevron.up")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, AHSpacing.m)
            .padding(.vertical, AHSpacing.s)
            .background(
                RoundedRectangle(cornerRadius: AHRadius.md).fill(Color.ahPaperAlt.opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AHRadius.md).strokeBorder(Color.ahBorder, lineWidth: 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 底部导航

    @ViewBuilder
    private var questionNavigationBar: some View {
        HStack(spacing: AHSpacing.s) {
            Button {
                if focusedQuestionIndex > 0 {
                    withAnimation(AHAnimation.standard) { focusedQuestionIndex -= 1 }
                }
            } label: {
                Label("上一题", systemImage: "chevron.left")
            }
            .buttonStyle(.ahGhost)
            .disabled(focusedQuestionIndex <= 0)
            .keyboardShortcut(.upArrow, modifiers: .command)

            Spacer()

            // 跳转圆点
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(Array(cachedDisplayQuestions.enumerated()), id: \.offset) { idx, q in
                        let answer = findAnswer(for: q.id, departmentId: selectedDepartmentId ?? "")
                        Button {
                            withAnimation(AHAnimation.quick) { focusedQuestionIndex = idx }
                        } label: {
                            Circle()
                                .fill(idx == focusedQuestionIndex ? Color.ahAccent : statusColor(for: answer))
                                .frame(width: idx == focusedQuestionIndex ? 8 : 6,
                                       height: idx == focusedQuestionIndex ? 8 : 6)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxWidth: 260)

            Spacer()

            Button {
                if focusedQuestionIndex < cachedDisplayQuestions.count - 1 {
                    withAnimation(AHAnimation.standard) { focusedQuestionIndex += 1 }
                }
            } label: {
                HStack(spacing: 4) {
                    Text("下一题")
                    Image(systemName: "chevron.right")
                }
            }
            .buttonStyle(.ahGhost)
            .disabled(cachedDisplayQuestions.isEmpty || focusedQuestionIndex >= cachedDisplayQuestions.count - 1)
            .keyboardShortcut(.downArrow, modifiers: .command)
        }
        .padding(.horizontal, AHSpacing.l)
        .padding(.vertical, AHSpacing.s)
        .background(Color.ahPaperBar)
        .overlay(Rectangle().fill(Color.ahDivider).frame(height: 1), alignment: .top)
    }

    // MARK: - 业务方法（完整保留 V2）

    func getEnhancer() -> AISurveyEnhancer {
        if let enhancer { return enhancer }
        let newEnhancer = AISurveyEnhancer(settings: settings)
        enhancer = newEnhancer
        return newEnhancer
    }

    func scheduleAIPolish(question: QuestionTemplate, answer: Answer) {
        guard settings.isLLMConfigured else { return }
        let hasLiveTranscript = speechService.isRecording && !speechService.latestConfirmedText.isEmpty
        guard answer.hasContent || !answer.noteText.isEmpty || !answer.voiceTranscript.isEmpty || hasLiveTranscript else { return }

        polishTask?.cancel()
        polishStatus = .pending
        let enhancer  = getEnhancer()
        let deptId    = selectedDepartmentId ?? ""
        let transcript = answer.voiceTranscript

        polishTask = Task { @MainActor in
            guard !Task.isCancelled else { polishStatus = .idle; return }
            if let result = await enhancer.polishNote(
                project: project, department: deptId,
                question: question.question, answer: answer.textValue,
                note: answer.noteText, transcript: transcript
            ) {
                guard !Task.isCancelled else { return }
                answer.polishedText = result.polished
                for (key, items) in result.extracts {
                    let category: MemoCategory? = switch key {
                    case "forms": .forms
                    case "metrics": .metrics
                    case "approvals": .approvals
                    case "needs": .needs
                    default: nil
                    }
                    if let cat = category {
                        for item in items where !item.isEmpty {
                            var existing = memoItems[cat] ?? []
                            let isDuplicate = existing.contains(where: {
                                $0.localizedCaseInsensitiveCompare(item) == .orderedSame ||
                                $0.localizedCaseInsensitiveContains(item) ||
                                item.localizedCaseInsensitiveContains($0)
                            })
                            if !isDuplicate, existing.count < 20 {
                                existing.append(item); memoItems[cat] = existing
                            } else if let idx = existing.firstIndex(where: { item.localizedCaseInsensitiveContains($0) && item.count > $0.count }) {
                                existing[idx] = item; memoItems[cat] = existing
                            }
                        }
                    }
                }
                polishStatus = .ready
            } else {
                polishStatus = .error(enhancer.lastError ?? "未知错误")
            }
        }
    }

    func scheduleFollowups(question: QuestionTemplate, answer: Answer) {
        guard settings.isLLMConfigured else { return }
        guard answer.hasContent else { followups = []; return }
        followupTask?.cancel()
        followupTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            isLoadingFollowups = true
            let enhancer = getEnhancer()
            let deptId = selectedDepartmentId ?? ""
            let results = await enhancer.generateFollowup(
                project: project, department: deptId,
                question: question.question, questionType: question.type.rawValue,
                options: question.options ?? [],
                answer: answer.textValue, note: answer.noteText
            )
            guard !Task.isCancelled else { return }
            isLoadingFollowups = false
            if !results.isEmpty { followups = results }
        }
    }

    func scheduleVoiceAutoFill(question: QuestionTemplate, answer: Answer) {
        guard settings.isLLMConfigured else { return }
        guard let options = question.options, !options.isEmpty else { return }
        let deptId     = selectedDepartmentId ?? ""
        let transcript = answer.voiceTranscript
        guard !transcript.isEmpty else { return }
        Task { @MainActor in
            let enhancer = getEnhancer()
            guard let result = await enhancer.voiceAutoFill(
                project: project, department: deptId, questions: [question], transcript: transcript
            ) else { return }
            guard let match = result.answers.first(where: { $0.questionId == question.id }),
                  match.confidence != "low" else { return }
            let matched = options.filter { opt in
                opt.localizedCaseInsensitiveContains(match.answer) ||
                match.answer.localizedCaseInsensitiveContains(opt)
            }
            guard !matched.isEmpty else { return }
            if question.type == .singleChoice {
                answer.selectedOptions = [matched[0]]
            } else {
                for opt in matched where !answer.selectedOptions.contains(opt) {
                    answer.selectedOptions.append(opt)
                }
            }
            if answer.status == .unanswered { answer.status = .answered }
        }
    }

    private func adoptFollowup(at index: Int, parentQuestion: QuestionTemplate) {
        guard index < followups.count else { return }
        let fq = followups[index]
        let deptId = selectedDepartmentId ?? ""
        let fuId = "followup-\(UUID().uuidString)"
        let template = QuestionTemplate(
            id: fuId, section: parentQuestion.section,
            topic: "追问·\(parentQuestion.topic)",
            question: fq.question,
            type: fq.options.isEmpty ? .text : .singleChoice,
            options: fq.options.isEmpty ? nil : fq.options,
            required: false,
            hints: fq.reason.isEmpty ? nil : [fq.reason],
            triggers: nil, meceGroup: nil, knowledgeRef: nil,
            industrySpecific: nil, order: parentQuestion.order
        )
        let adopted = AdoptedFollowup(
            id: fuId, parentQuestionId: parentQuestion.id,
            departmentId: deptId, template: template
        )
        adoptedFollowups.append(adopted)
        let answer = Answer(projectId: project.id, departmentId: deptId, questionId: fuId)
        modelContext.insert(answer)
        answerLookup["\(deptId)::\(fuId)"] = answer
        followups.remove(at: index)
        rebuildDisplayQuestions()
        if let newIndex = cachedDisplayQuestions.firstIndex(where: { $0.id == fuId }) {
            withAnimation(AHAnimation.standard) { focusedQuestionIndex = newIndex }
        }
    }

    private func ignoreFollowup(at index: Int) {
        guard index < followups.count else { return }
        followups.remove(at: index)
    }

    private func resetAIState() {
        polishTask?.cancel()
        followupTask?.cancel()
        polishStatus = .idle
        followups = []
        isLoadingFollowups = false
        updateProjectProgress()
        if focusedQuestionIndex < cachedDisplayQuestions.count {
            let q = cachedDisplayQuestions[focusedQuestionIndex]
            if let answer = findAnswer(for: q.id, departmentId: selectedDepartmentId ?? ""),
               !answer.polishedText.isEmpty {
                polishStatus = .ready
            }
        }
    }

    private func globalQuestionIndex(for question: QuestionTemplate) -> Int {
        cachedDisplayQuestions.firstIndex(where: { $0.id == question.id }) ?? 0
    }

    func statusColor(for answer: Answer?) -> Color {
        guard let answer else { return Color.gray.opacity(0.3) }
        switch answer.status {
        case .answered: return Color.ahSuccess
        case .ignored: return .gray
        case .transferred: return Color.ahWarning
        case .unanswered:
            return answer.hasContent ? Color.ahSuccess : Color.gray.opacity(0.3)
        }
    }

    func rebuildAnswerLookup() {
        var lookup: [String: Answer] = [:]
        for answer in allAnswers where answer.projectId == project.id {
            lookup["\(answer.departmentId)::\(answer.questionId)"] = answer
        }
        answerLookup = lookup
    }

    func rebuildDisplayQuestions() {
        cachedFollowupIds = Set(adoptedFollowups.map(\.template.id))
        guard let deptId = selectedDepartmentId else {
            cachedDisplayQuestions = []; return
        }
        var base = baseQuestions(for: deptId)
        if let priorities = project.aiEnhancement?.priorityAdjustments {
            base.sort { a, b in
                let pa = priorities[a.id] ?? 3
                let pb = priorities[b.id] ?? 3
                return pa < pb
            }
        }
        let deptFollowups = adoptedFollowups.filter { $0.departmentId == deptId }
        var result: [QuestionTemplate] = []
        for q in base {
            result.append(q)
            for fu in deptFollowups where fu.parentQuestionId == q.id {
                result.append(fu.template)
            }
        }
        if let additional = project.aiEnhancement?.additionalQuestions {
            let deptAdditional = additional.filter { $0.departmentId == deptId }
            for aq in deptAdditional {
                let template = QuestionTemplate(
                    id: aq.id, section: QuestionSection(rawValue: aq.section) ?? .painpoint,
                    topic: "AI补充", question: aq.text,
                    type: aq.type == "multi_choice" ? .multiChoice : .singleChoice,
                    options: aq.options, required: false, hints: [aq.reason],
                    triggers: nil, meceGroup: nil, knowledgeRef: nil,
                    industrySpecific: true, order: 999
                )
                result.append(template)
                let key = "\(deptId)::\(aq.id)"
                if answerLookup[key] == nil {
                    let answer = Answer(projectId: project.id, departmentId: deptId, questionId: aq.id)
                    modelContext.insert(answer)
                    answerLookup[key] = answer
                }
            }
        }
        cachedDisplayQuestions = result
    }

    func answeredCount(for departmentId: String) -> Int {
        answerLookup.values.filter { $0.departmentId == departmentId && $0.hasContent }.count
    }

    func findAnswer(for questionId: String, departmentId: String) -> Answer? {
        answerLookup["\(departmentId)::\(questionId)"]
    }

    private func ensureAnswersExist() {
        for deptId in project.selectedDepartmentIds {
            for question in baseQuestions(for: deptId) {
                let key = "\(deptId)::\(question.id)"
                if answerLookup[key] == nil {
                    let answer = Answer(projectId: project.id, departmentId: deptId, questionId: question.id)
                    modelContext.insert(answer)
                    answerLookup[key] = answer
                }
            }
        }
    }

    private func updateProjectProgress() {
        let total = project.selectedDepartmentIds.reduce(0) { $0 + baseQuestions(for: $1).count }
        let answered = project.selectedDepartmentIds.reduce(0) { $0 + answeredCount(for: $1) }
        project.totalQuestions = total
        project.answeredQuestions = answered
        project.progress = total > 0 ? Double(answered) / Double(total) : 0
    }
}
