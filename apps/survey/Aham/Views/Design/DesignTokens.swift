import SwiftUI
import AppKit

// MARK: - Design Tokens
//
// Aham App 全局设计系统 token —— 对齐 aham-ui 设计规范 v5.1。
// 机读事实源：aham-ui/tokens.json。所有视图必须使用这些 token，禁止硬编码。
//
// aham-ui 铁规（强约束）：
//   · 三层表面（亮）：#FFFFFF 内容 / #F3F3F3 面板·侧栏·卡片 / #E7E7E7 线·选中。无暖调。
//   · 文字四级：#262626 / #6E6E6E / #9B9B9B / #C4C4C4（对齐 Apple label 递减）。
//   · 蓝 #336EE8 是 garnish 不是 fill：只用于 logo / 主操作 / 发送 / 选中指示。
//   · 层次靠三层背景层差，不靠材质/模糊/阴影。静置/hover 无阴影，仅浮层有。
//   · 状态 = 6px 点 + 文字，绝不 pill/徽章/色块/红黄绿灯。
//   · 单一无衬线（Inter，缺失回退 system）；数字 mono（JetBrains，回退 SF Mono）。
//
// 改视觉改 token，不改 View。

// MARK: - HEX → Color 辅助

private extension NSColor {
    /// 从 "#RRGGBB" 创建 NSColor（sRGB）。
    convenience init(ahHex hex: String) {
        let s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let r = CGFloat((v & 0xFF0000) >> 16) / 255
        let g = CGFloat((v & 0x00FF00) >> 8) / 255
        let b = CGFloat(v & 0x0000FF) / 255
        self.init(srgbRed: r, green: g, blue: b, alpha: 1)
    }
}

extension Color {
    /// 亮/暗自适应动态色（跟随系统外观）。
    static func ahDynamic(_ light: String, dark: String) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(ahHex: isDark ? dark : light)
        })
    }
    /// 纯黑做底的半透明中性填充（hover/active），不随主题。
    static func ahInk(_ alpha: Double) -> Color { Color.black.opacity(alpha) }
}

// MARK: - 颜色

extension Color {
    // ─── 文字四级（亮 #262626/6E6E6E/9B9B9B/C4C4C4 · 暗 F5F5F5/A8A8A8/767676/4A4A4A）───
    /// 主文字 —— 正文/标题
    static let ahInk    = ahDynamic("#262626", dark: "#F5F5F5")
    /// 次要文字 —— 说明、副标题、元数据
    static let ahInk60  = ahDynamic("#6E6E6E", dark: "#A8A8A8")
    /// 三级文字 —— 占位/装饰（非正文）
    static let ahInk40  = ahDynamic("#9B9B9B", dark: "#767676")
    /// 四级 —— 最弱分隔/禁用，不承载正文
    static let ahInk20  = ahDynamic("#C4C4C4", dark: "#4A4A4A")
    /// accent 上的前景（恒白）
    static let ahOnAccent = Color.white

    // ─── 三层表面（亮 #FFFFFF/F3F3F3/E7E7E7 · 暗 #1C1C1C/2A2A2A/3A3A3A）───
    /// tier1 内容底色（窗口/内容区/输入框）
    static let ahPaper    = ahDynamic("#FFFFFF", dark: "#1C1C1C")
    /// tier2 面板/侧栏/卡片底色（靠层差区分，代替边框+阴影）
    static let ahPaperAlt = ahDynamic("#F3F3F3", dark: "#2A2A2A")
    /// 工具条/分隔条底色 —— 同 tier2
    static let ahPaperBar = ahDynamic("#F3F3F3", dark: "#2A2A2A")

    // ─── 描边与分隔（tier3 #E7E7E7 / 暗 #3A3A3A）───
    /// 边框/分隔线（颜色统一 tier3）
    static let ahBorder  = ahDynamic("#E7E7E7", dark: "#3A3A3A")
    /// 分隔线（同 tier3）
    static let ahDivider = ahDynamic("#E7E7E7", dark: "#3A3A3A")
    /// 选中态填充 —— 扁平灰 tier3（非蓝！铁规）
    static let ahSelected = ahDynamic("#E7E7E7", dark: "#3A3A3A")

    // ─── 中性交互填充（无色相，纯黑做底）───
    static let ahFillHover  = ahInk(0.04)
    static let ahFillActive = ahInk(0.08)

