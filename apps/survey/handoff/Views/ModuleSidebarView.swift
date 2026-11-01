import SwiftUI

// ModuleSidebarView V3
// ────────────────────────────────────────────────────────────────────────
// V3 改动：
//   1. 模块按钮选中态：从 accent 半透明背景 → ahAccentBG + 左侧 2pt accent 条
//   2. 统一所有尺寸走 AHIconBox
//   3. 去掉顶部 logo 按钮的描边和 hover 感

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
                    .font(.system(size: 18, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AHSpacing.l)
                    .foregroundStyle(isActive ? Color.ahAccent : Color.ahAccent.opacity(0.5))
            }
            .buttonStyle(.plain)
            .help("首页")

            Rectangle().fill(Color.ahDivider).frame(height: 1)

            VStack(spacing: AHSpacing.xxs) {
                moduleButton(icon: "doc.text.magnifyingglass", module: .survey, help: "调研")
                moduleButton(icon: "chart.line.uptrend.xyaxis", module: .sales, help: "看板")
            }
            .padding(.vertical, AHSpacing.s)

            Spacer()

            Rectangle().fill(Color.ahDivider).frame(height: 1)

            SettingsLink {
                Image(systemName: "gearshape")
                    .font(.system(size: 16))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AHSpacing.m)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.ahInk60)
            .help("设置 (⌘,)")
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.ahPaperBar)
    }

    private func moduleButton(icon: String, module: AppModule, help: String) -> some View {
        let isActive = appStore.activeModule == module
        return Button {
            appStore.isSurveying = false
            appStore.activeModule = module
        } label: {
            HStack(spacing: 0) {
                Rectangle()
                    .fill(isActive ? Color.ahAccent : Color.clear)
                    .frame(width: 2)
                Image(systemName: icon)
                    .font(.system(size: 17))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AHSpacing.s)
                    .foregroundStyle(isActive ? Color.ahAccent : Color.ahInk60)
            }
            .background(
                RoundedRectangle(cornerRadius: AHRadius.sm, style: .continuous)
                    .fill(isActive ? Color.ahAccentBG : Color.clear)
                    .padding(.leading, 2)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, AHSpacing.xs)
        .help(help)
    }
}
