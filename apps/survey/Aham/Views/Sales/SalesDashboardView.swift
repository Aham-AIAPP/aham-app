import SwiftUI

// MARK: - Dashboard Root

struct SalesDashboardView: View {
    @Environment(SettingsManager.self) private var settings
    @State private var store = SalesDashboardStore()
    @State private var selectedTab: DashTab = .team
    @State private var selectedPerson = "全部"
    @State private var periodLabel = "本周"
    @State private var startDate: Date
    @State private var endDate: Date

    enum DashTab: String, CaseIterable {
        case team  = "团队周报"
        case named = "列名客户穿透"
    }

    init() {
        let (s, e) = SalesDashboardStore.weekRange(offset: 0)
        _startDate = State(initialValue: s)
        _endDate   = State(initialValue: e)
    }

    var body: some View {
        VStack(spacing: 0) {
            periodToolbar
            Divider()
            tabAndFilterBar
            Divider()
            ZStack {
                ScrollView {
                    Group {
                        if selectedTab == .team {
                            TeamReportView(
                                person:  selectedPerson,
                                team:    store.teamMembers,
                                opps:    store.opps,
                                fups:    store.fups,
                                visits:  store.visits,
                                phones:  store.phones
                            )
                        } else {
                            NamedAccountsView(
                                person:   selectedPerson,
                                accounts: store.namedAccounts
                            )
                        }
                    }
                    .padding(AHSpacing.l)
                }
                .opacity(store.isLoading ? 0.3 : 1)

                if store.isLoading {
                    ProgressView("加载中…")
                        .controlSize(.large)
                        .padding(AHSpacing.xxl)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AHRadius.xl))
                }

                if !store.isLoading, let err = store.error {
                    errorBanner(err)
                }

                if !store.isLoading && store.error == nil && !store.hasData {
                    emptyState
                }
            }
        }
        .navigationTitle("销售看板")
        .navigationSubtitle(periodLabel)
        .task { await loadData() }
    }

    // MARK: - Period Toolbar

    private var periodToolbar: some View {
        HStack(spacing: AHSpacing.s) {
            Picker("周期", selection: Binding(
                get: { periodLabel },
                set: { newVal in if newVal != "自定义" { applyPeriod(newVal) } }
            )) {
                Text("本周").tag("本周")
                Text("上周").tag("上周")
                Text("本月").tag("本月")
                if periodLabel == "自定义" {
                    Text("自定义").tag("自定义")
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            Divider().frame(height: 20)

            HStack(spacing: AHSpacing.xxs) {
                DatePicker("", selection: $startDate, displayedComponents: .date)
                    .labelsHidden().controlSize(.small)
                    .onChange(of: startDate) { _, _ in periodLabel = "自定义"; Task { await loadData() } }
                Text("至").ahCaption().foregroundStyle(.secondary)
                DatePicker("", selection: $endDate, displayedComponents: .date)
                    .labelsHidden().controlSize(.small)
                    .onChange(of: endDate) { _, _ in periodLabel = "自定义"; Task { await loadData() } }
            }

            Spacer()

            Button {
                Task { await loadData() }
            } label: {
                Label("刷新", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.ahPrimary)
            .disabled(store.isLoading)

            if let updated = store.lastUpdated {
                Text("更新 \(updated, style: .time)")
                    .ahCaption().foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, AHSpacing.l)
        .padding(.vertical, AHSpacing.s)
        .background(.bar)
    }

    // MARK: - Tab + Filter Bar

    private var tabAndFilterBar: some View {
        HStack(spacing: 0) {
            Picker("视图", selection: $selectedTab) {
                ForEach(DashTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .padding(.leading, AHSpacing.l)

            Spacer()

            HStack(spacing: AHSpacing.xxs) {
                personPill("全部")
                ForEach(store.teamMembers, id: \.self) { name in personPill(name) }
            }
            .padding(.trailing, AHSpacing.l)
        }
        .frame(height: 42)
    }

    private func personPill(_ name: String) -> some View {
        Button(name) { selectedPerson = name }
            .buttonStyle(PillButtonStyle(selected: selectedPerson == name))
    }

    // MARK: - Empty / Error

    private var emptyState: some View {
        ContentUnavailableView {
            Label("暂无数据", systemImage: "chart.line.uptrend.xyaxis")
        } description: {
            Text("当前时间段内没有销售数据，或尚未连接金蝶系统")
        } actions: {
            Button("刷新") { Task { await loadData() } }
        }
    }

    @ViewBuilder
    private func errorBanner(_ msg: String) -> some View {
        VStack(spacing: AHSpacing.m) {
            Image(systemName: "exclamationmark.triangle.fill")
                .ahTitle().foregroundStyle(.orange)
            Text(msg).ahCallout().multilineTextAlignment(.center)
            Button("重试") { Task { await loadData() } }
                .buttonStyle(.ahPrimary)
        }
        .padding(AHSpacing.xxxl)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AHRadius.xl))
    }

    // MARK: - Actions

    private func applyPeriod(_ p: String) {
        periodLabel = p
        switch p {
        case "本周":  (startDate, endDate) = SalesDashboardStore.weekRange(offset: 0)
        case "上周":  (startDate, endDate) = SalesDashboardStore.weekRange(offset: -1)
        case "本月":  (startDate, endDate) = SalesDashboardStore.monthRange()
        default: break
        }
        Task { await loadData() }
    }

    private func loadData() async {
        await store.load(config: settings.kingdeeConfig, startDate: startDate, endDate: endDate)
    }
}



// MARK: - 团队周报

struct TeamReportView: View {
    let person:  String
    let team:    [String]
    let opps:    [SalesOpportunity]
    let fups:    [SalesFollowUp]
    let visits:  [SalesVisit]
    let phones:  [SalesPhone]

    private var fOpps:   [SalesOpportunity] { filtered(opps,   \.rep) }
    private var fFups:   [SalesFollowUp]    { filtered(fups,   \.rep) }
    private var fVisits: [SalesVisit]       { filtered(visits, \.visitor) }
    private var fPhones: [SalesPhone]       { filtered(phones, \.rep) }

    private func filtered<T>(_ arr: [T], _ kp: KeyPath<T, String>) -> [T] {
        person == "全部" ? arr : arr.filter { $0[keyPath: kp] == person }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AHSpacing.l) {
            metricsStrip
            if person == "全部" && !team.isEmpty { teamStrip }
            SalesCard(title: "新增商机", count: fOpps.count) {
                SalesDataTable(
                    cols: ["负责人","商机名称","客户","阶段","状态","预算","日期"],
                    rows: fOpps.map { [$0.rep,$0.name,$0.customer,$0.phase,$0.status,
                                      $0.budget > 0 ? String(format:"%.0f万",$0.budget/10000) : "-",$0.date] },
                    tagCols: [3:.teal, 4:.blue]
                )
            }
            SalesCard(title: "商机跟进", count: fFups.count) {
                SalesDataTable(
                    cols: ["负责人","商机","客户","跟进方式","跟进结果","日期"],
                    rows: fFups.map { [$0.rep,$0.oppName,$0.customer,$0.method,
                                      String($0.result.prefix(50)),$0.date] },
                    tagCols: [3:.orange]
                )
            }
            SalesCard(title: "客户拜访", count: fVisits.count) {
                SalesDataTable(
                    cols: ["拜访人","客户","拜访模式","拜访内容","日期"],
                    rows: fVisits.map { [$0.visitor,$0.customer,$0.mode,
                                        String($0.content.prefix(50)),$0.date] },
                    tagCols: [2:.green]
                )
            }
            SalesCard(title: "电话营销", count: fPhones.count) {
                SalesDataTable(
                    cols: ["负责人","客户","联系人","跟进记录","日期"],
                    rows: fPhones.map { [$0.rep,$0.customer,$0.contact,
                                        String($0.record.prefix(50)),$0.date] },
                    tagCols: [:]
                )
            }
        }
    }

    private var metricsStrip: some View {
        HStack(spacing: 0) {
            let budget = fOpps.reduce(0.0) { $0 + $1.budget }
            MetricTile(label:"新增商机", value:"\(fOpps.count)",
                       sub: budget > 0 ? "预算 \(String(format:"%.0f",budget/10000)) 万" : "暂无预算数据",
                       accent:.primary)
            Divider()
            MetricTile(label:"商机跟进", value:"\(fFups.count)",   sub:"跟进次数", accent:.green)
            Divider()
            MetricTile(label:"客户拜访", value:"\(fVisits.count)", sub:"拜访次数", accent:.orange)
            Divider()
            MetricTile(label:"电话营销", value:"\(fPhones.count)", sub:"电话次数", accent:.purple)
        }
        .frame(height: 90)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: AHRadius.md))
        .overlay(RoundedRectangle(cornerRadius: AHRadius.md).stroke(.separator))
    }

    private var teamStrip: some View {
        HStack(spacing: 0) {
            ForEach(team, id: \.self) { name in
                let oc = opps.filter    { $0.rep == name }.count
                let fc = fups.filter    { $0.rep == name }.count
                let vc = visits.filter  { $0.visitor == name }.count
                let pc = phones.filter  { $0.rep == name }.count
                VStack(alignment: .leading, spacing: AHSpacing.xs) {
                    Text(name).ahMeta().fontWeight(.semibold).foregroundStyle(.primary)
                    HStack(spacing: AHSpacing.xxs) {
                        pill("\(oc) 商机", .blue)
                        pill("\(fc) 跟进", .green)
                        pill("\(vc) 拜访", .orange)
                        pill("\(pc) 电话", .purple)
                    }
                }
                .padding(.horizontal, AHSpacing.m).padding(.vertical, AHSpacing.s)
                .frame(maxWidth: .infinity, alignment: .leading)
                if name != team.last { Divider() }
            }
        }
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: AHRadius.md))
        .overlay(RoundedRectangle(cornerRadius: AHRadius.md).stroke(.separator))
    }

    private func pill(_ text: String, _ color: Color) -> some View {
        Text(text).ahCaption()
            .padding(.horizontal, AHSpacing.xxs).padding(.vertical, AHSpacing.xxs)
            .background(color.opacity(0.12)).foregroundStyle(color)
            .clipShape(Capsule())
    }
}

