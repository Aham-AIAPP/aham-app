import SwiftUI

// ModuleSidebarView V3.1
// ────────────────────────────────────────────────────────────────────────
// V3.1 改动：
//   1. 修 bug：选中态 2pt accent 条用 overlay(alignment:) 而不是 HStack 里的
//      不定高 Rectangle —— 避免被上层 Spacer 拉成"大蓝方块"。
//   2. 正常 macOS sidebar 布局：logo 顶 → modules 紧贴 logo 向下顺排 → Spacer
//      推到底 → Settings 底部。未来加新 module 直接往 VStack 里加一行。
//   3. 保留 V3：accent 条 + ahAccentBG 背景做选中态、统一 AHIconBox.xs 尺寸。

struct ModuleSidebarView: View {
    @Environment(AppStore.self) private var appStore

    var body: some View {
        VStack(spacing: 0) {
            // Logo
            Button {
                appStore.isSurveying = false
                appStore.activeModule = .home
            } label: {
                let isActive = appStore.activeModule == .home
                Image(systemName: "sparkles")
                    .font(.system(size: AHIconBox.xs, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AHSpacing.l)
                    .foregroundStyle(isActive ? Color.ahAccent : Color.ahAccent.opacity(0.5))
            }
            .buttonStyle(.plain)
            .help("首页")

            Rectangle().fill(Color.ahDivider).frame(height: 1)

            // Modules
            VStack(spacing: AHSpacing.xxs) {
                moduleButton(icon: "doc.text.magnifyingglass", module: .survey, help: "调研")
                moduleButton(icon: "chart.line.uptrend.xyaxis", module: .sales, help: "看板")
            }
            .padding(.vertical, AHSpacing.s)

            Spacer(minLength: 0)

            // Bottom: Settings
            Rectangle().fill(Color.ahDivider).frame(height: 1)

            SettingsLink {
                Image(systemName: "gearshape")
                    .font(.system(size: AHIconBox.xs))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AHSpacing.m)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.ahInk60)
            .help("设置 (⌘,)")
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func moduleButton(icon: String, module: AppModule, help: String) -> some View {
        let isActive = appStore.activeModule == module
        return Button {
            appStore.isSurveying = false
            appStore.activeModule = module
        } label: {
            Image(systemName: icon)
                .font(.system(size: AHIconBox.xs))
                .frame(maxWidth: .infinity)
                .padding(.vertical, AHSpacing.s)
                .foregroundStyle(isActive ? Color.ahAccent : Color.ahInk60)
                .background(
                    RoundedRectangle(cornerRadius: AHRadius.sm, style: .continuous)
                        .fill(isActive ? Color.ahAccentBG : Color.clear)
                        .padding(.leading, 2)
                )
                .overlay(alignment: .leading) {
                    if isActive {
                        Rectangle()
                            .fill(Color.ahAccent)
                            .frame(width: 2)
                    }
                }
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
