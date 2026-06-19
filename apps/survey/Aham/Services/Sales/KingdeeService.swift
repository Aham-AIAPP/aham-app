import Foundation

/// 金蝶云星空 WebAPI 服务
/// 封装登录（AppSecret 方式）和 ExecuteBillQuery 查询
actor KingdeeService {

    // MARK: - 单例

    static let shared = KingdeeService()

    // MARK: - 状态

    private var session: URLSession
    private var cookies: [String] = []
    private var config: KingdeeConfig?
    private var isLoggedIn = false

    // MARK: - 初始化

    private init() {
        let cfg = URLSessionConfiguration.default
        cfg.httpShouldSetCookies = false      // 手动管理 Cookie
        cfg.timeoutIntervalForRequest = 15
        self.session = URLSession(configuration: cfg)
    }

    // MARK: - 静态登录测试（设置页用）

    static func testLogin(config: KingdeeConfig) async -> Bool {
        let svc = KingdeeService()
        return await svc.login(config: config)
    }

    // MARK: - 配置更新

    func configure(_ cfg: KingdeeConfig) {
        if config != cfg {
            config = cfg
            isLoggedIn = false
            cookies = []
        }
    }

    // MARK: - 登录

    @discardableResult
    func login(config cfg: KingdeeConfig) async -> Bool {
        let urlStr = cfg.serverURL.trimmingCharacters(in: .whitespaces)
            + "/Kingdee.BOS.WebApi.ServicesStub.AuthService.LoginByAppSecret.common.kdsvc"
        guard let url = URL(string: urlStr) else { return false }

        let body: [String: Any] = [
            "acctid":    cfg.acctId,
            "username":  cfg.username,
            "appid":     cfg.appId,
            "appsecret": cfg.appSecret,
            "lcid":      cfg.lcid
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return false }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = data

        do {
            let (respData, response) = try await session.data(for: req)
            // 保存 Set-Cookie
            if let http = response as? HTTPURLResponse,
               let fields = http.allHeaderFields as? [String: String] {
                let parsed = HTTPCookie.cookies(withResponseHeaderFields: fields, for: url)
                cookies = parsed.map { "\($0.name)=\($0.value)" }
            }
            if let json = try? JSONSerialization.jsonObject(with: respData) as? [String: Any],
               let result = json["LoginResultType"] as? Int {
                isLoggedIn = result == 1
                return isLoggedIn
            }
        } catch {}
        return false
    }

    // MARK: - 确保已登录

    private func ensureLoggedIn() async -> Bool {
        if isLoggedIn { return true }
        guard let cfg = config else { return false }
        return await login(config: cfg)
    }

    // MARK: - 查询

    /// ExecuteBillQuery 通用查询
    func query(
        formId: String,
        fields: String,
        filter: String = "",
        order: String = "",
        limit: Int = 2000
    ) async throws -> [[Any]] {
        guard await ensureLoggedIn(), let cfg = config else {
            throw KingdeeError.notLoggedIn
        }

        let urlStr = cfg.serverURL.trimmingCharacters(in: .whitespaces)
            + "/Kingdee.BOS.WebApi.ServicesStub.DynamicFormService.ExecuteBillQuery.common.kdsvc"
        guard let url = URL(string: urlStr) else { throw KingdeeError.invalidURL }

        let body: [String: Any] = [
            "data": [
                "FormId":       formId,
                "FieldKeys":    fields,
                "FilterString": filter,
                "OrderString":  order,
                "TopRowCount":  0,
                "StartRow":     0,
                "Limit":        limit
            ]
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else {
            throw KingdeeError.encodingFailed
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !cookies.isEmpty {
            req.setValue(cookies.joined(separator: "; "), forHTTPHeaderField: "Cookie")
        }
        req.httpBody = data

        let (respData, _) = try await session.data(for: req)

        // 返回格式: [[field1, field2, ...], ...]
        if let arr = try? JSONSerialization.jsonObject(with: respData) as? [[Any]] {
            // 有时第一行是列头描述，后续才是数据
            return arr
        }
        // 服务端有时返回 [[row1], [row2]] 嵌套形式
        if let outer = try? JSONSerialization.jsonObject(with: respData) as? [Any],
           let inner = outer.first as? [[Any]] {
            return inner
        }
        return []
    }

    // MARK: - 便捷查询方法（供 SalesDashboardStore 调用）

    /// 查询并映射为字典数组
    func queryRows(
        formId: String,
        fields: [String],
        filter: String = "",
        order: String = ""
    ) async throws -> [[String: String]] {
        let fieldStr = fields.joined(separator: ",")
        let raw = try await query(formId: formId, fields: fieldStr, filter: filter, order: order)
        return raw.map { row in
            var dict = [String: String]()
            for (i, key) in fields.enumerated() {
                dict[key] = i < row.count ? "\(row[i])".trimmingCharacters(in: .whitespaces) : ""
            }
            return dict
        }
    }

    // MARK: - 会话重置

    func logout() {
        isLoggedIn = false
        cookies = []
    }
}

// MARK: - Error

enum KingdeeError: LocalizedError {
    case notLoggedIn
    case invalidURL
    case encodingFailed
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .notLoggedIn:    return "未登录金蝶系统"
        case .invalidURL:     return "服务器地址无效"
        case .encodingFailed: return "请求编码失败"
        case .serverError(let msg): return "服务器错误: \(msg)"
        }
    }
}
