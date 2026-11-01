---
name: aham-design
description: >
  Aham 设计规范的入口：查颜色、字体、字号、线宽、圆角和间距的取值，按规范做阅读型网页、业务管理系统界面和 Excel 表格，
  检查文档、网页或界面是否符合规范，修改规范取值。覆盖文档、表格、PPT、网页、应用界面五类场景，全部取值来自插件根目录的 tokens.json。
  触发场景：问 Aham 规范里某个元素用什么颜色、字号或线宽；要按 Aham 规范做网页提案、调研报告、周报这类单页网页；
  要做列表页、单据页、记录详情页、设置页、对外填报页等业务系统界面或页面原型；要按 Aham 规范排 Excel 表格；
  要核对一份 Word、网页或界面有没有违反规范；要改 tokens.json 的取值。
  生成 Word 文件改用同插件的 aham-word；画 PPT 页面、导出 PPTX、检查 PPT 页面改用同插件的 aham-ppt；
  从材料做一整份方案或汇报 PPT 改用 aham-app 插件的 aham-ppt-proposal。
---

# Aham Design 规范

本技能是 Aham 设计规范的入口。规范分五类场景：文档、表格、PPT、网页、应用界面。每类场景有一份规范文件，取值全部来自插件根目录的 `tokens.json`。

本技能直接负责三件事：回答取值和规则问题，生成阅读型网页、业务系统界面和 Excel 表格，按规范核对成品。生成 Word 和 PPT 由同插件的两个引擎技能负责，见「场景与技能」一节。

## 文件位置

技能目录记作 `<规范>`。Claude Code 加载本技能时，`${CLAUDE_SKILL_DIR}` 就是这个目录，`${CLAUDE_PLUGIN_ROOT}` 是 aham-design 插件根目录。

| 路径 | 内容 |
|---|---|
| `../../tokens.json` | 全部视觉取值的唯一来源，分组见「取值」一节 |
| `references/document.md` | 文档规范：Word 文档和文档网页预览的页面、标题、正文、提示条、图片、页眉页脚 |
| `references/table.md` | 表格规范：Word、Excel 和网页表格的三线表、字号、列宽、数字列和容量 |
| `references/ppt.md` | PPT 通用规范：画布、字体、字号、颜色、线宽和页面框架 |
| `references/web.md` | 网页规范：网页提案、方案说明、报告、周报这类阅读型单页网页 |
| `references/app.md` | 界面规范：电脑浏览器里的业务管理系统，读取顺序、页型选择和生成时的硬约束 |
| `assets/ui/` | 界面的样式 `aham.css`、脚本 `aham.js`、设计理念、规则、组件契约和示例页，说明见 `assets/ui/README.md` |
| `../aham-word/` | Word 引擎技能，也含阅读型网页的渲染器 `scripts/build_html.py` 和审计脚本 `scripts/audit_html.py` |
| `../aham-ppt/` | PPT 引擎技能：HTML 幻灯片组件、预览、排版检查和 PPTX 导出 |

## 场景与技能

| 场景 | 先读 | 生成和检查 |
|---|---|---|
| 文档：Word 文档、文档的网页预览 | `references/document.md` | 生成 Word 和预览改用 aham-word 技能。本技能只回答规范问题、核对现成文档 |
| 表格：Word、Excel、网页里的表格 | `references/table.md` | Word 和网页表格由 aham-word 引擎画。Excel 没有引擎，本技能按 table.md 和 `size.excel`、`line.excel`、`layout.excel` 写 |
| PPT | `references/ppt.md` | 画页面、导出 PPTX、检查页面改用 aham-ppt。做一整份方案或汇报改用 aham-app 的 aham-ppt-proposal，它按阶段调用 aham-ppt |
| 网页：阅读型单页网页 | `references/web.md` | 本技能负责。内容写成 JSON，用 aham-word 的 `build_html.py` 生成，`audit_html.py` 审计 |
| 应用：业务管理系统界面 | `references/app.md` | 本技能负责。页面引用 `assets/ui/` 的 aham.css 和 aham.js，按示例页写 |

用户只说「做个网页」时，先问清是给人从上往下读的网页，还是要操作数据的系统界面。前者按 web.md，后者按 app.md。官网、营销页、桌面应用和 HTML 邮件不在规范范围内，遇到时告诉用户本规范不覆盖。

## 取值

`tokens.json` 的写法借用 DTCG 设计令牌的键名：`$value` 是取值，`$description` 是用途，值写成 `{组.名}` 时引用另一个取值。键名写成点分路径，例如 `size.word.body`。

