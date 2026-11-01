"""网页渲染器：读取文档块内容（JSON），输出单文件 HTML。Word 内容的网页预览也用它排版。

颜色、字体、字号、线宽和版面取自 tokens.json（经 webstyle 转成 CSS 变量），组件样式在 web/base.css。
本模块只拼结构，不写色值和字号。文字在渲染时按规则规范化（中文标点）。内容格式见技能的 references/web-format.md。

用法：python3 scripts/build_html.py 内容.json 输出.html [--fragment]
  默认输出完整 HTML 文件，可离线打开。
  --fragment 输出不含 <!doctype>、<html>、<head>、<body> 的页面片段，用于发布为网页（发布时由平台补齐外壳）。

扩展点：业务专有的内容块、表格行和样式经 register_block、register_row、register_stylesheet 登记，引擎不导入调用方脚本。
"""

from __future__ import annotations

import base64
import html
import json
import mimetypes
import re
import sys
from pathlib import Path
from typing import Any, Callable

from .blocks import BLOCK_TYPES, BlockError
from .brand import current_brand
from .paths import PACKAGE
from .text import cjk_punct
from .webstyle import behavior_js, stylesheet

__all__ = [
    "Builder", "HtmlError", "build", "data_uri", "esc", "inline", "main", "page",
    "register_block", "register_row", "register_stylesheet",
]

TEMPLATE = PACKAGE / "template.html"
CALLOUT_TONES = {"lead": "", "key": " key", "risk": " risk"}
TAG_CLASSES = {"solid": "tag tag-solid", "outline": "tag", "faint": "tag tag-faint", "hot": "tag tag-hot"}
ROW_CLASSES = {"row": "", "faint": "is-faint"}
HIGHLIGHT = re.compile(r"==(.+?)==")
# 不能放进折叠场景的块：它们自己有标题层级或整页交互。
_NOT_IN_SCENE = {"heading", "scenes", "with_aside", "checklist"}


class HtmlError(ValueError):
    pass


# ---------- 扩展点 ----------
# 登记按名称覆盖，重复登记不叠加。

BlockRenderer = Callable[["Builder", dict[str, Any], dict[str, Any]], str]
RowRenderer = Callable[["Builder", dict[str, Any], list[Any], set[int]], str]
_BLOCK_RENDERERS: dict[str, BlockRenderer] = {}
_ROW_RENDERERS: dict[str, RowRenderer] = {}
_STYLESHEETS: dict[str, str] = {}


def register_block(kind: str, renderer: BlockRenderer, required: tuple[str, ...] = ()) -> None:
    """登记一种内容块：renderer(builder, block, ctx) 返回 HTML。required 是生成前检查的必填字段。"""
    _BLOCK_RENDERERS[kind] = renderer
    _REQUIRED[kind] = tuple(required)


def register_row(kind: str, renderer: RowRenderer) -> None:
    """登记一种表格行：renderer(builder, row, columns, amount_cols) 返回完整的 <tr>。用于合计行、分组行等。"""
    _ROW_RENDERERS[kind] = renderer


def register_stylesheet(name: str, css: str) -> None:
    """登记附加样式，接在组件样式之后。附加样式只引用 :root 变量，不写色值和字号。"""
    _STYLESHEETS[name] = css


_REQUIRED: dict[str, tuple[str, ...]] = {}


def _validate(items: list[dict[str, Any]], where: str) -> None:
    """检查块类型已登记、必填字段齐全；递归检查旁注正文和折叠场景。"""
    for index, block in enumerate(items or []):
        label = f"{where}第 {index + 1} 块"
        kind = block.get("type", "paragraph")
        if kind in _BLOCK_RENDERERS:
            required = _REQUIRED.get(kind, ())
        elif kind in BLOCK_TYPES and hasattr(Builder, "b_" + kind):
            required = BLOCK_TYPES[kind]
        else:
            raise HtmlError(f"{label}：网页渲染器没有块类型 {kind!r}。业务专有的块用 register_block 登记")
        missing = [field for field in required if field not in block]
        if missing:
            raise HtmlError(f"{label}（{kind}）缺少字段：{'、'.join(missing)}")
        if kind == "with_aside":
            _validate(block.get("blocks") or [], f"{label} 正文")
        if kind == "scenes":
            for scene in block.get("items") or []:
                _validate(scene.get("blocks") or [], f"{label} 场景「{scene.get('title', '')}」")


