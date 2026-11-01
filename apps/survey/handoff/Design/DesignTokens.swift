import SwiftUI

// MARK: - Design Tokens
//
// Aham App 全局设计系统 token
// 所有视图必须使用这些 token，不允许硬编码颜色、字号、间距、圆角
//
// 修改此文件 = 修改全 App 视觉。请谨慎。
//
// 原则：
// 1. 颜色优先使用 semantic 名（ahInk / ahPaper），而非字面色值
// 2. 所有间距、圆角走 AHSpacing / AHRadius，禁止在 View 里写 magic number
// 3. 字体走 .ahTitle / .ahBody 等 ViewModifier，不写 .font(.system(size:18))

// MARK: - 颜色

extension Color {
    // ─── 文字 ─────────────────────────────────────
    /// 主文字（黑/白自适应）—— 对应 SwiftUI 默认 .primary
    static let ahInk        = Color.primary
    /// 次要文字（灰）—— 说明、副标题、元数据
    static let ahInk60      = Color.secondary
    /// 更弱文字 —— hint、时间戳、辅助说明
    static let ahInk40      = Color(NSColor.tertiaryLabelColor)
    /// 禁用文字
    static let ahInk20      = Color(NSColor.quaternaryLabelColor)

    // ─── 背景 ─────────────────────────────────────
    /// 主内容底色（窗口背景）
    static let ahPaper      = Color(NSColor.windowBackgroundColor)
    /// 次级底色（表单、卡片区）
    static let ahPaperAlt   = Color(NSColor.controlBackgroundColor)
    /// 工具条、分隔条底色
    static let ahPaperBar   = Color(NSColor.underPageBackgroundColor)

    // ─── 描边与分隔 ────────────────────────────────
    /// 卡片、输入框描边
    static let ahBorder     = Color.primary.opacity(0.12)
    /// 更淡的分隔线
    static let ahDivider    = Color.primary.opacity(0.06)

    // ─── Accent ───────────────────────────────────
    /// 强调色（跟随系统或用 .accentColor）
    static let ahAccent     = Color.accentColor
    /// Accent 的 tint 背景 —— 用于选中态卡片、高亮区域
    static let ahAccentBG   = Color.accentColor.opacity(0.10)
    /// Accent 描边
    static let ahAccentBorder = Color.accentColor.opacity(0.30)

    // ─── 语义色（不随主题变） ─────────────────────────
    static let ahSuccess = Color(.displayP3, red: 0.188, green: 0.82, blue: 0.345)   // #30d158
    static let ahWarning = Color(.displayP3, red: 1.0, green: 0.624, blue: 0.039)    // #ff9f0a
    static let ahDanger  = Color(.displayP3, red: 1.0, green: 0.271, blue: 0.227)    // #ff453a
    static let ahInfo    = Color.accentColor
}

// MARK: - 间距 (Spacing)
//
// 规则：所有 padding、spacing、gap 必须使用 AHSpacing 的值。
// 不要写 .padding(15) —— 请用 .padding(AHSpacing.m) 或 .padding(16)（对齐 .l）。

enum AHSpacing {
    /// 4 pt —— 极小间距（同行紧凑元素）
    static let xxs: CGFloat = 4
    /// 6 pt —— 小间距
    static let xs: CGFloat = 6
    /// 8 pt —— 小块内填充
    static let s: CGFloat = 8
    /// 12 pt —— 常规（按钮与图标间、卡内元素间）
    static let m: CGFloat = 12
    /// 16 pt —— 卡片标准 padding
    static let l: CGFloat = 16
    /// 20 pt —— 区块间距
    static let xl: CGFloat = 20
    /// 24 pt —— 大区块间距（Section 间）
    static let xxl: CGFloat = 24
    /// 32 pt —— 页面级间距
    static let xxxl: CGFloat = 32
    /// 48 pt —— Hero 底部等
    static let huge: CGFloat = 48
}

// MARK: - 圆角 (Radius)