    // ─── Accent（单蓝，唯一色相 · garnish only）───
    /// 主强调 #336EE8（暗 #5C8BED）
    static let ahAccent       = ahDynamic("#336EE8", dark: "#5C8BED")
    /// hover #5C8BED（暗 #7BA3F0）
    static let ahAccentHover  = ahDynamic("#5C8BED", dark: "#7BA3F0")
    /// press #164EC3（暗 #336EE8）
    static let ahAccentPress  = ahDynamic("#164EC3", dark: "#336EE8")
    /// 极浅蓝底（tint-surface，几乎不用）
    static let ahAccentBG     = ahDynamic("#EDF0F7", dark: "#23304A")
    /// 极浅蓝描边（tint-border，几乎不用）
    static let ahAccentBorder = ahDynamic("#C8D3EA", dark: "#3A4C6E")

    // ─── 语义色（极弱，仅真风险；禁红黄绿灯）───
    static let ahSuccess   = ahDynamic("#5A7A60", dark: "#8FB096")
    static let ahSuccessBG = ahDynamic("#F0F2F0", dark: "#222A24")
    static let ahWarning   = ahDynamic("#8A7333", dark: "#C2A855")
    static let ahWarningBG = ahDynamic("#F4F1E9", dark: "#2C2820")
    static let ahDanger    = ahDynamic("#9E3D31", dark: "#D08070")
    static let ahDangerBG  = ahDynamic("#F4ECEA", dark: "#2E2220")
    static let ahInfo      = ahAccent
}

// MARK: - 间距 (Spacing)
//
// 4 基网格。留白是首要分隔 —— 先加间距再考虑线。

enum AHSpacing {
    /// 4 pt
    static let xxs: CGFloat = 4
    /// 6 pt（半档，控件内紧凑）
    static let xs: CGFloat = 6
    /// 8 pt
    static let s: CGFloat = 8
    /// 12 pt —— 卡内元素间
    static let m: CGFloat = 12
    /// 16 pt —— 卡片标准 padding
    static let l: CGFloat = 16
    /// 20 pt
    static let xl: CGFloat = 20
    /// 24 pt —— Section 间
    static let xxl: CGFloat = 24
    /// 32 pt —— 页面级
    static let xxxl: CGFloat = 32
    /// 48 pt —— Hero 底部
    static let huge: CGFloat = 48
}

// MARK: - 圆角 (Radius) —— 对齐 aham-ui xs4/sm6/md8/lg12/xl16/2xl20/pill

enum AHRadius {
    /// 4 pt
    static let xs: CGFloat = 4
    /// 6 pt —— 小标签
    static let sm: CGFloat = 6
    /// 8 pt —— 按钮、输入框
    static let md: CGFloat = 8
    /// 12 pt —— 卡片/面板
    static let lg: CGFloat = 12
    /// 16 pt —— modal
    static let xl: CGFloat = 16
    /// 20 pt —— 大弹窗 / Hero squircle
    static let xxl: CGFloat = 20
    /// 999 pt —— 胶囊 / 圆形
    static let pill: CGFloat = 999
}

// MARK: - 字体 (Typography) —— 对齐 aham-ui 11 级文本样式（base 14）
//
// 字族：Inter 未内嵌，正文用 system sans；数字/代码用 system monospaced（≈SF Mono）。
// 取值（字号/行高/字重）严格对齐 tokens.json textStyles。
// 层次靠字号 + 字重 + 大小写 + 位置，禁衬线、禁 100–300 细重。

private extension View {
    /// 用 lineSpacing 近似行高（lineHeight 倍数 → 额外行距）。
    func ahLine(_ size: CGFloat, _ lineHeight: CGFloat) -> some View {
        self.lineSpacing(size * (lineHeight - 1))
    }
}

