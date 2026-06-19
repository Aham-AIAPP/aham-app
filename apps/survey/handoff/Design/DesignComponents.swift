import SwiftUI

// MARK: - Design Components
//
// Aham App 共用组件库。
// 新视图应尽量由下列原子拼装，而不是自己写 padding/background/overlay。
//
// 组件索引：
//   AHCard            — 所有卡片的底座（白/控件底 + 圆角 + 描边 + 浅阴影）
//   AHSection         — 带标题的 Section 容器（标题 + 可选右侧操作 + 内容）
//   AHPill            — 胶囊标签（状态/分类）
//   AHStatusDot       — 状态小圆点（绿/黄/红/灰）
//   AHIconTile        — 圆角图标容器（上色背景 + SF Symbol）
//   AHEmptyState      — 空状态占位
//   AHDivider         — 标准分隔线
//   AHSearchField     — 顶部搜索条样式
//   Button styles     — .buttonStyle(.ahPrimary) / .ahGhost / .ahSecondary

// MARK: - AHCard

/// 标准卡片底座。用法：
/// ```
/// AHCard {
///     VStack { ... }
/// }
/// ```
/// 默认 16pt padding + 10pt 圆角 + 描边 + 浅阴影。
/// 通过 padding:/radius:/elevated: 定制。
struct AHCard<Content: View>: View {
    var padding: CGFloat = AHSpacing.l
    var radius: CGFloat = AHRadius.lg
    var elevated: Bool = true
    var tinted: Bool = false     // true = 用 ahAccentBG 着色（选中/高亮卡）
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(tinted ? Color.ahAccentBG : Color.ahPaperAlt)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(tinted ? Color.ahAccentBorder : Color.ahBorder, lineWidth: 1)
            )
            .shadow(color: elevated ? .black.opacity(0.04) : .clear, radius: 1, x: 0, y: 1)
            .shadow(color: elevated ? .black.opacity(0.03) : .clear, radius: 2, x: 0, y: 1)
    }
}

// MARK: - AHSection

/// 带标题行的 Section 容器。用法：
/// ```
/// AHSection("调研进度") {
///     ...content
/// } trailing: {
///     Button("展开") { ... }
/// }
/// ```
struct AHSection<Content: View, Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var content: () -> Content
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        VStack(alignment: .leading, spacing: AHSpacing.m) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
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

// MARK: - AHPill

/// 胶囊标签。用于状态/分类/tag。
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
        var bg: Color { fg.opacity(0.12) }
    }

    let text: String
    var icon: String? = nil
    var style: Style = .neutral

    var body: some View {
        HStack(spacing: AHSpacing.xs) {
            if let icon {
                Image(systemName: icon).font(.system(size: 10, weight: .semibold))
            }
            Text(text).font(.caption.weight(.medium))
        }
        .foregroundStyle(style.fg)
        .padding(.horizontal, AHSpacing.s)
        .padding(.vertical, 3)
        .background(
            Capsule(style: .continuous).fill(style.bg)
        )
    }
}

// MARK: - AHStatusDot

/// 6pt 小圆点 —— 状态指示。
struct AHStatusDot: View {
    let color: Color
    var size: CGFloat = 6
    var body: some View {
        Circle().fill(color).frame(width: size, height: size)
    }
}

// MARK: - AHIconTile

/// 圆角图标容器（AccentBG + SF Symbol）。
/// size: 图标框大小；symbol: SF Symbol 名；tint: 图标颜色（默认 accent）。
struct AHIconTile: View {
    let symbol: String
    var size: CGFloat = AHIconBox.md
    var tint: Color = .ahAccent
    var background: Color? = nil   // 默认 tint.opacity(0.12)

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(background ?? tint.opacity(0.12))
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: size * 0.45, weight: .semibold))
                    .foregroundStyle(tint)
            )
            .frame(width: size, height: size)
    }
}

// MARK: - AHEmptyState

