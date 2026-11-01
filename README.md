# Aham 插件

Aham 系列的 Claude Code 插件市场，含两个插件：

| 插件 | 版本 | 内容 |
|---|---|---|
| [aham-design](plugins/aham-design/) | 1.0.1 | Aham 设计规范：通用规范和排版引擎，取值文件 `tokens.json`，文档、表格、PPT、网页、应用界面五类规范，界面样式库，Word 引擎和 PPT 引擎 |
| [aham-app](plugins/aham-app/) | 1.0.1 | Aham 应用技能：PPT 方案流程 `aham-ppt-proposal`。依赖 aham-design |

aham-design 与具体业务无关，只放规范、取值和引擎。aham-app 的技能决定写什么、按什么顺序写，画页面和排版调用 aham-design。

## 安装

在 Claude Code 会话里先添加插件市场，再安装插件：

```text
/plugin marketplace add Aham-AIAPP/aham-plugins
/plugin install aham-app@aham-plugins
```

在终端里不进入会话也可以安装：

```bash
claude plugin marketplace add Aham-AIAPP/aham-plugins
claude plugin install aham-app@aham-plugins
```

- Claude Code 2.1.275 及以上可以一步完成添加和安装：`/plugin install aham-app --marketplace Aham-AIAPP/aham-plugins`。终端里的同样写法要 2.1.292 及以上。
- 安装 aham-app 时，Claude Code 按 aham-app 声明的依赖，在同一范围里一并安装 aham-design。
- 只要规范和引擎时，单独安装 aham-design：`/plugin install aham-design@aham-plugins`。
- 插件默认装在用户范围。要给整个项目装，在终端命令后加 `--scope project`。
- 本地调试时，用 `/plugin marketplace add ./` 添加本仓库目录。

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
| PPT 引擎 | Node.js 20 及以上；在 `plugins/aham-design/skills/aham-ppt/assets/html2pptx` 运行 `npm install`，安装 pptxgenjs 和 playwright；Playwright 的 Chromium |
| PPT 检查、读材料 | `pip install -r` 两个技能各自的 `requirements.txt`：python-pptx，以及 pypdf、python-docx、openpyxl |
| 界面样式库的构建和检查 | Node.js 20 及以上；浏览器回归和截图另要 `@playwright/test` 和 Chromium、WebKit |

## 目录

```text
.claude-plugin/marketplace.json   插件市场清单
plugins/
  aham-design/
    .claude-plugin/plugin.json
    tokens.json                     全部视觉取值的唯一来源
    skills/
      aham-design/                  规范入口
        references/                 document.md、table.md、ppt.md、web.md、app.md
        assets/ui/                  界面样式、脚本、规则、组件契约、示例页
      aham-word/                    Word 引擎 aham_doc 和网页渲染器
      aham-ppt/                     PPT 引擎 html2pptx 和视觉检查
    tests/                          取值、Word 引擎、网页和 PPT 取值的测试
  aham-app/
    .claude-plugin/plugin.json      声明依赖 aham-design ^1.0.0
    skills/aham-ppt-proposal/       PPT 方案流程
scripts/
  check_public.py                   公开检查
  compare_outputs.py                产出比对
  build_ppt_samples.py              生成 PPT 基准样张
tests/                              上面三个脚本和 PPT 自查入口的测试
```

## 测试

在仓库根目录运行：

```bash
# Python 测试。PPT 取值的 Node 部分要先在 aham-ppt 引擎目录运行 npm install，否则跳过
(cd plugins/aham-design/skills/aham-ppt/assets/html2pptx && npm install)
python3 -m unittest discover -s plugins/aham-design/tests
python3 -m unittest discover -s tests

# 公开检查：仓库里不得出现私有名称
python3 scripts/check_public.py

# 插件清单
claude plugin validate plugins/aham-design
claude plugin validate plugins/aham-app

# 界面样式库：构建核对、lint、组件契约、主题和 node 测试
(cd plugins/aham-design/skills/aham-design/assets/ui && npm ci && npm run check)
```

要用浏览器的检查：

```bash
# 界面浏览器回归（Chromium 和 WebKit）和示例页截图
cd plugins/aham-design/skills/aham-design/assets/ui
npx playwright install chromium webkit
npm run test:browser
npm run shots

# PPT 样张：生成五页示例，跑 check_slides.js 和 check_deck.py
python3 scripts/build_ppt_samples.py 输出目录 --check
```

`.github/workflows/ci.yml` 在每次推送和拉取请求时运行以上全部检查，并把界面示例页截图和 PPT 样张上传为构件。

## 许可

MIT，见 [LICENSE](LICENSE)。第三方组件见 aham-ppt 和 aham-ppt-proposal 技能的 `NOTICE.md`，图标许可见 `plugins/aham-design/skills/aham-design/assets/ui/assets/icons/LICENSE`。