extension View {
    /// 视图主标题（24 / semibold）—— ↔ Apple Title 2 / aham-ui heading
    func ahTitle() -> some View {
        self.font(.system(size: 24, weight: .semibold))
            .tracking(-0.2)
            .ahLine(24, 1.25)
    }
    /// 区块标题（20 / semibold）—— ↔ subheading
    func ahTitle2() -> some View {
        self.font(.system(size: 20, weight: .semibold))
            .ahLine(20, 1.3)
    }
    /// 卡片标题（17 / semibold）—— ↔ card title
    func ahTitle3() -> some View {
        self.font(.system(size: 17, weight: .semibold))
            .ahLine(17, 1.5)
    }
    /// Section 标签（12 / semibold / uppercase / tracking）—— 次要灰
    func ahSectionLabel() -> some View {
        self.font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.ahInk60)
            .tracking(1.0)
            .textCase(.uppercase)
    }
    /// 正文（14 / regular）—— 主力档
    func ahBody() -> some View {
        self.font(.system(size: 14, weight: .regular))
            .ahLine(14, 1.55)
    }
    /// 次要正文（13 / regular）—— ↔ footnote
    func ahCallout() -> some View {
        self.font(.system(size: 13, weight: .regular))
            .ahLine(13, 1.45)
    }
    /// 元信息（12 / regular / 次要灰）
    func ahMeta() -> some View {
        self.font(.system(size: 12, weight: .regular))
            .foregroundStyle(Color.ahInk60)
    }
    /// 极小信息（12 / regular / 三级灰）—— ↔ caption
    func ahCaption() -> some View {
        self.font(.system(size: 12, weight: .regular))
            .foregroundStyle(Color.ahInk40)
    }
    /// Mono 数字/代码（跟随所在样式字号）
    func ahMono(_ size: CGFloat = 14, weight: Font.Weight = .regular) -> some View {
        self.font(.system(size: size, weight: weight, design: .monospaced))
    }
}

// MARK: - 阴影 —— FLAT：静置/hover 无阴影，仅浮层有一层柔和阴影。

enum AHShadow {
    /// 静置卡片 —— 无阴影（铁规）。保留 API 以兼容旧调用，实为 no-op。
    static func small<V: View>(_ view: V) -> some View { view }
    /// 下拉菜单 / popover（md：0 2px 8px rgba(20,20,20,.05)）
    static func medium<V: View>(_ view: V) -> some View {
        view.shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
    /// 模态（modal：0 12px 36px rgba(20,20,20,.10)）
    static func large<V: View>(_ view: V) -> some View {
        view.shadow(color: .black.opacity(0.10), radius: 18, x: 0, y: 12)
    }
}

// MARK: - 图标容器尺寸（线性单色图标尺阶 16/20/24，容器另设）

enum AHIconBox {
    /// 18pt —— 行内小图标容器
    static let xs: CGFloat = 18
    /// 22pt —— 部门图标容器（小）
    static let sm: CGFloat = 22
    /// 28pt —— 卡片标题图标
    static let md: CGFloat = 28
    /// 36pt —— 列表行图标容器
    static let lg: CGFloat = 36
    /// 48pt —— 卡片大图标
    static let xl: CGFloat = 48
    /// 64pt —— Hero icon
    static let hero: CGFloat = 64
}

// MARK: - 动效 —— 克制：服务反馈不表演。统一缓动 cubic-bezier(.2,0,0,1)，禁弹跳/循环/>.3s。

enum AHAnimation {
    /// fast .12s —— hover / 快速反馈
    static let quick = Animation.timingCurve(0.2, 0, 0, 1, duration: 0.12)
    /// base .18s —— tab 切换 / 面板进出
    static let standard = Animation.timingCurve(0.2, 0, 0, 1, duration: 0.18)
    /// slow .28s —— 展开折叠
    static let expand = Animation.timingCurve(0.2, 0, 0, 1, duration: 0.28)
}

// MARK: - 扁平饰面（替代旧 Liquid Glass）
//
// aham-ui 铁规：层次靠三层层差，禁材质/模糊。原 ahGlassBar/ahGlassCapsule
// 改为扁平实现，保留 API 以兼容调用方。

extension View {
    /// 水平 chrome 条（工具条/Tab 栏）—— 扁平 tier2 底，无玻璃。
    func ahGlassBar() -> some View {
        self.background(Color.ahPaperBar)
    }

    /// 胶囊容器 —— 扁平。
    /// - isEnabled: false 不画底（未选中）。
    /// - prominent: true 选中态用扁平灰 tier3（非蓝！铁规）。
    @ViewBuilder
    func ahGlassCapsule(isEnabled: Bool = true, prominent: Bool = false) -> some View {
        if isEnabled {
            self.background(
                Capsule(style: .continuous)
                    .fill(prominent ? Color.ahSelected : Color.ahPaperAlt)
            )
        } else {
            self
        }
    }
}