| 分组 | 内容 |
|---|---|
| `color` | 品牌蓝阶 `blue`、冷灰阶 `gray` 和深色 `gray_dark`、语义色 `semantic`、分类色 `categorical`、界面专用色 `ui`、PPT 专用色 `ppt`、荧光标记 `highlight` |
| `font` | 字体栈 `family.ui`、文件字体 `family.file`、代码字体 `family.code`，以及各介质的字重 |
| `size` | 字号，按介质分 `word`、`excel`、`web`、`ppt`、`ui`，各介质不互相换算 |
| `line` | 线宽，按介质分 `word`、`web`、`excel` |
| `radius`、`shadow` | 三档圆角；两档阴影，只给界面浮层 |
| `layout` | 纸张和版心 `page`，各介质的版面 `word`、`excel`、`web`、`ppt`、`ui`，数量上限 `limits` |
| `role` | 角色：`role.document` 把文档里的用途名指向上面的取值，例如 `role.document.color.ink` |

查一个键的实际取值（引用已展开）：

```bash
python3 -c "import sys; sys.path.insert(0, '${CLAUDE_SKILL_DIR}/../aham-word/scripts'); from aham_doc import tokens as T; print(T.value('role.document.color.ink'))"
```

- 回答取值问题时写键名和取值，取值现读 `tokens.json`，不凭记忆。规范文件只写键名，不抄数值。
- 引擎和构建脚本从自己所在目录逐级向上找同时有 `tokens.json` 和 `.claude-plugin/plugin.json` 的目录。环境变量 `AHAM_DESIGN_TOKENS` 指向另一份文件时，改读那一份。
- 改取值只改 `tokens.json`，不改 aham.css、引擎代码或规范文件里的数值。改完按「检查」一节重新构建并跑测试。

## 五类场景共用的约束

- 一份文件只用一种字体，中文、西文和数字相同。文件用 `font.family.file`，网页和界面用 `font.family.ui`，等宽字体 `font.family.code` 只给代码块。
- 不加载网络字体。字体栈里只有 Windows 和 Mac 自带的字体。
- 需要读的文字对底色不低于 4.5:1，图形、描边和图标不低于 3:1。`color` 下各色的 `$extensions.contrast` 写明了要求。
- 蓝字用 `color.blue.text`。`color.blue.base` 只给图形和按钮底色。
- 文档、网页和 PPT 不用阴影。阴影只用于界面的下拉菜单、命令面板和弹窗。
- 阅读型网页不用卡片：正文、要点和数字不套带底色、圆角或阴影的方框，分组靠标题、间距和细线。
- 表格用三线表，不画竖线，不铺表头底色，不用斑马纹。
- 示例数据一律虚构。公司名写成「示例……有限公司」，人名用虚构的名字。

## 阅读型网页的生成流程

1. 读 `references/web.md`，确认页面的读者、章节和是否需要目录。
2. 客户名、金额、日期这类事实，用户没给出时先问，没有来源的事实不写。
3. 按 aham-word 技能的 `references/web-format.md` 把内容写成 JSON，内容里不写颜色、字号和字体。
4. 运行 `python3 "${CLAUDE_SKILL_DIR}/../aham-word/scripts/build_html.py" 内容.json 输出.html`。
5. 运行 `python3 "${CLAUDE_SKILL_DIR}/../aham-word/scripts/audit_html.py" 输出.html`，错误改完再交付。
6. 按 web.md 的「交付前自查」逐条核对。

## 业务系统界面的生成流程

1. 按 `references/app.md` 的「读取顺序」读设计理念、规则和组件契约，再按「页型选择」选页型。
2. 新设计和改版先按 `assets/ui/rules/9-验收.md` 9.6 出方案，用户确认后再写页面。
3. 复制 `assets/ui/` 的 `aham.css`、`aham.js`、`aham.d.ts` 和 `assets/` 目录，页面只引用这两个文件，写法以 `assets/ui/examples/` 的示例页为准。
4. 颜色、字号、间距、圆角和尺寸只用 `var(--wb-*)`，不写十六进制色值和像素字号。
5. 交付前按 app.md 的「交付前自查」和 9.5 的十二项核对。

## Excel 表格

aham-design 没有 Excel 引擎。生成 Excel 时用环境里已有的表格库，按 `references/table.md` 的 Excel 写法设置字体、字号、线型和列宽，取值读 `size.excel`、`line.excel`、`layout.excel`。生成后打开文件核对表头、数字格式和线型，不能核对时告诉用户。

## 核对成品

用户要核对一份成品时，按场景读对应的规范文件，逐条列出不符合的地方，每条写明位置、现状、规范要求和对应的 tokens.json 键名或规则编号。网页先跑 `audit_html.py`，PPT 改用 aham-ppt 的检查脚本。

规范文件、`tokens.json` 和引擎实现三者不一致时，按缺陷处理，在回复里指出，不自行挑一个当准。

## 检查

改了本插件的文件后，在仓库根目录运行：

```bash
python3 -m unittest discover -s plugins/aham-design/tests
cd plugins/aham-design/skills/aham-design/assets/ui && npm run build && npm run check
```

界面的浏览器回归和截图（`npm run test:browser`、`npm run shots`）要用 Playwright 的 Chromium 和 WebKit，本机没有时由仓库的 CI 运行。
