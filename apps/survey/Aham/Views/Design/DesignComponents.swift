import SwiftUI

// MARK: - Design Components —— 对齐 aham-ui 10.1.0 原生适配
//
// Aham App 共用组件库。新视图应由下列原子拼装。
//
// 铁规落实：
//   · 卡片无边框无阴影；选中=扁平灰 tier3（非蓝）。深度靠三层层差。
//   · 状态 = 6px 点 + 文字（AHStatusDot / AHStatus），绝不 pill/徽章/色块。
//   · AHPill 仅作中性 tag（无色相填充）；不要用它表达状态。
//   · 蓝只用于主操作/选中指示；数字用 mono。
//
// 组件索引：
//   AHCard / AHSection / AHPill(中性 tag) / AHStatusDot / AHStatus(点+文字)
//   AHIconTile / AHEmptyState / AHDivider / AHSearchField / AHSegmentedTab
//   AHStatCard / AHLabeledRow / FlowLayout
//   Button styles: .ahPrimary / .ahSecondary / .ahGhost

// MARK: - AHCard

/// 标准卡片底座 —— 无边框、无阴影，靠 tier2 层差从 tier1 内容区浮出。
/// 选中（tinted）= 扁平灰 tier3。
struct AHCard<Content: View>: View {
    var padding: CGFloat = AHSpacing.l
    var radius: CGFloat = AHRadius.lg
    var elevated: Bool = true        // 兼容旧调用；铁规下静置无阴影，此参数忽略
    var tinted: Bool = false         // true = 选中/高亮，用扁平灰 tier3
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: AHSpacing.m) {
            content()
        }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(tinted ? Color.ahSelected : Color.ahPaperAlt)
            )
    }
}

// MARK: - AHSection

/// 带标题行的 Section 容器。
struct AHSection<Content: View, Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var content: () -> Content
    @ViewBuilder var trailing: () -> Trailing

    init(_ title: String,
         subtitle: String? = nil,
         @ViewBuilder content: @escaping () -> Content,
         @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.content = content
        self.trailing = trailing
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AHSpacing.m) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: AHSpacing.xxs) {
                    Text(title).ahSectionLabel()
                    if let s = subtitle {
                        Text(s).ahCaption()
                    }
                }
                Spacer()
                trailing()
            }
            content()
        }
    }
}

extension AHSection where Trailing == EmptyView {
    init(_ title: String, subtitle: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content
        self.trailing = { EmptyView() }
    }
}

// MARK: - AHPill（中性 tag）

/// 中性标签 —— 分类/属性 tag。**不用于状态**（状态请用 AHStatus）。
/// 铁规：tag 无色相，tier2 底 + 次要灰字。style 仅保留语义文字色（极弱），底统一中性。
struct AHPill: View {
    enum Style {
        case neutral, success, warning, danger, info, accent
        var fg: Color {
            switch self {
            case .neutral: return .ahInk60
            case .success: return .ahSuccess
            case .warning: return .ahWarning
            case .danger:  return .ahDanger
            case .info:    return .ahInfo
            case .accent:  return .ahAccent
            }
        }
    }

    let text: String
    var icon: String? = nil
    var style: Style = .neutral

    var body: some View {
        HStack(spacing: AHSpacing.xxs) {
            if let icon {
                Image(systemName: icon).font(.system(size: 10, weight: .medium))
            }
            Text(text).font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(style.fg)
        .padding(.horizontal, AHSpacing.s)
        .padding(.vertical, AHSpacing.xxs)
        .background(
            Capsule(style: .continuous).fill(Color.ahPaperAlt)
        )
    }
}

// MARK: - AHStatusDot / AHStatus

/// 6pt 状态点。
struct AHStatusDot: View {
    let color: Color
    var size: CGFloat = 6
    var body: some View {
        Circle().fill(color).frame(width: size, height: size)
    }
}

/// 状态指示 = 6px 点 + 文字（铁规）。颜色仅作辅助，文字承载语义（differentiate without color）。
struct AHStatus: View {
    let text: String
    var color: Color = .ahInk40
    var body: some View {
        HStack(spacing: AHSpacing.xs) {
            AHStatusDot(color: color)
            Text(text).font(.system(size: 12, weight: .regular)).foregroundStyle(Color.ahInk60)
        }
    }
}

// MARK: - AHIconTile

/// 圆角图标容器 —— 中性 tier2 底（铁规：禁彩色填充图标框）。
/// hero/logo 等需蓝着色时传 tint: .ahAccent。
struct AHIconTile: View {
    let symbol: String
    var size: CGFloat = AHIconBox.md
    var tint: Color = .ahInk
    var background: Color? = nil   // 默认中性 tier2

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(background ?? Color.ahPaperAlt)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: size * 0.45, weight: .medium))
                    .foregroundStyle(tint)
            )
            .frame(width: size, height: size)
    }
}

// MARK: - AHEmptyState

