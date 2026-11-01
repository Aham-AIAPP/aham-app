# Aham App 设计规范 v3

> 这是"说人话"的设计说明书。给设计师、前端工程师、AI 编辑器共同读。  
> 对应的源码真理：`handoff/Design/DesignTokens.swift` + `DesignComponents.swift`。

---

## 1. 设计哲学

Aham App 的 UI 做三件事：

1. **让信息密度可控。** 顾问现场调研时需要「看全」；看板汇总时需要「看重点」。同一组件在不同语境可以用不同尺寸。
2. **中性 + 一个重点色。** 全 App 视觉由灰阶构建，accent 色只在"需要用户关注"的地方出现（主操作按钮、选中态、进度条、AI 增强标识）。
3. **内容是主角。** 装饰最少，空白和字重负责节奏。避免阴影堆叠、渐变、彩色背景块。

---

## 2. 视觉语言

### 2.1 颜色

分三类：

**文字 / 背景 / 描边**（都是灰阶，深浅梯度）
- `ahInk` / `ahInk60` / `ahInk40` / `ahInk20` — 主文字 → 禁用文字
- `ahPaper` / `ahPaperAlt` / `ahPaperBar` — 窗口 → 卡片 → 工具条
- `ahBorder` (12% 不透明度) / `ahDivider` (6%)

**Accent 色族**（跟随系统 accent）
- `ahAccent` — 主强调
- `ahAccentBG` — 10% 不透明，选中态 / tint 背景
- `ahAccentBorder` — 30%，选中态描边

**语义色**（固定不随主题，用于传达状态）
- `ahSuccess` 绿 / `ahWarning` 橙 / `ahDanger` 红 / `ahInfo` = accent

**禁止：** 自定义色值、字面 Color.xxx.opacity、在 View 里临时拼颜色。

### 2.2 间距

全 App 只有 10 个间距：`xxs 4 / xs 6 / s 8 / m 12 / l 16 / xl 20 / xxl 24 / xxxl 32 / huge 48`。

经验值：
- 同行紧凑元素 → `xs/s`
- 卡内元素之间 → `m/l`
- 卡片之间、区块之间 → `xl/xxl`
- 页面左右边距 → `xxl`
- Hero 上下留白 → `huge`

### 2.3 圆角

| Token | 值 | 用途 |
|---|---|---|
| `xs` | 3 | pill 内部小 tag |
| `sm` | 5 | 小按钮、小标签 |
| `md` | 8 | 按钮、输入框 |
| `lg` | 10 | **标准卡片** |
| `xl` | 12 | 大卡片、面板 |
| `xxl` | 16 | Hero squircle、弹窗 |
| `pill` | 999 | 胶囊 |

### 2.4 字体

SwiftUI 语义字体 + 自定义 modifier：

| Modifier | 用途 |
|---|---|
| `.ahTitle()` | Hero / 页面主标题 |
| `.ahTitle2()` | 次标题 |
| `.ahTitle3()` | 卡内标题、Section 标题 |
| `.ahSectionLabel()` | 小标签（uppercase tracking 1.2） |
| `.ahBody()` | 正文 |
| `.ahCallout()` | 次要正文 |
| `.ahMeta()` | 元信息 (secondary) |
| `.ahCaption()` | 极小信息 (tertiary) |
| `.ahMono(size, weight)` | 数字、计数 |

### 2.5 阴影

只三种，按视觉重量递增：
- `AHShadow.small` — 卡片（几乎看不见，只给层次暗示）
- `AHShadow.medium` — 弹出菜单、面板
- `AHShadow.large` — 模态 overlay

### 2.6 动效

| Token | 曲线 | 用途 |
|---|---|---|
| `AHAnimation.quick` | easeOut 0.18s | tab 切换、hover |
| `AHAnimation.standard` | spring 0.35s | 面板进出 |
| `AHAnimation.expand` | spring 0.45s | 展开折叠 |

---

## 3. 组件语义

### 3.1 AHCard

**标准视觉容器**。所有"框里的东西"都应该是 AHCard，而不是临时 RoundedRectangle。

- 默认 16pt padding + 10pt 圆角 + 1pt 描边 + 浅阴影
- `tinted: true` 切换到 `ahAccentBG`（表示选中 / 高亮）
- `elevated: false` 关掉阴影（嵌套卡片时用）

### 3.2 AHSection

带标题行的容器（搭配 AHCard 使用）。
- 标题用 `.ahSectionLabel()` 风格（uppercase）
- 可选 trailing 放按钮或辅助信息

### 3.3 AHPill

状态 / 分类 / tag 胶囊。六种 style：`neutral / success / warning / danger / info / accent`。  
可带图标。文字 caption 字号，填充 8pt × 3pt。

### 3.4 AHIconTile

圆角图标容器。用途：
- 头像位（AHIconBox.lg）
- 卡片标题图标（AHIconBox.md）
- Hero 大图标（AHIconBox.hero）
- 小徽标（AHIconBox.xs / .sm）

`tint.opacity(0.12)` 做背景，`tint` 做前景 symbol。

### 3.5 AHSegmentedTab

横向 tab 切换，适合 3–6 项。选中态：白底描边，未选中：灰色文字。内嵌在 `ahPaperBar` 底座里。

### 3.6 AHStatCard

仪表盘数字卡：label + 大数字 (28pt rounded semibold) + 可选 delta。

### 3.7 Button Styles

- **`.ahPrimary`** — 实心 accent 背景、白字。全页唯一或一组 CTA 用。
- **`.ahSecondary`** — 灰底 + 描边 + 主文字色。次操作。
- **`.ahGhost`** — 无背景，hover/press 才有。导航 / 取消 / inline 操作。

密度：`.ahPrimary` 默认 12×7；传 `large: true` 变 16×10（Hero / 模态）。

---

## 4. 布局节奏

- 页面左右通常留 `AHSpacing.xxl` (24pt)。
- 页面最大内容宽度建议 960–1120pt（ProjectDetailView 960、Survey 自适应）。
- 卡片 grid：`HStack(spacing: AHSpacing.m)`，单卡 `maxWidth: .infinity`。
- 表单行：`AHLabeledRow(label:)` 固定 84pt 右对齐标签 + 右侧自由内容。

---

## 5. 什么是"好的 Aham 页面"

- ✅ 一屏只有 1 个 `.ahPrimary` 按钮（主动作清晰）
- ✅ 状态 / 分类 / 标签一律 AHPill
- ✅ 数字突出 → `.ahMono(28, weight: .semibold)`
- ✅ Section 间距 xxl，行间距 m
- ✅ 彩色 accent 出现次数能数得过来（< 10 处）

- ❌ 多种圆角 / 多种字号 同屏出现
- ❌ 装饰色大块 gradient
- ❌ 嵌套 3 层阴影
- ❌ 一行字超过 4 种 font weight
