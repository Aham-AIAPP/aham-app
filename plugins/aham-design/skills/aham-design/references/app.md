# 界面规范

本文写给按 Aham Design 生成业务管理系统界面的 AI。界面的样式、脚本、规则、组件契约和示例页都在 [../assets/ui/](../assets/ui/)。

## 适用范围

本规范覆盖电脑浏览器里的业务管理系统：列表、单据、记录详情和设置页。这类系统发给外部人员填写的对外填报页也在范围内。

网页提案、报告这类阅读型网页按 [web.md](web.md) 做。官网、营销页、桌面应用和 HTML 邮件不在本规范范围内。

## 取值来源

全部取值只有一个来源：插件根目录的 [tokens.json](../../../tokens.json)。

- 界面的 CSS 变量名沿用 `--wb-*`。每个变量对应 tokens.json 的一个键，对应关系写在 [scripts/tokens.mjs](../assets/ui/scripts/tokens.mjs)。
- 构建脚本读 tokens.json，生成 [aham.css](../assets/ui/aham.css) 里的变量。界面目录里没有第二份取值。
- 改取值时只改 tokens.json，再运行构建。不直接改 aham.css。

主要的对应关系：

| CSS 变量 | tokens.json 键 |
|---|---|
| 浅色的 `--wb-bg`、`--wb-canvas`、`--wb-line`、`--wb-ink` 等中性色 | `color.gray.0`–`color.gray.18`，例如 `--wb-canvas` 取 `color.gray.4` |
| 深色的中性色 | `color.gray_dark.*` |
| `--wb-action`、`--wb-action-hover`、`--wb-action-press` | `color.blue.base`、`color.blue.hover`、`color.blue.text` |
| `--wb-blue-bg`、`--wb-info-bg` | `color.blue.bg` |
| `--wb-success`、`--wb-warning`、`--wb-danger` 及浅底 | `color.semantic.*` |
| `--wb-cat-1`–`--wb-cat-6` | `color.categorical.1`–`color.categorical.6`；深色取 `color.ui.cat_*_dark` |
| 界面专用的状态色和深色浅底 | `color.ui.*` |
| `--wb-font`、`--wb-mono` | `font.family.ui`、`font.family.code` |
| `--wb-text-xs`、`--wb-body`、`--wb-title`、`--wb-total` 等字号 | `size.ui.*` |
| `--wb-s1`–`--wb-s8`、`--wb-icon-gap` | `layout.ui.space.*` |
| `--wb-control-radius`、`--wb-radius`、`--wb-radius-pill` | `radius.control`（6）、`radius.panel`（8）、`radius.pill` |
| `--wb-shadow-pop`、`--wb-shadow-float` | `shadow.pop`、`shadow.float` |
| `--wb-row`、`--wb-list-row`、`--wb-control` 等尺寸 | `layout.ui.size.*` |
| `--wb-rail`、`--wb-panel-narrow`、`--wb-record-width` 等版面宽度 | `layout.ui.frame.*` |
| `--wb-bp-*`、`--wb-z-*` | `layout.ui.breakpoint.*`、`layout.ui.z.*` |
| `--wb-fast`、`--wb-ease` 等动效 | `layout.ui.motion.*` |
| `--wb-scrim` | `color.ui.scrim` 加 `layout.ui.scrim_opacity.*` |

## 读取顺序

1. [设计理念.md](../assets/ui/设计理念.md)：总体标准、16 条原则和冲突时的取舍次序。规则没写到的情况，按这篇判断。
2. [tokens.json](../../../tokens.json)：全部取值，按上一节的表找到对应的 CSS 变量。
3. [rules/](../assets/ui/rules/)：十一个规则文件，按编号读。至少读 1-总则、2-视觉、3-控件、10-数据格式，再按页面类型读 4–8。
4. [components/index.json](../assets/ui/components/index.json)：全部组件契约的目录。每份契约写明控件和组合的结构、类名、状态和键盘。
5. [aham.css](../assets/ui/aham.css) 和 [aham.js](../assets/ui/aham.js)：样式和行为的参考实现。参数和返回值见 [aham.d.ts](../assets/ui/aham.d.ts)。
6. [examples/](../assets/ui/examples/)：示例页。拿不准的写法以示例页为准。

规则和 tokens.json、aham.css、aham.js 不一致时，按缺陷处理，在回复里指出。

## 引用方式

```html
<link rel="stylesheet" href="aham.css">
<div class="aham-workbench" data-theme="light">…</div>
<script type="module">
  import { initShell, initPalette } from './aham.js';
  const root = document.querySelector('.aham-workbench');
  initShell(root);
  initPalette({ root, groups: () => [/* 本页的命令 */], shell: true });
</script>
```

- 复制 `aham.css`、`aham.js`、`aham.d.ts` 和 `assets/` 目录。字体用系统自带字体，没有字体文件。
- 每个 `init*` 和 `create*` 返回的句柄都有 `destroy()`。React 里的写法见 [docs/react.md](../assets/ui/docs/react.md)。
- `initPalette({ shell: true })` 自带界面、账户、跳转、帮助四组命令和 ? 快捷键。页面只写本页的命令组。
- 根节点 `.aham-workbench` 的 `data-theme` 取 `light` 或 `dark`，不写时跟随系统。
- 图标写成 `<svg><use href="assets/icons/aham-icons.svg#i-名称"></use></svg>`，名称见 [icons.json](../assets/ui/assets/icons/icons.json)。

## 页型选择

