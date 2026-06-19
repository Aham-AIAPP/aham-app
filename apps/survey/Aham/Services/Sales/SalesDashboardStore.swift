import Foundation
import SwiftUI

// MARK: - 数据模型（共享给 View 层）

struct SalesOpportunity: Identifiable {
    let id = UUID()
    var no: String; var name: String; var customer: String
    var phase: String; var status: String; var budget: Double
    var rep: String; var date: String
}

struct SalesFollowUp: Identifiable {
    let id = UUID()
    var no: String; var oppName: String; var customer: String
    var method: String; var result: String; var rep: String; var date: String
}

struct SalesVisit: Identifiable {
    let id = UUID()
    var no: String; var customer: String; var mode: String
    var content: String; var visitor: String; var date: String
}

struct SalesPhone: Identifiable {
    let id = UUID()
    var no: String; var customer: String; var contact: String
    var record: String; var rep: String; var date: String
}

struct SalesNamedAccount: Identifiable {
    let id = UUID()
    var name: String; var salesRep: String
    var visitCount: Int; var phoneCount: Int; var followCount: Int; var oppCount: Int
    var lastActivity: String?; var isActive: Bool
}

// MARK: - Store

@Observable
final class SalesDashboardStore {

    // MARK: State
    var isLoading = false
    var error: String?
    var opps:          [SalesOpportunity]  = []
    var fups:          [SalesFollowUp]     = []
    var visits:        [SalesVisit]        = []
    var phones:        [SalesPhone]        = []
    var namedAccounts: [SalesNamedAccount] = []
    var lastUpdated:   Date?

    /// 固定销售团队成员列表，无论是否有数据都显示
    let teamMembers: [String] = ["李成豹","朱涛","顾云峰","高洁","孔庆宇","张燕"]

    var hasData: Bool { !opps.isEmpty || !fups.isEmpty || !visits.isEmpty || !phones.isEmpty }

    // MARK: Load

