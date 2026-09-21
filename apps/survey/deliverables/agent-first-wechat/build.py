#!/usr/bin/env python3
from __future__ import annotations

import base64
import html
import os
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
HERE = pathlib.Path(__file__).resolve().parent
SKILL = pathlib.Path("/Users/lichengbao/.codex/skills/aham-wechat")
sys.path.insert(0, str(SKILL / "scripts"))

from aham_post import FONT, Post  # noqa: E402
import plates as P  # noqa: E402

P.CJK = '"PingFang SC","Noto Sans CJK SC",sans-serif'
P.MONO = '"SF Mono","DejaVu Sans Mono",monospace'

OUT = HERE
NODE = pathlib.Path("/Users/lichengbao/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node")
NODE_MODULES = pathlib.Path("/Users/lichengbao/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules")
CHROMIUM = pathlib.Path(
    "/Users/lichengbao/Library/Caches/ms-playwright/chromium-1234/"
    "chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing"
)
RENDERER = HERE / "render.mjs"
QR = (ROOT / "assets" / "wechat-qr.png").resolve()
APP_SHOT = (ROOT / "assets" / "shots" / "survey-light.png").resolve()

BLUE = "#336EE8"
LIGHT_BG = "#EBEDF1"
DARK_BG = "#16181C"


def render(source: str, name: str, *, canvas_w: int = 900, fixed_h: int | None = None,
           out_w: int = 1080) -> pathlib.Path:
    source_path = OUT / f"_{name}.html"
    out_path = OUT / f"{name}.png"
    html_h = f"height:{fixed_h * 2}px;overflow:hidden;" if fixed_h else ""
    body_h = f"height:{fixed_h}px;" if fixed_h else ""
    wrapped = (
        "<!doctype html><html><head><meta charset='utf-8'>"
        "<style>*{margin:0;padding:0;box-sizing:border-box}"
        f"html{{width:{canvas_w * 2}px;{html_h}}}"
        f"body{{width:{canvas_w}px;{body_h}zoom:2;margin:0}}"
        "</style></head>" + source + "</html>"
    )
    source_path.write_text(wrapped, encoding="utf-8")
    env = os.environ.copy()
    env["CODEX_NODE_MODULES"] = str(NODE_MODULES)
    env["PLAYWRIGHT_CHROMIUM_EXECUTABLE"] = str(CHROMIUM)
    subprocess.run([
        str(NODE), str(RENDERER), str(source_path), str(out_path),
        str(canvas_w * 2), str(fixed_h * 2 if fixed_h else "auto"), str(out_w),
    ], check=True, env=env)
    return out_path


def plate(title: str, sub: str, inner: str, *, dark: bool = False, source: str = "") -> str:
    c = P.DARK if dark else P.LIGHT
    src = (
        f'<div style="margin-top:30px;padding-top:22px;border-top:1px solid {c["line"]};'
        f'font-size:28px;line-height:1.55;color:{c["ink3"]}">{source}</div>'
        if source else ""
    )
    return (
        f'<body style="background:{c["bg"]};padding:56px 52px 48px;'
        f'font-family:{P.CJK};color:{c["ink"]}">'
        f'<div style="font-size:44px;font-weight:700;line-height:1.25;color:{c["ink"]}">{title}</div>'
        f'<div style="margin-top:15px;font-size:29px;line-height:1.55;color:{c["ink2"]}">{sub}</div>'
        f'{inner}{src}</body>'
    )


def card(title: str, lines: list[str], *, dark: bool = False, accent: bool = False) -> str:
    c = P.DARK if dark else P.LIGHT
    border = BLUE if accent else c["line"]
    items = "".join(
        f'<div style="margin-top:17px;font-size:29px;line-height:1.45;color:{c["ink2"]}">— {line}</div>'
        for line in lines
    )
    return (
        f'<div style="padding:30px 30px 32px;background:{c["panel"]};border-top:5px solid {border}">'
        f'<div style="font-size:34px;font-weight:700;line-height:1.35;color:{c["ink"]}">{title}</div>{items}</div>'
    )


def two_col(left: str, right: str, *, gap: int = 24) -> str:
    return (
        '<table style="width:100%;border-collapse:separate;border-spacing:0;margin-top:38px"><tr>'
        f'<td style="width:50%;vertical-align:top;padding-right:{gap // 2}px">{left}</td>'
        f'<td style="width:50%;vertical-align:top;padding-left:{gap // 2}px">{right}</td>'
        '</tr></table>'
    )