// MARK: - 列名客户

struct NamedAccountsView: View {
    let person:   String
    let accounts: [SalesNamedAccount]
    @State private var expanded: UUID?

    private var filtered: [SalesNamedAccount] {
        person == "全部" ? accounts : accounts.filter { $0.salesRep == person }
    }
    private var activeCount: Int { filtered.filter(\.isActive).count }

    var body: some View {
        VStack(alignment: .leading, spacing: AHSpacing.l) {
            HStack(spacing: 0) {
                MetricTile(label:"列名客户总数", value:"\(filtered.count)", sub:"", accent:.teal)
                Divider()
                MetricTile(label:"本期有推动", value:"\(activeCount)",
                           sub: filtered.isEmpty ? "-" : "\(Int(Double(activeCount)/Double(filtered.count)*100))%",
                           accent:.green)
                Divider()
                MetricTile(label:"本期静默", value:"\(filtered.count - activeCount)",
                           sub:"无任何动作", accent:.red)
            }
            .frame(height: 90)
            .background(.background)
            .clipShape(RoundedRectangle(cornerRadius: AHRadius.md))
            .overlay(RoundedRectangle(cornerRadius: AHRadius.md).stroke(.separator))

            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Text("客户名称").frame(maxWidth:.infinity, alignment:.leading)
                    Text("负责人").frame(width:72, alignment:.leading)
                    Text("拜访").frame(width:44, alignment:.center)
                    Text("电话").frame(width:44, alignment:.center)
                    Text("跟进").frame(width:44, alignment:.center)
                    Text("商机").frame(width:44, alignment:.center)
                    Text("最近动作").frame(width:96, alignment:.center)
                    Text("状态").frame(width:80, alignment:.center)
                }
                .ahCaption().fontWeight(.semibold).foregroundStyle(.secondary)
                .padding(.horizontal, AHSpacing.m).padding(.vertical, AHSpacing.xs)
                .background(Color.secondary.opacity(0.08))
                Divider()
                ForEach(filtered) { acc in
                    AccountRow(account: acc, isExpanded: expanded == acc.id) {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            expanded = expanded == acc.id ? nil : acc.id
                        }
                    }
                    Divider()
                }
            }
            .background(.background)
            .clipShape(RoundedRectangle(cornerRadius: AHRadius.md))
            .overlay(RoundedRectangle(cornerRadius: AHRadius.md).stroke(.separator))
        }
    }
}

