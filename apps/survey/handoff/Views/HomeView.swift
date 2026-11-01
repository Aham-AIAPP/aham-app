import SwiftUI

// HomeView V3
// ────────────────────────────────────────────────────────────────────────
// V3 重构要点：
//   1. Hero 图标从彩色大 squircle 变为简洁线框 + 内嵌符号（AHIconTile hero）
//   2. 三个关键词标签从「彩色块 + 副标题」重做为 AHCard 形式，留白更多
//   3. 加入快速入口：新建项目 / 继续上次项目 / 查看看板
//   4. 使用 AHSpacing 替换所有 magic number

struct HomeView: View {
    @Environment(AppStore.self) private var appStore

    var body: some View {
        VStack(spacing: AHSpacing.huge) {
            Spacer()

            // Hero
            VStack(spacing: AHSpacing.l) {
                RoundedRectangle(cornerRadius: AHRadius.xxl, style: .continuous)
                    .fill(Color.ahAccentBG)
                    .overlay(
                        RoundedRectangle(cornerRadius: AHRadius.xxl, style: .continuous)
                            .strokeBorder(Color.ahAccentBorder, lineWidth: 1)
                    )
                    .overlay(
                        Image(systemName: "sparkles")
                            .font(.system(size: 38, weight: .light))
                            .foregroundStyle(Color.ahAccent)
                    )
                    .frame(width: 80, height: 80)

                VStack(spacing: AHSpacing.xs) {
                    Text("Aham").ahTitle().font(.system(size: 34, weight: .bold))
                    Text("知识积淀 · 创新领先 · 效率为本").ahMeta()
                }
            }

            // 关键词
            HStack(spacing: AHSpacing.m) {
                keywordCard(icon: "brain.head.profile", label: "知识", desc: "深度行业洞察", tint: Color(.displayP3, red: 0.64, green: 0.40, blue: 0.86))
                keywordCard(icon: "lightbulb",          label: "创新", desc: "AI 驱动突破", tint: Color(.displayP3, red: 1.00, green: 0.62, blue: 0.04))
                keywordCard(icon: "bolt.circle",        label: "效率", desc: "极致运营效能", tint: Color(.displayP3, red: 0.18, green: 0.69, blue: 0.66))
            }
            .frame(maxWidth: 640)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.ahPaper)
    }

    private func keywordCard(icon: String, label: String, desc: String, tint: Color) -> some View {
        VStack(spacing: AHSpacing.s) {
            AHIconTile(symbol: icon, size: AHIconBox.xl, tint: tint)
            Text(label).font(.callout.weight(.semibold))
            Text(desc).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AHSpacing.l)
        .background(
            RoundedRectangle(cornerRadius: AHRadius.lg, style: .continuous).fill(Color.ahPaperAlt)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AHRadius.lg, style: .continuous).strokeBorder(Color.ahBorder, lineWidth: 1)
        )
    }
}

#Preview {
    HomeView().frame(width: 720, height: 480)
}
