# CLAUDE.md — Aham App AI 编辑规则

> 此文件会被 Claude Code / Cursor / Zed AI 自动读取。  
> 内容是**强制性的**。违反这些规则 = 破坏全 App 视觉一致性。
> 设计事实源：兄弟仓库 **aham-ui**（`DESIGN.md` v5.1 / `tokens.json`）。Swift 端取值与铁规对齐它。

---

## 北极星

Claude desktop 气质——极简、克制、留白、内容优先。**冷色的纸、克制的金属感、对话式。**

**aham-ui 铁规（强约束，全文适用）：**
- **三层表面**：`ahPaper` #FFFFFF 内容 / `ahPaperAlt` #F3F3F3 面板·侧栏·卡片 / `ahBorder` #E7E7E7 线·选中。无暖调。
- **深度靠三层背景层差，不靠材质/模糊/阴影。** 静置/hover **无阴影**，仅浮层（菜单/popover/modal）有一层柔和阴影。
- **状态 = 6px 点 + 文字**（`AHStatusDot` / `AHStatus`），**绝不** pill/徽章/色块/红黄绿灯。
- **蓝 `ahAccent` #336EE8 是 garnish 不是 fill**：只用于 logo / 主操作 / 发送 / 选中指示。蓝若第一眼就注意到即超标。
- **选中态 = 扁平灰 `ahSelected` #E7E7E7，非蓝。**
- **卡片无边框无阴影**（`AHCard` 已内置）。靠层差区分：tier2 卡放 tier1 内容区上；卡内嵌块用 tier1 白。
- **语义色极弱，仅真风险**：`ahSuccess`/`ahWarning`/`ahDanger`。不靠颜色单独传达——配图标或文字（differentiate without color）。
- **单一无衬线**（Inter 缺失回退 system）；**数字 mono**（`.ahMono` / JetBrains 回退 SF Mono）。禁衬线、禁 100–300 细重、禁 `.rounded`。
- **内容区图标克制**：用 `•`+文字；图标仅导航/发送栏。禁多色/填充图标、emoji。

---

## 核心原则

1. **所有视觉 token 都在 `Design/DesignTokens.swift`。** 颜色、间距、圆角、字号、阴影、图标尺寸、动效—— 只能引用 `AHSpacing`、`AHRadius`、`AHIconBox`、`AHAnimation`、`Color.ah*`。**不准硬编码 magic number**，也**不准用 SwiftUI 直接色** `.green/.red/.orange/.blue/.purple/.gray`（用 `Color.ah*`）。

2. **所有视觉原子都在 `Design/DesignComponents.swift`。** 写 UI 必须优先复用 `AHCard`、`AHSection`、`AHStatus`、`AHStatusDot`、`AHIconTile`、`AHSegmentedTab`、`AHStatCard`、`AHEmptyState`。`AHPill` **仅作中性 tag**，不要拿它表达状态。禁止原生 `GroupBox`、`.borderedProminent`、临时 `RoundedRectangle { ... }.overlay(...)` 堆叠。

3. **字体只用 `.ah*` modifier。** `.ahTitle()`(24)、`.ahTitle2()`(20)、`.ahTitle3()`(17)、`.ahBody()`(14)、`.ahCallout()`(13)、`.ahMeta()`、`.ahCaption()`、`.ahSectionLabel()`、`.ahMono(size:, weight:)`。**禁止** `.font(.system(size:))` / `.font(.title)` 直接调用（除非在 ViewModifier 内定义新 `.ah*`）。

4. **按钮只用 `.buttonStyle(.ah*)`。** `.ahPrimary` / `.ahSecondary` / `.ahGhost`。禁止 `.borderedProminent`、`.bordered`、`.plain` 作为最终样式（`.plain` 仅在按钮外层取消原生样式，之后须套 AH 容器）。

5. **改视觉改 Tokens，不改 View。** 调整全 App 颜色/圆角，改 `DesignTokens.swift` 的值，所有 View 自动更新（含亮/暗双套）。

---

## 常见错误对照

