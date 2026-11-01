# Aham App 设计系统 V3 — Handoff 包

📦 交付物总览。开发者 / AI 编辑器从这里开始读。

## 目录

```
handoff/
├─ README.md                        ← 你在这里
├─ CLAUDE.md                        ← AI 编辑器自动读取的规则（Claude / Cursor / Zed）
├─ .cursorrules                     ← 同上，兼容 Cursor / Codeium
├─ MIGRATION.md                     ← 从 V2 代码迁移到 V3 的完整对照表
├─ Design/
│  ├─ DesignTokens.swift            ← 颜色 / 间距 / 圆角 / 字体 / 阴影 token
│  └─ DesignComponents.swift        ← AHCard / AHSection / AHPill / AHIconTile / ...
├─ Views/
│  ├─ ProjectDetailView.swift       ← V3 重构版（Segmented Tab 结构）
│  ├─ SurveyView.swift              ← V3 重构版（装饰层）
│  ├─ HomeView.swift                ← V3 重构版
│  └─ ModuleSidebarView.swift       ← V3 重构版
└─ docs/
   ├─ DESIGN-SPEC.md                ← 设计原则、颜色、间距、字体、组件语义
   ├─ COMPONENTS.md                 ← 每个组件的用法 + 反例
   └─ PAGES.md                      ← 每个页面的骨架铁律
```

## 快速上手

### 给开发者
1. 把 `handoff/Design/` 整个拷进 Xcode 项目，放在 `Aham-src/Views/Design/`。
2. 把 `handoff/CLAUDE.md` 和 `handoff/.cursorrules` 复制到项目根部。
3. 跟着 `MIGRATION.md` 的顺序替换视图。
4. 遇到新视图写法，查 `docs/COMPONENTS.md`。

### 给 AI 编辑器
编辑器会自动读到根部的 `CLAUDE.md` / `.cursorrules`。所有规则就是：
- 用 AHSpacing / AHRadius / AHIconBox，禁止 magic number
- 用 AHCard / AHSection / AHPill / AHIconTile / AHStatCard / AHEmptyState
- 用 `.ah*` 字体 modifier 和 `.ah*` 按钮样式
- 用 Color.ah* 语义色

## 核心改动（V2 → V3）

**ProjectDetailView**
- 拆分 Segmented Tab：概览 / 客户信息 / AI 增强 / 进度
- Header 简化：64pt squircle → 28pt icon + status pill
- 单列堆叠 → 三张 AHStatCard 横排

**SurveyView**
- 部门 tab 栏：底部强调线 → 胶囊选中态
- AI / 麦克风状态：松散 label → AHPill
- 聚焦卡片：显式 AHCard 容器 + accent 描边
- 跳转圆点：固定 10 个 → 水平滚动

**HomeView / Sidebar**
- 全部改用 AHCard / AHIconTile / 新 token

## 反问清单（审查 PR 时）

- [ ] 新代码是否引入了 magic number？
- [ ] 是否有地方还在用 GroupBox / .borderedProminent？
- [ ] 是否有地方手搓 RoundedRectangle 做卡片？
- [ ] accent 色与语义色是否混用？
- [ ] 字体是否用到 `.font(.system(size:))`？

如有一项违反，打回修改。
