import Foundation

/// 触发规则引擎：根据答案内容评估题库里的 `triggers` 规则。
///
/// 条件文法（递归下降解析，优先级 `!` > `&&` > `||`，支持括号）：
///
///     expr       := orExpr
///     orExpr     := andExpr ( '||' andExpr )*
///     andExpr    := unary ( '&&' unary )*
///     unary      := '!' unary | primary
///     primary    := '(' expr ')' | equality | membership | numeric
///     equality   := 'answer' ( '==' | '!=' ) STRING
///     membership := 'answer.includes(' STRING ')'
///     numeric    := 'answer.number' ( '<' | '<=' | '>' | '>=' | '==' | '!=' ) NUMBER
///     STRING     := 单引号或双引号包裹，内部可含中文、括号、比较号、逗号
///
/// 解析失败一律返回 false（现场宁可不提醒，也不误报）；
/// 为避免规则再次「静默失效」，`PluginLoader` 会在 DEBUG 构建下用
/// `validate(_:)` 把题库里所有条件走一遍并报到控制台。
struct TriggerEngine {

    /// 触发结果
    struct TriggerResult: Identifiable {
        let id = UUID()
        let type: TriggerType
        let content: String
        let model: String?
    }

    enum TriggerType: String {
        case followup
        case tip
        case warning
        case rule
    }

    /// 评估单个问题的触发规则
    static func evaluate(
        triggers: [TriggerRule],
        answer: String,
        selectedOptions: [String]
    ) -> [TriggerResult] {
        let context = Context(answer: answer, selectedOptions: selectedOptions)
        return triggers.compactMap { trigger in
            var parser = Parser(trigger.condition)
            guard let node = parser.parse() else { return nil }
            guard node.evaluate(in: context) else { return nil }
            let type = TriggerType(rawValue: trigger.type) ?? .tip
            return TriggerResult(type: type, content: trigger.content, model: trigger.model)
        }
    }

    /// 只做语法校验，不求值 —— 供 DEBUG 自检使用
    static func validate(_ condition: String) -> Bool {
        var parser = Parser(condition)
        return parser.parse() != nil
    }

    // MARK: - 求值上下文

    fileprivate struct Context {
        let answer: String
        let selectedOptions: [String]

        /// 文本里的第一个数字；取不到返回 nil（数值比较随之整体判为 false）
        var firstNumber: Double? {
            var digits = ""
            var seenDot = false
            for ch in answer {
                if ch.isNumber {
                    digits.append(ch)
                } else if ch == "." && !digits.isEmpty && !seenDot {
                    seenDot = true
                    digits.append(ch)
                } else if ch == "," && !digits.isEmpty {
                    continue                       // 千分位分隔符
                } else if !digits.isEmpty {
                    break
                }
            }
            if digits.hasSuffix(".") { digits.removeLast() }
            return digits.isEmpty ? nil : Double(digits)
        }
    }

    // MARK: - 语法树

    fileprivate enum NumericOp: String {
        case lt = "<", lte = "<=", gt = ">", gte = ">=", eq = "==", neq = "!="

        func compare(_ lhs: Double, _ rhs: Double) -> Bool {
            switch self {
            case .lt:  lhs <  rhs
            case .lte: lhs <= rhs
            case .gt:  lhs >  rhs
            case .gte: lhs >= rhs
            case .eq:  lhs == rhs
            case .neq: lhs != rhs
            }
        }
    }

    fileprivate indirect enum Node {
        case or(Node, Node)
        case and(Node, Node)
        case not(Node)
        case equals(String)
        case notEquals(String)
        case includes(String)
        case number(NumericOp, Double)

        func evaluate(in ctx: Context) -> Bool {
            switch self {
            case .or(let l, let r):     return l.evaluate(in: ctx) || r.evaluate(in: ctx)
            case .and(let l, let r):    return l.evaluate(in: ctx) && r.evaluate(in: ctx)
            case .not(let n):           return !n.evaluate(in: ctx)
            // 沿用既有语义：单选题的 answer 可能落在 textValue，也可能落在 selectedOptions
            case .equals(let v):        return ctx.answer == v || ctx.selectedOptions.contains(v)
            case .notEquals(let v):     return !(ctx.answer == v || ctx.selectedOptions.contains(v))
            case .includes(let v):      return ctx.selectedOptions.contains(v) || ctx.answer.contains(v)
            case .number(let op, let rhs):
                guard let lhs = ctx.firstNumber else { return false }
                return op.compare(lhs, rhs)
            }
        }
    }