enum AHRadius {
    /// 3 pt —— pill 内的 tag
    static let xs: CGFloat = 3
    /// 5 pt —— 小按钮、标签
    static let sm: CGFloat = 5
    /// 8 pt —— 按钮、输入框
    static let md: CGFloat = 8
    /// 10 pt —— 卡片
    static let lg: CGFloat = 10
    /// 12 pt —— 大卡片、面板
    static let xl: CGFloat = 12
    /// 16 pt —— Hero squircle、弹窗
    static let xxl: CGFloat = 16
    /// 999 pt —— 胶囊 / 圆形
    static let pill: CGFloat = 999
}

// MARK: - 字体 (Typography)
//
// 字体规则：
// 1. 优先用 SwiftUI 语义字体（.title / .body / .caption）— macOS 会自动适配 Dynamic Type
// 2. 用 AHType 提供的 ViewModifier 保证粗细、间距、行高一致
// 3. 绝不直接 .font(.system(size: 18)) — 用下面的 .ahTitle3() 等
//
// 对应 SwiftUI 尺寸（macOS 13+）：
//   largeTitle  26pt
//   title       22pt
//   title2      17pt
//   title3      15pt
//   headline    13pt bold
//   body        13pt
//   callout     12pt
//   subheadline 11pt
//   footnote    10pt
//   caption     10pt
//   caption2    10pt

extension View {
    /// Hero / 页面主标题（22pt bold）
    func ahTitle() -> some View {
        self.font(.title.weight(.bold))
            .tracking(-0.3)
    }
    /// 次标题（17pt semibold）
    func ahTitle2() -> some View {
        self.font(.title2.weight(.semibold))
    }
    /// 小标题（15pt semibold）—— 卡内标题
    func ahTitle3() -> some View {
        self.font(.title3.weight(.semibold))
    }
    /// Section 标签（11pt semibold uppercase tracking）—— "调研进度" 这种
    func ahSectionLabel() -> some View {
        self.font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .tracking(1.2)
            .textCase(.uppercase)
    }
    /// 正文（13pt）
    func ahBody() -> some View {
        self.font(.body)
    }
    /// 次要正文（12pt）
    func ahCallout() -> some View {
        self.font(.callout)
    }
    /// 元信息（11pt secondary）
    func ahMeta() -> some View {
        self.font(.subheadline)
            .foregroundStyle(.secondary)
    }
    /// 极小信息（10pt tertiary）
    func ahCaption() -> some View {
        self.font(.caption)
            .foregroundStyle(Color.ahInk40)
    }
    /// Mono 数字（进度计数等）
    func ahMono(_ size: CGFloat = 13, weight: Font.Weight = .regular) -> some View {
        self.font(.system(size: size, weight: weight, design: .monospaced))
    }
}

// MARK: - 阴影

enum AHShadow {
    /// 卡片浅阴影
    static func small<V: View>(_ view: V) -> some View {
        view.shadow(color: .black.opacity(0.04), radius: 1, x: 0, y: 1)
            .shadow(color: .black.opacity(0.03), radius: 2, x: 0, y: 1)
    }
    /// 弹出菜单、面板
    static func medium<V: View>(_ view: V) -> some View {
        view.shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 3)
            .shadow(color: .black.opacity(0.04), radius: 2, x: 0, y: 1)
    }
    /// 全局 overlay（关闭时模态框）
    static func large<V: View>(_ view: V) -> some View {
        view.shadow(color: .black.opacity(0.10), radius: 20, x: 0, y: 10)
            .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
    }
}

// MARK: - 图标容器尺寸

enum AHIconBox {
    /// 18pt —— 行内小图标容器
    static let xs: CGFloat = 18
    /// 22pt —— 部门图标容器（小）
    static let sm: CGFloat = 22
    /// 28pt —— 卡片标题图标
    static let md: CGFloat = 28
    /// 36pt —— 列表行头像 / 图标容器
    static let lg: CGFloat = 36
    /// 48pt —— 卡片大图标
    static let xl: CGFloat = 48
    /// 64pt —— Hero icon（项目详情）
    static let hero: CGFloat = 64
}

// MARK: - 动效

enum AHAnimation {
    /// 快速 UI 反馈（tab 切换、hover）
    static let quick = Animation.easeOut(duration: 0.18)
    /// 常规转场（面板进出）
    static let standard = Animation.spring(response: 0.35, dampingFraction: 0.85)
    /// 明显的展开折叠
    static let expand = Animation.spring(response: 0.45, dampingFraction: 0.82)
}
