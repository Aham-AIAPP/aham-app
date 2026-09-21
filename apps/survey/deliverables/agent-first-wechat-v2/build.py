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
MCP_SHOT = (ROOT / ".build" / "mcp-console-article-raw.png").resolve()

BLUE = "#336EE8"


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
        f'<div style="margin-top:28px;padding-top:20px;border-top:1px solid {c["line"]};'
        f'font-size:28px;line-height:1.55;color:{c["ink3"]}">{source}</div>'
        if source else ""
    )
    return (
        f'<body style="background:{c["bg"]};padding:54px 52px 46px;'
        f'font-family:{P.CJK};color:{c["ink"]}">'
        f'<div style="font-size:44px;font-weight:700;line-height:1.25;color:{c["ink"]}">{title}</div>'
        f'<div style="margin-top:14px;font-size:29px;line-height:1.55;color:{c["ink2"]}">{sub}</div>'
        f'{inner}{src}</body>'
    )


def card(title: str, lines: list[str], *, dark: bool = False, accent: bool = False) -> str:
    c = P.DARK if dark else P.LIGHT
    line = BLUE if accent else c["line"]
    items = "".join(
        f'<div style="margin-top:16px;font-size:28px;line-height:1.5;color:{c["ink2"]}">— {item}</div>'
        for item in lines
    )
    return (
        f'<div style="padding:28px 28px 30px;background:{c["panel"]};border-top:5px solid {line}">'
        f'<div style="font-size:34px;font-weight:700;color:{c["ink"]}">{title}</div>{items}</div>'
    )


def two_col(left: str, right: str) -> str:
    return (
        '<table style="width:100%;border-collapse:separate;border-spacing:0;margin-top:36px"><tr>'
        f'<td style="width:50%;vertical-align:top;padding-right:12px">{left}</td>'
        f'<td style="width:50%;vertical-align:top;padding-left:12px">{right}</td>'
        '</tr></table>'
    )


# ── Covers ───────────────────────────────────────────────────────────
render(P.cover(
    ["App 不再是入口", "而是能力载体"],
    "Agent First · AI 应用新范式 · Aham Survey 实践", issue="2026.08", kicker="AHAM · 实践笔记",
), "cover", canvas_w=900, fixed_h=383, out_w=1800)
render(P.cover_square(
    ["App 不再是", "入口，而是", "能力载体", "AI 应用新范式"],
    "Agent First · Aham Survey 实践", issue="2026.08", kicker="AHAM · 实践笔记",
), "cover_1x1", canvas_w=800, fixed_h=800, out_w=1000)

# ── Fig 1: real app workspace ───────────────────────────────────────
fig1 = (
    f'<body style="background:{P.LIGHT["bg"]};padding:34px;font-family:{P.CJK}">'
    '<div style="font-size:42px;font-weight:700;line-height:1.3;color:#1A1D21">'
    '最初，我只想把现场调研做利落</div>'
    '<div style="margin-top:14px;font-size:28px;line-height:1.5;color:#5F646B">'
    '项目、部门、题目、记录、进度和导出，先回到一个工作台</div>'
    '<div style="margin-top:28px;background:#FFFFFF;padding:12px">'
    f'<img src="{APP_SHOT.as_uri()}" style="width:100%;display:block"></div>'
    '<div style="margin-top:22px;font-size:28px;line-height:1.55;color:#5F646B">'
    'Aham Survey · 聚焦式问答界面</div></body>'
)
render(fig1, "fig01")

# ── Fig 2: the first additive version ───────────────────────────────
fig2_inner = two_col(
    card("调研工作台", ["项目与部门模板", "聚焦式问答", "现场备忘与导出"]),
    card("我又加进去的 AI", ["客户文档分析", "产品与工艺搜索", "知识库训练与动态建议"], accent=True),
)
render(plate(
    "第一反应，是把更多 AI 塞进 App",
    "功能越来越多，但真正困难的问题并没有消失",
    fig2_inner,
), "fig02")