/// 空列表占位
struct AHEmptyState: View {
    let symbol: String
    let title: String
    var message: String? = nil
    var actionLabel: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: AHSpacing.m) {
            Image(systemName: symbol)
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.tertiary)
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

/// 顶部工具条用的搜索框（胶囊形，带搜索图标）。
struct AHSearchField: View {
    @Binding var text: String
    var placeholder: String = "搜索..."

    var body: some View {
        HStack(spacing: AHSpacing.xs) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.callout)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, AHSpacing.m)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous).fill(Color.ahPaperAlt)
        )
        .overlay(
            Capsule(style: .continuous).strokeBorder(Color.ahBorder, lineWidth: 1)
        )
    }
}

// MARK: - AHSegmentedTab

/// 类似 Segmented Control 的横向 Tab。适合 3–6 项。
/// 用 selection binding + items 数组。
struct AHSegmentedTab<T: Hashable>: View {
    @Binding var selection: T
    let items: [(T, String, String?)]  // (value, label, sfSymbol?)

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items, id: \.0) { item in
                let selected = item.0 == selection
                Button {
                    withAnimation(AHAnimation.quick) { selection = item.0 }
                } label: {
                    HStack(spacing: AHSpacing.xs) {
                        if let sym = item.2 {
                            Image(systemName: sym).font(.system(size: 11, weight: .semibold))
                        }
                        Text(item.1).font(.callout.weight(selected ? .semibold : .regular))
                    }
                    .foregroundStyle(selected ? Color.ahInk : Color.ahInk60)
                    .padding(.horizontal, AHSpacing.m)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: AHRadius.sm, style: .continuous)
                            .fill(selected ? Color.ahPaperAlt : Color.clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: AHRadius.sm, style: .continuous)
                            .strokeBorder(selected ? Color.ahBorder : Color.clear, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: AHRadius.md, style: .continuous)
                .fill(Color.ahPaperBar)
        )
    }
}

// MARK: - AHStatCard

/// 数据卡片（仪表盘用）：label + 数字 + 可选变化值
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
                Text(value).font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                if let delta {
                    HStack(spacing: 2) {
                        Image(systemName: deltaPositive ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 10, weight: .bold))
                        Text(delta).font(.caption.weight(.medium))
                    }
                    .foregroundStyle(deltaPositive ? Color.ahSuccess : Color.ahDanger)
                }
            }
        }
    }
}

// MARK: - Button Styles

/// 主按钮：accent 背景 / 白字 / 圆角。
struct AHPrimaryButtonStyle: ButtonStyle {
    var large: Bool = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, large ? AHSpacing.l : AHSpacing.m)
            .padding(.vertical, large ? 10 : 7)
            .background(
                RoundedRectangle(cornerRadius: AHRadius.md, style: .continuous)
                    .fill(Color.ahAccent)
                    .opacity(configuration.isPressed ? 0.8 : 1)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

/// 次按钮：描边 / 文字色。
struct AHSecondaryButtonStyle: ButtonStyle {
    var large: Bool = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.medium))
            .foregroundStyle(Color.ahInk)
            .padding(.horizontal, large ? AHSpacing.l : AHSpacing.m)
            .padding(.vertical, large ? 9 : 6)
            .background(
                RoundedRectangle(cornerRadius: AHRadius.md, style: .continuous)
                    .fill(Color.ahPaperAlt)
                    .opacity(configuration.isPressed ? 0.7 : 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AHRadius.md, style: .continuous)
                    .strokeBorder(Color.ahBorder, lineWidth: 1)
            )
    }
}

/// Ghost 按钮：只在 hover/press 时有底。
struct AHGhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout)
            .foregroundStyle(Color.ahInk60)
            .padding(.horizontal, AHSpacing.s)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: AHRadius.sm, style: .continuous)
                    .fill(configuration.isPressed ? Color.ahPaperAlt : Color.clear)
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

/// 键-值一行（表单/信息展示）：左灰色 label，右正文。
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