/// 空状态 —— 图标 + 一句说明 + 下一步动作（铁规：空屏必须给出路）。
struct AHEmptyState: View {
    let symbol: String
    let title: String
    var message: String? = nil
    var actionLabel: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: AHSpacing.m) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Color.ahInk40)
            Text(title).ahTitle3()
            if let message {
                Text(message).ahMeta().multilineTextAlignment(.center)
            }
            if let actionLabel, let action {
                Button(actionLabel, action: action)
                    .buttonStyle(.ahPrimary)
                    .padding(.top, AHSpacing.xs)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(AHSpacing.xxl)
    }
}

// MARK: - AHDivider

struct AHDivider: View {
    var body: some View {
        Rectangle().fill(Color.ahDivider).frame(height: 1)
    }
}

// MARK: - AHSearchField

/// 搜索框 —— 扁平 tier2 底，无强边框。
struct AHSearchField: View {
    @Binding var text: String
    var placeholder: String = "搜索..."

    var body: some View {
        HStack(spacing: AHSpacing.xs) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Color.ahInk40)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.ahInk40)
                }
                .buttonStyle(.ahInline)
                .accessibilityLabel("清除搜索")
            }
        }
        .padding(.horizontal, AHSpacing.m)
        .padding(.vertical, AHSpacing.xs)
        .background(
            Capsule(style: .continuous).fill(Color.ahPaperAlt)
        )
    }
}

// MARK: - AHSegmentedTab

/// 横向 Tab —— 扁平。选中 = 扁平灰 tier3 + 主文字（非蓝）；容器 tier2。
struct AHSegmentedTab<T: Hashable>: View {
    @Binding var selection: T
    let items: [(T, String, String?)]  // (value, label, sfSymbol?)

    var body: some View {
        HStack(spacing: AHSpacing.xxs) {
            ForEach(items, id: \.0) { item in
                let selected = item.0 == selection
                Button {
                    selection = item.0
                } label: {
                    HStack(spacing: AHSpacing.xs) {
                        if let sym = item.2 {
                            Image(systemName: sym).font(.system(size: 11, weight: .medium))
                        }
                        Text(item.1).font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(selected ? Color.ahInk : Color.ahInk60)
                    .padding(.horizontal, AHSpacing.m)
                    .padding(.vertical, AHSpacing.xs)
                    .ahGlassCapsule(isEnabled: selected, prominent: selected)
                }
                .buttonStyle(AHInlineButtonStyle(selected: selected, radius: AHRadius.pill))
                .accessibilityValue(selected ? "已选中" : "")
            }
        }
        .padding(AHSpacing.xxs)
        .background(
            Capsule(style: .continuous).fill(Color.ahPaperAlt)
        )
    }
}

// MARK: - AHStatCard

/// 数据卡片 —— mono 数值（铁规：数字 mono）。delta 用箭头形状 + 极弱语义色。
struct AHStatCard: View {
    let label: String
    let value: String
    var delta: String? = nil
    var deltaPositive: Bool = true
    var icon: String? = nil

    var body: some View {
        AHCard {
            VStack(alignment: .leading, spacing: AHSpacing.s) {
                HStack {
                    Text(label).ahMeta()
                    Spacer()
                    if let icon {
                        AHIconTile(symbol: icon, size: AHIconBox.sm)
                    }
                }
                Text(value)
                    .font(.system(size: 26, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.ahInk)
                if let delta {
                    HStack(spacing: AHSpacing.xxs) {
                        Image(systemName: deltaPositive ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 10, weight: .bold))
                        Text(delta).font(.system(size: 12, weight: .medium, design: .monospaced))
                    }
                    .foregroundStyle(deltaPositive ? Color.ahSuccess : Color.ahDanger)
                }
            }
        }
    }
}

// MARK: - Button Styles

/// 按钮共用状态机；主按钮使用中性 action/on 配对色，蓝色仅表示键盘焦点。
enum AHButtonVariant: CaseIterable { case primary, secondary, ghost }

/// One state resolver keeps disabled > pressed > hover precedence across variants.
enum AHControlState: Equatable {
    case idle, hover, pressed, disabled
    static func resolve(enabled: Bool, pressed: Bool, hovered: Bool) -> Self {
        if !enabled { return .disabled }
        if pressed { return .pressed }
        return hovered ? .hover : .idle
    }
}

private struct AHButtonSurface<Label: View>: View {
    let label: Label
    let variant: AHButtonVariant
    let pressed: Bool
    var large = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.isFocused) private var focused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false
    private var state: AHControlState { .resolve(enabled: enabled, pressed: pressed, hovered: hovered) }
    private var foreground: Color {
        state == .disabled ? .ahInk60 : (variant == .primary ? .ahOnAccent : .ahInk)
    }
    private var background: Color {
        if state == .disabled { return .ahButton }
        switch variant {
        case .primary: return state == .pressed ? .ahActionPress : state == .hover ? .ahActionHover : .ahAction
        case .secondary: return state == .pressed ? .ahButtonPress : state == .hover ? .ahButtonHover : .ahButton
        case .ghost: return state == .pressed ? .ahFillActive : state == .hover ? .ahFillHover : .clear
        }
    }
    var body: some View {
        label
            .transaction { $0.animation = nil }
            .font(.system(size: 14, weight: variant == .primary ? .medium : .regular))
            .foregroundStyle(foreground)
            .padding(.horizontal, variant == .ghost ? AHSpacing.s : AHSpacing.m)
            .frame(minHeight: large ? AHLayout.largeControl : AHLayout.control)
            .background(background, in: .rect(cornerRadius: AHRadius.sm))
            .overlay {
                RoundedRectangle(cornerRadius: AHRadius.sm)
                    .strokeBorder(focused && enabled ? Color.ahAccent : .clear, lineWidth: 2)
            }
            .contentShape(Rectangle())
            .onHover { hovered = $0 }
            .animation(hovered || !enabled || reduceMotion ? nil : AHAnimation.quick, value: hovered)
    }
}

