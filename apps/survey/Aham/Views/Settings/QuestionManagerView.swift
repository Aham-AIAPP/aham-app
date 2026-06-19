import SwiftUI

/// 问题管理视图 — 浏览所有内置问题，按部门/行业过滤，可排除不需要的问题
struct QuestionManagerView: View {
    let departments: [DepartmentTemplate]
    let pluginLoader: PluginLoader
    let onDone: () -> Void

    @State private var selectedIndustry: Industry = .general
    @State private var excludedIds: Set<String>
    @State private var expandedDepts: Set<String> = []
    private let store = QuestionExclusionStore()

    init(departments: [DepartmentTemplate], pluginLoader: PluginLoader, onDone: @escaping () -> Void) {
        self.departments = departments
        self.pluginLoader = pluginLoader
        self.onDone = onDone
        _excludedIds = State(initialValue: QuestionExclusionStore().load())
    }

    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("问题管理").ahTitle2()
                    Text("取消勾选的问题在新建项目时自动排除，已有项目不受影响")
                        .ahCaption().foregroundStyle(.secondary)
                }
                Spacer()
                Picker("行业", selection: $selectedIndustry) {
                    ForEach(Industry.allCases) { ind in
                        Label(ind.label, systemImage: ind.icon).tag(ind)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 130)
            }
            .padding()

            Divider()

            // 问题列表
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(departments) { dept in
                        deptSection(dept)
                    }
                }
                .padding()
            }

            Divider()

            // 底部操作栏
            HStack {
                let count = excludedIds.count
                if count > 0 {
                    Label("已排除 \(count) 条问题", systemImage: "minus.circle")
                        .ahCaption().foregroundStyle(.orange)
                } else {
                    Text("所有问题均已启用").ahCaption().foregroundStyle(.secondary)
                }

                Spacer()

                Button("取消", role: .cancel) { onDone() }

                Button("保存") {
                    try? store.save(excludedIds)
                    onDone()
                }
                .buttonStyle(.ahPrimary)
            }
            .padding()
        }
        .frame(width: 620, height: 540)
    }

    @ViewBuilder
    private func deptSection(_ dept: DepartmentTemplate) -> some View {
        let questions = pluginLoader.questions(for: dept.id, industry: selectedIndustry)
        if !questions.isEmpty {
            let isExpanded = expandedDepts.contains(dept.id)
            let excludedInDept = questions.filter { excludedIds.contains($0.id) }.count

            VStack(alignment: .leading, spacing: 0) {
                // 部门行（展开/收起）
                Button {
                    if isExpanded { expandedDepts.remove(dept.id) }
                    else { expandedDepts.insert(dept.id) }
                } label: {
                    HStack(spacing: AHSpacing.s) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .ahCaption().foregroundStyle(.secondary).frame(width: 12)
                        Image(systemName: dept.sfSymbol).foregroundStyle(.secondary).ahCallout()
                        Text(dept.name).ahCallout().fontWeight(.medium)

                        if excludedInDept > 0 {
                            Text("已排除 \(excludedInDept)/\(questions.count)")
                                .ahCaption().foregroundStyle(.orange)
                                .padding(.horizontal, AHSpacing.xs).padding(.vertical, AHSpacing.xxs)
                                .background(.orange.opacity(0.1), in: .capsule)
                        } else {
                            Text("\(questions.count) 条")
                                .ahCaption().foregroundStyle(.secondary)
                                .padding(.horizontal, AHSpacing.xs).padding(.vertical, AHSpacing.xxs)
                                .background(.secondary.opacity(0.1), in: .capsule)
                        }
                        Spacer()

                        // 部门级别快捷操作
                        if isExpanded {
                            let allExcluded = questions.allSatisfy { excludedIds.contains($0.id) }
                            Button(allExcluded ? "全部恢复" : "全部排除") {
                                if allExcluded {
                                    questions.forEach { excludedIds.remove($0.id) }
                                } else {
                                    questions.forEach { excludedIds.insert($0.id) }
                                }
                            }
                            .ahCaption()
                            .buttonStyle(.ahGhost)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, AHSpacing.s)
                }
                .buttonStyle(.plain)

                // 问题列表
                if isExpanded {
                    ForEach(questions) { q in
                        Toggle(isOn: Binding(
                            get: { !excludedIds.contains(q.id) },
                            set: { isOn in
                                if isOn { excludedIds.remove(q.id) }
                                else { excludedIds.insert(q.id) }
                            }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(q.question)
                                    .ahCallout()
                                    .foregroundStyle(excludedIds.contains(q.id) ? .secondary : .primary)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(q.section.label)
                                    .ahCaption()
                            }
                        }
                        .toggleStyle(.checkbox)
                        .padding(.leading, AHSpacing.xxl)
                        .padding(.vertical, AHSpacing.xxs)
                    }
                }

                Divider().padding(.leading, AHSpacing.xxl)
            }
        }
    }
}
