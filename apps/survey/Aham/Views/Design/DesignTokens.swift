import SwiftUI
import AppKit

// MARK: - AhamUI 10.1.1 native tokens
// Source: aham-ui/tokens.json (9afc302). Native controls retain macOS semantics.
// Brand-blue primary actions (same in light and dark), paired light/dark colors, stable control geometry.

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
    static let ahInk = ahDynamic("#151515", dark: "#F5F5F3")
    static let ahInk60 = ahDynamic("#666664", dark: "#A6A6A3")
    static let ahInk40 = ahDynamic("#888886", dark: "#7B7B79")
    static let ahInk20 = ahDynamic("#E5E5E4", dark: "#2E2E2C")
    static let ahOnAccent = ahDynamic("#FFFFFF", dark: "#151515")
    static let ahPaper = ahDynamic("#FFFFFF", dark: "#151515")
    static let ahPaperAlt = ahDynamic("#F3F3F3", dark: "#20201F")
    static let ahPaperBar = ahDynamic("#EDECEB", dark: "#0B0B0B")
    static let ahCanvas = ahDynamic("#EDECEB", dark: "#0B0B0B")
    static let ahBorder = ahDynamic("#E5E5E4", dark: "#2E2E2C")
    static let ahInputBorder = ahDynamic("#8C8B89", dark: "#6E6E6B")
    static let ahDivider = ahDynamic("#E5E5E4", dark: "#2E2E2C")
    static let ahSelected = ahDynamic("#EBEBEA", dark: "#2C2C2A")
    static let ahFillHover = ahDynamic("#F3F3F3", dark: "#20201F")
    static let ahFillActive = ahDynamic("#E3E2E1", dark: "#383836")
    static let ahAccent = ahDynamic("#336EE8", dark: "#6C97F0")
    static let ahAccentHover = ahDynamic("#336EE8", dark: "#6C97F0")
    static let ahAccentPress = ahDynamic("#336EE8", dark: "#6C97F0")
    static let ahAccentBG = ahDynamic("#EDF1FA", dark: "#1F2A40")
    static let ahAccentBorder = ahDynamic("#E5E5E4", dark: "#2E2E2C")
    static let ahAction = ahDynamic("#336EE8", dark: "#336EE8")
    static let ahActionHover = ahDynamic("#2A62D6", dark: "#2A62D6")
    static let ahActionPress = ahDynamic("#2357C4", dark: "#2357C4")
    static let ahOnAction = ahDynamic("#FFFFFF", dark: "#FFFFFF")
    static let ahButton = ahDynamic("#F3F3F2", dark: "#252524")
    static let ahButtonHover = ahDynamic("#EBEBEA", dark: "#2E2E2C")
    static let ahButtonPress = ahDynamic("#E3E2E1", dark: "#383836")
    static let ahSuccess = ahDynamic("#1F7A4D", dark: "#6DBE8F")
    static let ahSuccessBG = ahDynamic("#EAF4EE", dark: "#1C2A22")
    static let ahWarning = ahDynamic("#A15C07", dark: "#E0A84A")
    static let ahWarningBG = ahDynamic("#FBF2E4", dark: "#2E2617")
    static let ahDanger = ahDynamic("#B42318", dark: "#F08A7E")
    static let ahDangerBG = ahDynamic("#FBEBE9", dark: "#33201D")
    static let ahInfo = ahDynamic("#336EE8", dark: "#7EA4F2")
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
    /// 视图主标题（20 / semibold）—— ↔ Apple Title 2 / aham-ui heading
    func ahTitle() -> some View {
        self.font(.system(size: 20, weight: .semibold))
            .tracking(-0.2)
            .ahLine(20, 1.3)
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
            .foregroundStyle(Color.ahInk60)
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
    /// Keyboard actions and Reduce Motion never move geometry.
    static func motion(_ duration: Double) -> Animation? {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              NSApp.currentEvent?.type != .keyDown else { return nil }
        return .timingCurve(0.2, 0, 0, 1, duration: duration)
    }
    static var quick: Animation? { motion(0.12) }
    static var standard: Animation? { motion(0.15) }
    static var expand: Animation? { motion(0.20) }
}

enum AHLayout {
    static let control: CGFloat = 32
    static let largeControl: CGFloat = 40
    static let editorHeight: CGFloat = 120
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