def esc(value: Any) -> str:
    return html.escape(str(value if value is not None else ""), quote=True)


def inline(text: Any) -> str:
    """规范中文标点后转义文字；==文字== 写成荧光标记；换行照原样分行；必答标记「★」用重点色。"""
    parts = HIGHLIGHT.split(cjk_punct(str(text if text is not None else "")))
    out = "".join(f"<mark>{esc(p)}</mark>" if i % 2 else esc(p) for i, p in enumerate(parts))
    return out.replace("\n", "<br>").replace("★", '<span class="req" aria-label="必答">★</span>')


def data_uri(path: Path) -> str:
    if not path.is_file():
        raise HtmlError(f"图片不存在：{path}")
    mime = mimetypes.guess_type(path.name)[0] or "image/png"
    return f"data:{mime};base64,{base64.b64encode(path.read_bytes()).decode()}"


class Builder:
    def __init__(self, content: dict[str, Any], base_dir: Path):
        self.c = content
        self.base = base_dir
        # 参与方按出场顺序对应 4 种参与方颜色。lane=false 的参与方只出现在清单和图例里，不占泳道，须排在最后。
        raw = content.get("parties", [])
        if len(raw) > 4:
            raise HtmlError("参与方最多 4 个，对应 4 种参与方颜色")
        self.parties = [p["name"] for p in raw]
        self.aliases = {alias: i + 1 for i, p in enumerate(raw) for alias in [p["name"], *p.get("aliases", [])]}
        self.lanes = [p["name"] for p in raw if p.get("lane", True)]
        if self.parties[:len(self.lanes)] != self.lanes:
            raise HtmlError("不占泳道的参与方须排在参与方列表最后")

    # ---------- 行内与小组件 ----------
    def party(self, ref: Any) -> int:
        if isinstance(ref, int):
            if not 1 <= ref <= len(self.parties):
                raise HtmlError(f"参与方编号 {ref} 超出范围")
            return ref
        if ref in self.aliases:
            return self.aliases[ref]
        raise HtmlError(f"未登记的参与方：{ref}")

    def party_label(self, ref: Any) -> str:
        """清单和表格里显示调用方写的名称（可以是别名），颜色按所属参与方。"""
        return self.parties[ref - 1] if isinstance(ref, int) else str(ref)

    def dot(self, ref: Any) -> str:
        return f'<i class="dot dot-{self.party(ref)}"></i>'

    def cell(self, value: Any) -> str:
        if isinstance(value, dict):
            text = inline(value.get("text", ""))
            if "tag" in value:
                return f'<span class="{TAG_CLASSES[value["tag"]]}">{text}</span>'
            if "party" in value:
                return f"{self.dot(value['party'])}{text}"
            if "level" in value:
                hot = value["level"] == "hot"
                return f'<span class="lv{" lv-hot" if hot else ""}">{text}</span>'
            if value.get("required"):
                return f'<span class="req" aria-label="必答">★</span>{text}'
            if value.get("strike"):
                return f"<s>{text}</s>"
            if value.get("faint"):
                return f'<span class="faint">{text}</span>'
            return text
        return inline(value)

    # ---------- 块 ----------
    def block(self, b: dict[str, Any], ctx: dict[str, Any]) -> str:
        kind = b.get("type", "paragraph")
        if kind in _BLOCK_RENDERERS:
            return _BLOCK_RENDERERS[kind](self, b, ctx)
        method = getattr(self, "b_" + kind, None)
        if method is None:
            raise HtmlError(f"未知的内容块类型：{kind}。业务专有的块用 register_block 登记")
        return method(b, ctx)

    def blocks(self, items: list[dict[str, Any]], ctx: dict[str, Any]) -> str:
        return "\n".join(self.block(b, ctx) for b in items)

    def b_paragraph(self, b, ctx):
        cls = ' class="note"' if b.get("muted") else ""
        return f"<p{cls}>{inline(b['text'])}</p>"

    def b_heading(self, b, ctx):
        level = int(b.get("level", 2))
        if "number" in b:
            # 编号由调用方给定（如网页预览按 Word 大纲编号），不参与自动计数；空字符串表示不编号。
            num = f'<span class="num">{esc(b["number"])}</span>' if b["number"] else ""
            tag_name = "h3" if level <= 2 else "h4"
            return f"<{tag_name}>{num}{esc(b['title'])}</{tag_name}>"
        if level == 2:
            ctx["sub"] += 1
            ctx["subsub"] = 0
            number = f"{ctx['chapter']}.{ctx['sub']}"
            ident = b.get("id") or f"c{ctx['chapter']}-{ctx['sub']}"
            ctx["toc"].append((number, b["title"], ident))
            tag = f' <span class="{TAG_CLASSES[b["tag"]]}">{esc(b.get("tag_text", ""))}</span>' if b.get("tag") else ""
            return f'<h3 id="{esc(ident)}"><span class="num">{number}</span>{esc(b["title"])}{tag}</h3>'
        ctx["subsub"] += 1
        number = f"{ctx['chapter']}.{ctx['sub']}.{ctx['subsub']}"
        return f'<h4><span class="num">{number}</span>{esc(b["title"])}</h4>'

    def b_list(self, b, ctx):
        tag = "ol" if b.get("ordered") else "ul"
        def item(i):
            if isinstance(i, dict):
                return f'<li{" class=\"faint\"" if i.get("faint") else ""}>{inline(i["text"])}</li>'
            return f"<li>{inline(i)}</li>"
        items = "".join(item(i) for i in b["items"])
        return f'<{tag} class="list">{items}</{tag}>'

    def b_quote(self, b, ctx):
        cite = f"<cite>{esc(b['source'])}</cite>" if b.get("source") else ""
        return f"<blockquote><p>{inline(b['text'])}</p>{cite}</blockquote>"

    def b_callout(self, b, ctx):
        tone = b.get("tone", "lead")
        if tone not in CALLOUT_TONES:
            raise HtmlError(f"提示条 tone 只能是 lead、key 或 risk：{tone}")
        return (f'<div class="callout{CALLOUT_TONES[tone]}"><span class="lb">{esc(b["label"])}</span>'
                f"<p>{inline(b['text'])}</p></div>")

    def b_codebox(self, b, ctx):
        """指令框：整段可复制的文字。text 可以是字符串或行列表，原样保留换行。"""
        text = b.get("text", "")
        if isinstance(text, list):
            text = "\n".join(str(t) for t in text)
        label = esc(b.get("label", "复制后发送"))
        return (f'<div class="cmd"><div class="cmd-hd"><span class="lb">{label}</span>'
                f'<button type="button" class="btn cmd-copy">复制全文</button></div>'
                f"<pre>{esc(text)}</pre></div>")

    def b_table(self, b, ctx):
        if b.get("layout") == "key_value":
            # 键值表（版面规则 key_value_table）：单栏，标签在左，不设表头行。
            caption = f"<caption>{esc(b['caption'])}</caption>" if b.get("caption") else ""
            body = "".join(
                f'<tr><th scope="row" class="kv-k">{self.cell(r[0])}</th><td>{self.cell(r[1] if len(r) > 1 else "")}</td></tr>'
                for r in (x if isinstance(x, list) else x.get("cells", []) for x in b["rows"]))
            return f'<div class="scroll"><table class="tbl kv">{caption}<tbody>{body}</tbody></table></div>'
        cols = b["columns"]
        amount = set(b.get("amount_cols", []))
        row_header = b.get("row_header", True)
        table_id = b.get("id") or f"t{ctx['chapter']}-{len(ctx['tables']) + 1}"
        ctx["tables"].append(table_id)
        head = "".join(
            f'<th class="{"amount" if i in amount else ""}{" w-no" if i == 0 and b.get("number_col") else ""}">{self.cell(c)}</th>'
            for i, c in enumerate(cols))
        rows = []
        for r in b["rows"]:
            r = {"cells": r} if isinstance(r, list) else r
            kind = r.get("kind", "row")
            if kind in _ROW_RENDERERS:
                rows.append(_ROW_RENDERERS[kind](self, r, cols, amount))
                continue
            if kind not in ROW_CLASSES:
                raise HtmlError(f"表格行 kind 只能是 row 或 faint：{kind}。合计行、分组行等业务行用 register_row 登记")
            cls = ROW_CLASSES[kind]
            attrs = f' class="{cls}"' if cls else ""
            if r.get("key"):
                attrs += f' data-key="{esc(r["key"])}"'
            cells = r["cells"]
            if len(cells) != len(cols):
                raise HtmlError(f"表格「{b.get('caption', table_id)}」有一行列数 {len(cells)} 与表头 {len(cols)} 不一致")
            tds = []
            aligns = b.get("alignments") or []
            for i, v in enumerate(cells):
                klass = "amount" if i in amount else ("faint" if isinstance(v, str) and v in b.get("faint_values", []) else "")
                cattr = f' class="{klass}"' if klass else ""
                if i < len(aligns) and aligns[i] in ("center", "right") and i not in amount:
                    cattr += f' style="text-align:{aligns[i]}"'
                if i == 0 and row_header:
                    tds.append(f'<th scope="row"{cattr}>{self.cell(v)}</th>')
                else:
                    tds.append(f"<td{cattr}>{self.cell(v)}</td>")
            rows.append(f"<tr{attrs}>{''.join(tds)}</tr>")
        caption = f"<caption>{esc(b['caption'])}</caption>" if b.get("caption") else ""
        tools = ""
        if b.get("filter"):
            f = b["filter"]
            keys = [r.get("key") for r in b["rows"] if isinstance(r, dict)]
            buttons = [f'<button type="button" class="seg" aria-pressed="true" data-key="all">全部<span class="num">{len(keys)}</span></button>']
            for opt in f["options"]:
                n = sum(1 for k in keys if k == opt["key"])
                buttons.append(f'<button type="button" class="seg" aria-pressed="false" data-key="{esc(opt["key"])}">{esc(opt["label"])}<span class="num">{n}</span></button>')
            tools = (f'<div class="tools"><div class="segs" role="group" aria-label="{esc(f.get("label", "筛选"))}" '
                     f'data-filter="{esc(table_id)}">{"".join(buttons)}</div></div>')
        return (f'{tools}<div class="scroll"><table class="tbl" id="{esc(table_id)}">{caption}'
                f"<thead><tr>{head}</tr></thead><tbody>{''.join(rows)}</tbody></table></div>")

    def b_figure(self, b, ctx):
        src = f'<span class="src">{esc(b["source"])}</span>' if b.get("source") else ""
        width = f' style="max-width:{int(b["max_width"])}px"' if b.get("max_width") else ""
        img = data_uri(self.base / b["path"])
        return (f'<figure class="shot"{width}><img src="{img}" alt="{esc(b.get("alt") or b["caption"])}">'
                f"<figcaption>{esc(b['caption'])}{src}</figcaption></figure>")

    def b_figures(self, b, ctx):
        return '<div class="shots">' + "".join(self.b_figure(i, ctx) for i in b["items"]) + "</div>"

    def b_svg(self, b, ctx):
        """内联 SVG 图。图里只能用 web/base.css 的 .bx .bx-a .ln .ln-a .t1 .t1a .t2 .ah .ah-a 等类，不写色值和字号。"""
        svg = (self.base / b["path"]).read_text("utf-8")
        src = f'<span class="src">{esc(b["source"])}</span>' if b.get("source") else ""
        return f'<figure class="flow">{svg}<figcaption>{esc(b["caption"])}{src}</figcaption></figure>'

    def b_anatomy(self, b, ctx):
        parts = []
        for i, p in enumerate(b["parts"]):
            if i and b.get("separator"):
                parts.append(f'<span class="seg-c" aria-hidden="true"><b class="faint">{esc(b["separator"])}</b></span>')
            parts.append(f'<span class="seg-c{" v" if p.get("key") else ""}"><b>{esc(p["code"])}</b><span class="dim">{esc(p["label"])}</span></span>')
        return (f'<figure><div class="anat" role="img" aria-label="{esc(b.get("alt") or b["caption"])}">{"".join(parts)}</div>'
                f"<figcaption>{esc(b['caption'])}</figcaption></figure>")

    def b_notes(self, b, ctx):
        def item(text: str) -> str:
            label, sep, body = text.partition("：")
            return f"<li><b>{esc(label)}：</b>{inline(body)}</li>" if sep and len(label) <= 8 else f"<li>{inline(text)}</li>"
        title = f'<p class="notes-t">{esc(b["title"])}</p>' if b.get("title") else ""
        return f'{title}<ol class="notes">{"".join(item(t) for t in b["items"])}</ol>'

    def b_columns(self, b, ctx):
        cols = []
        for col in b["items"]:
            dot = self.dot(col["party"]) if col.get("party") else ""
            items = "".join(f"<li>{inline(i)}</li>" for i in col["items"])
            cols.append(f"<div><h4>{dot}{esc(col['title'])}</h4><ol>{items}</ol></div>")
        return f'<div class="cols">{"".join(cols)}</div>'

    def b_legend(self, b, ctx):
        labels = b.get("labels") or self.lanes
        return '<div class="legend">' + "".join(
            f"<span>{self.dot(i)}{esc(label)}</span>" for i, label in enumerate(labels, 1)) + "</div>"

    def b_with_aside(self, b, ctx):
        notes = []
        for a in b["aside"]:
            tone = a.get("tone")
            if tone in {"lead", "key", "risk"}:
                cls = "rule" + ("" if tone == "lead" else f" {tone}")
                notes.append(f'<div class="{cls}"><span class="lb">{esc(a["label"])}</span><p>{inline(a["text"])}</p></div>')
            else:
                notes.append(f'<div><span class="lb">{esc(a["label"])}</span>{inline(a["text"])}</div>')
        return (f'<div class="with-aside"><div>{self.blocks(b["blocks"], ctx)}</div>'
                f'<aside class="side">{"".join(notes)}</aside></div>')

    def b_swimlane(self, b, ctx):
        """独立泳道图：steps 为 [执行方, 角色, 操作] 列表。Word 内容的泳道图在网页预览里用它。"""
        caption = f"<figcaption>{esc(b['caption'])}</figcaption>" if b.get("caption") else ""
        steps = [tuple(s) if not isinstance(s, dict) else (s.get("party"), s.get("role", ""), s.get("text", "")) for s in b["steps"]]
        return f'<figure class="flow-lane"><div class="scroll">{self.swimlane(steps)}</div>{caption}</figure>'

    # ---------- 场景 ----------
    def swimlane(self, steps: list) -> str:
        n, lanes = len(steps), len(self.lanes)
        out = [f'<div class="sl" style="--n:{n};--lanes:{lanes}" role="img" aria-label="{n} 个步骤在 {lanes} 条泳道上的分布">',
               '<span class="sl-axis" aria-hidden="true"></span>']
        out += [f'<span class="sl-no" style="grid-column:{i + 1}">{i:02d}</span>' for i in range(1, n + 1)]
        for row, name in enumerate(self.lanes, 2):
            cls = ["sl-lane"] + (["first"] if row == 2 else []) + (["even"] if row % 2 == 1 else []) + (["last"] if row == lanes + 1 else [])
            out.append(f'<span class="{" ".join(cls)}" style="grid-row:{row}"></span>')
            out.append(f'<span class="sl-name" style="grid-row:{row}">{self.dot(name)}{esc(name)}</span>')
        for i, (who, role, text) in enumerate(steps, 1):
            lane = self.party(who)
            if lane > lanes:
                raise HtmlError(f"步骤执行方「{who}」不占泳道")
            r = f"<b>{esc(role)}</b>" if role else ""
            out.append(f'<span class="sl-box sl-{lane}" style="grid-column:{i + 1};grid-row:{lane + 1}">{r}{esc(text)}</span>')
        return "".join(out) + "</div>"

    def steps_table(self, steps: list) -> str:
        rows = "".join(
            f'<tr><td class="num">{i:02d}</td><td>{self.dot(who)}{esc(role or self.parties[self.party(who) - 1])}</td><td>{esc(text)}</td></tr>'
            for i, (who, role, text) in enumerate(steps, 1))
        return ('<table class="tbl"><thead><tr><th class="w-no">步骤</th><th class="w-who">执行方</th><th>操作</th></tr></thead>'
                f"<tbody>{rows}</tbody></table>")

    def matrix(self, m: dict) -> str:
        head = "".join(f"<th>{self.dot(n)}{esc(n)}</th>" for n in self.lanes)
        none = m.get("none", "不涉及")
        rows = "".join(
            f'<tr><th scope="row">{esc(r[0])}</th>' + "".join(
                f'<td class="{"faint" if v == none else ""}">{esc(v)}</td>' for v in r[1:]) + "</tr>"
            for r in m["rows"])
        return f'<table class="tbl"><thead><tr><th>{esc(m.get("label", "情况"))}</th>{head}</tr></thead><tbody>{rows}</tbody></table>'

    def b_scenes(self, b, ctx):
        out = []
        chips = []
        for s in b["items"]:
            ctx["sub"] += 1
            number = f"{ctx['chapter']}.{ctx['sub']}"
            ident = s.get("id") or f"s{ctx['chapter']}-{ctx['sub']}"
            ctx["toc"].append((number, s["title"], ident))
            chips.append(f'<a href="#{esc(ident)}"><span class="num">{number}</span>{esc(s["title"])}</a>')
            if "table" in s:
                body = self.b_table(s["table"], ctx)
                count = s.get("count") or f"{len(s['table']['rows'])} 项"
            elif "steps" in s:
                steps = s["steps"]
                hint = (f'<p class="hint">共 {len(steps)} 步，左右滑动查看全部，或切换到步骤表。</p>' if len(steps) > 7 else "")
                body = ('<div class="view-switch" role="group" aria-label="显示方式">'
                        '<button type="button" class="seg" aria-pressed="true" data-view="lane">泳道图</button>'
                        '<button type="button" class="seg" aria-pressed="false" data-view="table">步骤表</button></div>'
                        f'<div class="view" data-view="lane"><div class="scroll">{self.swimlane(steps)}</div>{hint}</div>'
                        f'<div class="view" data-view="table" hidden><div class="scroll">{self.steps_table(steps)}</div></div>')
                count = f"{len(steps)} 步"
            elif "blocks" in s:
                for inner in s["blocks"]:
                    if inner.get("type") in _NOT_IN_SCENE:
                        raise HtmlError(f"折叠段「{s['title']}」里不能放 {inner.get('type')} 块")
                body = self.blocks(s["blocks"], ctx)
                count = s.get("count", "")
            else:
                body = f'<div class="scroll">{self.matrix(s["matrix"])}</div>'
                count = f"{len(s['matrix']['rows'])} 种情况"
            lead = f"<p>{inline(s['lead'])}</p>" if s.get("lead") else ""
            note = f'<p class="note">{inline(s["note"])}</p>' if s.get("note") else ""
            opened = " open" if s.get("open", True) else ""
            count_html = f'<span class="count">{esc(count)}</span>' if count else ""
            out.append(f'<details class="fold" id="{esc(ident)}"{opened}><summary><span class="num">{number}</span>{esc(s["title"])}'
                       f'{count_html}<span class="chev" aria-hidden="true"></span></summary>'
                       f'<div class="fold-body">{lead}{body}{note}</div></details>')
        index = f'<nav class="chips" aria-label="场景索引">{"".join(chips)}</nav>' if b.get("index") else ""
        switch = ""
        if b.get("switch_all"):
            switch = ('<div class="tools"><div class="segs" role="group" aria-label="全部场景的显示方式">'
                      '<button type="button" class="seg" aria-pressed="true" data-all="lane">全部看泳道图</button>'
                      '<button type="button" class="seg" aria-pressed="false" data-all="table">全部看步骤表</button></div></div>')
        ctx["has_folds"] = True
        return switch + index + "\n".join(out)

    def b_checklist(self, b, ctx):
        items = b["items"]
        ident = b.get("id", "qs")
        lis = []
        for i, it in enumerate(items, 1):
            star = '<span class="req" aria-label="必答">★</span>' if it.get("required") else ""
            who = ""
            key = ""
            if it.get("party"):
                p = self.party(it["party"])
                who = f'<span class="who">{self.dot(p)}{esc(self.party_label(it["party"]))}</span>'
                key = f' data-key="{p}"'
            lis.append(f'<li{key}><input type="checkbox" id="{ident}-{i}"><label for="{ident}-{i}"><span class="num">{i:02d}</span>'
                       f'<span class="qt">{star}{inline(it["text"])}</span>{who}</label></li>')
        segs = ""
        if any(it.get("party") for it in items):
            counts, names = {}, {}
            for it in items:
                if it.get("party"):
                    p = self.party(it["party"])
                    counts[p] = counts.get(p, 0) + 1
                    names.setdefault(p, self.party_label(it["party"]))
            buttons = "".join(f'<button type="button" class="seg" aria-pressed="false" data-key="{p}">{esc(names[p])}<span class="num">{n}</span></button>'
                              for p, n in sorted(counts.items()))
            segs = (f'<div class="segs" role="group" aria-label="按答复方筛选" data-filter-list="{ident}">'
                    f'<button type="button" class="seg" aria-pressed="true" data-key="all">全部<span class="num">{len(items)}</span></button>{buttons}</div>')
        store = b.get("store_key") or f"proposal-{ident}"
        return (f'<div class="q-tools">{segs}<div class="prog" data-prog="{ident}"><span>{esc(b.get("progress_label", "已确认"))} '
                f'<span class="prog-n num">0 / {len(items)}</span></span><span class="prog-bar"><span></span></span></div>'
                f'<button type="button" class="btn btn-ghost" data-clear="{ident}">清空勾选</button></div>'
                f'<ul class="qs" id="{ident}" data-store="{esc(store)}">{"".join(lis)}</ul>')

    # ---------- 页面 ----------
    def build(self, fragment: bool = False, script: bool = True) -> str:
        return page(self.c["meta"].get("page_title") or self.c["meta"]["title"], self.body(), fragment=fragment, script=script)

    def body(self, bar: bool = True) -> str:
        """工具条、正文和页尾，不含页面外壳。多份文档合成一页时逐份调用，只有第一份带工具条。"""
        m = self.c["meta"]
        chapters_html, toc = [], []
        has_folds = False
        for n, ch in enumerate(self.c["chapters"], 1):
            ctx = {"chapter": n, "sub": 0, "subsub": 0, "toc": [], "tables": [], "has_folds": False}
            ident = ch.get("id") or f"c{n}"
            try:
                _validate(ch.get("blocks", []), f"第 {n} 章「{ch.get('title', '')}」")
            except BlockError as exc:
                raise HtmlError(str(exc)) from exc
            body = self.blocks(ch.get("blocks", []), ctx)
            has_folds = has_folds or ctx["has_folds"]
            # 章编号可由调用方给定（网页预览按 Word 大纲），空字符串表示不编号。
            number = str(ch["number"]) if "number" in ch else str(n)
            num_html = f'<span class="num">{esc(number)}</span>' if number else ""
            chapters_html.append(f'<section class="ch" id="{esc(ident)}"><h2>{num_html}{esc(ch["title"])}</h2>\n{body}\n</section>')
            toc.append((number, ch["title"], ident, ctx["toc"] if ch.get("toc_sub") else []))
        keys = "".join(f'<li><span class="k">{esc(k["label"])}</span><span class="v">{inline(k["value"])}</span></li>'
                       for k in self.c.get("keys", []))
        if m.get("items"):
            meta_items = [(x["label"], x["value"]) for x in m["items"]]
        else:
            meta_items = [("项目", m.get("project")), ("编制", m.get("author")), ("版本", m.get("version")), ("日期", m.get("date"))]
            meta_items += [(x["label"], x["value"]) for x in m.get("extra", [])]
        meta = "".join(f'<span>{esc(k)}<b{" class=\"num\"" if k in ("日期", "版本") else ""}>{esc(v)}</b></span>' for k, v in meta_items if v)
        toc_html = ""
        if len(toc) >= 4 and self.c.get("toc", True):
            entries = []
            for num, title, ident, subs in toc:
                entries.append(f'<li><a href="#{esc(ident)}"><span class="num">{num}</span>{esc(title)}</a></li>')
                entries += [f'<li class="sub"><a href="#{esc(i)}"><span class="num">{sn}</span>{esc(st)}</a></li>' for sn, st, i in subs]
            half = (len(entries) + 1) // 2
            toc_html = (f'<nav class="toc" aria-label="目录"><ol>{"".join(entries[:half])}</ol>'
                        f'<ol>{"".join(entries[half:])}</ol></nav>')
        buttons = []
        if has_folds:
            buttons += ['<button type="button" class="btn btn-ghost" data-fold="open">展开全部场景</button>',
                        '<button type="button" class="btn btn-ghost" data-fold="close">收起全部场景</button>']
        for link in self.c.get("toolbar", {}).get("links", [])[:1]:
            buttons.append(f'<a class="btn btn-primary" href="{esc(link["href"])}">{esc(link["label"])}</a>')
        eyebrow = " · ".join(x for x in (m.get("customer"), m.get("doc_kind")) if x)
        bar_sub = m.get("bar_subtitle") or m.get("doc_kind") or m.get("version", "")
        brand = current_brand()
        brand_line = brand.company if brand.wordmark in brand.company else f"{brand.company} · {brand.wordmark}"
        footer_right = " · ".join(x for x in (m.get("footer_note"), m.get("version"), m.get("date")) if x)
        header = (f'''<header class="bar"><div class="bar-in">
<span class="bar-t"><b>{esc(m["title"])}</b>　{esc(bar_sub)}</span>
{"".join(buttons)}</div></header>
''' if bar else "")
        eyebrow_html = f'<p class="eyebrow">{esc(eyebrow)}</p>\n' if eyebrow else ""
        lede_html = f'<p class="lede">{inline(m["lede"])}</p>\n' if m.get("lede") else ""
        return header + f'''<main class="page">
<div class="head">
{eyebrow_html}<h1>{esc(m["title"])}</h1>
{lede_html}<div class="meta">{meta}</div>
{f'<ul class="keys">{keys}</ul>' if keys else ""}
{toc_html}
</div>
{"".join(chapters_html)}
<footer><span>{esc(brand_line)}</span><span>{esc(footer_right)}</span></footer>
</main>'''


