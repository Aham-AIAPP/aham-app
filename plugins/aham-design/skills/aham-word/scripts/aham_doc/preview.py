"""Word 内容的网页预览：同一份内容 JSON（格式见技能的 references/content-format.md）排成单文件 HTML。

预览与 Word 走同一套取值函数：章节编号用 outline，单元格文字、金额千分位、表格标记和泳道步骤用 word 模块的公开函数，
排版交给网页渲染器 html。用户确认的预览因此与交付的 Word 一致。

用法：python3 scripts/build_preview.py 内容.json 输出.html
"""

from __future__ import annotations

import sys
from pathlib import Path
from typing import Any

from . import html as H
from . import word as W
from .document import check_limits, load_content
from .outline import display_heading, flatten_numbered_chapters
from .paths import layout_rule

__all__ = ["build_preview", "main", "preview_content", "register_block"]

CALLOUT_TONES = {"risk": "risk", "key": "key", "rule": "key"}
CALLOUT_LABELS = {"risk": "风险提示", "key": "规则"}
STATUS_TO_TAG = {"solid": "solid", "outline": "outline", "dashed": "faint", "hot": "hot"}

BlockConverter = Any
_CONVERTERS: dict[str, BlockConverter] = {}


def register_block(kind: str, converter: BlockConverter) -> None:
    """登记一种 Word 内容块在预览里的写法：converter(block, base_dir) 返回网页内容块列表。"""
    _CONVERTERS[kind.lower()] = converter


def _split_heading(text: str) -> tuple[str, str]:
    """「3.1 标题」拆成编号和标题；没有编号时编号为空。"""
    head, _, tail = text.partition(" ")
    if tail and all(part.isdigit() for part in head.split(".")):
        return head, tail
    return "", text


def _marked(text: str, mark: tuple[str, Any] | None) -> Any:
    """表格标记（等级、状态、参与方）转成网页单元格写法，与 Word 的同一判据。"""
    if not mark or not str(text).strip():
        return text
    kind, option = mark
    if kind == "level":
        return {"level": "hot" if text.strip() in option else "normal", "text": text}
    if kind == "status":
        tags, default = option
        return {"tag": STATUS_TO_TAG[tags.get(text.strip(), default)], "text": text}
    if kind == "party" and W.party_color(text):
        return {"party": text, "text": text}
    return text


def _table(block: dict[str, Any]) -> dict[str, Any] | None:
    headers = [W.safe_text(value) for value in block.get("columns", block.get("headers", []))]
    if not headers:
        return None
    rows = W.normalized_table_rows(headers, list(block.get("rows", []) or []))
    money = [index for index, header in enumerate(headers) if any(m in header for m in W.MONEY_HEADER_MARKERS)]
    marks = W.table_marks(block, headers)
    cells = []
    for values in rows:
        shown = [W.display_money(v) if col in money else W.display_value(v) for col, v in enumerate(values)]
        cells.append([_marked(cell, marks["columns"].get(col)) for col, cell in enumerate(shown)])
    columns: list[Any] = [W.money_header(h) for h in headers]
    if marks["party_header"]:
        columns = [{"party": h, "text": h} if W.party_color(h) else h for h in columns]
    table = {"type": "table", "columns": columns, "rows": cells, "amount_cols": money, "row_header": False,
             "alignments": list(block.get("alignments") or [])}
    if block.get("caption"):
        table["caption"] = W.safe_text(block["caption"])
    return table


