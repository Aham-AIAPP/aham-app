import SwiftUI

// MARK: - 右侧面板

extension SurveyView {

    @ViewBuilder
    var surveyRightPanel: some View {
        VStack(spacing: 0) {
            // 面板标题
            HStack {
                Text("智能提示")
                    .ahCaption()
                    .fontWeight(.semibold)
                Spacer()
            }
            .padding(.horizontal, AHSpacing.s)
            .padding(.vertical, AHSpacing.xs)
            .ahGlassBar()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: AHSpacing.m) {
                    // AI 提示区
                    if focusedQuestionIndex < cachedDisplayQuestions.count {
                        let question = cachedDisplayQuestions[focusedQuestionIndex]

                        if let record = findAnswer(for: question.id, departmentId: selectedDepartmentId ?? "") {
                            DisclosureGroup("来源证据与转写") {
                                Text(record.evidence.isEmpty ? "尚未关联来源证据。可通过 MCP 导入访谈原文或定位。" : record.evidence)
                                    .ahBody().textSelection(.enabled)
                                if !record.voiceTranscript.isEmpty {
                                    DisclosureGroup("原始转写") {
                                        Text(record.voiceTranscript).ahBody().textSelection(.enabled)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }.ahCaption()
                                }
                                AHStatus(text: isValidAnswer(record, for: question) ? "已满足题型要求" : "待补充答案",
                                         color: isValidAnswer(record, for: question) ? .ahSuccess : .ahInk40)
                                Text("证据保留原文，仍需业务核对。").ahMeta()
                            }.ahCaption().padding(AHSpacing.s)
                            AHDivider()
                        }

                        if let hints = question.hints, !hints.isEmpty {
                            VStack(alignment: .leading, spacing: AHSpacing.xs) {
                                HStack(spacing: AHSpacing.xxs) {
                                    Image(systemName: "lightbulb.fill")
                                        .ahCaption()
                                        .foregroundStyle(Color.ahWarning)
                                    Text("调研提示")
                                        .ahCaption()
                                        .fontWeight(.medium)
                                }
                                ForEach(hints, id: \.self) { hint in
                                    HStack(alignment: .top, spacing: AHSpacing.xxs) {
                                        Text("•")
                                            .ahCaption()
                                            .foregroundStyle(Color.ahWarning)
                                        Text(hint)
                                            .ahCaption()
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .padding(AHSpacing.s)
                            .background(.background, in: .rect(cornerRadius: AHRadius.md))
                        }

                        // 触发反馈
                        let answer = findAnswer(for: question.id, departmentId: selectedDepartmentId ?? "")
                        if let ans = answer, !ans.textValue.isEmpty,
                           let triggers = question.triggers, !triggers.isEmpty {
                            let results = TriggerEngine.evaluate(
                                triggers: triggers,
                                answer: ans.textValue,
                                selectedOptions: ans.selectedOptions
                            )
                            if !results.isEmpty {
                                VStack(alignment: .leading, spacing: AHSpacing.xs) {
                                    HStack(spacing: AHSpacing.xxs) {
                                        Image(systemName: "brain")
                                            .ahCaption()
                                            .foregroundStyle(Color.ahAccent)
                                        Text("智能分析")
                                            .ahCaption()
                                            .fontWeight(.medium)
                                    }
                                    ForEach(results) { result in
                                        HStack(alignment: .top, spacing: AHSpacing.xxs) {
                                            Image(systemName: triggerIcon(for: result.type))
                                                .ahCaption()
                                                .foregroundStyle(triggerColor(for: result.type))
                                            Text(result.content)
                                                .ahCaption()
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                .padding(AHSpacing.s)
                                .background(.background, in: .rect(cornerRadius: AHRadius.md))
                            }
                        }
                    }

                    // 部门完成进度
                    VStack(alignment: .leading, spacing: AHSpacing.xs) {
                        HStack(spacing: AHSpacing.xxs) {
                            Image(systemName: "chart.bar.fill")
                                .ahCaption()
                                .foregroundStyle(Color.ahSuccess)
                            Text("部门进度")
                                .ahCaption()
                                .fontWeight(.medium)
                        }
                        ForEach(pluginLoader.selectedDepartments(ids: project.selectedDepartmentIds)) { dept in
                            let total = progressQuestions(for: dept.id).count
                            let done = answeredCount(for: dept.id)
                            let pct = total > 0 ? Double(done) / Double(total) : 0
                            let isCurrent = dept.id == selectedDepartmentId

                            HStack(spacing: AHSpacing.xs) {
                                Text(dept.name)
                                    .ahCaption()
                                    .fontWeight(isCurrent ? .semibold : .regular)
                                    .foregroundStyle(isCurrent ? .primary : .secondary)
                                    .frame(minWidth: 30)
                                ProgressView(value: pct)
                                    .tint(pct >= 1 ? Color.ahSuccess : Color.ahAccent)
                                Text("\(done)/\(total)")
                                    .ahCaption()
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                                    .frame(width: 32, alignment: .trailing)
                            }
                        }
                    }
                    .padding(AHSpacing.s)
                    .background(.background, in: .rect(cornerRadius: AHRadius.md))

                    Spacer()
                }
                .padding(AHSpacing.s)
            }
            .background(Color.ahPaper)
        }
    }
}
