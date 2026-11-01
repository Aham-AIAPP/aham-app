# aham-app

Aham 系列的应用技能插件，中文名「Aham 应用技能」，版本 1.0.1。技能决定写什么、按什么顺序写；规范、取值和排版引擎来自 aham-design 插件。

## 依赖 aham-design

`.claude-plugin/plugin.json` 声明依赖 `aham-design` 的 `^1.0.0`。从插件市场安装本插件时，Claude Code 在同一范围里一并安装 aham-design：

```text
/plugin marketplace add Aham-AIAPP/aham-plugins
/plugin install aham-app@aham-plugins
```

两个插件装在不同目录。技能运行时 `CLAUDE_PLUGIN_ROOT` 指向本插件，所以 aham-ppt-proposal 用 `scripts/find_engine.py` 查找 aham-design 的 PPT 引擎。查找顺序：

1. 环境变量 `AHAM_DESIGN_ROOT`；
2. 与本插件同级的 `aham-design` 目录；
3. Claude Code 安装记录 `installed_plugins.json` 里的安装路径；
4. 插件缓存里同一市场下版本最高的 aham-design。

每个候选目录都核对插件名、主版本号 1 和 `skills/aham-ppt/SKILL.md`。找不到时脚本列出查过的位置并报错。

## 技能

| 技能 | 用途 |
|---|---|
| [aham-ppt-proposal](skills/aham-ppt-proposal/SKILL.md) | 把材料做成方案级、汇报级的 PPT。八个阶段：受众与规范、材料解析、论点提炼、叙事骨架、页面规划、样页确认、逐页设计、质检交付。页面写成 HTML 幻灯片，网页预览确认后导出可编辑 PPTX |

## 依赖

- aham-design 的 PPT 引擎依赖：Node.js 包 pptxgenjs、playwright，Playwright 的 Chromium，Python 包 python-pptx。
- 本技能的 Python 依赖：`pip install -r skills/aham-ppt-proposal/requirements.txt`，用于读材料提纲和检查 PPTX。
- LibreOffice 可选，用于导出 PDF 和抽查渲染。

## 测试

本插件的测试在仓库根目录的 `tests/`：

```bash
python3 -m unittest discover -s tests
```

## 许可

MIT。第三方组件见 [skills/aham-ppt-proposal/NOTICE.md](skills/aham-ppt-proposal/NOTICE.md)。