# Cover
render(P.cover(
    ["App 不再是入口", "而是能力载体"],
    "Agent First · Skill · MCP · 专业 App", issue="2026.08", kicker="AHAM · 实践笔记",
), "cover", canvas_w=900, fixed_h=383, out_w=1800)
render(P.cover_square(
    ["App 不再", "是入口", "而是能力", "载体"],
    "Agent First · AI 应用新范式", issue="2026.08", kicker="AHAM · 实践笔记",
), "cover_1x1", canvas_w=800, fixed_h=800, out_w=1000)

# Fig 1: old/new paradigm
fig1_inner = two_col(
    card("UI First", ["用户先打开 App", "学习菜单、页面与字段", "沿固定流程完成任务"]),
    card("Agent First", ["用户先表达目标", "Agent 选择方法与工具", "App 接收可信动作"], accent=True),
)
render(plate(
    "改变的不是一个按钮，而是工作的入口",
    "从“人去适应软件”，转向“软件能力被 Agent 组织”",
    fig1_inner,
), "fig01")

# Fig 2: key architecture, the only dark plate
c = P.DARK
layer = lambda n, t, d, accent=False: (
    f'<table style="width:100%;border-collapse:collapse;margin-top:20px;background:{c["panel"]};'
    f'border-left:6px solid {BLUE if accent else c["dim"]}"><tr>'
    f'<td style="width:98px;padding:26px 18px;font-family:{P.MONO};font-size:30px;'
    f'font-weight:700;color:{BLUE if accent else c["ink3"]}">{n}</td>'
    f'<td style="padding:26px 18px 26px 0"><div style="font-size:34px;font-weight:700;'
    f'color:{c["ink"]}">{t}</div><div style="margin-top:8px;font-size:28px;line-height:1.5;'
    f'color:{c["ink2"]}">{d}</div></td></tr></table>'
)
fig2_inner = (
    layer("01", "Agent", "理解目标、研究资料、拆解并调度工作", True)
    + layer("02", "Skill", "装载方法、步骤、事实边界与确认规则")
    + layer("03", "MCP", "发现并调用工具、资源和 Prompt")
    + layer("04", "App", "保存状态，执行规则，提供专业界面")
)
render(plate(
    "Agent First 的四层结构",
    "人表达目标，Agent 组织工作，App 对状态与动作负责",
    fig2_inner, dark=True,
), "fig02")

# Fig 3: development questions shift
fig3_inner = P.booktabs(
    ["过去先问", "现在还要先问"],
    [
        ["要做哪些页面？", "App 必须拥有哪类可信状态？"],
        ["菜单怎么组织？", "Agent 可以发现哪些能力？"],
        ["流程如何固定？", "哪些步骤放进 Skill？"],
        ["接口怎么对接？", "哪些写入必须确认和审计？"],
        ["模型放在哪里？", "哪些判断应交给当前更强的 Agent？"],
    ],
    dark=False, widths=["43%", "57%"], dim_cols=(0,),
)
render(plate(
    "开发起点，从页面转向能力",
    "UI 仍然重要，但不再是软件能力的唯一入口",
    fig3_inner,
), "fig03")

# Fig 4: dynamic intelligence loop
fig4_inner = P.pipeline([
    ("用户提出目标", "不是选择某个功能，而是描述要完成的工作"),
    ("Agent 研究并规划", "读取文件、搜索行业工艺、理解当前上下文"),
    ("Skill 约束方法", "规定事实边界、调用顺序、预览与确认"),
    ("MCP 调用 App", "读取真实状态，提交经过确认的结构化结果"),
    ("App 留住成果", "校验、保存、审计，并交还专业界面继续工作"),
], dark=False)
render(plate(
    "复杂智能留在 Agent，稳定结果回到 App",
    "模型与知识可以变化，领域状态不能含糊",
    fig4_inner,
), "fig04")

# Fig 5: real product evidence. The screenshot is mounted on the light plate.
mount_html = (
    f'<body style="background:{LIGHT_BG};padding:34px;font-family:{P.CJK}">'
    f'<div style="font-size:42px;font-weight:700;line-height:1.3;color:#1A1D21">'
    '一次本地 App 实验</div>'
    '<div style="margin-top:14px;font-size:28px;line-height:1.5;color:#5F646B">'
    'Aham Survey 保留专业界面，同时把部分能力交给 Agent 调用</div>'
    f'<div style="margin-top:30px;background:#FFFFFF;padding:12px">'
    f'<img src="{APP_SHOT.as_uri()}" style="width:100%;display:block"></div>'
    '<div style="margin-top:24px;font-size:28px;line-height:1.55;color:#5F646B">'
    '截图只证明这套分工能够落地，不代表所有 App 都该采用同一界面。</div></body>'
)
render(mount_html, "fig05")