def _block(block: dict[str, Any], base_dir: Path) -> list[dict[str, Any]]:
    """一个 Word 内容块转成网页内容块。"""
    kind = W.safe_text(block.get("type", "paragraph")).lower()
    if kind in _CONVERTERS:
        return list(_CONVERTERS[kind](block, base_dir))
    if kind in {"paragraph", "text"}:
        return [{"type": "paragraph", "text": line} for line in W.safe_text(block.get("text", "")).split("\n") if line]
    if kind in {"lead", "callout"}:
        tone = CALLOUT_TONES.get(W.safe_text(block.get("tone", "")).lower(), "lead")
        label = block.get("label") or CALLOUT_LABELS.get(tone, "说明")
        return [{"type": "callout", "tone": tone, "label": W.safe_text(label), "text": W.safe_text(block.get("text", ""))}]
    if kind in {"bullets", "list"}:
        items = [W.safe_text(i.get("text", "") if isinstance(i, dict) else i) for i in block.get("items", [])]
        return [{"type": "list", "items": items, "ordered": bool(block.get("ordered"))}]
    if kind == "table":
        if block.get("layout") == "key_value":
            rows = [[W.display_value(c) for c in (r if isinstance(r, list) else [r.get("label"), r.get("value")])]
                    for r in block.get("rows") or []]
            out = {"type": "table", "layout": "key_value", "columns": ["项目", "内容"], "rows": rows}
            if block.get("caption"):
                out["caption"] = W.safe_text(block["caption"])
            return [out]
        table = _table(block)
        if table is None:
            return []
        out = [table]
        if block.get("note"):
            out.append({"type": "paragraph", "text": W.safe_text(block["note"]), "muted": True})
        return out
    if kind in {"figure", "image", "gallery", "svg"}:
        caption = W.safe_text(block.get("caption", "配图"))
        source = W.safe_text(block.get("source", ""))
        svg = block.get("svg") or (block.get("path") if kind == "svg" else None)
        if svg and (base_dir / svg).exists():
            return [{"type": "svg", "path": svg, "caption": caption, "source": source}]
        paths = [p for p in (block.get("paths") or [block.get("path")]) if p and (base_dir / p).exists()]
        if not paths:
            return [{"type": "callout", "tone": "lead", "label": "配图状态",
                     "text": "［待补充］未找到指定图片，正式交付前需补齐或移除该图。"}]
        if len(paths) == 1:
            return [{"type": "figure", "path": paths[0], "caption": caption, "source": source}]
        return [{"type": "figures", "items": [{"path": p, "caption": caption} for p in paths]}]
    if kind == "swimlane":
        names = dict(W.lane_names())
        steps = [[names[lane], role, text] for lane, role, text in W.swimlane_steps(block)]
        out = [{"type": "swimlane", "steps": steps, "caption": W.safe_text(block.get("caption"))}]
        if block.get("note"):
            out.append({"type": "paragraph", "text": W.safe_text(block["note"]), "muted": True})
        return out
    if kind == "quote":
        source = "｜".join(filter(None, (W.safe_text(block.get(k, "")) for k in ("speaker", "timestamp", "source_id"))))
        return [{"type": "quote", "text": W.safe_text(block.get("text", "")), "source": source}]
    if kind == "notes":
        items = [W.safe_text(v).strip() for v in block.get("items", []) if W.safe_text(v).strip()]
        return [{"type": "notes", "title": W.safe_text(block.get("title") or "说明"), "items": items}] if items else []
    if kind == "subheading":
        number, title = _split_heading(display_heading(block))
        level = int(block.get("_resolved_level") or block.get("level", 2))
        return [{"type": "heading", "level": 2 if level <= 2 else 3, "title": title, "number": number}]
    if kind in {"page_break", "spacer"}:
        return []
    return [{"type": "paragraph", "text": f"［待补充］未识别的内容块类型：{kind}"}]


