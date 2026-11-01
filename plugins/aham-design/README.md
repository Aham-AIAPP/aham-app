# aham-design

Aham 系列的通用设计规范和排版引擎，中文名「Aham 设计规范」，版本 1.0.1。本插件与具体业务无关，只放规范、取值和引擎。应用技能在 aham-app 插件里，它们依赖本插件。

## 安装

```text
/plugin install aham-design --marketplace Aham-AIAPP/aham-plugins
```

这一行同时添加插件市场并安装，要 Claude Code 2.1.275 及以上。版本较低时分两步：先 `/plugin marketplace add Aham-AIAPP/aham-plugins`，再 `/plugin install aham-design@aham-plugins`。安装 aham-app 时会一并安装本插件。

## 取值

[tokens.json](tokens.json) 是全部视觉取值的唯一来源：颜色、字体、字号、线宽、圆角、阴影、版面和角色。Word 引擎、网页渲染器、PPT 引擎和界面样式库都在运行或构建时读这一份文件，代码和规范文件里不另存数值。

- 引擎从自己所在目录逐级向上，找同时有 `tokens.json` 和 `.claude-plugin/plugin.json` 的目录。
- 环境变量 `AHAM_DESIGN_TOKENS` 指向另一份 tokens.json 时，引擎改读那一份。换一套规范时复制 tokens.json 改值，不改引擎。

## 技能

| 技能 | 用途 | 入口 |
|---|---|---|
| [aham-design](skills/aham-design/SKILL.md) | 规范入口：查取值和规则；做阅读型网页、业务系统界面和 Excel 表格；核对成品是否符合规范 | `references/` 下五份规范、`assets/ui/` 界面样式库 |
| [aham-word](skills/aham-word/SKILL.md) | 把结构化内容排成 Word 文档和网页预览 | `scripts/build_docx.py`、`build_preview.py`、`build_html.py`、`audit_html.py` |
| [aham-ppt](skills/aham-ppt/SKILL.md) | HTML 幻灯片组件、预览、排版检查、导出可编辑 PPTX、PPTX 视觉检查 | `assets/html2pptx/`、`assets/tools/check_deck_visual.py` |

## 五类规范

| 场景 | 规范 | 引擎或样式库 |
|---|---|---|
| 文档 | [document.md](skills/aham-design/references/document.md) | aham-word 的 aham_doc |
| 表格 | [table.md](skills/aham-design/references/table.md) | Word 和网页表格由 aham_doc 画；Excel 没有引擎 |
| PPT | [ppt.md](skills/aham-design/references/ppt.md) | aham-ppt 的 html2pptx |
| 网页 | [web.md](skills/aham-design/references/web.md) | aham-word 的网页渲染器 `aham_doc.html` |
| 应用界面 | [app.md](skills/aham-design/references/app.md) | [assets/ui](skills/aham-design/assets/ui/README.md) 的 aham.css 和 aham.js |

## 依赖

- Word 引擎：Python 3、python-docx、lxml。导出 PDF 和刷新目录页码另要 LibreOffice。
- PPT 引擎：Node.js 20 及以上，在 `skills/aham-ppt/assets/html2pptx` 运行 `npm install`；预览、检查和导出要用 Playwright 的 Chromium。PPTX 视觉检查要 python-pptx。
- 界面样式库：Node.js 20 及以上。浏览器回归和截图要 `@playwright/test` 和 Chromium、WebKit。

## 测试

在仓库根目录运行：

```bash
python3 -m unittest discover -s plugins/aham-design/tests
(cd plugins/aham-design/skills/aham-design/assets/ui && npm run check)
```

`tests/test_ppt_tokens.py` 里调用 Node 的部分，要先在 `skills/aham-ppt/assets/html2pptx` 运行 `npm install`，否则跳过。

## 许可

MIT。第三方组件见 [skills/aham-ppt/NOTICE.md](skills/aham-ppt/NOTICE.md)，图标许可见 [assets/ui/assets/icons/LICENSE](skills/aham-design/assets/ui/assets/icons/LICENSE)。