| 需求 | 页型 | 示例 |
|---|---|---|
| 登录后先看今天要关心的事 | 我的工作台 | [home.html](../assets/ui/examples/home.html) |
| 查找、筛选、批量处理 | 列表页 | [list.html](../assets/ui/examples/list.html) |
| 有明细、金额或审批的业务对象 | 单据页 | [document.html](../assets/ui/examples/document.html) |
| 逐条处理分给自己的待办 | 工作清单 | [worklist.html](../assets/ui/examples/worklist.html) |
| 没有审批流程的记录 | 记录详情页 | [record.html](../assets/ui/examples/record.html) |
| 协作方和我方共用、按阶段推进的对象 | 共用对象的列表页和详情页 | [scenes.html](../assets/ui/examples/scenes.html)、[scene.html](../assets/ui/examples/scene.html) |
| 新建简单的记录：必填字段少于 8 个、没有明细表 | 新建弹窗 | `openCreateDialog()` |
| 新建单据：有明细表或必填字段 8 个以上 | 单据页的新建态 | 没有单独的示例页 |
| 新建过程分 3–8 步、前后步骤有依赖 | 向导 | 没有参考实现 |
| 先输入编号或名称，再打开对应的单据 | 初始页 | 没有参考实现 |
| 打印单据 | 打印预览页 | [print.html](../assets/ui/examples/print.html) |
| 请公司外部的人填写信息 | 对外填报页 | [form.html](../assets/ui/examples/form.html) |
| 个人或工作区设置 | 设置页 | [settings.html](../assets/ui/examples/settings.html) |
| 成员、角色和权限 | 设置页的成员与角色 | [members.html](../assets/ui/examples/members.html) |

完整的选择表见 [rules/4-页面.md](../assets/ui/rules/4-页面.md) 4.2。

## 生成时的硬约束

- 颜色、字号、间距、圆角、尺寸只用 `var(--wb-*)`，不写十六进制色值和像素字号。
- 圆角只有三档：控件和小元素 `radius.control`（6px），面板、菜单和弹窗 `radius.panel`（8px），胶囊 `radius.pill`。
- 阴影只用在浮层：下拉菜单和命令面板用 `shadow.pop`，弹窗用 `shadow.float`。卡片和面板不加阴影。
- 字体只用 `font.family.ui`，代码块用 `font.family.code`。两套都是 Windows 和 Mac 自带的字体，不加载网络字体。
- 列表页用单行列表 `.wb-table.wb-list-rows`：不显示表头，按分组排列，数据行 44px（`--wb-list-row`），分组行 36px。
- 需要逐列比较数字的数据表格用 `.wb-table`，行高 36px（`--wb-row`），紧凑 32px。控件 32px。
- 外框是 220px 的文字侧栏（`.wb-rail`），⌘/Ctrl + B 收起成 52px。侧栏项写 `data-go`，登记 G 加字母的跳转。
- 字号只用两档：正文 14px，辅助信息 12px。20px 标题一页一次，只在详情页、单据页和设置页。
- 24px 只给金额汇总和记录详情页关键信息的数。字重只用 400、500、600。
- 金额、数量、单价和就地变化的计数用 `.wb-tnum`。它开启等宽数字，不换字体。编号和日期不用。
- 图标 16px，描边 2。主色蓝只用在主按钮、焦点框、当前项标记、进行中的阶段图标。正文链接用 `.wb-link`。
- 标签是描边胶囊加分类色圆点（`.wb-tag`）。人员用 `personHTML()`，对象所在阶段用 `stageIconHTML()`。
- 每个当前任务层有一个主操作。优先用文字按钮，图标和文字的间距是 6px（`--wb-icon-gap`）。
- 侧栏用 `--wb-canvas`，表头用白底加分隔线。多行区块只有 [2-视觉.md](../assets/ui/rules/2-视觉.md) 2.1 列出的几类可以铺底。
- 状态用圆点加文字（`.wb-status`），不给整行上色。
- 单据的显示态和编辑态用同一版式，按状态只显示当前可用的操作。编辑态的取消和保存放在页脚工具栏（[5-单据.md](../assets/ui/rules/5-单据.md) 5.4）。
- 日期写 2026-10-17，金额写 44,990.00。空值按类型写：文字「未填写」、选项「未选择」、人员「未指定」、数值和日期「–」。
- 需要读的文字不低于 4.5:1，用 `--wb-muted` 及更深的颜色。`--wb-faint` 只用于图标和禁用文字。
- 每个元素先答三个问题：谁在什么时候用、不看会不会做错、能不能从别处看到。答不上来就删除，不挪进抽屉或页签。
- 有流程的对象在标题下放下一步提示条 `.wb-next`。动态和修改记录折叠在页尾（`.wb-fold`）。
- 协作方和我方共用的对象，人名后写组织简称。仅我方的内容加 `.wb-scope` 标记，协作方看不到的内容不渲染（[4-页面.md](../assets/ui/rules/4-页面.md) 4.15）。
- 删除、作废、撤回之前用确认弹窗（`openConfirm()`），按钮写动作名。
- 界面文字不用「请」「您」「抱歉」，写法见 [6-反馈.md](../assets/ui/rules/6-反馈.md) 6.6。
- 示例数据一律虚构。公司名写成「示例……有限公司」，人名用虚构的名字。

## 交付前自查

- 新设计和改版先按 [9-验收.md](../assets/ui/rules/9-验收.md) 9.6 出方案，用户确认后再写代码。
- 交付前逐条核对 9.5 的十二项。改了视觉的再核对 9.7 的风格判据。
- 产品仓库提交前按 9.8 做挤压测试，并运行 `node scripts/product-check.mjs --config <配置文件>`（9.9）。
- 产品的业务词写在产品自己的用语表里。界面上不出现内部代号和数据库里的写法。

改了界面目录里的文件时，在 `assets/ui/` 里运行全部检查：

```bash
npm run check
```
