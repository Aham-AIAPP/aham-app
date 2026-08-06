import SwiftUI

// MARK: - 备忘录栏

extension SurveyView {

    @ViewBuilder
    var memoBar: some View {
        VStack(spacing: 0) {
            Divider()

            // 折叠状态：显示四类标签 + 计数
            Button {
                withAnimation(AHAnimation.quick) {
                    memoExpanded.toggle()
                }
            } label: {
                HStack(spacing: 0) {
                    ForEach(MemoCategory.allCases) { category in
                        HStack(spacing: AHSpacing.xxs) {
                            Image(systemName: category.icon)
                                .ahCaption()
                                .foregroundStyle(category.color)
                            Text(category.label)
                                .ahCaption()
                                .foregroundStyle(.primary)
                            Text("(\(memoItems[category]?.count ?? 0))")
                                .ahCaption()
                                .fontWeight(.semibold)
                                .foregroundStyle(category.color)
                        }
                        .padding(.horizontal, AHSpacing.s)
                        .padding(.vertical, AHSpacing.xxs)

                        if category != MemoCategory.allCases.last {
                            Divider()
                                .frame(height: 12)
                        }
                    }

                    Spacer()

                    // 总进度
                    let totalAll = project.selectedDepartmentIds.reduce(0) { $0 + baseQuestions(for: $1).count }
                    let answeredAll = project.selectedDepartmentIds.reduce(0) { $0 + answeredCount(for: $1) }
                    let pct = totalAll > 0 ? Int(Double(answeredAll) / Double(totalAll) * 100) : 0
                    Text("\(pct)%")
                        .ahCallout()
                        .fontWeight(.bold)
                        .foregroundStyle(pct >= 100 ? Color.ahSuccess : Color.ahAccent)
                        .monospacedDigit()
                        .padding(.trailing, AHSpacing.xxs)

                    Image(systemName: memoExpanded ? "chevron.down" : "chevron.up")
                        .ahCaption()
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, AHSpacing.m)
                .padding(.vertical, AHSpacing.xxs)
                .ahGlassBar()
            }
            .buttonStyle(.plain)

            // 展开状态：四列网格
            if memoExpanded {
                Divider()
                HStack(alignment: .top, spacing: 0) {
                    ForEach(MemoCategory.allCases) { category in
                        VStack(alignment: .leading, spacing: AHSpacing.xxs) {
                            // 标题
                            HStack {
                                Image(systemName: category.icon)
                                    .ahCaption()
                                    .foregroundStyle(category.color)
                                Text(category.label)
                                    .ahCaption()
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.primary)
                                Spacer()
                                // 添加按钮
                                Button {
                                    activeMemoCategory = category
                                } label: {
                                    Image(systemName: "plus")
                                        .ahCaption()
                                }
                                .buttonStyle(.borderless)
                            }
                            .padding(.bottom, 2)

                            // 条目列表
                            ScrollView {
                                ForEach(memoItems[category] ?? []) { item in
                                    HStack(spacing: AHSpacing.xxs) {
                                        Text(item.text)
                                            .ahCaption()
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                        Spacer()
                                        Button {
                                            modelContext.delete(item)
                                        } label: {
                                            Image(systemName: "xmark")
                                                .ahCaption()
                                                .foregroundStyle(.tertiary)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }

                            // 添加输入框（当此类别被激活时）
                            if activeMemoCategory == category {
                                HStack(spacing: AHSpacing.xxs) {
                                    TextField(category.placeholder, text: $newMemoText)
                                        .ahCaption()
                                        .foregroundStyle(.primary)
                                        .textFieldStyle(.plain)
                                        .onSubmit { addMemoItem(to: category) }
                                    Button {
                                        addMemoItem(to: category)
                                    } label: {
                                        Image(systemName: "return")
                                            .ahCaption()
                                    }
                                    .buttonStyle(.borderless)
                                    .disabled(newMemoText.trimmingCharacters(in: .whitespaces).isEmpty)
                                }
                                .padding(AHSpacing.xxs)
                                .background(.fill.quaternary, in: .rect(cornerRadius: AHRadius.xs))
                            }

                            Spacer()
                        }
                        .padding(AHSpacing.s)
                        .frame(maxWidth: .infinity, alignment: .leading)

                        if category != MemoCategory.allCases.last {
                            Divider()
                        }
                    }
                }
                .frame(minHeight: 120, maxHeight: 200)
                .background(.background.secondary)
            }
        }
    }

    /// 添加备忘条目：写入用户选中的类别，不再经过 LLM 分类。
    /// 旧实现会在 AI 判定「不属于任何类别」时静默丢弃用户输入，这里保证非空输入必定落地。
    private func addMemoItem(to category: MemoCategory) {
        let trimmed = newMemoText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        newMemoText = ""

        guard (memoItems[category] ?? []).count < 20 else { return }
        modelContext.insert(MemoItem(projectId: project.id, category: category, text: trimmed))
    }
}
