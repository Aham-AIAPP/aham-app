# Aham App 组件库 — 用法手册

每个组件都给出：**何时用 / 何时不用 / 代码模板 / 反例**。

---

## AHCard

**用来**：任何"框"。成功避免自建 `RoundedRectangle.fill(...).overlay(...)` 堆叠。

```swift
AHCard {
    VStack(alignment: .leading, spacing: AHSpacing.m) {
        Text("客户信息").ahTitle3()
        ...
    }
}

// 选中态
AHCard(tinted: true) { ... }

// 嵌套在另一个卡内（关阴影）
AHCard(elevated: false, radius: AHRadius.sm) { ... }
```

❌ 反例：
```swift
VStack { ... }
    .padding(16)
    .background(.white)
    .cornerRadius(10)
    .overlay(RoundedRectangle(cornerRadius: 10).stroke(.gray, lineWidth: 1))
// 全硬编码，没语义
```

---

## AHSection

**用来**：卡内需要标题行时。

```swift
AHCard {
    AHSection("调研配置") {
        VStack { ... }       // 内容
    } trailing: {
        Button("展开") { ... }.buttonStyle(.ahGhost)
    }
}
```

无 trailing 时不写就行：
```swift
AHSection("调研配置") {
    VStack { ... }
}
```

---

## AHPill

**用来**：状态（已完成 / 进行中）、类别（行业 / 部门）、AI 提示（"补充问题"）。

```swift
AHPill(text: "已完成", icon: "checkmark.circle.fill", style: .success)
AHPill(text: "AI 增强", icon: "wand.and.stars",       style: .accent)
AHPill(text: "待处理", icon: "clock",                  style: .warning)
AHPill(text: "失败",   icon: "xmark.octagon",          style: .danger)
AHPill(text: "草稿",                                   style: .neutral)
```

❌ 反例：自己拼 `HStack + Capsule().fill(.green.opacity(0.12))`

---

## AHIconTile

**用来**：给标题、列表行、Hero 的图标一个「小方块背景」。

```swift
AHIconTile(symbol: "building.2", size: AHIconBox.md)                  // 28pt，accent
AHIconTile(symbol: "sparkles",  size: AHIconBox.hero, tint: .purple) // 64pt
AHIconTile(symbol: "mic",       size: AHIconBox.sm, tint: .ahSuccess)
```

---

## AHStatusDot

**用来**：问题状态、连接状态等"一眼看"场景。

```swift
AHStatusDot(color: Color.ahSuccess)               // 6pt
AHStatusDot(color: Color.ahWarning, size: 8)       // 大一点
```

---

## AHSegmentedTab

**用来**：页面内横向切换视图，项数 3–6。

```swift
@State var tab: DetailTab = .overview

AHSegmentedTab(
    selection: $tab,
    items: [
        (.overview,       "概览",    "square.grid.2x2"),
        (.customer,       "客户信息", "person.text.rectangle"),
        (.aiEnhancement,  "AI 增强", "wand.and.stars"),
        (.progress,       "进度",    "chart.bar")
    ]
)
```

---

## AHStatCard

**用来**：仪表盘 / 项目概览的数字看板。

```swift
HStack(spacing: AHSpacing.m) {
    AHStatCard(label: "完成度", value: "68%", delta: "+12%", deltaPositive: true, icon: "chart.bar")
    AHStatCard(label: "已答题", value: "45/66",                                 icon: "checkmark.seal")
    AHStatCard(label: "部门数", value: "4",                                     icon: "building.2")
}
```

---

## AHEmptyState

**用来**：列表空态、零配置状态。

```swift
AHEmptyState(
    symbol: "doc.text.magnifyingglass",
    title: "还没有项目",
    message: "点击左下角 + 新建一个调研项目",
    actionLabel: "新建项目",
    action: { /* ... */ }
)
```

---

## AHLabeledRow

**用来**：信息展示 / 表单"键-值"一行（标签右对齐 84pt + 内容左）。

```swift
AHLabeledRow(label: "客户名称") {
    Text("阿哈玛机械").ahBody()
}

AHLabeledRow(label: "员工规模") {
    Picker("", selection: $scale) { ... }.labelsHidden()
}
```

---

## 按钮样式

规则："全页最重要的动作"用 `.ahPrimary`，其他全部 `.ahSecondary` 或 `.ahGhost`。

```swift
Button { } label: { Label("开始调研", systemImage: "play.fill") }
    .buttonStyle(.ahPrimary)

Button("取消") { }.buttonStyle(.ahSecondary)
Button("跳过") { }.buttonStyle(.ahGhost)

// Large 版本（模态框底部等）
.buttonStyle(.ahPrimaryLarge)
.buttonStyle(.ahSecondaryLarge)
```

❌ 不要：`.buttonStyle(.borderedProminent)` / `.bordered`

---

## AHSearchField

```swift
@State var query = ""

AHSearchField(text: $query, placeholder: "搜索项目...")
    .frame(maxWidth: 240)
```

---

## 组合示例：一个完整 Section

```swift
AHCard {
    AHSection("AI 增强") {
        HStack(spacing: AHSpacing.m) {
            AHIconTile(symbol: "wand.and.stars", size: AHIconBox.lg, tint: .ahAccent)
            VStack(alignment: .leading, spacing: AHSpacing.xs) {
                Text("生成动态选项与优先级调整").ahTitle3()
                Text("根据客户行业和规模，自动优化问题库。").ahMeta()
            }
            Spacer()
            AHPill(text: "已完成", icon: "checkmark.circle.fill", style: .success)
        }
    } trailing: {
        Button("重新生成") { }.buttonStyle(.ahSecondary)
    }
}
```
