import SwiftUI

// MARK: - Design Components —— 对齐 aham-ui v5.1 铁规
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
        content()
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
                .buttonStyle(.plain)
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
                    withAnimation(AHAnimation.quick) { selection = item.0 }
                } label: {
                    HStack(spacing: AHSpacing.xs) {
                        if let sym = item.2 {
                            Image(systemName: sym).font(.system(size: 11, weight: .medium))
                        }
                        Text(item.1).font(.system(size: 13, weight: selected ? .semibold : .regular))
                    }
                    .foregroundStyle(selected ? Color.ahInk : Color.ahInk60)
                    .padding(.horizontal, AHSpacing.m)
                    .padding(.vertical, AHSpacing.xs)
                    .ahGlassCapsule(isEnabled: selected, prominent: selected)
                }
                .buttonStyle(.plain)
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

/// 主按钮 —— accent 实底 / 白字（铁规：一组一个 primary，蓝只在主操作）。
struct AHPrimaryButtonStyle: ButtonStyle {
    var large: Bool = false
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: large ? 15 : 14, weight: .semibold))
            .foregroundStyle(Color.ahOnAccent)
            .padding(.horizontal, large ? AHSpacing.xl : AHSpacing.l)
            .padding(.vertical, large ? 10 : 7)
            .background(
                RoundedRectangle(cornerRadius: AHRadius.md, style: .continuous)
                    .fill(configuration.isPressed ? Color.ahAccentPress : Color.ahAccent)
            )
            .opacity(isEnabled ? 1 : 0.4)
    }
}

/// 次按钮 —— tier2 底 + 细 tier3 描边 + 主文字。
struct AHSecondaryButtonStyle: ButtonStyle {
    var large: Bool = false
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: large ? 15 : 14, weight: .medium))
            .foregroundStyle(Color.ahInk)
            .padding(.horizontal, large ? AHSpacing.xl : AHSpacing.l)
            .padding(.vertical, large ? 9 : 6)
            .background(
                RoundedRectangle(cornerRadius: AHRadius.md, style: .continuous)
                    .fill(configuration.isPressed ? Color.ahSelected : Color.ahPaperAlt)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AHRadius.md, style: .continuous)
                    .strokeBorder(Color.ahBorder, lineWidth: 1)
            )
            .opacity(isEnabled ? 1 : 0.4)
    }
}

/// Ghost 按钮 —— 仅 hover/press 有中性填充底。
struct AHGhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .regular))
            .foregroundStyle(Color.ahInk60)
            .padding(.horizontal, AHSpacing.s)
            .padding(.vertical, AHSpacing.xs)
            .background(
                RoundedRectangle(cornerRadius: AHRadius.sm, style: .continuous)
                    .fill(configuration.isPressed ? Color.ahFillActive : Color.clear)
            )
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
