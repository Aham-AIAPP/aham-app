# 变更记录

本文件按 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/) 的格式记录变更，版本号遵循[语义化版本](https://semver.org/lang/zh-CN/)。aham-design 和 aham-app 两个插件同步发版。

## [Unreleased]

### 修复

- 公开检查漏查中文文件名：git 默认把中文路径转义后输出，检查脚本按转义后的名字读不到文件，会静默跳过。改为按原样读取路径后，仓库里 12 个中文文件名的文件纳入检查，现有内容全部通过。新增一项测试覆盖这种情况。插件内容不变。

## [1.0.1] - 2026-11-01

两个插件的中文显示名配成一对：「Aham 设计规范」和「Aham 应用技能」。插件标识、技能、取值和引擎都不变，已安装的用户更新即可。

### 变更

- aham-design 的显示名由「Aham Design」改为「Aham 设计规范」，插件说明和插件市场说明以「Aham 设计规范」开头。`tokens.json` 的 `$meta.version` 仍是 1.0.0：它是取值的版本，写进 Word 的样式信息，这次取值没有变。
- aham-app 的显示名由「Aham App」改为「Aham 应用技能」。
- aham-app 的说明改为「Aham 应用技能：按 Aham 设计规范（aham-design）把材料做成方案级、汇报级的 PPT（aham-ppt-proposal）」，插件市场里的说明同样以「Aham 应用技能」开头。

## [1.0.0] - 2026-11-01

第一个版本。三个旧仓库的内容并入本仓库，拆成 aham-design 和 aham-app 两个插件。全部视觉取值按取值决议表统一，写进 `plugins/aham-design/tokens.json`。

### 来源

| 旧仓库 | 迁入时的版本 | 迁入位置 |
|---|---|---|
| Aham-AIAPP/aham-word | 0.3.1 之后的 main | aham-design 的 `skills/aham-word`。规范说明和样张内容迁入；排版引擎换成原文档引擎（另一套文档技能里与业务无关的通用部分），改名 `aham_doc` |
| Aham-AIAPP/aham-ppt | 5.0.0 | 排版引擎 html2pptx、视觉检查和范例库迁入 aham-design 的 `skills/aham-ppt`；八阶段方案流程迁入 aham-app 的 `skills/aham-ppt-proposal` |
| Aham-AIAPP/aham-ui | 10.1.1 之后的 main | 样式、脚本、规则、组件契约和示例页迁入 aham-design 的 `skills/aham-design/assets/ui`；给 AI 的读取说明改写成 `references/app.md` |

### 新增

- `tokens.json`：全部取值的唯一来源，分组 color、font、size、line、radius、shadow、layout、role。Word 引擎、网页渲染器、PPT 引擎和界面构建脚本都读它，代码里不写色值和字号。
- `aham-design` 技能：规范入口，五份规范 `document.md`、`table.md`、`ppt.md`、`web.md`、`app.md`。
- Word 引擎 `aham_doc` 的网页渲染器和网页审计，可以把同一份内容排成 Word 和网页预览。
- `scripts/check_public.py` 公开检查，`scripts/compare_outputs.py` 产出比对，`scripts/build_ppt_samples.py` PPT 基准样张。
- GitHub Actions 工作流 `.github/workflows/ci.yml`。

### 变更：按取值决议表统一的取值

- 品牌蓝合成一套蓝阶：蓝 336EE8、悬停 2A62D6、文字 2453C7、加重 1C45AC、浅蓝底 EEF2FC。文档里的蓝字一律用 2453C7。
- 中性灰全部换成冷灰：浅色 19 档（`color.gray.0`–`18`），深色一套（`color.gray_dark`）。换算时明度不变，色相统一为 260°。
- 语义色：成功 1F7A4D、警示 A15C07、错误 B42318、重点 C2410C。
- 分类色定为 6 种，次序改变。界面的标签和头像颜色跟着变。
- 字体：去掉 Inter、JetBrains Mono 和数字用的 Consolas。Word、Excel、PPT 文件统一用微软雅黑，中文、西文和数字同一种；网页和界面用系统字体栈；等宽字体只给代码块。PPT 预览页不再加载网络字体。
- 圆角只留三档：6px、8px 和胶囊。界面原来的 4px 改为 6px，12px 改为 8px。
- 阴影只留界面浮层的两档，卡片、面板、文档和 PPT 不用阴影。
- 对比度不足的颜色按规则改深：PPT 的墨三 7D8695 改为 6B7482；PPT 的橙 D4892A 改为 CE8422，青绿 17998A 保留。
- PPT 的底一 F6F7F9 改为 F6F8FB，浅蓝底 EAF0FD 改为 EEF2FC。
- Aham Word 文档随引擎更换改变：封面标题 32 磅改为 28 磅，图注、表注和页脚 9 磅改为 8.5 磅，正文 10.5 磅不变；文字色改为冷灰；正文行距、段距、首行缩进、页眉页脚距离和表格线改用原文档引擎的规则；表格改为三线表，表头不铺底色。

### 变更：决议表以外

- Word 页脚和表注的颜色是 muted 5D6675。决议表写的是 6B7482；新引擎沿用原文档引擎的颜色角色，没有单独改。
- Word 标题按元素对照：文首标题 22 磅、章标题 16 磅不变，节标题 13 磅改为 14 磅，新增 12 磅的小节标题。
- Word 表格数据字号改为 9 磅。表题、表注、目录、封面、页眉页脚、列表和引语改用原文档引擎的规则；装饰蓝线只留在封面、提示条和引语。
- Word 目录在生成时写入标题文字，页码要在 Word 里更新域，或运行 `update_toc_export.py` 后才有。
- PPT 预览页外框的深色模式颜色改读 `color.gray_dark`，只影响预览网页。
- 界面新增 `color.ui` 和 `layout.ui` 两组取值；高对比深色模式的线色按冷灰重算为 73777D。
- 界面示例页的业务数据换成中性内容：报价改成费用申请，客户和商机改成项目，客户方改成协作方。侧栏跳转字母随对象名称改变。
- 规范和说明里的禁用词按中文写作规则替换，不影响显示。

### 移除

- 报价相关的业务内容不进 aham-design，由使用它的应用技能自己实现。
- aham-ui 的旧截图、AGENTS.md 和单独的许可文件；许可统一为仓库根目录的 MIT。

迁移时逐项比对过新旧产出：Word 样张、PPT 样张和界面样式各有一份差异清单，没有放进本仓库。

[Unreleased]: https://github.com/Aham-AIAPP/aham-plugins/compare/v1.0.1...HEAD
[1.0.1]: https://github.com/Aham-AIAPP/aham-plugins/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/Aham-AIAPP/aham-plugins/releases/tag/v1.0.0