# ── Fig 3: the knowledge wall ───────────────────────────────────────
fig3_inner = P.booktabs(
    ["标准题库能回答", "现场真正还要判断"],
    [
        ["调研有哪些部门", "这家企业的核心工艺是什么"],
        ["每个部门问什么", "哪些问题与本次目标最相关"],
        ["答案如何记录", "客户刚才那句话应该追问什么"],
        ["什么算完成", "哪些资料需要先搜索和交叉核对"],
    ],
    dark=False, widths=["44%", "56%"], dim_cols=(0,),
)
render(plate(
    "我撞到的墙：题目可以预置，判断不能",
    "行业、工艺、客户现状不断变化，题库只能守住最低覆盖线",
    fig3_inner,
), "fig03")

# ── Fig 4: subtraction ──────────────────────────────────────────────
fig4_inner = two_col(
    card("从 App 中移出", ["产品与工艺搜索", "知识库训练", "客户文档分析", "新建项目 UI"]),
    card("留在 App 里", ["本地项目与题库", "现场问答界面", "校验与触发规则", "审计、撤销与导出"], accent=True),
)
render(plate(
    "这次重构的主动作，不是加，而是删",
    "复杂智能交给 Agent，确定状态留在 App",
    fig4_inner,
), "fig04")

# ── Fig 5: real MCP console, cropped before local command path ──────
fig5 = (
    f'<body style="background:{P.LIGHT["bg"]};padding:34px;font-family:{P.CJK}">'
    '<div style="font-size:42px;font-weight:700;line-height:1.3;color:#1A1D21">'
    '首页，后来变成了 MCP 控制台</div>'
    '<div style="margin-top:14px;font-size:28px;line-height:1.5;color:#5F646B">'
    'App 在本机提供能力，Claude、Codex 等 Agent 从外部接入</div>'
    '<div style="margin-top:28px;background:#111315;padding:10px;height:348px;overflow:hidden">'
    f'<img src="{MCP_SHOT.as_uri()}" style="width:100%;display:block"></div>'
    '<div style="margin-top:22px;font-size:28px;line-height:1.55;color:#5F646B">'
    '真实运行截图 · Token 仅显示指纹，配置路径已裁去</div></body>'
)
render(fig5, "fig05")

# ── Fig 6: final definition, the only dark plate ────────────────────
c = P.DARK
def layer(num: str, title: str, desc: str, accent: bool = False) -> str:
    return (
        f'<table style="width:100%;border-collapse:collapse;margin-top:20px;background:{c["panel"]};'
        f'border-left:6px solid {BLUE if accent else c["dim"]}"><tr>'
        f'<td style="width:92px;padding:25px 16px;font-family:{P.MONO};font-size:30px;'
        f'font-weight:700;color:{BLUE if accent else c["ink3"]}">{num}</td>'
        f'<td style="padding:25px 16px 25px 0"><div style="font-size:34px;font-weight:700;'
        f'color:{c["ink"]}">{title}</div><div style="margin-top:8px;font-size:28px;line-height:1.5;'
        f'color:{c["ink2"]}">{desc}</div></td></tr></table>'
    )

fig6_inner = (
    layer("01", "人", "描述目标，不必先学习某个 App", True)
    + layer("02", "Agent + Skill", "研究、判断，并按业务方法组织工作")
    + layer("03", "MCP", "把意图转换为可确认的 App 动作")
    + layer("04", "App", "保存事实，执行规则，承接专业操作")
)
render(plate(
    "做完这次重构，我才把它叫作 Agent First",
    "App 没有消失，它从唯一入口变成了可信能力载体",
    fig6_inner, dark=True,
), "fig06")

# ── Footer ──────────────────────────────────────────────────────────
render(P.footer(
    str(QR),
    ["来自 aha moment —— 每个工具只把一件事做好。",
     "这一期：从 Aham Survey 的重构，走到 Agent First。"],
    "github.com/Aham-AIAPP",
), "footer")

# ── Article ─────────────────────────────────────────────────────────
o = Post(kicker="AHAM · 实践笔记", meta="2026.08")
b, m = o.b, o.m

o.lede("Aham Survey 真正的转折，不是我给它加了 AI，而是我删掉了“新建项目”按钮。")
o.p("我一开始只想解决一个很具体的问题。做 ERP、MES、WMS 调研时，现场一边聊一边记，回来还要对着录音和零散笔记重新整理。部门、问题和证据很容易散掉。")
o.p("所以我做了 Aham Survey。先把项目、部门、题目和答案装进一个本地 App，让一次访谈能直接沉淀为结构化结果。")

