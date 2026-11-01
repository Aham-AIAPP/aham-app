# Aham Design · 界面部分

本目录是 Aham Design 的界面部分，给电脑浏览器里的业务管理系统用。它包括设计理念、规则、样式、脚本、组件契约和示例页。当前版本 1.0.0。

总体标准是：界面退到业务对象后面，让人看清现在的状态和下一步，再用最少的操作做完。16 条原则和冲突时的取舍次序见 [设计理念.md](设计理念.md)，先读这一篇。

给 AI 的读取顺序和硬约束见技能目录的 [references/app.md](../../references/app.md)。

## 取值

全部取值来自插件根目录的 [tokens.json](../../../../tokens.json)，本目录不另存取值。

- [scripts/tokens.mjs](scripts/tokens.mjs) 写明每个 `--wb-*` 变量对应 tokens.json 的哪个键。
- [scripts/build.mjs](scripts/build.mjs) 读 tokens.json，生成 aham.css 的变量。它也改写规则里的色值表和对比度表。
- 构建脚本向上查找插件根目录的 tokens.json。也可以用环境变量 `AHAM_DESIGN_TOKENS` 指定文件。

## 目录

| 位置 | 内容 |
|---|---|
| [设计理念.md](设计理念.md) | 总体标准、16 条原则、冲突时的取舍次序 |
| [rules/](rules/) | 规则正文，十一个文件：总则、视觉、控件、页面、单据、反馈、键盘与命令、AI 协作、验收、数据格式、交互 |
| [components/](components/) | 组件契约，写明每个控件和组合的结构、类名、状态和键盘；[schema.json](components/schema.json) 规定契约的字段 |
| [src/](src/)、[js/](js/) | 样式和行为的源文件，按编号拼接 |
| [aham.css](aham.css)、[aham.js](aham.js) | 由构建脚本生成，页面只引这两个文件，不手改 |
| [aham.d.ts](aham.d.ts) | aham.js 的类型声明 |
| [examples/](examples/) | 示例页，数据全部虚构；侧栏写在 `_rail.html`，构建时复制进各页 |
| [assets/icons/](assets/icons/) | Lucide 图标（ISC 许可） |
| [docs/react.md](docs/react.md) | React 里的接入写法 |
| [scripts/](scripts/)、[tests/](tests/)、[qa/](qa/) | 构建、检查、测试和截图脚本 |

## 示例页

| 页面 | 演示内容 |
|---|---|
| [单据页](examples/document.html) | 费用申请单的关键信息、锚点栏、显示态、编辑态、页脚保存、草稿、校验、提交、审批、退回、作废、删除 |
| [打印预览](examples/print.html) | A4 版式、未生效标记、金额大写 |
| [列表页](examples/list.html) | 项目列表的筛选、视图、显示选项、分组、批量编辑、批量删除的结果、导出 |
| [工作清单](examples/worklist.html) | 待审批的费用申请，行内通过和退回，批量通过 |
| [记录详情页](examples/record.html) | 属性栏、折叠的动态、带附件的评论、AI 摘要 |
| [对外填报页](examples/form.html) | 单栏居中、分段进度、附件跟随问题 |
| [设置页](examples/settings.html) | 分区设置、立即生效、危险操作 |
| [控件总览](examples/controls.html) | 按钮、输入框、选择控件、状态、标签、提示条、阶段条、时间线 |

## 检查

```bash
npm run build   # 由 tokens.json、src/、js/ 生成 aham.css 和 aham.js
npm run check   # 构建核对、lint、契约、主题生成和 node 测试
```

浏览器回归和截图（`npm run test:browser`、`npm run shots`）要用 Playwright 和 Chromium，本机没有时跳过。