| ❌ 不要这样写 | ✅ 应当这样写 |
|---|---|
| `.padding(16)` | `.padding(AHSpacing.l)` |
| `.cornerRadius(10)` | `.clipShape(RoundedRectangle(cornerRadius: AHRadius.lg))` |
| `.font(.title2).fontWeight(.semibold)` | `.ahTitle2()` |
| `.foregroundStyle(.secondary)` | 允许（≈`ahInk60`）；新代码优先 `Color.ahInk60` |
| `.foregroundStyle(.green/.red/.orange)` | `Color.ahSuccess/.ahDanger/.ahWarning` |
| 蓝底选中 `Color.ahAccentBG` | 扁平灰选中 `Color.ahSelected` |
| `GroupBox { ... } label: { ... }` | `AHCard { AHSection(title) { ... } }` |
| `.buttonStyle(.borderedProminent)` | `.buttonStyle(.ahPrimary)` |
| `AHPill(text:"进行中", style:.info)` 做状态 | `AHStatus(text:"进行中", color:.ahAccent)` |
| `Capsule().fill(.red.opacity(0.12))` 做状态 | `AHStatus(text:..., color:.ahDanger)`（点+文字）|
| `.background(.green.opacity(0.08))` 成功块 | `Color.ahSuccessBG` |
| 数字 `.font(.system(size:,design:.rounded))` | `.ahMono(size, weight:)` |
| 静置卡片 `.shadow(...)` | 不加阴影（`AHCard` 已无阴影）|
| 彩色图标框 `AHIconTile(tint:.accent)` 滥用 | `AHIconTile(symbol:...)`（默认中性 `ahInk`）|

---

## 各视图模块的结构铁律

### ProjectDetailView
- 用 Segmented Tab 分屏：`概览 / 客户信息 / AI 增强 / 进度`。
- Header 固定结构：`AHIconTile(中性) + 标题 + AHStatus(状态点+文字) + meta + 操作按钮`。

### SurveyView
- 顶部：部门 Tab 栏（扁平灰选中）+ 状态指示（`AHStatus` AI/麦克风点+文字）+ 进度条。
- 中部：左侧 sidebar + 中间焦点卡 + 右侧 AI 面板。
- 焦点卡样式：tier1 白填充 + `ahAccent` 1.5pt 焦点边（focus-ring 语义）+ **无阴影**。侧栏/选项选中=`ahSelected` 灰。

### HomeView
- hero squircle（仅 logo 蓝着色）+ 标题 + slogan + 三张关键词卡（`AHCard` + 中性 `AHIconTile`）。

### Sidebar
- 模块按钮选中态：左侧 2pt accent 指示条 + `ahSelected` 灰背景（**非** `ahAccentBG` 蓝）。

---

## 改动任何视觉前自检

- [ ] 是否直接写了数字 padding / size / radius？→ 换 token
- [ ] 是否用了原生 `GroupBox` / `.borderedProminent`？→ 换组件
- [ ] 新加的颜色是否走 `Color.ah*`？→ 若无对应语义，去 DesignTokens 加新 token
- [ ] 是否重复定义了已有组件的替代品？→ 不允许，改用已有组件

---

## 添加新视图时

1. 先在 `Design/DesignComponents.swift` 找能复用的原子。
2. 如需新组件，**先** 加到 `DesignComponents.swift`，**后** 在视图里使用。
3. 新组件命名以 `AH` 前缀，语义化：`AHDatePill`、`AHFileRow` 等。
4. 新组件必须只依赖 DesignTokens，不能硬编码。

---

## 参考文档

- `handoff/Design/DesignTokens.swift` — Token 完整定义
- `handoff/Design/DesignComponents.swift` — 组件库
- `handoff/docs/DESIGN-SPEC.md` — 原则与视觉系统详细说明
- `handoff/docs/COMPONENTS.md` — 每个组件的用法 + 反例
- `handoff/docs/PAGES.md` — 各页面的结构铁律
- `handoff/MIGRATION.md` — 旧代码 → 新代码迁移指南