# Footer
render(P.footer(
    str(QR),
    ["来自 aha moment —— 每个工具只把一件事做好。",
     "这一期：Agent First 与 AI 应用的新分工。"],
    "github.com/Aham-AIAPP",
), "footer")

# Article body
o = Post(kicker="AHAM · 实践笔记", meta="2026.08")
b, m = o.b, o.m

o.lede("App 不会消失，但会从交互中心退到能力载体。")
o.p("过去做软件，我们先画页面、菜单和流程。用户要完成一项工作，得先判断打开哪个 App，再学习字段藏在哪里。软件组织工作，人去适应软件。")
o.p(f"{b('Agent First 把这个顺序倒了过来。')}人先说目标，Agent 决定要读什么、查什么、调用什么。App 仍然存在，只是不再垄断入口。")
o.fig("##FIG01##", "图 1 · 从 UI First 到 Agent First")

o.h2("01", "入口", "用户真正掌握的是目标")
o.p("“准备明天的客户调研”不是某个按钮。它可能同时需要阅读客户资料、搜索行业工艺、整理问题、检查历史记录，再把结果放进一个调研工具。")
o.p("传统 App 会把这件事拆进多个页面。Agent 可以先理解目标，再临时组织路径。工作的入口从菜单变成了自然语言。")

o.h2("02", "单元", "软件正在从 App 变成能力")
o.p("过去的软件交付单元是一个完整 App：界面、流程和能力绑在一起。新的交付单元，可能是一组能被 Agent 理解、调用和组合的能力。")
o.p("这时，App 更像一个有状态的领域节点。它保存事实，执行确定规则，处理权限和审计，也保留适合人操作的专业界面。")
o.fig("##FIG02##", "图 2 · Agent First 的四层结构（全文唯一深色重点图）")
o.deft("Agent", "理解目标，调动模型、搜索、文件和多个软件。")
o.deft("Skill", "把业务方法、步骤、边界和恢复方式写成可复用说明。")
o.deft("MCP", "向 Agent 暴露可发现的工具、资源和 Prompt。")
o.deft("App", "拥有真实状态，校验动作，并把结果留在可继续工作的地方。")

o.h2("03", "开发", "起点不再只是页面")
o.p("这会改变产品设计的第一轮问题。页面仍要做，但在画页面之前，要先划清软件和 Agent 的责任。")
o.fig("##FIG03##", "图 3 · Agent First 带来的开发问题变化")
o.p("最关键的一刀，是区分确定性与不确定性。数据结构、合法状态和写入规则交给代码；需要研究、理解和动态判断的部分，交给 Agent。")
o.p("变化最快的部分，也不必每次跟着 App 发布。行业方法改变，可以更新 Skill；模型能力改变，可以更换 Agent；数据结构和校验规则仍由 App 保持稳定。")

o.h2("04", "智能", "最难的功能不必写死在 App 里")
o.p("以制造业调研为例，一套标准题库只能守住最低覆盖线。真正难的是理解客户产品、行业工艺和现场异常，再决定下一步问什么。")
o.p("如果把这些都塞进 App，开发者还得自己维护模型接入、网络搜索、文件解析和长流程调度。Agent 平台原本就拥有其中不少能力。")
o.p("新的做法是让 Agent 完成研究和推理，让 Skill 规定方法，再通过 MCP 读取 App 的真实状态，把确认后的结果交还给 App。")
o.fig("##FIG04##", "图 4 · Agent、Skill、MCP 与 App 的运行循环")
o.aside("MCP 不是 API 的替代品。底层仍可能是 API、数据库或本地服务；MCP 补的是面向 Agent 的发现和调用方式，Skill 再补上“何时用、按什么顺序用”。资料来源：MCP Architecture Overview（modelcontextprotocol.io/docs/learn/architecture）和 Agent Skills 开放规范（agentskills.io/home）。")