def preview_content(content: dict[str, Any], base_dir: Path) -> dict[str, Any]:
    """Word 内容转成网页渲染器的内容。"""
    meta = dict(content.get("meta") or {})
    W.set_numeric_facts(W.numeric_fact_values(content))
    W.configure_parties(content)
    title = W.safe_text(meta.get("title"))
    if layout_rule("cover_title").get("main") == "project_name" and meta.get("project_name"):
        title = W.safe_text(meta["project_name"]) + title
    items = [{"label": label, "value": W.safe_text(meta.get(key))}
             for label, key in (("客户", "customer_name"), ("项目", "project_name"), ("版本", "version"), ("日期", "date"))
             if meta.get(key) and not (key == "project_name" and W.safe_text(meta[key]) in title)]
    if meta.get("show_workflow_status"):
        items.append({"label": "状态", "value": W.safe_text(meta.get("status_text", "草稿"))})
    chapters: list[dict[str, Any]] = []
    for chapter, level in flatten_numbered_chapters(content.get("chapters", [])):
        number, heading = _split_heading(display_heading(chapter))
        blocks: list[dict[str, Any]] = []
        if chapter.get("summary"):
            if layout_rule("section_summary").get("style") == "subtitle":
                blocks.append({"type": "paragraph", "text": W.safe_text(chapter["summary"]), "muted": True})
            else:
                blocks.append({"type": "callout", "tone": "lead", "label": W.safe_text(chapter.get("summary_label", "本章要点")),
                               "text": W.safe_text(chapter["summary"])})
        for block in chapter.get("blocks", []):
            if isinstance(block, dict):
                blocks += _block(block, base_dir)
        if level == 1 or not chapters:
            chapters.append({"title": heading, "number": number, "blocks": blocks})
        else:
            chapters[-1]["blocks"].append({"type": "heading", "level": 2 if level == 2 else 3, "title": heading, "number": number})
            chapters[-1]["blocks"] += blocks
    intro = content.get("intro")
    if isinstance(intro, dict) and intro.get("text"):
        lead = {"type": "callout", "tone": "lead", "label": W.safe_text(intro.get("label", "文档用途")),
                "text": W.safe_text(intro["text"])}
        if chapters:
            chapters[0]["blocks"].insert(0, lead)
        else:
            chapters.append({"title": "", "number": "", "blocks": [lead]})
    if content.get("closing_note") and chapters:
        chapters[-1]["blocks"].append({"type": "callout", "tone": "lead", "label": W.safe_text(content.get("closing_label", "说明")),
                                       "text": W.safe_text(content["closing_note"])})
    parties = []
    for item in content.get("parties") or []:
        entry = item if isinstance(item, dict) else {"name": item}
        parties.append({"name": W.safe_text(entry["name"]), "aliases": [W.safe_text(a) for a in entry.get("aliases") or []],
                        **({"lane": False} if entry.get("lane") is False else {})})
    with_toc = bool(content.get("toc", len(content.get("chapters") or []) >= 4))
    return {
        "meta": {"customer": W.safe_text(meta.get("customer_name")), "title": title, "lede": W.safe_text(meta.get("lede")),
                 "items": items, "version": W.safe_text(meta.get("version", "V1.0")), "date": W.safe_text(meta.get("date")),
                 "bar_subtitle": W.safe_text(meta.get("customer_name") or meta.get("version", "V1.0"))},
        "keys": [{"label": W.safe_text(k.get("label")), "value": W.safe_text(k.get("value"))}
                 for k in meta.get("key_figures") or [] if isinstance(k, dict)],
        "parties": parties,
        "toc": with_toc,
        "chapters": chapters,
    }


def build_preview(content: dict[str, Any], base_dir: Path, *, script: bool = False) -> str:
    """Word 内容排成一页网页预览。缺省不嵌交互脚本，作只读确认用。"""
    if not str((content.get("meta") or {}).get("title") or "").strip():
        raise H.HtmlError("meta.title 必填：文档类型或文档名")
    check_limits(content)
    page_content = preview_content(content, Path(base_dir))
    return H.page(page_content["meta"]["title"] + " 预览", H.Builder(page_content, Path(base_dir)).body(), script=script)


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print(__doc__, file=sys.stderr)
        return 2
    source, target = Path(argv[0]), Path(argv[1])
    try:
        markup = build_preview(load_content(source), source.parent)
    except (H.HtmlError, ValueError, KeyError) as exc:
        print(f"生成失败：{exc}", file=sys.stderr)
        return 1
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(markup, "utf-8")
    print(target)
    return 0