struct AccountRow: View {
    let account: SalesNamedAccount
    let isExpanded: Bool
    let onTap: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onTap) {
                HStack(spacing: 0) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .ahCaption().foregroundStyle(.tertiary).frame(width: 20)
                    Text(account.name).fontWeight(.medium)
                        .frame(maxWidth:.infinity, alignment:.leading)
                    Text(account.salesRep).foregroundStyle(.secondary)
                        .frame(width:72, alignment:.leading)
                    countCell(account.visitCount,  .blue)   .frame(width:44)
                    countCell(account.phoneCount,  .purple) .frame(width:44)
                    countCell(account.followCount, .orange) .frame(width:44)
                    countCell(account.oppCount,    .teal)   .frame(width:44)
                    Text(account.lastActivity ?? "-")
                        .ahCaption().foregroundStyle(.secondary)
                        .frame(width:96, alignment:.center)
                    statusBadge.frame(width:80)
                }
                .ahCallout()
                .padding(.horizontal, AHSpacing.m).padding(.vertical, AHSpacing.s)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(isExpanded ? Color.ahAccentBG : Color.clear)

            if isExpanded { accountDetail.padding(AHSpacing.m).background(Color.secondary.opacity(0.04)) }
        }
        .animation(.easeInOut(duration: 0.15), value: isExpanded)
    }

    @ViewBuilder
    private func countCell(_ n: Int, _ color: Color) -> some View {
        if n > 0 {
            Text("\(n)").ahCaption().fontWeight(.medium).foregroundStyle(color)
                .frame(maxWidth:.infinity, alignment:.center)
        } else {
            Text("-").ahCaption().foregroundStyle(.quaternary)
                .frame(maxWidth:.infinity, alignment:.center)
        }
    }

    private var statusBadge: some View {
        HStack(spacing: AHSpacing.xxs) {
            Circle().fill(account.isActive ? Color.green : Color.secondary.opacity(0.35))
                .frame(width:6, height:6)
            Text(account.isActive ? "有推动" : "静默")
                .ahCaption()
                .foregroundStyle(account.isActive ? .green : .secondary)
        }.frame(maxWidth:.infinity, alignment:.center)
    }

    private var accountDetail: some View {
        typealias Item = (icon: String, label: String, color: Color, count: Int)
        let raw: [Item] = [
            (icon: "building.2.fill", label: "拜访",  color: .blue,   count: account.visitCount),
            (icon: "phone.fill",      label: "电话",  color: .purple, count: account.phoneCount),
            (icon: "arrow.2.circlepath", label: "跟进", color: .orange, count: account.followCount),
            (icon: "star.fill",       label: "商机",  color: .teal,   count: account.oppCount),
        ]
        let items = raw.filter { $0.count > 0 }

        return Group {
            if items.isEmpty {
                Text("本期无推动记录").ahCaption().foregroundStyle(.tertiary)
            } else {
                HStack(spacing: AHSpacing.xl) {
                    ForEach(items, id: \.label) { item in
                        Label {
                            VStack(alignment:.leading, spacing:1) {
                                Text(item.label).ahCaption().fontWeight(.semibold).foregroundStyle(item.color)
                                Text("本期 \(item.count) 次").ahCaption().foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: item.icon).foregroundStyle(item.color).ahCaption()
                        }
                    }
                }
            }
        }
        .frame(maxWidth:.infinity, alignment:.leading)
    }
}