o.h2("01", "起点", "先把调研现场装进一个 App")
o.p("第一版很像一款正常的专业软件：顶部按部门切换，左侧是章节和问题，中间聚焦当前题目，右侧放提示和部门进度。顾问记录、现场备忘、已采纳追问，最后一起进入报告。")
o.fig("##FIG01##", "图 1 · Aham Survey 的聚焦式现场问答")
o.p("数据保存在本机。题型、合法选项、完成进度和触发提醒由 App 判断。到这里，它已经是一把能用的现场工具。")

o.h2("02", "加法", "我又开始往里面塞 AI")
o.p("接下来走的是一条很自然的路：既然是 AI App，就让它再聪明一点。")
o.p("我做过客户文档分析、产品与工艺搜索、知识库训练、动态选项、优先级排序，也把润色和追问放进界面。每碰到一个问题，就准备再加一个模块。")
o.fig("##FIG02##", "图 2 · 从调研工作台走向一款“大而全”的 AI App")
o.p("功能确实多了。但开发到后面，我越来越清楚：最难的部分不是调用一次模型，而是让 App 提前知道所有行业应该怎么调研。")

o.h2("03", "撞墙", "题目可以预置，判断不能")
o.p("编一套通用题库并不难。难的是面对一家具体企业，先理解它生产什么、工艺怎么走、哪些异常值得追问，再决定这次应该把时间放在哪里。")
o.p("离散装配、机加工和流程生产，可以共享一些基础问题，但不会共享同一套高价值追问。题库做得太通用，现场问不深；题库继续膨胀，顾问又很难用。")
o.fig("##FIG03##", "图 3 · 标准结构与动态判断之间的缺口")
o.p("而这些恰好是强 Agent 擅长的工作：读客户资料，搜索行业工艺，比较多个来源，再根据当前上下文生成提纲和追问。为了使用这些能力，我没有必要在每个 App 里重新做一遍搜索、文件阅读和模型编排。")

o.h2("04", "减法", "我决定先删掉一批功能")
o.p("于是这次重构反过来了。我移出了产品与工艺搜索、知识库训练、客户文档分析和项目级 AI，也把语音转写交给独立工具。")
o.p("最后，我连“新建项目”按钮也删了。项目由 Agent 根据用户资料创建；App 只接收结构化、经过校验的结果。")
o.fig("##FIG04##", "图 4 · 从 App 中移出什么，又留下什么")
o.p("留下来的部分反而更清楚：本地项目、标准题库、现场界面、答案校验、触发规则、变更记录、撤销和导出。App 变小了，但它对结果负责。")

o.h2("05", "接线", "Skill 和 MCP 把两边接了起来")
o.p("我给 Aham Survey 加了一个只监听本机的 MCP 服务，又写了一份 Agent Skill。")
o.p("MCP 负责把项目、题目、答案和导出能力交给 Agent。Skill 负责另一件事：告诉 Agent 先读什么、哪些事实不能猜、批量回写为什么必须先预览、冲突后怎样重新确认。")
o.fig("##FIG05##", "图 5 · 当前 Aham Survey 首页的 MCP 控制台")
o.p("现在，一段访谈材料可以先由 Agent 拆成证据，映射到 App 返回的真实题目；App 校验题型和选项，生成预览；用户确认后再提交。写入完成，结果仍回到现场界面和报告里。")
o.p("目前这条链路已经覆盖项目创建、题目读取、访谈映射、预览提交、变更记录、撤销和导出。行业搜索后把自定义提纲完整写回 App，还是我准备继续补的一段。")

