# Aham 插件

Aham 系列的 Claude Code 插件市场，含两个插件。aham-app 在本仓库，aham-design 在独立仓库 [Aham-AIAPP/aham-design](https://github.com/Aham-AIAPP/aham-design)：

| 插件 | 版本 | 内容 |
|---|---|---|
| [aham-design](https://github.com/Aham-AIAPP/aham-design) | 1.0.1 | Aham 设计规范：通用规范和排版引擎，取值文件 `tokens.json`，文档、表格、PPT、网页、应用界面五类规范，界面样式库，Word 引擎和 PPT 引擎 |
| [aham-app](plugins/aham-app/) | 1.0.1 | Aham 应用技能：PPT 方案流程 `aham-ppt-proposal`。依赖 aham-design |

aham-design 与具体业务无关，只放规范、取值和引擎。aham-app 的技能决定写什么、按什么顺序写，画页面和排版调用 aham-design。

## 安装

在 Claude Code 会话里先添加插件市场，再安装插件：

```text
/plugin marketplace add Aham-AIAPP/aham-app
/plugin install aham-app@aham-plugins
```

在终端里不进入会话也可以安装：

```bash
claude plugin marketplace add Aham-AIAPP/aham-app
claude plugin install aham-app@aham-plugins
```

- Claude Code 2.1.275 及以上可以一步完成添加和安装：`/plugin install aham-app --marketplace Aham-AIAPP/aham-app`。终端里的同样写法要 2.1.292 及以上。
- 安装 aham-app 时，Claude Code 按 aham-app 声明的依赖，在同一范围里一并安装 aham-design。
- 只要规范和引擎时，单独安装 aham-design：`/plugin install aham-design@aham-plugins`。
- 插件默认装在用户范围。要给整个项目装，在终端命令后加 `--scope project`。
- 插件市场的名字仍是 aham-plugins，安装命令里的 `@aham-plugins` 不变。仓库由 aham-plugins 改名为 aham-app，旧地址 Aham-AIAPP/aham-plugins 自动转到新地址。
- 本地调试时，用 `/plugin marketplace add ./` 添加本仓库目录。市场清单里 aham-design 的来源是它的 GitHub 仓库，所以本地调试同样从 GitHub 安装 aham-design。

安装命令的写法依据 Claude Code 文档的 [Install and manage plugins](https://code.claude.com/docs/en/discover-plugins)。

## 技能

| 技能 | 插件 | 用途 |
|---|---|---|
| `aham-design` | aham-design | 规范入口：查取值和规则；做阅读型网页、业务系统界面和 Excel 表格；核对成品是否符合规范 |
| `aham-word` | aham-design | 把结构化内容排成 Word 文档，同一份内容也能排成网页预览 |
| `aham-ppt` | aham-design | 用组件写 1920×1080 的 HTML 幻灯片，预览、排版检查、导出可编辑 PPTX |
| `aham-ppt-proposal` | aham-app | 从材料做一整份方案或汇报 PPT，分八个阶段，调用 aham-ppt 引擎 |

## 依赖

| 用途 | 依赖 |
|---|---|
| Word 引擎 | Python 3、python-docx、lxml |
| 导出 PDF、刷新 Word 目录页码 | LibreOffice（可选） |
| PPT 引擎 | Node.js 20 及以上；在 aham-design 的 `skills/aham-ppt/assets/html2pptx` 运行 `npm install`，安装 pptxgenjs 和 playwright；Playwright 的 Chromium |
| PPT 检查、读材料 | `pip install -r` 两个技能各自的 `requirements.txt`：python-pptx，以及 pypdf、python-docx、openpyxl |

## 目录

```text
.claude-plugin/marketplace.json   插件市场清单，aham-design 的来源指向 Aham-AIAPP/aham-design
plugins/
  aham-app/
    .claude-plugin/plugin.json      声明依赖 aham-design ^1.0.0
    skills/aham-ppt-proposal/       PPT 方案流程
  aham-design/                      不提交。本地开发和 CI 把 aham-design 仓库检出到这里
scripts/
  check_public.py                   公开检查
  compare_outputs.py                产出比对
  build_ppt_samples.py              生成 PPT 基准样张
tests/                              上面三个脚本和 PPT 自查入口的测试
```

## 测试

测试和 PPT 样张要用 aham-design 的 PPT 引擎。先把 aham-design 检出到 `plugins/aham-design`，路径与拆分前一致，`.gitignore` 已排除这个目录：

```bash
git clone https://github.com/Aham-AIAPP/aham-design plugins/aham-design
```

在仓库根目录运行：

```bash
# Python 测试
python3 -m unittest discover -s tests

# 公开检查：仓库里不得出现私有名称
python3 scripts/check_public.py

# 插件清单
claude plugin validate plugins/aham-app

# PPT 样张：先在引擎目录安装 npm 依赖和 Chromium，再生成五页示例，跑 check_slides.js 和 check_deck.py
(cd plugins/aham-design/skills/aham-ppt/assets/html2pptx && npm install && npx playwright install chromium)
python3 scripts/build_ppt_samples.py 输出目录 --check
```

`.github/workflows/ci.yml` 在每次推送和拉取请求时运行以上检查，并把 PPT 样张上传为构件。aham-design 自己的测试、界面样式库检查、浏览器回归和截图在 aham-design 仓库的 CI 里运行。

## 许可

MIT，见 [LICENSE](LICENSE)。第三方组件见 aham-ppt-proposal 技能的 `NOTICE.md`。aham-design 的第三方组件和图标许可见 aham-design 仓库。