o.h2("05", "实验", "我先在一个 App 里试了试")
o.p("我用 Aham Survey 做了一次小实验：专业界面继续承担现场记录和人工复核；项目创建、题目读取、答案预览与提交、报告导出，则可以由 Agent 按 Skill 通过 MCP 完成。")
o.fig("##FIG05##", "图 5 · Aham Survey 真实界面，只作为范式落地证据")
o.p("这段实践的意义不在调研工具本身。它让我看到：一个 App 可以同时面向人和 Agent，而不必把全部智能绑定在自己的进程里。")

o.h2("06", "边界", "这还不是所有软件的答案")
o.p("实时控制、复杂编辑、视觉分析和高风险确认，仍需要专门界面。Agent 也会带来权限、成本、延迟、错误恢复和平台差异。")
o.aside("我不确定 Agent First 会不会成为所有 App 的默认形态。能确认的是：面对跨资料、跨工具、需要研究与判断的复杂任务，传统的“先打开 App 再找功能”已经不是唯一入口。")
o.p("接下来真正值得讨论的，是哪些规则必须留在代码里，哪些方法可以交给 Skill，哪些能力适合经 MCP 开放，以及人应该在哪一步确认。")
o.quote("App 不会消失，<br/>但会从交互中心退到能力载体。")
o.plate("##FOOTER##")

BODY = o.html()
(OUT / "body.html").write_text(BODY, encoding="utf-8")


def b64(name: str) -> str:
    data = (OUT / name).read_bytes()
    return "data:image/png;base64," + base64.b64encode(data).decode("ascii")


replacements = {
    "##FIG01##": "fig01.png",
    "##FIG02##": "fig02.png",
    "##FIG03##": "fig03.png",
    "##FIG04##": "fig04.png",
    "##FIG05##": "fig05.png",
    "##FOOTER##": "footer.png",
}
preview_body = BODY
for placeholder, filename in replacements.items():
    preview_body = preview_body.replace(placeholder, b64(filename))

title = "Agent First：App 不再是入口，而是能力载体"
preview = f"""<!doctype html><html lang="zh"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>{html.escape(title)}</title>
<style>*{{margin:0;padding:0;box-sizing:border-box}}body{{background:#D8DBDF;font-family:{FONT};padding:26px 12px 60px}}.w{{max-width:414px;margin:0 auto}}.cap{{font-size:11px;letter-spacing:2px;color:#5F646B;margin:0 0 8px;font-weight:700}}.cov img{{width:100%;display:block}}.n{{font-size:12px;line-height:1.7;color:#5F646B;margin:10px 0 28px}}.ph{{background:#fff}}.hd{{padding:26px 20px 0}}.t{{font-size:22px;line-height:1.45;font-weight:700;color:#1A1D21}}.m{{margin-top:14px;font-size:13px;color:#9BA1A8}}.a{{padding:24px 20px 40px}}</style></head><body><div class="w">
<div class="cap">封面 · 2.35:1</div><div class="cov"><img src="{b64('cover.png')}"></div>
<div class="cov"><img src="{b64('cover_1x1.png')}" style="width:160px;margin-top:10px"></div>
<div class="n">白底、顶部蓝条；正文只有一张深色重点图。</div>
<div class="cap">正文 · 手机宽度预览（非微信真实渲染）</div>
<div class="ph"><div class="hd"><div class="t">{html.escape(title)}</div><div class="m">原创&nbsp; Aham</div></div><div class="a">{preview_body}</div></div>
<div class="n">正式发布前仍需在公众号后台做一次真机预览，并检查深色模式。</div>
</div></body></html>"""
(OUT / "preview.html").write_text(preview, encoding="utf-8")

(OUT / "README.md").write_text(
    "# Agent First · 微信公众号交付包\n\n"
    "- `preview.html`：浏览器手机宽度预览\n"
    "- `body.html`：微信公众号正文，图片仍为上传占位符\n"
    "- `cover.png`：1800×766 头条封面\n"
    "- `cover_1x1.png`：1000×1000 分享封面\n"
    "- `fig01`—`fig05`：正文配图\n"
    "- `footer.png`：Aham 尾板\n\n"
    "标题：Agent First：App 不再是入口，而是能力载体\n",
    encoding="utf-8",
)

for generated in OUT.glob("_*.html"):
    generated.unlink()

print("Generated:")
for f in sorted(OUT.iterdir()):
    if f.is_file():
        print(f"  {f.name:24s} {f.stat().st_size // 1024:5d} KB")