def page(title: str, body: str, *, fragment: bool = False, script: bool = True) -> str:
    """把正文套进页面外壳。script=False 时不嵌交互脚本，用于只读的确认预览。"""
    css = stylesheet(extra="".join(_STYLESHEETS.values()))
    values = {"{{TITLE}}": esc(title), "{{STYLE}}": css, "{{BODY}}": body,
              "{{SCRIPT}}": behavior_js() if script else ""}
    if fragment:
        shell = ('<title>{{TITLE}}</title>\n<meta name="claude:viewport-fit-sides" content="cover">\n'
                 "<style>\n{{STYLE}}</style>\n{{BODY}}\n" + ("<script>\n{{SCRIPT}}</script>\n" if script else ""))
    else:
        shell = TEMPLATE.read_text("utf-8")
        if not script:
            shell = re.sub(r"<script>\s*\{\{SCRIPT\}\}\s*</script>\n?", "", shell)
    # 一次替换全部占位符：正文里出现「{{STYLE}}」这类文字时不会被再次替换。
    return re.sub(r"\{\{(TITLE|STYLE|BODY|SCRIPT)\}\}", lambda m: values[m.group(0)], shell)


def build(content_path: Path, output: Path, fragment: bool = False) -> Path:
    content = json.loads(Path(content_path).read_text("utf-8"))
    markup = Builder(content, Path(content_path).parent).build(fragment=fragment)
    output = Path(output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(markup, "utf-8")
    return output


def main(argv: list[str]) -> int:
    fragment = "--fragment" in argv
    args = [a for a in argv if a != "--fragment"]
    if len(args) != 2:
        print("用法：python3 scripts/build_html.py 内容.json 输出.html [--fragment]", file=sys.stderr)
        return 2
    try:
        print(build(Path(args[0]), Path(args[1]), fragment=fragment))
    except (HtmlError, KeyError) as exc:
        print(f"生成失败：{exc}", file=sys.stderr)
        return 1
    return 0