// MARK: - 通用组件

struct MetricTile: View {
    let label: String; let value: String; let sub: String; let accent: Color
    var body: some View {
        VStack(alignment:.leading, spacing:3) {
            Text(label).ahCaption().textCase(.uppercase).foregroundStyle(.secondary)
            Text(value).ahTitle().fontWeight(.light)
                .foregroundStyle(accent == .primary ? .primary : accent)
            if !sub.isEmpty {
                Text(sub).ahCaption().foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, AHSpacing.l)
        .frame(maxWidth:.infinity, alignment:.leading)
    }
}

struct SalesCard<Content: View>: View {
    let title: String; let count: Int
    @ViewBuilder let content: () -> Content
    @State private var open = true

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.1)) { open.toggle() }
            } label: {
                HStack {
                    Text(title).ahMeta().fontWeight(.semibold)
                    Text("(\(count))").ahCaption().foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: open ? "chevron.down" : "chevron.right")
                        .ahCaption().foregroundStyle(.tertiary)
                }
                .padding(.horizontal, AHSpacing.m).padding(.vertical, AHSpacing.s)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open { Divider(); content() }
        }
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: AHRadius.md))
        .overlay(RoundedRectangle(cornerRadius: AHRadius.md).stroke(.separator))
    }
}

struct SalesDataTable: View {
    let cols: [String]
    let rows: [[String]]
    let tagCols: [Int: Color]

