# 旧代码 → V3 迁移指南

这份文档给开发者/AI：把 V2 代码逐项替换成 V3 token + 组件的**完整对照表**。

## 一键 find & replace

这些可以机械替换。先做这些，能消灭 70% 差异。

| Find | Replace |
|---|---|
| `.padding(4)` | `.padding(AHSpacing.xxs)` |
| `.padding(6)` | `.padding(AHSpacing.xs)` |
| `.padding(8)` | `.padding(AHSpacing.s)` |
| `.padding(12)` | `.padding(AHSpacing.m)` |
| `.padding(16)` | `.padding(AHSpacing.l)` |
| `.padding(20)` | `.padding(AHSpacing.xl)` |
| `.padding(24)` | `.padding(AHSpacing.xxl)` |
| `cornerRadius: 3` | `cornerRadius: AHRadius.xs` |
| `cornerRadius: 6`/`5` | `cornerRadius: AHRadius.sm` |
| `cornerRadius: 8` | `cornerRadius: AHRadius.md` |
| `cornerRadius: 10` | `cornerRadius: AHRadius.lg` |
| `cornerRadius: 12` | `cornerRadius: AHRadius.xl` |
| `cornerRadius: 16` | `cornerRadius: AHRadius.xxl` |
| `Color.accentColor.opacity(0.12)` | `Color.ahAccentBG` |
| `Color.accentColor.opacity(0.1)` | `Color.ahAccentBG` |
| `Color.accentColor.opacity(0.3)` | `Color.ahAccentBorder` |
| `.foregroundStyle(.green)` | `.foregroundStyle(Color.ahSuccess)` |
| `.foregroundStyle(.red)` | `.foregroundStyle(Color.ahDanger)` |
| `.foregroundStyle(.orange)` | `.foregroundStyle(Color.ahWarning)` |
| `spacing: 16` | `spacing: AHSpacing.l` |
| `spacing: 12` | `spacing: AHSpacing.m` |

## 结构替换（需要手动）

### 1. GroupBox → AHCard + AHSection

**旧：**
```swift
GroupBox {
    VStack { ... }
} label: {
    Label("调研配置", systemImage: "gearshape")
        .font(.headline)
}
```
**新：**
```swift
AHCard {
    AHSection("调研配置") {
        VStack { ... }
    }
}
```

### 2. `.borderedProminent` → `.ahPrimary`

| 旧 | 新 |
|---|---|
| `.buttonStyle(.borderedProminent).controlSize(.large)` | `.buttonStyle(.ahPrimaryLarge)` |
| `.buttonStyle(.borderedProminent).controlSize(.regular)` | `.buttonStyle(.ahPrimary)` |
| `.buttonStyle(.bordered)` | `.buttonStyle(.ahSecondary)` |
| `.buttonStyle(.plain) + 自己加灰底描边` | `.buttonStyle(.ahGhost)` |

### 3. 手搓胶囊 → AHPill

**旧：**
```swift
HStack(spacing: 4) {
    Image(systemName: "checkmark.circle.fill")
    Text("已完成")
}
.font(.caption)
.padding(.horizontal, 8).padding(.vertical, 3)
.background(Color.green.opacity(0.12), in: .capsule)
.foregroundStyle(.green)
```
**新：**
```swift
AHPill(text: "已完成", icon: "checkmark.circle.fill", style: .success)
```

### 4. 手搓图标容器 → AHIconTile

**旧：**
```swift
ZStack {
    RoundedRectangle(cornerRadius: 16)
        .fill(gradient)
        .frame(width: 64, height: 64)
    Image(systemName: "doc.text.magnifyingglass")
        .font(.title2)
        .foregroundStyle(.white)
}
```
**新：**
```swift
AHIconTile(symbol: "doc.text.magnifyingglass",
           size: AHIconBox.hero, tint: Color.ahAccent)
```

### 5. 字体

| 旧 | 新 |
|---|---|
| `.font(.title).fontWeight(.bold)` | `.ahTitle()` |
| `.font(.title2).fontWeight(.semibold)` | `.ahTitle2()` |
| `.font(.title3).fontWeight(.semibold)` | `.ahTitle3()` |
| `.font(.caption).foregroundStyle(.secondary)` | `.ahMeta()`（12pt）或 `.ahCaption()` |
| `.font(.system(.title, design: .monospaced))` | `.ahMono(22, weight: .semibold)` |
| `.font(.caption).fontWeight(.semibold).textCase(.uppercase).tracking(1.2)` | `.ahSectionLabel()` |

## 文件迁移顺序（最安全）

1. **先合并 token 文件**：把 `DesignTokens.swift` / `DesignComponents.swift` 拷贝到 `Views/Design/` 目录（或新建）。确保能编译。
2. **改 HomeView**（最小最独立）。验证：跑起来视觉正常。
3. **改 ModuleSidebarView**。
4. **改 ProjectDetailView**：对比 `handoff/Views/ProjectDetailView.swift`，直接替换整文件。原文件中的业务函数（`runAIEnhancement / importDocument / exportToObsidian / buildExportSnapshot`）**已原样保留**，不会破坏逻辑。
5. **改 SurveyView**：对比 `handoff/Views/SurveyView.swift`。同上，业务逻辑未动。注意它仍引用 `FocusedCardContent`、`SurveyView+MemoBar`、`SurveyView+RightPanel`、`TriggerHelpers`、`SurveyTypes` —— 这些文件保持 V2 原样即可（只是装饰层不含 magic number 时最好也顺手改）。
6. **最后改 ProjectListView / ProjectRowView / NewProjectView / SalesDashboardView / SettingsView**：按 COMPONENTS.md 里的模板自查替换（结构简单，无 handoff 模板时可 AI 辅助完成）。

## 常见编译错误

- `Cannot find 'AHSpacing' in scope` → 确认 `DesignTokens.swift` 在 target membership 里
- `Ambiguous reference` 同名 struct `FlowLayout` → V3 `ProjectDetailView.swift` 里重新定义了 `FlowLayout`，如原项目已有同名实现，删一个
- `DocImportPhase` 重复 → 同上，V3 文件内含，如原位置还在要删掉
- Button label 变色 → `.ahPrimary` 强制白字，所以 `Label` 里不要再叠 `.foregroundStyle`

## 验证清单

- [ ] 所有页面在浅色 / 深色模式下都正常（ahInk/ahPaper 自动适配）
- [ ] accent 色换成橙色 / 绿色后视觉仍统一（改系统 accent 色验证）
- [ ] 整个项目 grep `padding(1[0-9])` 空结果
- [ ] grep `.borderedProminent` 空结果
- [ ] grep `Color\.(blue|green|orange|red)\.opacity` 空结果或都有合理上下文（如渐变）
