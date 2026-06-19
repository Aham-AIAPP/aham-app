# CLAUDE.md — Aham App AI 编辑规则

> 此文件会被 Claude Code / Cursor / Zed AI 自动读取。  
> 内容是**强制性的**。违反这些规则 = 破坏全 App 视觉一致性。

---

## 核心原则

1. **所有视觉 token 都在 `Design/DesignTokens.swift`。** 颜色、间距、圆角、字号、阴影、图标尺寸、动效—— 只能引用 `AHSpacing`、`AHRadius`、`AHIconBox`、`AHAnimation`、`Color.ah*`。**不准硬编码 magic number**（`padding(15)`、`cornerRadius: 8`、`Color.blue.opacity(0.12)` 等均属违规）。

2. **所有视觉原子都在 `Design/DesignComponents.swift`。** 写 UI 必须优先复用 `AHCard`、`AHSection`、`AHPill`、`AHStatusDot`、`AHIconTile`、`AHSegmentedTab`、`AHStatCard`、`AHEmptyState`。禁止原生 `GroupBox`、`.borderedProminent`、临时 `RoundedRectangle { ... }.overlay(...)` 堆叠。

3. **字体只用 `.ah*` modifier。** `self.ahTitle()`、`.ahTitle3()`、`.ahMeta()`、`.ahCaption()`、`.ahSectionLabel()`、`.ahMono(size:, weight:)`。**禁止** `.font(.system(size: 13))` 或 `.font(.title)` 这种直接调用（除非在 ViewModifier 内部定义新的 `.ah*`）。

4. **按钮只用 `.buttonStyle(.ah*)`。** `.ahPrimary` / `.ahSecondary` / `.ahGhost`。禁止 `.borderedProminent`、`.bordered`、`.plain` 作为最终样式（`.plain` 仅在按钮外层用于取消原生样式，之后必须套 AH 容器）。

5. **改视觉改 Tokens，不改 View。** 要调整全 App 颜色 / 圆角，改 `DesignTokens.swift` 里的值，所有 View 自动更新。

---

## 常见错误对照

| ❌ 不要这样写 | ✅ 应当这样写 |
|---|---|
| `.padding(16)` | `.padding(AHSpacing.l)` |
| `.cornerRadius(10)` | `.clipShape(RoundedRectangle(cornerRadius: AHRadius.lg))` |
| `.font(.title2).fontWeight(.semibold)` | `.ahTitle2()` |
| `.foregroundStyle(.secondary)` | 直接允许（映射到 `Color.ahInk60`）|
| `Color.blue.opacity(0.15)` | `Color.ahAccentBG` 或语义色 |
| `GroupBox { ... } label: { ... }` | `AHCard { AHSection(title) { ... } }` |
| `.buttonStyle(.borderedProminent)` | `.buttonStyle(.ahPrimary)` |
| `.buttonStyle(.bordered)` | `.buttonStyle(.ahSecondary)` |
| `Capsule().fill(.red.opacity(0.12))` 做标签 | `AHPill(text: "...", style: .danger)` |
| `RoundedRectangle().fill(accent.opacity(0.1)) + Image` 做图标框 | `AHIconTile(symbol: "...", size: AHIconBox.lg)` |

---

## 各视图模块的结构铁律

### ProjectDetailView
- 必须用 Segmented Tab 分屏：`概览 / 客户信息 / AI 增强 / 进度`。
- Header 固定结构：`AHIconTile + 标题 + 状态 AHPill + meta + 操作按钮`。

### SurveyView
- 顶部：部门 Tab 栏（胶囊选中）+ 状态指示（AHPill AI/麦克风）+ 进度条。
- 中部：左侧 sidebar + 中间焦点卡（AHCard 内置）+ 右侧 AI 面板。
- 焦点卡样式：`ahPaperAlt` 填充 + `ahAccentBorder` 1.5pt 边框 + 小阴影。

### HomeView
- 80pt hero squircle + 标题 + slogan + 三张关键词卡（AHIconTile + 标签）。

### Sidebar
- 模块按钮选中态：左侧 2pt accent 条 + `ahAccentBG` 背景。

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