/// Feedback for existing row/tab/icon geometry. Adds no padding, scale or shadow.
struct AHInlineButtonStyle: ButtonStyle {
    var selected = false
    var radius: CGFloat = AHRadius.sm
    func makeBody(configuration: Configuration) -> some View {
        AHInlineSurface(label: configuration.label, pressed: configuration.isPressed,
                        selected: selected, radius: radius)
    }
}

struct AHInlineSurface<Label: View>: View {
    let label: Label
    let pressed: Bool
    let selected: Bool
    let radius: CGFloat
    @State private var hovered = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.isFocused) private var focused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var state: AHControlState { .resolve(enabled: enabled, pressed: pressed, hovered: hovered) }
    private var fill: Color {
        if state == .disabled { return .clear }
        if state == .pressed { return .ahFillActive }
        if selected { return .ahSelected }
        return state == .hover ? .ahFillHover : .clear
    }
    var body: some View {
        label
            .transaction { $0.animation = nil }
            .background(fill, in: .rect(cornerRadius: radius))
            .overlay {
                RoundedRectangle(cornerRadius: radius)
                    .fill(Color.ahInk.opacity(state == .pressed ? 0.08 : state == .hover ? 0.04 : 0))
                    .allowsHitTesting(false)
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(focused && enabled ? Color.ahAccent : .clear, lineWidth: 2)
            }
            .contentShape(Rectangle())
            .onHover { hovered = $0 }
            .animation(hovered || !enabled || reduceMotion ? nil : AHAnimation.quick, value: hovered)
    }
}

extension ButtonStyle where Self == AHInlineButtonStyle {
    static var ahInline: AHInlineButtonStyle { .init() }
}

/// Input focus uses the same border for all editors; layout stays unchanged.
struct AHInputBorder: ViewModifier {
    let focused: Bool
    var radius: CGFloat = AHRadius.sm
    func body(content: Content) -> some View {
        content.overlay {
            RoundedRectangle(cornerRadius: radius)
                .strokeBorder(focused ? Color.ahAccent : Color.ahInputBorder, lineWidth: focused ? 2 : 1)
                .allowsHitTesting(false)
        }
    }
}
extension View {
    func ahInputBorder(focused: Bool, radius: CGFloat = AHRadius.sm) -> some View {
        modifier(AHInputBorder(focused: focused, radius: radius))
    }
}

struct AHPrimaryButtonStyle: ButtonStyle {
    var large = false
    func makeBody(configuration: Configuration) -> some View {
        AHButtonSurface(label: configuration.label, variant: .primary, pressed: configuration.isPressed, large: large)
    }
}
struct AHSecondaryButtonStyle: ButtonStyle {
    var large = false
    func makeBody(configuration: Configuration) -> some View {
        AHButtonSurface(label: configuration.label, variant: .secondary, pressed: configuration.isPressed, large: large)
    }
}
struct AHGhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        AHButtonSurface(label: configuration.label, variant: .ghost, pressed: configuration.isPressed)
    }
}

extension ButtonStyle where Self == AHPrimaryButtonStyle {
    static var ahPrimary: AHPrimaryButtonStyle { .init() }
    static var ahPrimaryLarge: AHPrimaryButtonStyle { .init(large: true) }
}
extension ButtonStyle where Self == AHSecondaryButtonStyle {
    static var ahSecondary: AHSecondaryButtonStyle { .init() }
    static var ahSecondaryLarge: AHSecondaryButtonStyle { .init(large: true) }
}
extension ButtonStyle where Self == AHGhostButtonStyle {
    static var ahGhost: AHGhostButtonStyle { .init() }
}

// MARK: - AHLabeledRow

/// 键-值一行：左次要灰 label，右正文。
struct AHLabeledRow<Content: View>: View {
    let label: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: AHSpacing.m) {
            Text(label)
                .ahMeta()
                .frame(width: 84, alignment: .trailing)
            content()
            Spacer(minLength: 0)
        }
    }
}

// MARK: - FlowLayout

/// 自动换行流式布局，适合多个 tag 横排自动折行。
struct FlowLayout: Layout {
    var spacing: CGFloat = AHSpacing.xs

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var height: CGFloat = 0
        var x: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                height += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
        height += rowHeight
        return CGSize(width: maxWidth, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
    }
}

// MARK: - Preview helpers

#if DEBUG
struct AHPreviewBox<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: AHSpacing.s) {
            Text(title).ahSectionLabel()
            content()
        }
        .padding(AHSpacing.l)
    }
}
#endif