o.h2("06", "命名", "做完以后，我才把它叫作 Agent First")
o.p("我不是先想出一套架构，再找 Aham Survey 来证明。顺序正好相反：先做 App，给它不断加功能，撞到知识边界，再通过删减和外接，把各自的职责分开。")
o.fig("##FIG06##", "图 6 · 从一次 App 重构中长出来的 Agent First")
o.p("这时我才意识到，App 不一定继续承担所有交互。人可以先把目标交给 Agent；Skill 提供业务方法；MCP 把动作交给 App；App 保存事实，执行确定规则，并在人真正需要时提供专业界面。")
o.aside("我不确定这种方式会不会适合所有软件。实时控制、复杂编辑和高风险确认仍然需要直接界面。MCP 也不替代 API，它提供的是 Agent 可发现的能力边界。资料来源：MCP Architecture Overview（modelcontextprotocol.io/docs/learn/architecture）和 Agent Skills 开放规范（agentskills.io/home）。")
o.p("我现在更想讨论的，不是 App 会不会消失，而是下一款 App 开发时，我们会先画页面，还是先决定应该向 Agent 开放哪些可信能力。")
o.quote("Agent First 不是我先想出来的。<br/>它是从一次 App 重构里长出来的。")
o.plate("##FOOTER##")

BODY = o.html()
(OUT / "body.html").write_text(BODY, encoding="utf-8")


def b64(name: str) -> str:
    return "data:image/png;base64," + base64.b64encode((OUT / name).read_bytes()).decode("ascii")


files = {
    "##FIG01##": "fig01.png",
    "##FIG02##": "fig02.png",
    "##FIG03##": "fig03.png",
    "##FIG04##": "fig04.png",
    "##FIG05##": "fig05.png",
    "##FIG06##": "fig06.png",
    "##FOOTER##": "footer.png",
}
preview_body = BODY
for placeholder, filename in files.items():
    preview_body = preview_body.replace(placeholder, b64(filename))

title = "Agent First：App 不再是入口，而是能力载体，AI 应用新范式"
preview = f"""<!doctype html><html lang="zh"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>{html.escape(title)}</title>
<style>*{{margin:0;padding:0;box-sizing:border-box}}body{{background:#D8DBDF;font-family:{FONT};padding:26px 12px 60px}}.w{{max-width:414px;margin:0 auto}}.cap{{font-size:11px;letter-spacing:2px;color:#5F646B;margin:0 0 8px;font-weight:700}}.cov img{{width:100%;display:block}}.n{{font-size:12px;line-height:1.7;color:#5F646B;margin:10px 0 28px}}.ph{{background:#fff}}.hd{{padding:26px 20px 0}}.t{{font-size:22px;line-height:1.45;font-weight:700;color:#1A1D21}}.m{{margin-top:14px;font-size:13px;color:#9BA1A8}}.a{{padding:24px 20px 40px}}</style></head><body><div class="w">
<div class="cap">封面 · 2.35:1</div><div class="cov"><img src="{b64('cover.png')}"></div>
<div class="cov"><img src="{b64('cover_1x1.png')}" style="width:160px;margin-top:10px"></div>
<div class="n">第二版：先讲开发实践和转折，最后才定义 Agent First。</div>
<div class="cap">正文 · 手机宽度预览（非微信真实渲染）</div>
<div class="ph"><div class="hd"><div class="t">{html.escape(title)}</div><div class="m">原创&nbsp; Aham</div></div><div class="a">{preview_body}</div></div>
<div class="n">正式发布前仍需在公众号后台做一次真机预览，并检查深色模式。</div>
</div></body></html>"""
(OUT / "preview.html").write_text(preview, encoding="utf-8")

(OUT / "README.md").write_text(
    "# Agent First · 微信公众号第二版\n\n"
    "标题：Agent First：App 不再是入口，而是能力载体，AI 应用新范式\n\n"
    "叙事顺序：开发起点 → AI 加法 → 知识边界 → 功能减法 → Skill + MCP → Agent First。\n\n"
    "- `preview.html`：浏览器手机宽度预览\n"
    "- `body.html`：微信公众号正文，图片为上传占位符\n"
    "- `cover.png` / `cover_1x1.png`：双封面\n"
    "- `fig01.png`—`fig06.png`：正文图\n"
    "- `footer.png`：尾板\n",
    encoding="utf-8",
)

for generated in OUT.glob("_*.html"):
    generated.unlink()

print("Generated:")
for f in sorted(OUT.iterdir()):
    if f.is_file():
        print(f"  {f.name:20s} {f.stat().st_size // 1024:5d} KB")