    func load(config: KingdeeConfig, startDate: Date, endDate: Date) async {
        guard config.isConfigured else {
            error = "请先在「设置 → 销售看板」中配置金蝶连接信息"
            return
        }
        isLoading = true
        error = nil

        let svc = KingdeeService.shared
        await svc.configure(config)

        let sd = Self.fmt(startDate)
        let ed = Self.fmt(endDate)

        do {
            // 并发拉取 5 张表
            async let rawOpps   = svc.query(
                formId: "BCS_opportunity",
                fields: "FBillNo,F_BCS_OPPNAME,F_BCS_CreateDate,F_BCS_phase.FDataValue,F_BCS_status.FDataValue,F_BCS_budget,F_BCS_CUST.FName,F_BCS_RESPONSIBLE.FName,FCompany.FName",
                filter: "F_BCS_CreateDate>='\(sd)' and F_BCS_CreateDate<='\(ed) 23:59:59'",
                order:  "F_BCS_CreateDate DESC"
            )
            async let rawFups   = svc.query(
                formId: "BCS_OPPTrack",
                fields: "FBillNo,F_BCS_TRDate,F_BCS_YG2.FName,F_BCS_TRACKINGWAY.FDataValue,F_BCS_result,F_BCS_CUST.FName,F_WQKQ_SJNAME,FCOMPANY.FName",
                filter: "F_BCS_TRDate>='\(sd)' and F_BCS_TRDate<='\(ed) 23:59:59'",
                order:  "F_BCS_TRDate DESC"
            )
            async let rawVisits = svc.query(
                formId: "BCS_VISITLIST",
                fields: "FBillNo,F_BCS_Date1,FCUSTOMID.FName,F_BCS_BFMS.FDataValue,F_BCS_BFNR,F_UAZE_Text",
                filter: "F_BCS_Date1>='\(sd)' and F_BCS_Date1<='\(ed) 23:59:59'",
                order:  "F_BCS_Date1 DESC"
            )
            async let rawPhones = svc.query(
                formId: "k35aa0f88fc5c47fe8e73b54a2cd4bc63",
                fields: "FBillNo,F_Telemarketing_Date,F_BCS__head.FName,F_BCS__custom.FName,F_Follow_up_records,F_customer_contact,F_WQKQ_QYXX.FName",
                filter: "F_Telemarketing_Date>='\(sd)' and F_Telemarketing_Date<='\(ed) 23:59:59'",
                order:  "F_Telemarketing_Date DESC"
            )
            async let rawNamed  = svc.query(
                formId: "BCS_QYXXB",
                fields: "FName,FNumber,F_UAZE_Combo,FModifyDate,FSALEPRE.FName",
                filter: "F_UAZE_Combo='1'"
            )

            let (o, f, v, p, n) = try await (rawOpps, rawFups, rawVisits, rawPhones, rawNamed)

            let mappedOpps   = o.map { r in
                SalesOpportunity(
                    no:       s(r,0), name:     s(r,1), customer: cust(s(r,6), s(r,8)),
                    phase:    s(r,3), status:   s(r,4), budget:   Double(s(r,5)) ?? 0,
                    rep:      s(r,7), date:     d10(s(r,2))
                )
            }
            let mappedFups   = f.map { r in
                SalesFollowUp(
                    no:       s(r,0), oppName:  s(r,6), customer: cust(s(r,5), s(r,7)),
                    method:   s(r,3), result:   s(r,4), rep:      s(r,2), date: d10(s(r,1))
                )
            }
            let mappedVisits = v.map { r in
                SalesVisit(
                    no:       s(r,0), customer: s(r,2), mode:    s(r,3),
                    content:  s(r,4), visitor:  s(r,5), date:    d10(s(r,1))
                )
            }
            let mappedPhones = p.map { r in
                SalesPhone(
                    no:       s(r,0), customer: cust(s(r,3), s(r,6)), contact: s(r,5),
                    record:   s(r,4), rep:      s(r,2), date: d10(s(r,1))
                )
            }
            let mappedNamed  = buildNamed(raw: n, visits: mappedVisits,
                                          phones: mappedPhones, fups: mappedFups,
                                          opps: mappedOpps, sd: sd, ed: ed)

            opps          = mappedOpps
            fups          = mappedFups
            visits        = mappedVisits
            phones        = mappedPhones
            namedAccounts = mappedNamed
            lastUpdated   = Date()

        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - 帮助方法

    private func s(_ row: [Any], _ i: Int) -> String {
        guard i < row.count else { return "" }
        let v = "\(row[i])".trimmingCharacters(in: .whitespaces)
        return v == "<null>" || v == "null" ? "" : v
    }

    private func d10(_ raw: String) -> String {
        guard raw.count >= 10 else { return raw }
        return String(raw.prefix(10))
    }

    /// 公司名优先，没有取客户名
    private func cust(_ custName: String, _ compName: String) -> String {
        let c = compName.trimmingCharacters(in: .whitespaces)
        let k = custName.trimmingCharacters(in: .whitespaces)
        return c.isEmpty ? k : c
    }

    /// 列名客户 + 活跃度聚合
    private func buildNamed(
        raw: [[Any]],
        visits: [SalesVisit],
        phones: [SalesPhone],
        fups: [SalesFollowUp],
        opps: [SalesOpportunity],
        sd: String,
        ed: String
    ) -> [SalesNamedAccount] {
        raw.map { r in
            let name    = s(r, 0)
            let rep     = s(r, 4)
            let modDate = d10(s(r, 3))

            let vc = visits.filter { $0.customer.contains(name) }.count
            let pc = phones.filter { $0.customer.contains(name) }.count
            let fc = fups.filter   { $0.customer.contains(name) }.count
            let oc = opps.filter   { $0.customer.contains(name) }.count
            let updated = !modDate.isEmpty && modDate >= sd && modDate <= ed
            let active  = vc + pc + fc + oc > 0 || updated

            let lastAct: String? = {
                var dates = [String]()
                if vc > 0 { dates += visits.filter { $0.customer.contains(name) }.map(\.date) }
                if pc > 0 { dates += phones.filter { $0.customer.contains(name) }.map(\.date) }
                if fc > 0 { dates += fups.filter   { $0.customer.contains(name) }.map(\.date) }
                if oc > 0 { dates += opps.filter   { $0.customer.contains(name) }.map(\.date) }
                if updated { dates.append(modDate) }
                return dates.max()
            }()

            return SalesNamedAccount(
                name: name, salesRep: rep,
                visitCount: vc, phoneCount: pc, followCount: fc, oppCount: oc,
                lastActivity: lastAct, isActive: active
            )
        }
        .sorted { ($0.visitCount+$0.phoneCount+$0.followCount+$0.oppCount) > ($1.visitCount+$1.phoneCount+$1.followCount+$1.oppCount) }
    }

    // MARK: - 日期格式化

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()

    static func fmt(_ d: Date) -> String { dateFmt.string(from: d) }

    // MARK: - 周期快捷

    static func weekRange(offset: Int = 0) -> (Date, Date) {
        var cal = Calendar.current
        cal.firstWeekday = 2  // 周一为一周起始
        let today = Date()
        let weekday = cal.component(.weekday, from: today)
        let daysFromMonday = (weekday + 5) % 7
        let monday = cal.date(byAdding: .day, value: -daysFromMonday + offset * 7, to: today)!
        let sunday = cal.date(byAdding: .day, value: 6, to: monday)!
        return (monday, sunday)
    }

    static func monthRange() -> (Date, Date) {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: Date())
        let start = cal.date(from: comps)!
        let end   = cal.date(byAdding: DateComponents(month: 1, day: -1), to: start)!
        return (start, end)
    }
}