    // MARK: - 解析器

    fileprivate struct Parser {
        private let chars: [Character]
        private var pos = 0

        init(_ condition: String) {
            chars = Array(condition)
        }

        /// 解析整条条件；语法非法或有多余尾串时返回 nil
        mutating func parse() -> Node? {
            guard let node = parseOr() else { return nil }
            skipSpaces()
            return pos == chars.count ? node : nil
        }

        // orExpr := andExpr ( '||' andExpr )*
        private mutating func parseOr() -> Node? {
            guard var left = parseAnd() else { return nil }
            while match("||") {
                guard let right = parseAnd() else { return nil }
                left = .or(left, right)
            }
            return left
        }

        // andExpr := unary ( '&&' unary )*
        private mutating func parseAnd() -> Node? {
            guard var left = parseUnary() else { return nil }
            while match("&&") {
                guard let right = parseUnary() else { return nil }
                left = .and(left, right)
            }
            return left
        }

        // unary := '!' unary | primary
        private mutating func parseUnary() -> Node? {
            skipSpaces()
            // 注意：'!=' 属于比较运算符，不能在这里当成取反吃掉
            if peek() == "!" && peek(offset: 1) != "=" {
                pos += 1
                guard let inner = parseUnary() else { return nil }
                return .not(inner)
            }
            return parsePrimary()
        }

        // primary := '(' expr ')' | equality | membership | numeric
        private mutating func parsePrimary() -> Node? {
            skipSpaces()
            if peek() == "(" {
                pos += 1
                guard let inner = parseOr() else { return nil }
                skipSpaces()
                guard match(")") else { return nil }
                return inner
            }

            if match("answer.includes(") {
                guard let value = parseQuoted() else { return nil }
                skipSpaces()
                guard match(")") else { return nil }
                return .includes(value)
            }

            if match("answer.number") {
                skipSpaces()
                guard let op = parseNumericOp() else { return nil }
                skipSpaces()
                guard let rhs = parseNumber() else { return nil }
                return .number(op, rhs)
            }

            if match("answer") {
                skipSpaces()
                if match("==") {
                    skipSpaces()
                    guard let value = parseQuoted() else { return nil }
                    return .equals(value)
                }
                if match("!=") {
                    skipSpaces()
                    guard let value = parseQuoted() else { return nil }
                    return .notEquals(value)
                }
                return nil
            }

            return nil
        }

        // MARK: 词法

        private func peek(offset: Int = 0) -> Character? {
            let i = pos + offset
            return i < chars.count ? chars[i] : nil
        }

        private mutating func skipSpaces() {
            while let c = peek(), c == " " || c == "\t" || c == "\n" { pos += 1 }
        }

        /// 跳过空白后尝试吃掉字面量；命中才移动游标
        private mutating func match(_ literal: String) -> Bool {
            skipSpaces()
            let target = Array(literal)
            guard pos + target.count <= chars.count else { return false }
            for (i, c) in target.enumerated() where chars[pos + i] != c { return false }
            pos += target.count
            return true
        }

        /// 引号包裹的字符串；内部允许中文、括号、比较号、逗号
        private mutating func parseQuoted() -> String? {
            skipSpaces()
            guard let quote = peek(), quote == "'" || quote == "\"" else { return nil }
            pos += 1
            var value = ""
            while let c = peek() {
                if c == quote {
                    pos += 1
                    return value
                }
                value.append(c)
                pos += 1
            }
            return nil   // 引号未闭合
        }

        private mutating func parseNumericOp() -> NumericOp? {
            for raw in ["<=", ">=", "==", "!=", "<", ">"] where match(raw) {
                return NumericOp(rawValue: raw)
            }
            return nil
        }

        private mutating func parseNumber() -> Double? {
            skipSpaces()
            var digits = ""
            if peek() == "-" { digits.append("-"); pos += 1 }
            while let c = peek(), c.isNumber || c == "." {
                digits.append(c)
                pos += 1
            }
            return Double(digits)
        }
    }
}
