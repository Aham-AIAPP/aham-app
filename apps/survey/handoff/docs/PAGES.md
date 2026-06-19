# Aham App 页面结构铁律

每个页面的"骨架"必须遵守。具体装饰可灵活。

---

## HomeView

```
┌─────────────────────────────┐
│                             │
│         (huge spacer)       │
│                             │
│      [ 80pt hero squircle ] │
│        Aham                 │
│        知识·创新·效率        │
│                             │
│   [知识] [创新] [效率]       │ ← 三张 keyword card (AHIconTile xl)
│                             │
│         (huge spacer)       │
└─────────────────────────────┘
```

---

## ProjectDetailView

```
┌─────────────────────────────────────────┐
│ [icon] 项目名  [status pill]  [主按钮]   │ ← header
│        meta meta meta meta              │
├─────────────────────────────────────────┤
│ [ 概览 | 客户信息 | AI 增强 | 进度 ]     │ ← AHSegmentedTab
├─────────────────────────────────────────┤
│  ScrollView（内容 maxWidth 960）        │
│                                         │
│  [AHStatCard] [AHStatCard] [AHStatCard] │
│                                         │
│  ┌─ AHCard ───────────────┐             │
│  │ AHSection("调研配置")   │             │
│  │  key: value             │             │
│  └────────────────────────┘             │
│                                         │
│  ┌─ AHCard ("快速操作") ──┐              │
│  │ [icon+label] × 4       │              │
│  └────────────────────────┘              │
└─────────────────────────────────────────┘
```

每个 tab 独立内容：
- **概览**：3 个 AHStatCard + 调研配置 AHCard + 快速操作 AHCard
- **客户信息**：基本信息 AHCard + 产品与工艺 AHCard + 文档导入 AHCard
- **AI 增强**：单个大 AHCard（未生成/进行中/已完成三态）
- **进度**：总进度 AHCard + 各部门详情 AHCard

---

## SurveyView

```
┌────────────────────────────────────────────┐
│ [部门tab] [部门tab]   ...    [AI●] [mic●]  │ ← departmentTabBar (ahPaperBar)
│ 42/66 完成  ████████░░░░  第 17/66 题      │ ← progressBar
├────────┬──────────────────────┬────────────┤
│        │                      │            │
│ sidebar│   adjacent card      │ right      │
│ 220pt  │   ─────────────      │ panel      │
│        │   FOCUSED CARD       │ 300pt      │
│        │   (AHCard xl +       │            │
│        │    accent border)    │            │
│        │   ─────────────      │            │
│        │   adjacent card      │            │
│        │                      │            │
│        │   memoBar            │            │
│        │   navBar (ahPaperBar)│            │
└────────┴──────────────────────┴────────────┘
```

聚焦卡片视觉：`AHCard radius xl + ahPaperAlt fill + ahAccentBorder 1.5pt + shadow.small`

---

## ModuleSidebarView

```
┌────┐
│ ✦  │  ← logo (accent)
├────┤
│ 🔍 │  ← 激活: 左 2pt accent 条 + ahAccentBG
│ 📊 │
│    │
│    │
│    │
├────┤
│ ⚙ │  ← SettingsLink
└────┘
48pt wide
```

---

## 反模式清单（出现即拒）

- 一页两个 `.ahPrimary` 按钮（除非是 confirm/cancel）
- 标题、数字、状态色三色在同一行 400%+ 堆砌
- 在 AHCard 里再手搓 RoundedRectangle
- 自定义 font size 而不用 `.ah*` modifier
- 直接用 `.bordered` / `.borderedProminent` 作最终样式