    var body: some View {
        if rows.isEmpty {
            Text("暂无数据").ahCallout().foregroundStyle(.tertiary)
                .frame(maxWidth:.infinity).padding(AHSpacing.xxl)
        } else {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(cols, id:\.self) { c in
                        Text(c).ahCaption().fontWeight(.semibold).foregroundStyle(.secondary)
                            .frame(maxWidth:.infinity, alignment:.leading)
                            .padding(.horizontal, AHSpacing.m).padding(.vertical, AHSpacing.xs)
                    }
                }
                .background(Color.secondary.opacity(0.06))
                Divider()
                ForEach(Array(rows.enumerated()), id:\.offset) { idx, row in
                    HStack(spacing: 0) {
                        ForEach(Array(row.enumerated()), id:\.offset) { i, val in
                            Group {
                                if let color = tagCols[i], !val.isEmpty {
                                    Text(val).ahCaption()
                                        .padding(.horizontal, AHSpacing.xs).padding(.vertical, AHSpacing.xxs)
                                        .background(color.opacity(0.12)).foregroundStyle(color)
                                        .clipShape(Capsule())
                                } else {
                                    Text(val.isEmpty ? "-" : val).ahCallout()
                                        .foregroundStyle(i <= 1 ? .primary : .secondary)
                                        .lineLimit(1)
                                }
                            }
                            .frame(maxWidth:.infinity, alignment:.leading)
                            .padding(.horizontal, AHSpacing.m)
                        }
                    }
                    .padding(.vertical, AHSpacing.xs)
                    .background(idx % 2 == 0 ? Color.clear : Color.secondary.opacity(0.04))
                    if idx < rows.count - 1 { Divider() }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview("Dashboard") {
    NavigationStack {
        SalesDashboardView()
    }
    .environment(SettingsManager())
    .frame(width: 1100, height: 800)
}
