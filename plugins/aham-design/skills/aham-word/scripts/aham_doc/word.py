"""Word 渲染器：样式、封面、页眉页脚、目录、文首和各类内容块。

颜色、字号和线宽读插件根的 tokens.json（经 tokens.document_style 生成的文档取值视图）；
版面规则读技能的 config/layout-rules.json，生成时直接执行。
通用的整份文档组装见 document 模块；业务专有的内容块和表格规则经本模块的扩展点登记。
"""

from __future__ import annotations

import hashlib
import json
import math
import re
import sys
import tempfile
import zipfile
from xml.etree import ElementTree as ET
from dataclasses import dataclass
from datetime import date
from pathlib import Path
from typing import Any, Callable, Iterable

from lxml import etree

from docx import Document
from docx.enum.section import WD_ORIENT, WD_SECTION
from docx.enum.style import WD_STYLE_TYPE
from docx.enum.table import WD_ALIGN_VERTICAL, WD_TABLE_ALIGNMENT
from docx.enum.text import WD_ALIGN_PARAGRAPH, WD_BREAK, WD_TAB_ALIGNMENT, WD_TAB_LEADER
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.shared import Cm, Pt, RGBColor

from .brand import current_brand
from .docx_ooxml import set_property_child
from .docx_typography import resolve_render_typography, style as load_style_tokens
from .docx_widths import CELL_PAD, REGULAR_CELL_PAD, auto_widths
from .notes import note_ordinal_prefix, split_note_label
from .outline import display_heading, outline_entries
from .paths import layout_rule
from .text import cjk_punct


# 公开接口。技能脚本只用这里列出的名字；其余以下划线开头的函数是引擎内部实现，随时可能改。
__all__ = [
    # 样式配置
    "configure_typography", "configure_render_typography", "TYPOGRAPHY", "STYLE",
    "FONT_HEADING", "FONT_BODY", "FONT_TABLE", "FONT_LATIN",
    "INK", "MUTED", "FAINT", "ACCENT", "LINE", "TINT", "WHITE", "HOT", "RULE", "WORD_PT",
    # 扩展点
    "TableHooks", "TableRowContext", "prepare_table_cell", "table_row_bottom", "set_cell_fill", "register_block", "register_table_hooks", "set_svg_rasterizer", "set_svg_styler",
    # 文字与取值
    "numeric_fact_values", "set_numeric_facts", "safe_text", "display_value", "display_money",
    "MONEY_HEADER_MARKERS", "money_header", "normalized_table_rows",
    # 参与方、泳道与表格标记
    "configure_parties", "party_color", "lane_names", "swimlane_steps", "table_marks",
    # 文档与章节
    "new_document", "normalize_orientation", "section_orientation", "start_section",
    "add_cover", "add_header_footer", "add_toc", "add_inner_title",
    # 内容块
    "render_block", "add_heading", "add_body", "add_lead", "add_chapter_summary", "add_list", "add_table",
    # 低层排版函数，供技能自己的内容块使用
    "set_run_font", "clear_indent", "set_table_geometry", "set_keep_together",
    "set_cell_margins", "set_cell_width_cm", "set_cell_borders", "add_named_bookmark",
    # 保存后处理
    "normalize_formal_numbering",
]

STYLE = load_style_tokens()


# 以下取值都由 _apply_style 按样式文件设置，这里只声明名字和类型。
FONT_HEADING: str
FONT_BODY: str
FONT_TABLE: str
FONT_LATIN: str
WORD_PARAGRAPH: dict[str, float]
WORD_LAYOUT: dict[str, Any]
TYPOGRAPHY: dict[str, Any]
INK: str
MUTED: str
FAINT: str
ACCENT: str
LINE: str
TINT: str
WHITE: str
HOT: str
RULE: dict[str, Any]
WORD_PT: dict[str, Any]
PORTRAIT_BODY_CM: float
LANDSCAPE_BODY_CM: float


def _apply_style(style: dict[str, Any], roles: dict[str, str], word_layout: dict[str, Any],
                 style_version: str) -> None:
    """按样式取值设置本模块的字体、颜色、线宽和字号。取值只在这里读一次。"""
    global STYLE, FONT_HEADING, FONT_BODY, FONT_TABLE, FONT_LATIN, WORD_PARAGRAPH
    global WORD_LAYOUT, TYPOGRAPHY
    global INK, MUTED, FAINT, ACCENT, LINE, TINT, WHITE, HOT, RULE
    global WORD_PT, PORTRAIT_BODY_CM, LANDSCAPE_BODY_CM
    STYLE = dict(style)
    FONT_HEADING = roles["heading"]
    FONT_BODY = roles["body"]
    FONT_TABLE = roles["table"]
    FONT_LATIN = roles["latin"]
    WORD_LAYOUT = dict(word_layout)
    spacing = dict(WORD_LAYOUT["line_spacing"])
    WORD_PARAGRAPH = {
        "body_line_pt": float(spacing["body_pt"]),
        "list_line_pt": float(spacing["list_pt"]),
        "table_line_pt": float(spacing["table_pt"]),
        "body_space_after_pt": float(spacing["body_space_after_pt"]),
    }
    TYPOGRAPHY = {"style_version": style_version, "font_roles": dict(roles)}
    # 颜色、线宽和字号取自 tokens.json 的文档取值视图。用法见 references/word-spec.md。
    INK = STYLE["colors"]["ink"]
    MUTED = STYLE["colors"]["muted"]
    FAINT = STYLE["colors"]["faint"]
    ACCENT = STYLE["colors"]["accent"]
    LINE = STYLE["colors"]["line"]
    TINT = STYLE["colors"]["tint"]
    WHITE = STYLE["colors"]["white"]
    HOT = STYLE["colors"]["hot"]
    RULE = STYLE["rules"]["word_eighth_pt"]
    WORD_PT = STYLE["word_pt"]
    PORTRAIT_BODY_CM = STYLE["page"]["portrait_body_mm"] / 10
    LANDSCAPE_BODY_CM = STYLE["page"]["landscape_body_mm"] / 10


def _lw(dotted: str) -> float:
    """按点分路径取 layout.word 下的一个版式数值，例如 _lw("cover.logo_width_cm")。缺键时报错，不退回写死的值。"""
    node: Any = WORD_LAYOUT
    for part in dotted.split("."):
        if not isinstance(node, dict) or part not in node:
            raise ValueError(f"tokens.json 缺少版式取值：layout.word.{dotted}")
        node = node[part]
    return float(node)


def _twips(points: float) -> int:
    """磅换成 OOXML 的 dxa（1/20 磅）。"""
    return round(float(points) * 20)


def _page_cm(key: str) -> float:
    """layout.page 下以 mm 为单位的取值换成 cm。"""
    return float(STYLE["page"][key]) / 10


_apply_style(STYLE, STYLE["fonts"], STYLE["word"], STYLE["version"])


def configure_typography() -> None:
    """Re-read the single style file (unit-level and diagnostic builder use)."""
    configure_render_typography(resolve_render_typography({}))


def configure_render_typography(resolved: dict[str, Any]) -> None:
    """Configure the renderer from a verified Render Contract typography view."""
    style = dict(resolved["style"])
    word_layout = dict(resolved.get("word_layout") or style["word"])
    capacity = word_layout.get("table_capacity") if isinstance(word_layout.get("table_capacity"), dict) else {}
    if capacity and float(style["word_pt"]["table"]) < float(capacity["min_font_pt"]):
        raise ValueError("Word 表格字号低于样式令牌最小可读字号")
    _apply_style(style, dict(resolved["font_roles"]), word_layout, resolved["style_version"])


# ---------- 扩展点 ----------
# 引擎只认识通用内容块。技能自己的内容块、表格列宽规则和隐藏书签经这里登记，
# 引擎不 import 任何技能脚本。登记按名称覆盖，重复登记不叠加。

@dataclass(frozen=True)
class TableRowContext:
    """render_row 扩展点收到的一行：表格、表头、列宽、密度、行号、本行取值、原始行、是否末行。"""
    doc: Any
    table: Any
    row: Any
    headers: list[str]
    widths: list[float]
    density: str
    index: int
    values: list[Any]
    source: Any
    is_last: bool


@dataclass(frozen=True)
class TableHooks:
    """表格扩展。

    - adjust_widths(表头, 列宽)：原地改列宽。
    - render_row(上下文)：接管一行的写法，返回已写单元格 [(单元格, 取值, 列号)]；返回 None 时按普通行写。
    - after_row(表头, 已写单元格, 原始行)：每行写完后调用。
    - after_table(表格, 表头, 原始行列表, 密度)：全部行写完、整表同页规则执行前调用，用于合并单元格等整表处理。
    """
    adjust_widths: Callable[[list[str], list[float]], None] | None = None
    after_row: Callable[[list[str], list[tuple[Any, Any, int]], Any], None] | None = None
    render_row: Callable[[TableRowContext], list[tuple[Any, Any, int]] | None] | None = None
    after_table: Callable[[Any, list[str], list[Any], str], None] | None = None


BlockRenderer = Callable[[Document, dict[str, Any], Path, str], None]
_BLOCK_RENDERERS: dict[str, BlockRenderer] = {}
_TABLE_HOOKS: dict[str, TableHooks] = {}
_SVG_RASTERIZER: Callable[[Path, Path], Path | None] | None = None
_SVG_STYLER: Callable[[str, dict[str, Any]], str] | None = None


def register_block(kind: str, renderer: BlockRenderer) -> None:
    """登记一种内容块的渲染函数：renderer(doc, block, base_dir, previous_kind)。通用块类型不能被覆盖。"""
    _BLOCK_RENDERERS[kind.lower()] = renderer


def register_table_hooks(name: str, hooks: TableHooks) -> None:
    _TABLE_HOOKS[name] = hooks


def set_svg_rasterizer(rasterizer: Callable[[Path, Path], Path | None] | None) -> None:
    """传入 SVG 转 PNG 的函数：rasterizer(源 SVG, 目标 PNG)，失败时返回 None。"""
    global _SVG_RASTERIZER
    _SVG_RASTERIZER = rasterizer


def set_svg_styler(styler: Callable[[str, dict[str, Any]], str] | None) -> None:
    """传入 SVG 预处理函数：styler(SVG 文字, 文档取值视图) 返回自带样式的 SVG 文字。

    没有传入时，引擎按原样嵌入 SVG，要求 SVG 自己写好颜色和字体。
    """
    global _SVG_STYLER
    _SVG_STYLER = styler


# 一个数字只声明一次，正文和表格都引用同一处：\u007b\u007bfact:line_count\u007d\u007d。
# 手抄的数字会各自漂移——架构图写 ×22、正文写 25 这种错能活过整个版本，就是因为
# 同一个事实在文档里存在多份互不相干的副本。
NUMERIC_FACT_REFERENCE = re.compile(r"\{\{\s*fact:([A-Za-z0-9_.\-]+)\s*\}\}")
_NUMERIC_FACTS: dict[str, str] = {}


def numeric_fact_values(spec: dict[str, Any]) -> dict[str, str]:
    """Project ``numeric_facts`` declarations into their rendered strings."""

    result: dict[str, str] = {}
    for fact in spec.get("numeric_facts") or []:
        if not isinstance(fact, dict):
            continue
        identifier = str(fact.get("id") or "").strip()
        if not identifier:
            continue
        value = fact.get("value")
        if isinstance(value, float) and value.is_integer():
            text = str(int(value))
        else:
            text = str(value if value is not None else "")
        unit = str(fact.get("unit") or "")
        result[identifier] = f"{text}{unit}" if fact.get("inline_unit") else text
    return result


def set_numeric_facts(values: dict[str, str]) -> None:
    """设置本次渲染用的数字事实（numeric_fact_values 的结果）。"""
    global _NUMERIC_FACTS
    _NUMERIC_FACTS = dict(values)


def _resolve_numeric_facts(text: str) -> str:
    if "{{" not in text:
        return text
    return NUMERIC_FACT_REFERENCE.sub(
        lambda match: _NUMERIC_FACTS.get(match.group(1), match.group(0)), text
    )


def safe_text(value: Any) -> str:
    if value is None:
        return ""
    text = str(value).replace("\r\n", "\n").replace("\r", "\n")
    text = _resolve_numeric_facts(text)
    text = re.sub(r"[\u0000-\u0008\u000B\u000C\u000E-\u001F]", "", text)
    # 版面规则 cjk_punctuation（GB/T 15834-2011）：中文语境的半角标点在渲染时转全角。
    return cjk_punct(text) if _CJK_PUNCT else text


_CJK_PUNCT = bool(layout_rule("cjk_punctuation").get("normalize_halfwidth_in_cjk"))


def display_value(value: Any) -> str:
    """Use a cached/display value in Word; never expose an Excel formula object."""
    if isinstance(value, dict):
        for key in ("display", "display_value", "value", "cached_value", "result"):
            if key in value and value[key] is not None:
                return safe_text(value[key])
        return ""
    return safe_text(value)


MONEY_HEADER_MARKERS = ("金额", "单价", "总价", "税额")


def display_money(value: Any) -> str:
    """Render a monetary projection with thousands separators and two decimals.

    Only the visible text changes; callers that reconcile amounts strip the
    separators before comparing.
    """
    text = display_value(value)
    stripped = text.strip().replace(",", "").replace("，", "")
    if not re.fullmatch(r"-?\d+(?:\.\d+)?", stripped):
        return text
    try:
        number = float(stripped)
    except ValueError:
        return text
    return f"{number:,.2f}"


def _write_two_route_fonts(rpr, family: str) -> None:
    """Write the four ``w:rFonts`` slots on two routes and drop theme fonts.

    ``w:eastAsia`` carries the Chinese family; ``w:ascii``/``w:hAnsi``/``w:cs``
    carry the Latin family so digits, English and abbreviations render in
    the configured Latin family; since 6.0 that is 微软雅黑, the same as Chinese.
    """
    rfonts = rpr.find(qn("w:rFonts"))
    if rfonts is None:
        rfonts = OxmlElement("w:rFonts")
    for attr in ("asciiTheme", "hAnsiTheme", "eastAsiaTheme", "cstheme", "hint"):
        rfonts.attrib.pop(qn(f"w:{attr}"), None)
    rfonts.set(qn("w:eastAsia"), family)
    for attr in ("ascii", "hAnsi", "cs"):
        rfonts.set(qn(f"w:{attr}"), FONT_LATIN)
    set_property_child(rpr, rfonts)


def _write_run_language(rpr) -> None:
    """``en-US`` for the Latin route so ``1,200,000`` never breaks after a comma."""
    lang = rpr.find(qn("w:lang"))
    if lang is None:
        lang = OxmlElement("w:lang")
    lang.set(qn("w:val"), "en-US")
    lang.set(qn("w:eastAsia"), "zh-CN")
    lang.attrib.pop(qn("w:bidi"), None)
    set_property_child(rpr, lang)


def set_run_font(run, family: str, size: float, *, bold: bool = False,
                  color: str = INK, italic: bool = False) -> None:
    """Set all Word font slots explicitly (two routes) and remove theme fallbacks."""
    run.font.name = family
    run.font.size = Pt(size)
    run.font.bold = bold
    run.font.italic = italic
    run.font.color.rgb = RGBColor.from_string(color)
    rpr = run._element.get_or_add_rPr()
    _write_two_route_fonts(rpr, family)
    _write_run_language(rpr)


def _set_style_font(style, family: str, size: float, *, bold: bool = False,
                    color: str = INK) -> None:
    style.font.name = family
    style.font.size = Pt(size)
    style.font.bold = bold
    style.font.color.rgb = RGBColor.from_string(color)
    rpr = style.element.get_or_add_rPr()
    _write_two_route_fonts(rpr, family)
    _write_run_language(rpr)


def _set_doc_defaults_font(doc: Document) -> None:
    """Write the two-route fonts into ``w:docDefaults`` so inherited runs match."""
    styles_element = doc.styles.element
    defaults = styles_element.find(qn("w:docDefaults"))
    if defaults is None:
        defaults = OxmlElement("w:docDefaults")
        styles_element.insert(0, defaults)
    rpr_default = defaults.find(qn("w:rPrDefault"))
    if rpr_default is None:
        rpr_default = OxmlElement("w:rPrDefault")
        defaults.insert(0, rpr_default)
    rpr = rpr_default.find(qn("w:rPr"))
    if rpr is None:
        rpr = OxmlElement("w:rPr")
        rpr_default.append(rpr)
    _write_two_route_fonts(rpr, FONT_BODY)
    _write_run_language(rpr)


def _set_first_line_chars(target, value: int) -> None:
    """Write the first-line indent on both OOXML routes.

    ``w:firstLineChars`` is the CJK-correct unit (2 characters, whatever the
    font size), but LibreOffice — which renders the PDF — ignores it when no
    absolute ``w:firstLine`` accompanies it, so the same paragraph came out
    indented in Word and flush in the PDF.  Writing both keeps the two hosts
    identical; Word prefers the character route, LibreOffice the twip one.
    """
    if hasattr(target, "_p"):
        ppr = target._p.get_or_add_pPr()
    else:
        ppr = target.element.get_or_add_pPr()
    ind = ppr.find(qn("w:ind"))
    if ind is None:
        ind = OxmlElement("w:ind")
    for attr in ("hanging", "hangingChars"):
        ind.attrib.pop(qn(f"w:{attr}"), None)
    twips = round(float(value) / 100.0 * float(WORD_PT["body"]) * 20)
    ind.set(qn("w:firstLine"), str(twips))
    ind.set(qn("w:firstLineChars"), str(value))
    set_property_child(ppr, ind)


def _set_line_spacing_at_least(target, points: float) -> None:
    """Use explicit at-least line spacing to avoid host font-metric clipping."""
    element = target._p if hasattr(target, "_p") else target.element
    ppr = element.get_or_add_pPr()
    spacing = ppr.find(qn("w:spacing"))
    if spacing is None:
        spacing = OxmlElement("w:spacing")
    spacing.set(qn("w:line"), str(round(float(points) * 20)))
    spacing.set(qn("w:lineRule"), "atLeast")
    set_property_child(ppr, spacing)


def clear_indent(paragraph) -> None:
    ppr = paragraph._p.get_or_add_pPr()
    ind = ppr.find(qn("w:ind"))
    if ind is None:
        ind = OxmlElement("w:ind")
    for attr in ("firstLineChars", "firstLine", "hanging", "hangingChars"):
        ind.attrib.pop(qn(f"w:{attr}"), None)
    ind.set(qn("w:left"), "0")
    ind.set(qn("w:firstLine"), "0")
    ind.set(qn("w:firstLineChars"), "0")
    set_property_child(ppr, ind)


def _paragraph_border(paragraph, *, side: str, color: str, size: int,
                      space: int = 4) -> None:
    ppr = paragraph._p.get_or_add_pPr()
    pbdr = ppr.find(qn("w:pBdr"))
    if pbdr is None:
        pbdr = OxmlElement("w:pBdr")
        set_property_child(ppr, pbdr)
    old = pbdr.find(qn(f"w:{side}"))
    if old is not None:
        pbdr.remove(old)
    border = OxmlElement(f"w:{side}")
    border.set(qn("w:val"), "single")
    border.set(qn("w:sz"), str(size))
    border.set(qn("w:space"), str(round(float(space))))  # OOXML 的 w:space 是整磅
    border.set(qn("w:color"), color)
    pbdr.append(border)


def _style_paragraph_border(style, *, side: str, color: str, size: int, space: int = 4) -> None:
    ppr = style.element.get_or_add_pPr()
    pbdr = ppr.find(qn("w:pBdr"))
    if pbdr is None:
        pbdr = OxmlElement("w:pBdr")
        set_property_child(ppr, pbdr)
    old = pbdr.find(qn(f"w:{side}"))
    if old is not None:
        pbdr.remove(old)
    border = OxmlElement(f"w:{side}")
    border.set(qn("w:val"), "single")
    border.set(qn("w:sz"), str(size))
    border.set(qn("w:space"), str(round(float(space))))  # OOXML 的 w:space 是整磅
    border.set(qn("w:color"), color)
    pbdr.append(border)


def _field(paragraph, instruction: str, display: str = "", size: float | None = None) -> None:
    begin_run = OxmlElement("w:r")
    begin = OxmlElement("w:fldChar")
    begin.set(qn("w:fldCharType"), "begin")
    begin.set(qn("w:dirty"), "true")
    begin_run.append(begin)
    paragraph._p.append(begin_run)

    instr_run = OxmlElement("w:r")
    instr = OxmlElement("w:instrText")
    instr.set(qn("xml:space"), "preserve")
    instr.text = f" {instruction} "
    instr_run.append(instr)
    paragraph._p.append(instr_run)

    separate_run = OxmlElement("w:r")
    separate = OxmlElement("w:fldChar")
    separate.set(qn("w:fldCharType"), "separate")
    separate_run.append(separate)
    paragraph._p.append(separate_run)

    if display:
        display_run = paragraph.add_run(display)
        # 域的显示 run 必须跟随调用处的字号。写死正文 10.5pt 时，页脚的
        # 「第 3 页」里数字比前后的「第」「页」大 2pt，肉眼看像换了字体。
        set_run_font(
            display_run, FONT_BODY,
            WORD_PT["body"] if size is None else size, color=MUTED,
        )

    end_run = OxmlElement("w:r")
    end = OxmlElement("w:fldChar")
    end.set(qn("w:fldCharType"), "end")
    end_run.append(end)
    paragraph._p.append(end_run)


def _configure_word_open_safety(doc: Document) -> None:
    """Use modern Word mode without automatic field-update prompts."""

    settings = doc.settings.element
    node = settings.find(qn("w:updateFields"))
    if node is not None:
        settings.remove(node)
    compat = settings.find(qn("w:compat"))
    if compat is None:
        compat = OxmlElement("w:compat")
        settings.append(compat)
    for existing in list(compat.findall(qn("w:compatSetting"))):
        if existing.get(qn("w:name")) == "compatibilityMode":
            compat.remove(existing)
    mode = OxmlElement("w:compatSetting")
    mode.set(qn("w:name"), "compatibilityMode")
    mode.set(qn("w:uri"), "http://schemas.microsoft.com/office/word")
    mode.set(qn("w:val"), "15")
    compat.append(mode)


def set_cell_fill(cell, color: str | None) -> None:
    tcpr = cell._tc.get_or_add_tcPr()
    old = tcpr.find(qn("w:shd"))
    if old is not None:
        tcpr.remove(old)
    if color:
        shd = OxmlElement("w:shd")
        shd.set(qn("w:val"), "clear")
        shd.set(qn("w:fill"), color)
        set_property_child(tcpr, shd)


def set_cell_margins(cell, top: int | None = None, start: int | None = None,
                      bottom: int | None = None, end: int | None = None) -> None:
    """写单元格四边内边距，单位 dxa（1/20 磅）。没写的边取 layout.word.table.default_cell。"""
    vertical = _twips(_lw("table.default_cell.vertical_pt"))
    side = _twips(_lw("table.default_cell.side_pt"))
    top = vertical if top is None else top
    bottom = vertical if bottom is None else bottom
    start = side if start is None else start
    end = side if end is None else end
    tcpr = cell._tc.get_or_add_tcPr()
    old = tcpr.find(qn("w:tcMar"))
    if old is not None:
        tcpr.remove(old)
    margins = OxmlElement("w:tcMar")
    for side, width in (("top", top), ("start", start), ("bottom", bottom), ("end", end)):
        node = OxmlElement(f"w:{side}")
        node.set(qn("w:w"), str(width))
        node.set(qn("w:type"), "dxa")
        margins.append(node)
    set_property_child(tcpr, margins)


def _set_cell_edge_margins(cell, index: int, count: int, *, last_index: int | None = None) -> None:
    """三线表首列不留左内边距、末列不留右内边距，文字与正文左右边线齐平。"""
    last = index if last_index is None else last_index
    if index != 0 and last != count - 1:
        return
    tcpr = cell._tc.get_or_add_tcPr()
    margins = tcpr.find(qn("w:tcMar"))
    if margins is None:
        set_cell_margins(cell)
        margins = tcpr.find(qn("w:tcMar"))
    for side, applies in (("start", index == 0), ("end", last == count - 1)):
        if applies:
            node = margins.find(qn(f"w:{side}"))
            node.set(qn("w:w"), "0")


def _set_cell_no_wrap(cell) -> None:
    tcpr = cell._tc.get_or_add_tcPr()
    if tcpr.find(qn("w:noWrap")) is None:
        set_property_child(tcpr, OxmlElement("w:noWrap"))


# 表格密度：常规版和紧凑版的内边距与行距取自 word.table。
TABLE_DENSITIES = ("regular", "compact")


def _table_density(block: dict[str, Any]) -> str:
    value = safe_text(block.get("density") or "regular").lower()
    if value not in TABLE_DENSITIES:
        raise ValueError(f"表格 density 只能写 regular 或 compact，收到 {value}")
    return value


def _table_geometry(density: str) -> dict[str, float]:
    return {
        "vertical": _twips(_lw(f"table.{density}.cell_vertical_pt")),
        "side": _twips(_lw(f"table.{density}.cell_side_pt")),
        "line_pt": _lw(f"table.{density}.line_pt"),
    }


def _table_v_align():
    table = WORD_LAYOUT.get("table") or {}
    return WD_ALIGN_VERTICAL.TOP if table.get("v_align", "top") == "top" else WD_ALIGN_VERTICAL.CENTER


def _set_table_cell_margins(cell, density: str) -> None:
    geometry = _table_geometry(density)
    set_cell_margins(
        cell, top=geometry["vertical"], start=geometry["side"],
        bottom=geometry["vertical"], end=geometry["side"],
    )


def _table_style_name(base: str, density: str) -> str:
    return f"{base} Compact" if density == "compact" else base


# 参与方圆点、等级短横线这类装饰字符用品牌配置里的标记字符样式（mark_style），
# 比对表格文字时可以跳过这个样式。
STATUS_TAG_KINDS = ("solid", "outline", "dashed", "hot")
_PARTIES: dict[str, int] = {}
_NO_LANE: set[int] = set()


def configure_parties(spec: dict[str, Any]) -> None:
    """登记参与方：名称和别名对应 party_1 至 party_4。"""
    _PARTIES.clear()
    _NO_LANE.clear()
    raw = spec.get("parties") or []
    if not isinstance(raw, list):
        raise ValueError("parties 必须是数组")
    if len(raw) > 4:
        raise ValueError(f"parties 最多 4 个，收到 {len(raw)} 个")
    for index, item in enumerate(raw, start=1):
        entry = item if isinstance(item, dict) else {"name": item}
        name = safe_text(entry.get("name")).strip()
        if not name:
            raise ValueError(f"parties 第 {index} 项缺少 name")
        if entry.get("lane") is False:
            _NO_LANE.add(index)
        for alias in [name, *[safe_text(a).strip() for a in entry.get("aliases") or []]]:
            if alias:
                _PARTIES[alias] = index


def party_color(text: str) -> str | None:
    index = _PARTIES.get(safe_text(text).strip())
    return STYLE["categorical"][f"party_{index}"] if index else None


def _add_mark_run(paragraph, text: str, color: str, *, size: float | None = None,
                  bold: bool = False):
    run = paragraph.add_run(text)
    run.style = paragraph.part.document.styles[current_brand().mark_style]
    set_run_font(run, FONT_TABLE, size or WORD_PT["table"], bold=bold, color=color)
    return run


def _add_party_dot(paragraph, text: str, *, size: float | None = None) -> bool:
    color = party_color(text)
    if not color:
        return False
    _add_mark_run(paragraph, "●\u00a0", color, size=size)
    return True


def _set_run_border(run, color: str, *, dashed: bool = False) -> None:
    rpr = run._element.get_or_add_rPr()
    node = OxmlElement("w:bdr")
    node.set(qn("w:val"), "dashed" if dashed else "single")
    node.set(qn("w:sz"), "4")
    node.set(qn("w:space"), "0")
    node.set(qn("w:color"), color)
    set_property_child(rpr, node)


def _set_run_shading(run, fill: str) -> None:
    rpr = run._element.get_or_add_rPr()
    node = OxmlElement("w:shd")
    node.set(qn("w:val"), "clear")
    node.set(qn("w:color"), "auto")
    node.set(qn("w:fill"), fill)
    set_property_child(rpr, node)


def _add_status_tag(paragraph, text: str, kind: str, *, size: float | None = None):
    """状态标签：字符边框或字符底纹，两侧各一个不换行空格。"""
    if kind not in STATUS_TAG_KINDS:
        raise ValueError(f"状态标签类型只能是 {'、'.join(STATUS_TAG_KINDS)}，收到 {kind}")
    run = paragraph.add_run(f"\u00a0{text}\u00a0")
    color = {"solid": WHITE, "outline": INK, "dashed": FAINT, "hot": HOT}[kind]
    set_run_font(run, FONT_TABLE, size or WORD_PT["table"], color=color)
    if kind == "solid":
        _set_run_shading(run, INK)
    else:
        _set_run_border(run, HOT if kind == "hot" else LINE, dashed=kind == "dashed")
    return run


def _add_level(paragraph, text: str, hot: bool, *, size: float | None = None) -> None:
    """等级短横线。"""
    color = HOT if hot else MUTED
    _add_mark_run(paragraph, "—\u00a0", color, size=size)
    run = paragraph.add_run(text)
    set_run_font(run, FONT_TABLE, size or WORD_PT["table"], bold=hot, color=color)


def table_marks(block: dict[str, Any], headers: list[str]) -> dict[str, Any]:
    """读取表格的 marks 声明：等级列、状态列、参与方列。单元格仍是纯文字。"""
    raw = block.get("marks") or {}
    if not isinstance(raw, dict):
        raise ValueError("表格 marks 必须是对象")
    unknown = set(raw) - {"level", "status", "party", "party_header"}
    if unknown:
        raise ValueError(f"表格 marks 不支持的键：{'、'.join(sorted(unknown))}")
    columns: dict[int, tuple[str, Any]] = {}

    def column_index(name: str, key: str) -> int:
        if name not in headers:
            raise ValueError(f"表格 marks.{key} 指向的列「{name}」不在表头里")
        return headers.index(name)

    level = raw.get("level")
    if level:
        spec = level if isinstance(level, dict) else {"column": level}
        hot = set(spec.get("hot") or ["重点"])
        columns[column_index(safe_text(spec.get("column")), "level")] = ("level", hot)
    status = raw.get("status")
    if status:
        spec = status if isinstance(status, dict) else {"column": status}
        tags = dict(spec.get("tags") or {})
        for value in tags.values():
            if value not in STATUS_TAG_KINDS:
                raise ValueError(f"marks.status.tags 的类型只能是 {'、'.join(STATUS_TAG_KINDS)}")
        default = spec.get("default", "outline")
        columns[column_index(safe_text(spec.get("column")), "status")] = ("status", (tags, default))
    for name in raw.get("party") or []:
        columns[column_index(safe_text(name), "party")] = ("party", None)
    if (raw.get("party") or raw.get("party_header")) and not _PARTIES:
        raise ValueError("表格声明了参与方圆点，文档没有登记 parties")
    return {"columns": columns, "party_header": bool(raw.get("party_header"))}


def _decorated_headers(headers: list[str], marks: dict[str, Any]) -> list[str]:
    """列宽估算用：把圆点算进表头宽度。"""
    if not marks["party_header"]:
        return headers
    return [f"●\u00a0{h}" if party_color(h) else h for h in headers]


def _decorated_rows(rows: list[list[Any]], marks: dict[str, Any]) -> list[list[Any]]:
    """列宽估算用：把短横线、圆点和标签两侧的空格算进内容宽度。"""
    if not marks["columns"]:
        return rows
    prefix = {"level": "—\u00a0", "party": "●\u00a0", "status": "\u00a0"}
    suffix = {"status": "\u00a0"}
    result = []
    for row in rows:
        new = list(row)
        for index, (kind, _) in marks["columns"].items():
            if index < len(new) and display_value(new[index]).strip():
                new[index] = prefix[kind] + display_value(new[index]) + suffix.get(kind, "")
        result.append(new)
    return result


def _write_marked_cell(paragraph, text: str, mark: tuple[str, Any]) -> bool:
    """按 marks 写单元格；写了返回 True。空值和未登记的参与方按普通文字写。"""
    kind, option = mark
    if not text.strip():
        return False
    if kind == "level":
        _add_level(paragraph, text, text.strip() in option)
        return True
    if kind == "status":
        tags, default = option
        _add_status_tag(paragraph, text, tags.get(text.strip(), default))
        return True
    if kind == "party" and party_color(text):
        _add_party_dot(paragraph, text)
        paragraph.add_run(text)
        return True
    return False


def set_cell_width_cm(cell, width_cm: float) -> None:
    tcw = cell._tc.get_or_add_tcPr().find(qn("w:tcW"))
    if tcw is None:
        tcw = OxmlElement("w:tcW")
    tcw.set(qn("w:w"), str(round(width_cm / 2.54 * 1440)))
    tcw.set(qn("w:type"), "dxa")
    set_property_child(cell._tc.get_or_add_tcPr(), tcw)


def set_cell_borders(cell, *, top=None, bottom=None, start=None, end=None) -> None:
    tcpr = cell._tc.get_or_add_tcPr()
    old = tcpr.find(qn("w:tcBorders"))
    if old is not None:
        tcpr.remove(old)
    borders = OxmlElement("w:tcBorders")
    set_property_child(tcpr, borders)

    def add(name: str, spec) -> None:
        node = OxmlElement(f"w:{name}")
        if spec is None:
            node.set(qn("w:val"), "nil")
        else:
            color, size = spec
            node.set(qn("w:val"), "single")
            node.set(qn("w:sz"), str(size))
            node.set(qn("w:space"), "0")
            node.set(qn("w:color"), color)
        borders.append(node)

    add("top", top)
    add("left", start)
    add("bottom", bottom)
    add("right", end)


def set_table_geometry(table, widths_cm: list[float]) -> None:
    table.autofit = False
    table.alignment = WD_TABLE_ALIGNMENT.LEFT
    total_twips = round(sum(widths_cm) / 2.54 * 1440)
    tblpr = table._tbl.tblPr
    layout = tblpr.find(qn("w:tblLayout"))
    if layout is None:
        layout = OxmlElement("w:tblLayout")
    layout.set(qn("w:type"), "fixed")
    set_property_child(tblpr, layout)
    tblw = tblpr.find(qn("w:tblW"))
    if tblw is None:
        tblw = OxmlElement("w:tblW")
    tblw.set(qn("w:w"), str(total_twips))
    tblw.set(qn("w:type"), "dxa")
    set_property_child(tblpr, tblw)
    tblind = tblpr.find(qn("w:tblInd"))
    if tblind is None:
        tblind = OxmlElement("w:tblInd")
    tblind.set(qn("w:w"), "0")
    tblind.set(qn("w:type"), "dxa")
    set_property_child(tblpr, tblind)

    grid = table._tbl.tblGrid
    for child in list(grid):
        grid.remove(child)
    for width in widths_cm:
        twips = round(width / 2.54 * 1440)
        col = OxmlElement("w:gridCol")
        col.set(qn("w:w"), str(twips))
        grid.append(col)
    for row in table.rows:
        for idx, cell in enumerate(row.cells):
            width = widths_cm[min(idx, len(widths_cm) - 1)]
            twips = round(width / 2.54 * 1440)
            tcw = cell._tc.get_or_add_tcPr().find(qn("w:tcW"))
            if tcw is None:
                tcw = OxmlElement("w:tcW")
            tcw.set(qn("w:w"), str(twips))
            tcw.set(qn("w:type"), "dxa")
            set_property_child(cell._tc.get_or_add_tcPr(), tcw)


def _repeat_header(row) -> None:
    trpr = row._tr.get_or_add_trPr()
    if trpr.find(qn("w:tblHeader")) is None:
        node = OxmlElement("w:tblHeader")
        node.set(qn("w:val"), "true")
        set_property_child(trpr, node)


def set_keep_together(row) -> None:
    trpr = row._tr.get_or_add_trPr()
    if trpr.find(qn("w:cantSplit")) is None:
        set_property_child(trpr, OxmlElement("w:cantSplit"))


def _normalize_template_style_fonts(doc: Document) -> None:
    """Rewrite every template style's ``w:rFonts`` onto the two font routes.

    python-docx's bundled template declares theme fonts on ~160 unused styles
    (Title, Quote, LightShading…).  A stray reference to one of them would fall
    back to Calibri/等线, so all of them get the configured heading or body family
    on eastAsia and the Latin family on ascii/hAnsi/cs.  Sizes and colours are left untouched.
    """
    heading_like = ("Heading", "Title", "Subtitle", "TOCHeading", "BookTitle")
    for style in doc.styles:
        element = style.element
        style_id = str(element.get(qn("w:styleId")) or "")
        family = FONT_HEADING if style_id.startswith(heading_like) else FONT_BODY
        # Conditional table formatting (w:tblStylePr/w:rPr) carries its own
        # rFonts; rewrite every rPr below the style, not only the top-level one.
        for rpr in element.iter(qn("w:rPr")):
            if rpr.find(qn("w:rFonts")) is None and rpr.getparent().tag != qn("w:style"):
                continue
            _write_two_route_fonts(rpr, family)
            _write_run_language(rpr)


def _ensure_paragraph_style(doc: Document, name: str):
    if name in doc.styles:
        return doc.styles[name]
    return doc.styles.add_style(name, WD_STYLE_TYPE.PARAGRAPH)


def _configure_styles(doc: Document) -> None:
    _set_doc_defaults_font(doc)
    _normalize_template_style_fonts(doc)
    normal = doc.styles["Normal"]
    _set_style_font(normal, FONT_BODY, WORD_PT["body"], color=INK)
    normal.paragraph_format.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
    normal.paragraph_format.space_before = Pt(0)
    normal.paragraph_format.space_after = Pt(WORD_PARAGRAPH["body_space_after_pt"])
    _set_line_spacing_at_least(normal, WORD_PARAGRAPH["body_line_pt"])
    _set_first_line_chars(normal, round(_lw("paragraph.first_line_indent_chars") * 100))

    heading_specs = {
        f"Heading {level}": (WORD_PT[f"h{level}"], _lw(f"heading.h{level}.space_before_pt"),
                             _lw(f"heading.h{level}.space_after_pt"))
        for level in (1, 2, 3)
    }
    for name, (size, before, after) in heading_specs.items():
        style = doc.styles[name]
        _set_style_font(style, FONT_HEADING, size, bold=True, color=INK)
        style.paragraph_format.left_indent = Pt(0)
        style.paragraph_format.first_line_indent = Pt(0)
        style.paragraph_format.space_before = Pt(before)
        style.paragraph_format.space_after = Pt(after)
        style.paragraph_format.line_spacing = _lw("heading.line_multiple")
        style.paragraph_format.keep_with_next = True
        _set_first_line_chars(style, 0)
    # 章标题上方一条正文色粗线。
    _style_paragraph_border(doc.styles["Heading 1"], side="top", color=INK,
                            size=RULE["chapter_top"], space=_lw("heading.chapter_rule_space_pt"))

    for name in ("List Bullet", "List Bullet 2", "List Number", "List Number 2"):
        if name not in doc.styles:
            continue
        style = doc.styles[name]
        _set_style_font(style, FONT_BODY, WORD_PT["body"], color=INK)
        style.paragraph_format.space_after = Pt(_lw("list.space_after_pt"))
        _set_line_spacing_at_least(style, WORD_PARAGRAPH["list_line_pt"])

    for idx in range(1, 10):
        name = f"TOC {idx}"
        if name in doc.styles:
            style = doc.styles[name]
            _set_style_font(style, FONT_BODY, WORD_PT["body"] if idx < 3 else WORD_PT["toc_minor"], color=INK)
            style.paragraph_format.space_after = Pt(_lw("toc.style_space_after_pt"))

    for style in doc.styles:
        if style.type == WD_STYLE_TYPE.TABLE:
            _set_style_font(style, FONT_TABLE, WORD_PT["table"], color=INK)

    # 不缩进的正文槽：列表引语、图注前引、附录条目等按语义走这一路，
    # 而不是在每个段落上单写 w:ind。
    flush = _ensure_paragraph_style(doc, "Body Flush")
    _set_style_font(flush, FONT_BODY, WORD_PT["body"], color=INK)
    flush.paragraph_format.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
    flush.paragraph_format.space_before = Pt(0)
    flush.paragraph_format.space_after = Pt(WORD_PARAGRAPH["body_space_after_pt"])
    _set_line_spacing_at_least(flush, WORD_PARAGRAPH["body_line_pt"])
    _set_first_line_chars(flush, 0)

    # 表格正文/表头两槽：字体、字号、行距、零缩进都由样式承担，
    # 单元格上只留内容决定的横向排法与底色。
    table_text = _ensure_paragraph_style(doc, "Table Text")
    _set_style_font(table_text, FONT_TABLE, WORD_PT["table"], color=INK)
    table_text.paragraph_format.alignment = WD_ALIGN_PARAGRAPH.LEFT
    table_text.paragraph_format.space_before = Pt(0)
    table_text.paragraph_format.space_after = Pt(0)
    _set_line_spacing_at_least(table_text, WORD_PARAGRAPH["table_line_pt"])
    _set_first_line_chars(table_text, 0)

    table_header = _ensure_paragraph_style(doc, "Table Header")
    # 三线表表头：次要色、常规字重、居左。
    _set_style_font(table_header, FONT_TABLE, WORD_PT["table_header"], bold=False, color=MUTED)
    table_header.paragraph_format.alignment = WD_ALIGN_PARAGRAPH.LEFT
    table_header.paragraph_format.space_before = Pt(0)
    table_header.paragraph_format.space_after = Pt(0)
    _set_line_spacing_at_least(table_header, WORD_PARAGRAPH["table_line_pt"])
    _set_first_line_chars(table_header, 0)

    # 紧凑版表格：字体字号同常规版，只收紧行距。
    compact_line = _table_geometry("compact")["line_pt"]
    for base_name, color in (("Table Text", INK), ("Table Header", MUTED)):
        compact = _ensure_paragraph_style(doc, f"{base_name} Compact")
        _set_style_font(compact, FONT_TABLE, WORD_PT["table"], bold=False, color=color)
        compact.paragraph_format.alignment = WD_ALIGN_PARAGRAPH.LEFT
        compact.paragraph_format.space_before = Pt(0)
        compact.paragraph_format.space_after = Pt(0)
        _set_line_spacing_at_least(compact, compact_line)
        _set_first_line_chars(compact, 0)
    mark_style = current_brand().mark_style
    if mark_style not in doc.styles:
        doc.styles.add_style(mark_style, WD_STYLE_TYPE.CHARACTER)

    note_style_name = "Quote Note"
    note_style = (
        doc.styles[note_style_name]
        if note_style_name in doc.styles
        else doc.styles.add_style(note_style_name, WD_STYLE_TYPE.PARAGRAPH)
    )
    _set_style_font(note_style, FONT_BODY, WORD_PT["caption"], color=MUTED)
    note_style.paragraph_format.alignment = WD_ALIGN_PARAGRAPH.LEFT
    note_style.paragraph_format.left_indent = Pt(0)
    note_style.paragraph_format.first_line_indent = Pt(0)
    note_style.paragraph_format.space_before = Pt(0)
    note_style.paragraph_format.space_after = Pt(_lw("notes.table_note_space_after_pt"))
    note_style.paragraph_format.line_spacing = _lw("notes.table_note_line_multiple")
    _set_first_line_chars(note_style, 0)


def normalize_orientation(value: Any) -> str:
    text = safe_text(value).strip().lower()
    return "landscape" if text in {"landscape", "horizontal", "横向", "横版"} else "portrait"


def _configure_section_geometry(section, orientation: str = "portrait") -> None:
    """Apply real A4 geometry; changing orientation alone is not sufficient in OOXML."""
    orientation = normalize_orientation(orientation)
    if orientation == "landscape":
        section.orientation = WD_ORIENT.LANDSCAPE
        section.page_width = Cm(_page_cm("paper_height_mm"))
        section.page_height = Cm(_page_cm("paper_width_mm"))
    else:
        section.orientation = WD_ORIENT.PORTRAIT
        section.page_width = Cm(_page_cm("paper_width_mm"))
        section.page_height = Cm(_page_cm("paper_height_mm"))
    section.top_margin = Cm(_page_cm("top_margin_mm"))
    section.bottom_margin = Cm(_page_cm("bottom_margin_mm"))
    section.left_margin = Cm(_page_cm("left_margin_mm"))
    section.right_margin = Cm(_page_cm("right_margin_mm"))
    section.header_distance = Cm(_page_cm("header_distance_mm"))
    section.footer_distance = Cm(_page_cm("footer_distance_mm"))


def section_orientation(section) -> str:
    return "landscape" if section.orientation == WD_ORIENT.LANDSCAPE else "portrait"


def _section_body_width_cm(section) -> float:
    return max(
        1.0,
        float(section.page_width.cm - section.left_margin.cm - section.right_margin.cm),
    )


def _current_body_width_cm(doc: Document) -> float:
    return _section_body_width_cm(doc.sections[-1])


def new_document() -> Document:
    doc = Document()
    section = doc.sections[0]
    _configure_section_geometry(section, "portrait")
    section.different_first_page_header_footer = True
    _configure_styles(doc)
    _configure_word_open_safety(doc)
    return doc


def _add_page_break(doc: Document) -> None:
    # 版式补丁（第二阶段）：不再插入「只含分页符的空段落」。
    # 旧写法是空段落 + 段内 w:br type="page"：前文正好排到页底时，空段落本身先被推到
    # 下一页占一行，段内分页符再把后续内容推一次，中间夹出一整页空白页。
    # 改用 w:pageBreakBefore：段落自身即新页起点，不可能夹页。
    p = doc.add_paragraph()
    clear_indent(p)
    p.paragraph_format.space_before = Pt(0)
    p.paragraph_format.space_after = Pt(0)
    p.paragraph_format.page_break_before = True


def _add_spacer(doc: Document, points: float) -> None:
    p = doc.add_paragraph()
    clear_indent(p)
    p.paragraph_format.space_before = Pt(0)
    p.paragraph_format.space_after = Pt(points)
    p.paragraph_format.line_spacing = Pt(1)
    run = p.add_run(" ")
    set_run_font(run, FONT_BODY, 1, color=WHITE)


_COVER_TITLE = layout_rule("cover_title")
_INFO_LINE = layout_rule("first_page_info_line")
_SUMMARY = layout_rule("section_summary")
_AMOUNT_UNIT = layout_rule("amount_unit")
_KEEP_SMALL_TABLE_ROWS = int(layout_rule("keep_small_tables")["max_rows"])


def _cover_title_text(value: Any) -> str:
    """Insert a semantic line break before long document-name suffixes.

    Letting Word wrap CJK titles character-by-character can leave the final
    character of “报告” or “方案” alone on a third line. Keep the project name
    intact and move the complete document type to the next line instead.
    """
    title = safe_text(value).strip()
    if "\n" in title or len(re.sub(r"\s+", "", title)) < 16:
        return title
    for suffix in ("需求报告", "解决方案"):
        if title.endswith(suffix):
            prefix = title[:-len(suffix)].rstrip()
            if prefix:
                return f"{prefix}\n{suffix}"
    return title


def add_cover(doc: Document, meta: dict[str, Any]) -> None:
    brand = current_brand()
    logo = brand.logo
    if logo is not None and logo.exists():
        p = doc.add_paragraph()
        clear_indent(p)
        p.alignment = WD_ALIGN_PARAGRAPH.CENTER
        p.paragraph_format.space_after = Pt(_lw("cover.logo_space_after_pt"))
        shape = p.add_run().add_picture(str(logo), width=Cm(_lw("cover.logo_width_cm")))
        shape._inline.docPr.set("title", brand.logo_title)
        shape._inline.docPr.set("descr", f"{brand.company} {brand.wordmark} 品牌标识")
    else:
        _add_spacer(doc, _lw("cover.no_logo_space_pt"))

    if safe_text(meta.get("kicker")):
        kicker = doc.add_paragraph()
        clear_indent(kicker)
        kicker.alignment = WD_ALIGN_PARAGRAPH.CENTER
        kicker.paragraph_format.space_after = Pt(_lw("cover.kicker_space_after_pt"))
        set_run_font(kicker.add_run(safe_text(meta["kicker"])),
                     FONT_BODY, WORD_PT["body"], bold=True, color=MUTED)

    title = doc.add_paragraph()
    clear_indent(title)
    title.alignment = WD_ALIGN_PARAGRAPH.CENTER
    title.paragraph_format.space_after = Pt(_lw("cover.title_space_after_pt"))
    title.paragraph_format.line_spacing = _lw("cover.title_line_multiple")
    project_first = _COVER_TITLE.get("main") == "project_name" and bool(safe_text(meta.get("project_name")))
    # 版面规则 cover_title（ISO 24896:2026 3.3.2）：标题要能识别内容。项目名作主标题，文档类型作副标题。
    main_title = meta.get("project_name") if project_first else meta["title"]
    set_run_font(title.add_run(_cover_title_text(main_title)), FONT_HEADING,
                  WORD_PT["cover_title"], bold=True, color=INK)
    if project_first:
        sub_title = doc.add_paragraph()
        clear_indent(sub_title)
        sub_title.alignment = WD_ALIGN_PARAGRAPH.CENTER
        sub_title.paragraph_format.space_after = Pt(_lw("cover.subtitle_space_after_pt"))
        set_run_font(sub_title.add_run(safe_text(meta["title"])), FONT_HEADING,
                      WORD_PT["h1"], color=INK)

    # 副标题原来重复印一遍「客户简称｜项目名」，与下方信息块完全同义。
    # 对客封面的标识只有四项：客户、项目、版本、日期。

    rule = doc.add_paragraph()
    clear_indent(rule)
    rule.alignment = WD_ALIGN_PARAGRAPH.CENTER
    rule.paragraph_format.left_indent = Cm(_lw("cover.rule_indent_cm"))
    rule.paragraph_format.right_indent = Cm(_lw("cover.rule_indent_cm"))
    rule.paragraph_format.space_after = Pt(_lw("cover.rule_space_after_pt"))
    _paragraph_border(rule, side="bottom", color=ACCENT, size=RULE["cover_rule"],
                      space=_lw("cover.rule_space_pt"))

    # cover_fields 写明时按它印 [标签, 值]；不写时印客户、项目、版本、日期。客户写全称。
    if meta.get("cover_fields") is not None:
        rows = [(safe_text(label), value) for label, value in meta["cover_fields"]]
    else:
        rows = [
            ("客户", meta.get("customer_name", "")),
            *([] if project_first else [("项目", meta.get("project_name", ""))]),
            ("版本", meta.get("version", "V1.0")),
            ("日期", meta.get("date", date.today().isoformat())),
        ]
        if meta.get("show_workflow_status"):
            # 文档状态只印在内部版。
            rows.append(("文档状态", meta.get("status_text", "草稿")))
    for label, value in rows:
        p = doc.add_paragraph()
        clear_indent(p)
        p.alignment = WD_ALIGN_PARAGRAPH.CENTER
        p.paragraph_format.space_after = Pt(_lw("cover.field_space_after_pt"))
        set_run_font(p.add_run(f"{label}："), FONT_BODY, WORD_PT["body"], color=MUTED)
        set_run_font(p.add_run(safe_text(value)), FONT_BODY, WORD_PT["body"], color=INK)

    footer = doc.sections[0].first_page_footer
    fp = footer.paragraphs[0]
    clear_indent(fp)
    fp.alignment = WD_ALIGN_PARAGRAPH.CENTER
    fp.paragraph_format.space_after = Pt(0)
    # 英文品牌名已包含在公司名里时只印公司名，避免同一个品牌名印两遍。
    cover_footer = brand.company if brand.wordmark in brand.company else f"{brand.company} · {brand.wordmark}"
    set_run_font(fp.add_run(cover_footer),
                 FONT_BODY, WORD_PT["header_footer"], color=MUTED)


def _clear_story(story) -> None:
    for child in list(story._element):
        story._element.remove(child)


def add_header_footer(section, meta: dict[str, Any]) -> None:
    body_width = _section_body_width_cm(section)
    header = section.header
    header.is_linked_to_previous = False
    _clear_story(header)
    logo_column = min(_lw("header_footer.logo_column_max_cm"), body_width * _lw("header_footer.logo_column_ratio"))
    table = header.add_table(rows=1, cols=2, width=Cm(body_width))
    table.alignment = WD_TABLE_ALIGNMENT.CENTER
    table.autofit = False
    set_table_geometry(table, [body_width - logo_column, logo_column])
    left_cell, right_cell = table.rows[0].cells
    for cell in (left_cell, right_cell):
        set_cell_margins(cell, top=0, start=0, bottom=0, end=0)
        set_cell_borders(cell)
        cell.vertical_alignment = WD_ALIGN_VERTICAL.CENTER
    p = left_cell.paragraphs[0]
    clear_indent(p)
    p.alignment = WD_ALIGN_PARAGRAPH.LEFT
    p.paragraph_format.space_after = Pt(0)
    p.paragraph_format.line_spacing = _lw("header_footer.line_multiple")
    _header_title = safe_text(meta["title"])
    _header_project = safe_text(meta.get("project_name", ""))
    # 项目名已包含在文档标题内时不再重复，避免页眉出现
    # 「传感器车间 MES 一期技术协议｜传感器车间 MES 一期」这类叠字。
    _header_text = (
        _header_title
        if _header_project and _header_project in _header_title
        else "｜".join(filter(None, [_header_title, _header_project]))
    )
    footer_pt = WORD_PT["header_footer"]
    set_run_font(p.add_run(_header_text), FONT_BODY, footer_pt, color=MUTED)
    p = right_cell.paragraphs[0]
    clear_indent(p)
    p.alignment = WD_ALIGN_PARAGRAPH.RIGHT
    p.paragraph_format.space_after = Pt(0)
    p.paragraph_format.line_spacing = _lw("header_footer.line_multiple")
    brand = current_brand()
    if brand.logo is not None and brand.logo.exists():
        shape = p.add_run().add_picture(str(brand.logo), width=Cm(_lw("header_footer.logo_width_cm")))
        shape._inline.docPr.set("title", brand.logo_title)
        shape._inline.docPr.set("descr", f"{brand.short_name} {brand.wordmark} 品牌标识")
    else:
        set_run_font(p.add_run(brand.wordmark), FONT_BODY, footer_pt, bold=True, color=INK)

    footer = section.footer
    footer.is_linked_to_previous = False
    _clear_story(footer)
    p = footer.add_paragraph()
    clear_indent(p)
    p.paragraph_format.space_after = Pt(0)
    p.paragraph_format.line_spacing = _lw("header_footer.line_multiple")
    p.paragraph_format.tab_stops.add_tab_stop(Cm(body_width), WD_TAB_ALIGNMENT.RIGHT)
    left_parts = [brand.company, safe_text(meta.get("version", "V1.0"))]
    if meta.get("show_workflow_status"):
        left_parts.append(safe_text(meta.get("status_text", "草稿")))
    left = "｜".join(filter(None, left_parts))
    set_run_font(p.add_run(left), FONT_BODY, footer_pt, color=MUTED)
    p.add_run("\t")
    # 只有 PAGE 时读者不知道全文多长；补 NUMPAGES 域，页脚读作「第 3 页 / 共 12 页」。
    set_run_font(p.add_run("第 "), FONT_BODY, footer_pt, color=MUTED)
    _field(p, "PAGE", "1", size=footer_pt)
    set_run_font(p.add_run(" 页 / 共 "), FONT_BODY, footer_pt, color=MUTED)
    _field(p, "NUMPAGES", "1", size=footer_pt)
    set_run_font(p.add_run(" 页"), FONT_BODY, footer_pt, color=MUTED)
    # 0.5pt（sz=4，单位为 1/8 pt）分隔线色细线。
    _paragraph_border(p, side="top", color=LINE, size=RULE["footer_top"],
                      space=_lw("header_footer.footer_rule_space_pt"))


def start_section(doc: Document, orientation: str, meta: dict[str, Any]):
    """Start a new A4 section and give it orientation-aware chrome."""
    section = doc.add_section(WD_SECTION.NEW_PAGE)
    _configure_section_geometry(section, orientation)
    section.different_first_page_header_footer = False
    add_header_footer(section, meta)
    return section


def add_toc(
    doc: Document, flattened_chapters: Iterable[tuple[dict[str, Any], int]],
) -> None:
    # 版式补丁：用标题段落的 page_break_before 分页，不插入只含分页符的空段落。
    # 空段落本身占一行，前文排到接近页底时会被推到下一页，其内部分页符再推一次，中间产生空白页。
    p = doc.add_paragraph()
    clear_indent(p)
    p.paragraph_format.page_break_before = True
    p.paragraph_format.space_after = Pt(_lw("toc.title_space_after_pt"))
    set_run_font(p.add_run("目录"), FONT_HEADING, WORD_PT["toc_title"], bold=True, color=INK)
    _paragraph_border(p, side="bottom", color=INK, size=RULE["table_frame"], space=_lw("toc.title_rule_space_pt"))
    level1_before = _lw("toc.level1_space_before_pt")
    level1_after = _lw("toc.level1_space_after_pt")
    minor_after = _lw("toc.minor_space_after_pt")
    toc_rule_space = _lw("toc.rule_space_pt")
    entries = outline_entries(flattened_chapters)
    if not entries:
        # 没有章节时目录只留一行占位，目录域仍然完整。
        entries = [("（目录）", 1)]
    # 目录样式：不用点线引导，一级条目加粗并在下方画分隔线。
    # 样式上也写同样的制表位和线，Word 重新更新目录域时沿用。
    for level in (1, 2, 3):
        style_name = f"TOC {level}"
        style = doc.styles[style_name] if style_name in doc.styles else doc.styles.add_style(
            style_name, WD_STYLE_TYPE.PARAGRAPH)
        _set_style_font(style, FONT_BODY, WORD_PT["body"], bold=level == 1, color=INK)
        style.paragraph_format.tab_stops.add_tab_stop(
            Cm(PORTRAIT_BODY_CM), WD_TAB_ALIGNMENT.RIGHT, WD_TAB_LEADER.SPACES,
        )
        style.paragraph_format.space_after = Pt(level1_after if level == 1 else minor_after)
        style.paragraph_format.space_before = Pt(level1_before if level == 1 else 0)
        if level == 1:
            # 相邻的一级条目边框相同，Word 会把它们合成一组，只在组底画线；between 让每条之间也画线。
            _style_paragraph_border(style, side="bottom", color=LINE, size=RULE["table_row"], space=toc_rule_space)
            _style_paragraph_border(style, side="between", color=LINE, size=RULE["table_row"], space=toc_rule_space)
    for index, (heading, level) in enumerate(entries):
        style_name = f"TOC {level}"
        toc = doc.add_paragraph(style=style_name)
        clear_indent(toc)
        toc.alignment = WD_ALIGN_PARAGRAPH.LEFT
        toc.paragraph_format.left_indent = Cm(_lw("toc.indent_per_level_cm") * (level - 1))
        toc.paragraph_format.first_line_indent = Pt(0)
        toc.paragraph_format.space_before = Pt(
            _lw("toc.first_entry_space_before_pt") if index == 0 else (level1_before if level == 1 else 0))
        toc.paragraph_format.space_after = Pt(level1_after if level == 1 else minor_after)
        toc.paragraph_format.tab_stops.add_tab_stop(
            Cm(PORTRAIT_BODY_CM), WD_TAB_ALIGNMENT.RIGHT, WD_TAB_LEADER.SPACES,
        )
        if index == 0:
            begin_run = OxmlElement("w:r")
            begin = OxmlElement("w:fldChar")
            begin.set(qn("w:fldCharType"), "begin")
            begin.set(qn("w:dirty"), "false")
            begin_run.append(begin)
            toc._p.append(begin_run)
            instr_run = OxmlElement("w:r")
            instr = OxmlElement("w:instrText")
            instr.set(qn("xml:space"), "preserve")
            instr.text = ' TOC \\o "1-3" \\h \\z \\u '
            instr_run.append(instr)
            toc._p.append(instr_run)
            separate_run = OxmlElement("w:r")
            separate = OxmlElement("w:fldChar")
            separate.set(qn("w:fldCharType"), "separate")
            separate_run.append(separate)
            toc._p.append(separate_run)
        match = _HEADING_NUMBER.match(heading)
        bold = level == 1
        if match:
            number = toc.add_run(match.group(1))
            set_run_font(number, FONT_BODY, WORD_PT["body"], bold=bold,
                          color=ACCENT if level < 3 else INK)
            title = toc.add_run(match.group(2) + match.group(3))
        else:
            title = toc.add_run(heading)
        set_run_font(title, FONT_BODY, WORD_PT["body"], bold=bold, color=INK)
        page = toc.add_run("\t［待刷新］")
        set_run_font(page, FONT_BODY, WORD_PT["body"], color=MUTED)
        if index == len(entries) - 1:
            end_run = OxmlElement("w:r")
            end = OxmlElement("w:fldChar")
            end.set(qn("w:fldCharType"), "end")
            end_run.append(end)
            toc._p.append(end_run)


def add_inner_title(doc: Document, meta: dict[str, Any]) -> None:
    """正文第一页的文首区块：客户名、标题、导语、信息行和关键数字。"""
    # 版式补丁：同 add_toc，改用 page_break_before，避免目录与正文之间出现空白页。
    # 没有客户名时不印客户名那一行，分页落在标题段上。
    customer = safe_text(meta.get("customer_name"))
    if customer:
        eyebrow = doc.add_paragraph()
        clear_indent(eyebrow)
        eyebrow.paragraph_format.page_break_before = True
        eyebrow.paragraph_format.space_after = Pt(_lw("inner_title.eyebrow_space_after_pt"))
        eyebrow.paragraph_format.keep_with_next = True
        _add_mark_run(eyebrow, "——\u00a0", ACCENT, size=WORD_PT["table"])
        set_run_font(eyebrow.add_run(customer), FONT_BODY,
                      WORD_PT["table"], bold=True, color=ACCENT)
    p = doc.add_paragraph()
    clear_indent(p)
    if not customer:
        p.paragraph_format.page_break_before = True
    p.paragraph_format.space_after = Pt(_lw("inner_title.title_space_after_pt"))
    p.paragraph_format.keep_with_next = True
    inner_title = safe_text(meta["title"])
    if _COVER_TITLE.get("main") == "project_name" and safe_text(meta.get("project_name")):
        inner_title = safe_text(meta.get("project_name")) + inner_title
    set_run_font(p.add_run(inner_title), FONT_HEADING,
                  WORD_PT["document_title"], bold=True, color=INK)
    lede = safe_text(meta.get("lede"))
    if lede:
        lp = doc.add_paragraph()
        clear_indent(lp)
        lp.alignment = WD_ALIGN_PARAGRAPH.LEFT
        lp.paragraph_format.space_after = Pt(_lw("inner_title.lede_space_after_pt"))
        lp.paragraph_format.keep_with_next = True
        _set_line_spacing_at_least(lp, WORD_PARAGRAPH["body_line_pt"] + _lw("inner_title.lede_line_extra_pt"))
        set_run_font(lp.add_run(lede), FONT_BODY, WORD_PT["lede"], color=INK)
    if not _INFO_LINE.get("show_when_cover", True):
        # 封面已有客户、项目、版本、日期（内部版还有文档状态），正文首页不再重复一行。
        p.paragraph_format.space_after = Pt(_lw("inner_title.title_space_after_no_info_pt"))
        figures = meta.get("key_figures") or []
        if figures:
            _add_key_figures(doc, figures)
        return
    # 信息行：客户全称｜项目名｜版本｜日期。流程状态只在内部版补在末位。
    info = doc.add_paragraph()
    clear_indent(info)
    info.paragraph_format.space_before = Pt(_lw("inner_title.info_space_before_pt"))
    info.paragraph_format.space_after = Pt(_lw("inner_title.info_space_after_pt"))
    info_rule_space = _lw("inner_title.info_rule_space_pt")
    _paragraph_border(info, side="top", color=INK, size=RULE["table_frame"], space=info_rule_space)
    _paragraph_border(info, side="bottom", color=LINE, size=RULE["table_row"], space=info_rule_space)
    items = [
        ("客户", meta.get("customer_name")),
        ("项目", meta.get("project_name")),
        ("版本", meta.get("version")),
        ("日期", meta.get("date")),
    ]
    if meta.get("show_workflow_status"):
        items.append(("状态", meta.get("status_text")))
    first = True
    for label, value in items:
        value = safe_text(value)
        if not value:
            continue
        if not first:
            set_run_font(info.add_run("\u3000\u3000"), FONT_BODY, WORD_PT["table"], color=MUTED)
        first = False
        set_run_font(info.add_run(f"{label}\u00a0"), FONT_BODY, WORD_PT["table"], color=MUTED)
        set_run_font(info.add_run(value), FONT_BODY, WORD_PT["table"], color=INK)
    figures = meta.get("key_figures") or []
    if figures:
        _add_key_figures(doc, figures)


def _add_key_figures(doc: Document, figures: list[Any]) -> None:
    """关键数字：最多 4 个，上方一条正文色线。"""
    if len(figures) > 4:
        raise ValueError(f"key_figures 最多 4 个，收到 {len(figures)} 个")
    items = []
    for index, item in enumerate(figures, start=1):
        if not isinstance(item, dict) or not safe_text(item.get("label")) or not safe_text(item.get("value")):
            raise ValueError(f"key_figures 第 {index} 项要写 label 和 value")
        items.append((safe_text(item["label"]), safe_text(item["value"])))
    body = _current_body_width_cm(doc)
    gap = _lw("key_figures.gap_cm")
    n = len(items)
    cell_cm = (body - gap * (n - 1)) / n
    widths = [w for i in range(n) for w in ((cell_cm,) if i == 0 else (gap, cell_cm))]
    table = doc.add_table(rows=1, cols=len(widths))
    set_table_geometry(table, widths)
    for col_index, cell in enumerate(table.rows[0].cells):
        cell.text = ""
        set_cell_width_cm(cell, widths[col_index])
        set_cell_margins(cell, top=_twips(_lw("key_figures.cell_top_pt")),
                         bottom=_twips(_lw("key_figures.cell_bottom_pt")), start=0, end=0)
        cell.vertical_alignment = WD_ALIGN_VERTICAL.TOP
        if col_index % 2 == 1:
            set_cell_borders(cell)
            continue
        set_cell_borders(cell, top=(INK, RULE["key_figure_top"]))
        label, value = items[col_index // 2]
        lp = cell.paragraphs[0]
        lp.style = doc.styles["Table Text"]
        set_run_font(lp.add_run(label), FONT_BODY, WORD_PT["caption"], color=MUTED)
        vp = cell.add_paragraph(style="Table Text")
        vp.paragraph_format.space_before = Pt(_lw("key_figures.value_space_before_pt"))
        set_run_font(vp.add_run(value), FONT_HEADING, WORD_PT["key_value"], bold=True, color=INK)
    spacer = doc.add_paragraph()
    clear_indent(spacer)
    spacer.paragraph_format.space_after = Pt(_lw("key_figures.space_after_pt"))


# 正文与标题只套样式：字体、字号、颜色、行距、横向排法、首行缩进都在
# _configure_styles 里定义一次。逐 run 写 rFonts/sz/b/color 会让同一种段落在
# 文档里存在几十份互相漂移的副本，改一次版式要改几十处，还改不干净。
_HEADING_NUMBER = re.compile(r"^(\d+(?:\.\d+)*)(\s+)(.+)$", re.S)


def add_heading(doc: Document, text: str, level: int = 1) -> None:
    """标题文字仍是「编号 标题」；编号单独一段文字，章、节编号用主色。"""
    level = max(1, min(3, level))
    p = doc.add_paragraph(style=f"Heading {level}")
    value = safe_text(text)
    match = _HEADING_NUMBER.match(value)
    if not match:
        p.add_run(value)
        return
    number = p.add_run(match.group(1))
    number.font.color.rgb = RGBColor.from_string(ACCENT if level < 3 else INK)
    p.add_run(match.group(2) + match.group(3))


# 必答标记：问卷类文档在编号后写「★」，渲染为红色，其余文字仍按段落样式。
# 只加颜色一项直接格式，字体与字号继承样式，不改动四个字体槽。
REQUIRED_MARK = "★"


def _add_marked_runs(paragraph, text: str) -> None:
    parts = text.split(REQUIRED_MARK)
    for index, part in enumerate(parts):
        if part:
            paragraph.add_run(part)
        if index < len(parts) - 1:
            mark = paragraph.add_run(REQUIRED_MARK)
            mark.font.color.rgb = RGBColor.from_string(HOT)


def add_body(doc: Document, text: str, *, indent: bool = True,
              bold_prefix: str | None = None) -> None:
    style = "Normal" if indent else "Body Flush"
    for index, para_text in enumerate(safe_text(text).split("\n")):
        if not para_text and index == 0:
            continue
        p = doc.add_paragraph(style=style)
        if bold_prefix and para_text.startswith(bold_prefix):
            p.add_run(bold_prefix).bold = True
            _add_marked_runs(p, para_text[len(bold_prefix):])
        else:
            _add_marked_runs(p, para_text)


CALLOUT_TONES = {"lead": "callout_top", "key": "key_top", "risk": "risk_top"}


def add_lead(doc: Document, label: str, text: str, *, tone: str = "lead",
              color: str | None = None) -> None:
    """提示条、规则条和风险条。

    上方一条色线、下方一条分隔线；提示条用主色，规则条与风险条用重点色。
    ``color`` 只给配图缺失这类状态说明用，覆盖上线颜色、标签保持正文色。
    """
    rule_color = STYLE["colors"][STYLE["rules"]["colors"][CALLOUT_TONES.get(tone, "callout_top")]]
    top_color = color or rule_color
    label_color = INK if color else rule_color
    p = doc.add_paragraph()
    clear_indent(p)
    p.paragraph_format.space_before = Pt(_lw("callout.space_before_pt"))
    p.paragraph_format.space_after = Pt(_lw("callout.space_after_pt"))
    _set_line_spacing_at_least(p, WORD_PARAGRAPH["body_line_pt"])
    rule_space = _lw("callout.rule_space_pt")
    _paragraph_border(p, side="top", color=top_color, size=RULE["callout_top"], space=rule_space)
    _paragraph_border(p, side="bottom", color=LINE, size=RULE["callout_bottom"], space=rule_space)
    set_run_font(p.add_run(f"{safe_text(label)}："), FONT_BODY,
                  WORD_PT["body"], bold=True, color=label_color)
    set_run_font(p.add_run(safe_text(text)), FONT_BODY, WORD_PT["body"], color=INK)


def add_chapter_summary(doc: Document, label: str, text: str) -> None:
    """章节说明（版面规则 section_summary）：章题下一行灰色副题，不加标签和色线。"""
    if _SUMMARY.get("style") != "subtitle":
        add_lead(doc, label, text)
        return
    p = doc.add_paragraph()
    clear_indent(p)
    p.paragraph_format.space_before = Pt(0)
    p.paragraph_format.space_after = Pt(_lw("summary.space_after_pt"))
    p.paragraph_format.keep_with_next = True
    _set_line_spacing_at_least(p, WORD_PARAGRAPH["body_line_pt"])
    set_run_font(p.add_run(safe_text(text)), FONT_BODY, WORD_PT["summary"], color=MUTED)


# 编号一律「1. 2. 3.」（GB/T 9704-2012 7.3.3）。底稿正文已自带编号（"1）"、"1. "、"（2）"、"3、"）时
# 不再叠加前缀，否则渲染成「1. 1. …」。
_AUTHORED_NUMBER_PREFIX = re.compile(r"^\s*(?:[（(]\s*\d{1,3}\s*[)）]|\d{1,3}\s*[.、)）])\s*")


def add_list(
    doc: Document, items: Iterable[Any], *, ordered: bool = False, start: int = 1
) -> None:
    # 一个逻辑列表被说明段落拆成两个块时，第二块传 start 续号，不要从 1 重来。
    for position, item in enumerate(items, start=start):
        if isinstance(item, dict):
            text = item.get("text", "")
            level = int(item.get("level", 1))
        else:
            text = item
            level = 1
        # LibreOffice routes native Word bullet numbering through OpenSymbol.
        # Use literal glyphs/numbers so every visible character stays on the
        # declared font routes.
        # 列表标记一律用字面前缀（下方 prefix），段落不套 List Number / List Bullet
        # 样式——那两个样式带 numPr 自动编号，与字面前缀叠加会渲染成「1. 1.」「• •」。
        # 缩进由下面的 left_indent / first_line_indent 显式设置，不依赖列表样式。
        style_name = "Normal"
        p = doc.add_paragraph(style=style_name)
        clear_indent(p)
        p.paragraph_format.left_indent = Cm(_lw("list.indent_cm") if level == 1 else _lw("list.indent_level2_cm"))
        p.paragraph_format.first_line_indent = Cm(-_lw("list.hanging_cm"))
        p.paragraph_format.space_after = Pt(_lw("list.space_after_pt"))
        _set_line_spacing_at_least(p, WORD_PARAGRAPH["list_line_pt"])
        body = safe_text(text)
        if ordered:
            prefix = "" if _AUTHORED_NUMBER_PREFIX.match(body) else f"{position}. "
        else:
            prefix = "" if body.lstrip().startswith(("•", "·", "・")) else "• "
        p.add_run(prefix + body)


def _normalize_widths(headers: list[str], requested: list[float] | None,
                      total: float = PORTRAIT_BODY_CM,
                      rows: list | None = None,
                      density: str = "regular") -> list[float]:
    """列宽分配。显式声明优先；否则按内容驱动计算。

    历史实现仅按表头字数做 sqrt 启发式（「编号」2字→1.41 vs
    「本项目应用说明」7字→2.65，权重差 1.9 倍，而真实内容需求差约 20 倍），
    导致短列虚胖、长列被挤。现改为依据表头与单元格内容的显示宽度计算。
    """
    n = max(1, len(headers))
    if requested is not None:
        if len(requested) != n:
            raise ValueError(f"显式表格列宽数量 {len(requested)} 与列数 {n} 不一致")
        try:
            declared = [float(value) for value in requested]
        except (TypeError, ValueError) as exc:
            raise ValueError("显式表格列宽必须全部为数字") from exc
        if not math.isfinite(total) or total <= 0:
            raise ValueError(f"表格可用总宽度必须为正数：{total}")
        if any(not math.isfinite(value) or value <= 0 for value in declared):
            raise ValueError(f"显式表格列宽必须全部为正数：{requested}")
        declared_total = sum(declared)
        if not math.isfinite(declared_total):
            raise ValueError(f"显式表格列宽总和无效：{requested}")
        scale = total / declared_total
        return [round(value * scale, 3) for value in declared]
    if rows:
        pad = CELL_PAD if density == "compact" else REGULAR_CELL_PAD
        return auto_widths([safe_text(h) for h in headers], rows, total, cell_pad=pad)
    # 无内容可依（仅表头）→ 等分，比表头字数启发式更可预期
    return [round(total / n, 3)] * n


def _add_table_caption(doc: Document, caption: str) -> None:
    p = doc.add_paragraph()
    clear_indent(p)
    p.paragraph_format.space_before = Pt(_lw("caption.space_before_pt"))
    p.paragraph_format.space_after = Pt(_lw("caption.space_after_pt"))
    p.paragraph_format.keep_with_next = True
    set_run_font(p.add_run(safe_text(caption)), FONT_TABLE,
                  WORD_PT["caption"], bold=True, color=INK)


def normalized_table_rows(headers: list[str], raw_rows: Any) -> list[list[Any]]:
    """Return positional rows without silently padding or truncating cells.

    Named rows may contain non-cell metadata that table hooks read, so only
    declared header keys are projected.  Positional
    rows, however, have no such distinction: a width mismatch would either
    invent a blank cell or discard a confirmed value and must fail closed.
    """

    if raw_rows in (None, []):
        return []
    if not isinstance(raw_rows, (list, tuple)):
        raise ValueError("Word 表格 rows 必须为数组")
    rows: list[list[Any]] = []
    expected = len(headers)
    for row_index, values in enumerate(raw_rows, start=1):
        if isinstance(values, dict):
            rows.append([values.get(header, "") for header in headers])
            continue
        if not isinstance(values, (list, tuple)):
            raise ValueError(f"Word 表格第{row_index}行必须为数组或命名对象")
        if len(values) != expected:
            raise ValueError(
                f"Word 表格第{row_index}行列数 {len(values)} 与列定义 {expected} 不一致"
            )
        rows.append(list(values))
    return rows


def add_named_bookmark(paragraph, name: str) -> None:
    if not name:
        return
    bookmark_id = str(int(hashlib.sha256(name.encode("utf-8")).hexdigest()[:8], 16))
    start = OxmlElement("w:bookmarkStart")
    start.set(qn("w:id"), bookmark_id)
    start.set(qn("w:name"), name)
    end = OxmlElement("w:bookmarkEnd")
    end.set(qn("w:id"), bookmark_id)
    paragraph._p.append(start)
    paragraph._p.append(end)


def money_header(header: str) -> str:
    """版面规则 amount_unit：金额列表头写明单位，单元格只放数字。"""
    suffix = _AMOUNT_UNIT.get("header_suffix", "")
    if _AMOUNT_UNIT.get("in_header") and suffix and any(m in header for m in MONEY_HEADER_MARKERS) and "元" not in header:
        return header + suffix
    return header


def _add_key_value_table(doc: Document, block: dict[str, Any]) -> None:
    """键值表（版面规则 key_value_table）：单栏，标签在左，不设表头行，只留上下两条线。"""
    pairs = []
    for row in block.get("rows") or []:
        if isinstance(row, dict):
            pairs.append((safe_text(row.get("label")), safe_text(row.get("value"))))
        else:
            pairs.append((safe_text(row[0] if row else ""), safe_text(row[1] if len(row) > 1 else "")))
    if not pairs:
        return
    if block.get("caption"):
        _add_table_caption(doc, block["caption"])
    label_cm = float((block.get("widths_cm") or [_lw("table.key_value.label_cm")])[0])
    widths = [label_cm, _current_body_width_cm(doc) - label_cm]
    table = doc.add_table(rows=len(pairs), cols=2)
    table.alignment = WD_TABLE_ALIGNMENT.LEFT
    set_table_geometry(table, widths)
    last = len(pairs) - 1
    kv_vertical = _twips(_lw("table.key_value.cell_vertical_pt"))
    kv_end = _twips(_lw("table.key_value.cell_end_pt"))
    for index, (label, value) in enumerate(pairs):
        row = table.rows[index]
        set_keep_together(row)
        for col, cell in enumerate(row.cells):
            cell.text = ""
            set_cell_width_cm(cell, widths[col])
            set_cell_margins(cell, top=kv_vertical, bottom=kv_vertical, start=0, end=kv_end)
            edges = {}
            if index == 0:
                edges["top"] = (INK, RULE["table_frame"])
            if index == last:
                edges["bottom"] = (LINE, RULE["table_row"])
            set_cell_borders(cell, **edges)
            p = cell.paragraphs[0]
            p.style = doc.styles["Table Text"]
            set_run_font(p.add_run(label if col == 0 else value), FONT_TABLE, WORD_PT["table"],
                          color=MUTED if col == 0 else INK)
            if index < last:
                ppr = p._p.get_or_add_pPr()
                if ppr.find(qn("w:keepNext")) is None:
                    set_property_child(ppr, OxmlElement("w:keepNext"))


def prepare_table_cell(context: TableRowContext, cell, col_index: int, *,
                       last_index: int | None = None):
    """清空单元格并套上表格正文的样式、内边距和竖向位置，返回首段。render_row 扩展点写单元格时用。"""
    cell.text = ""
    cell.vertical_alignment = _table_v_align()
    _set_table_cell_margins(cell, context.density)
    _set_cell_edge_margins(cell, col_index, len(context.headers), last_index=last_index)
    paragraph = cell.paragraphs[0]
    paragraph.style = context.doc.styles[_table_style_name("Table Text", context.density)]
    return paragraph


def table_row_bottom(context: TableRowContext) -> tuple[str, int]:
    """三线表的行下线：行间用分隔线色细线，末行用正文色粗线。"""
    return (INK, RULE["table_frame"]) if context.is_last else (LINE, RULE["table_row"])


def add_table(doc: Document, block: dict[str, Any]) -> None:
    if block.get("layout") == "key_value":
        _add_key_value_table(doc, block)
        return
    headers = [safe_text(value) for value in block.get("columns", block.get("headers", []))]
    if not headers:
        return
    source_rows = list(block.get("rows", []) or [])
    rows = normalized_table_rows(headers, source_rows)
    capacity = WORD_LAYOUT.get("table_capacity") if isinstance(WORD_LAYOUT.get("table_capacity"), dict) else {}
    if capacity:
        if len(headers) > int(capacity["max_columns"]):
            raise ValueError(
                f"Word 表格列数 {len(headers)} 超出版式基线容量 {capacity['max_columns']}"
            )
        hard_max_rows = int(capacity["hard_max_rows"])
        if len(rows) > hard_max_rows:
            raise ValueError(
                f"Word 表格行数 {len(rows)} 超出资源保护上限 {hard_max_rows}"
            )
    if block.get("caption"):
        _add_table_caption(doc, block["caption"])
    table = doc.add_table(rows=1, cols=len(headers))
    table.alignment = WD_TABLE_ALIGNMENT.LEFT
    _WIDTH_KEYS = ("widths_cm", "widths", "col_widths", "column_widths")
    _requested = None
    for _key in _WIDTH_KEYS:
        if block.get(_key):
            _requested = block[_key]
            break
    else:
        # 疑似宽度键但拼写不匹配 → 显式失败。静默忽略会导致整篇列宽失控且无人察觉。
        _suspect = [k for k in block if "width" in str(k).lower() and k not in _WIDTH_KEYS]
        if _suspect:
            raise ValueError(
                f"表格「{safe_text(block.get('caption', ''))}」使用了未识别的宽度键 {_suspect}；"
                f"请改用 {_WIDTH_KEYS[0]}。"
            )
    density = _table_density(block)
    marks = table_marks(block, headers)
    widths = _normalize_widths(
        _decorated_headers(headers, marks), _requested, _current_body_width_cm(doc),
        rows=_decorated_rows(rows, marks), density=density,
    )
    for hooks in _TABLE_HOOKS.values():
        if hooks.adjust_widths is not None:
            hooks.adjust_widths(headers, widths)
    set_table_geometry(table, widths)

    def alignment_for(col: int) -> str | None:
        declared = block.get("alignments", [])
        if col < len(declared) and declared[col]:
            return declared[col]
        if any(marker in headers[col] for marker in MONEY_HEADER_MARKERS):
            return "right"
        return None

    for index, value in enumerate(headers):
        cell = table.rows[0].cells[index]
        cell.text = ""
        cell.vertical_alignment = _table_v_align()
        _set_table_cell_margins(cell, density)
        p = cell.paragraphs[0]
        p.style = doc.styles[_table_style_name("Table Header", density)]
        if alignment_for(index) == "right":
            p.alignment = WD_ALIGN_PARAGRAPH.RIGHT
        if marks["party_header"]:
            _add_party_dot(p, value, size=WORD_PT["table_header"])
        p.add_run(money_header(value))
        _set_cell_edge_margins(cell, index, len(headers))
        set_cell_borders(cell, top=(INK, RULE["table_frame"]), bottom=(INK, RULE["table_header_bottom"]))
    _repeat_header(table.rows[0])

    for row_index, values in enumerate(rows):
        row = table.add_row()
        set_keep_together(row)
        source_row = source_rows[row_index] if row_index < len(source_rows) else None
        is_last_row = row_index == len(rows) - 1
        context = TableRowContext(
            doc=doc, table=table, row=row, headers=headers, widths=widths, density=density,
            index=row_index, values=values, source=source_row, is_last=is_last_row,
        )
        rendered_cells = None
        for hooks in _TABLE_HOOKS.values():
            if hooks.render_row is not None:
                rendered_cells = hooks.render_row(context)
                if rendered_cells is not None:
                    break
        if rendered_cells is None:
            rendered_cells = [
                (cell, values[index] if index < len(values) else "", index)
                for index, cell in enumerate(row.cells)
            ]
            for cell, value, col_index in rendered_cells:
                p = prepare_table_cell(context, cell, col_index)
                alignment = alignment_for(col_index)
                if alignment == "center":
                    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
                elif alignment == "right":
                    p.alignment = WD_ALIGN_PARAGRAPH.RIGHT
                else:
                    p.alignment = WD_ALIGN_PARAGRAPH.LEFT
                is_money_column = col_index < len(headers) and any(
                    marker in headers[col_index] for marker in MONEY_HEADER_MARKERS
                )
                cell_text = display_money(value) if is_money_column else display_value(value)
                mark = marks["columns"].get(col_index)
                if mark and _write_marked_cell(p, cell_text, mark):
                    pass
                elif REQUIRED_MARK in cell_text:
                    _add_marked_runs(p, cell_text)
                else:
                    p.add_run(cell_text)
                set_cell_borders(cell, bottom=table_row_bottom(context))
        if source_row is not None:
            for hooks in _TABLE_HOOKS.values():
                if hooks.after_row is not None:
                    hooks.after_row(headers, rendered_cells, source_row)

    for hooks in _TABLE_HOOKS.values():
        if hooks.after_table is not None:
            hooks.after_table(table, headers, source_rows, density)

    if len(table.rows) <= _KEEP_SMALL_TABLE_ROWS:
        # 版面规则 keep_small_tables（W3C《中文排版需求》孤行规则）：小表整表同页，末行不单独落到下一页。
        for row in table.rows[:-1]:
            for paragraph in row._tr.iter(qn("w:p")):
                ppr = paragraph.get_or_add_pPr()
                if ppr.find(qn("w:keepNext")) is None:
                    set_property_child(ppr, OxmlElement("w:keepNext"))

    if block.get("note"):
        p = doc.add_paragraph(style="Quote Note")
        p.paragraph_format.space_before = Pt(_lw("notes.block_note_space_before_pt"))
        p.paragraph_format.space_after = Pt(_lw("notes.block_note_space_after_pt"))
        p.add_run(safe_text(block["note"]))


SVG_BLIP_URI = "{96DAC541-7B7A-43D3-8B79-37D633B846F1}"
SVG_NS = "http://schemas.microsoft.com/office/drawing/2016/SVG/main"


def _attach_svg(doc: Document, shape, svg_bytes: bytes) -> None:
    """在 PNG 图片上挂接 SVG：Word 2016 及以后显示矢量图，其余软件显示 PNG。"""
    from docx.opc.constants import RELATIONSHIP_TYPE as RT
    from docx.opc.part import Part

    package = doc.part.package
    partname = package.next_partname("/word/media/image%d.svg")
    svg_part = Part(partname, "image/svg+xml", svg_bytes, package)
    rel_id = doc.part.relate_to(svg_part, RT.IMAGE)
    blip = shape._inline.graphic.graphicData.pic.blipFill.blip
    ext_lst = OxmlElement("a:extLst")
    ext = OxmlElement("a:ext")
    ext.set("uri", SVG_BLIP_URI)
    svg_blip = etree.SubElement(ext, f"{{{SVG_NS}}}svgBlip", nsmap={"asvg": SVG_NS})
    svg_blip.set(qn("r:embed"), rel_id)
    ext_lst.append(ext)
    blip.append(ext_lst)


def _svg_figure_assets(block: dict[str, Any], base_dir: Path) -> tuple[bytes, Path] | None:
    """读取 SVG，转成自带样式的独立 SVG，并找到或生成 PNG 备用图。"""
    raw = Path(safe_text(block.get("svg")))
    svg_path = raw if raw.is_absolute() else base_dir / raw
    if not svg_path.is_file():
        return None
    svg_text = svg_path.read_text("utf-8")
    if _SVG_STYLER is not None:
        svg_text = _SVG_STYLER(svg_text, STYLE)
    fallback = block.get("path")
    if fallback:
        png = Path(fallback) if Path(fallback).is_absolute() else base_dir / fallback
    else:
        png = svg_path.with_suffix(".png")
    if not png.is_file():
        if _SVG_RASTERIZER is None:
            raise RuntimeError("没有 PNG 备用图，调用方也没有用 set_svg_rasterizer 传入 SVG 转 PNG 的函数")
        work = Path(tempfile.mkdtemp(prefix="aham-svg-"))
        source = work / svg_path.name
        source.write_text(svg_text, "utf-8")
        png = _SVG_RASTERIZER(source, work / f"{svg_path.stem}.png")
        if png is None:
            return None
    return svg_text.encode("utf-8"), png


def _add_figure(doc: Document, block: dict[str, Any], base_dir: Path) -> None:
    svg_assets = None
    if block.get("svg"):
        svg_assets = _svg_figure_assets(block, base_dir)
        if svg_assets is None:
            add_lead(doc, "配图状态", "［待补充］未找到流程图 SVG 或无法生成 PNG 备用图，正式对客前需补齐或移除该图。", color=LINE)
            return
    paths = [svg_assets[1]] if svg_assets else (block.get("paths") or [block.get("path")])
    paths = [Path(path) if Path(path).is_absolute() else base_dir / path for path in paths if path]
    paths = [path for path in paths if path.exists()]
    if not paths:
        add_lead(doc, "配图状态", "［待补充］未找到指定图片，正式对客前需补齐或移除该图。", color=LINE)
        return

    if len(paths) == 1:
        p = doc.add_paragraph()
        clear_indent(p)
        p.alignment = WD_ALIGN_PARAGRAPH.LEFT
        p.paragraph_format.space_before = Pt(_lw("figure.space_before_pt"))
        p.paragraph_format.space_after = Pt(_lw("figure.space_after_pt"))
        body_width = _current_body_width_cm(doc)
        width = min(float(block.get("width_cm", body_width - _lw("figure.width_inset_cm"))), body_width)
        shape = p.add_run().add_picture(str(paths[0]), width=Cm(width))
        shape._inline.docPr.set("title", safe_text(block.get("caption", paths[0].stem)))
        shape._inline.docPr.set("descr", safe_text(block.get("alt", block.get("caption", paths[0].stem))))
        if svg_assets:
            _attach_svg(doc, shape, svg_assets[0])
    else:
        table = doc.add_table(rows=1, cols=len(paths))
        table.alignment = WD_TABLE_ALIGNMENT.CENTER
        body_width = _current_body_width_cm(doc)
        widths = [body_width / len(paths)] * len(paths)
        set_table_geometry(table, widths)
        for idx, path in enumerate(paths):
            cell = table.rows[0].cells[idx]
            gallery_margin = _twips(_lw("figure.gallery_cell_margin_pt"))
            set_cell_margins(cell, top=gallery_margin, start=gallery_margin, bottom=gallery_margin, end=gallery_margin)
            set_cell_borders(cell)
            p = cell.paragraphs[0]
            clear_indent(p)
            p.alignment = WD_ALIGN_PARAGRAPH.CENTER
            shape = p.add_run().add_picture(str(path), width=Cm(widths[idx] - _lw("figure.gallery_image_inset_cm")))
            shape._inline.docPr.set("title", path.stem)
            shape._inline.docPr.set("descr", safe_text(block.get("alt", path.stem)))

    # 图题注放在图下方居左，用次要色；来源另起一行用淡化色。
    caption = doc.add_paragraph()
    clear_indent(caption)
    caption.alignment = WD_ALIGN_PARAGRAPH.LEFT
    caption.paragraph_format.space_after = Pt(_lw("figure.caption_space_after_pt"))
    set_run_font(caption.add_run(safe_text(block.get("caption", "项目配图"))),
                  FONT_BODY, WORD_PT["caption"], color=MUTED)
    source = doc.add_paragraph()
    clear_indent(source)
    source.alignment = WD_ALIGN_PARAGRAPH.LEFT
    source.paragraph_format.space_after = Pt(_lw("figure.source_space_after_pt"))
    set_run_font(source.add_run(safe_text(block.get("source", "来源：项目资料；状态：待核验"))),
                  FONT_BODY, WORD_PT["caption"], color=FAINT)


def swimlane_steps(block: dict[str, Any]) -> list[tuple[int, str, str]]:
    """泳道步骤：[执行方, 角色, 操作]，执行方可写别名。返回 (参与方序号, 角色, 操作)。"""
    steps = []
    for index, item in enumerate(block.get("steps") or [], start=1):
        if isinstance(item, dict):
            party, role, text = item.get("party"), item.get("role", ""), item.get("text", "")
        elif isinstance(item, (list, tuple)) and len(item) == 3:
            party, role, text = item
        else:
            raise ValueError(f"泳道图第 {index} 步要写 [执行方, 角色, 操作]")
        lane = _PARTIES.get(safe_text(party).strip())
        if not lane:
            raise ValueError(f"泳道图第 {index} 步的执行方「{party}」没有在 parties 里登记")
        steps.append((lane, safe_text(role), safe_text(text)))
    if not steps:
        raise ValueError("泳道图没有步骤")
    return steps


def lane_names() -> list[tuple[int, str]]:
    names: dict[int, str] = {}
    for name, index in _PARTIES.items():
        names.setdefault(index, name)
    return sorted(names.items())


def _add_swimlane(doc: Document, block: dict[str, Any]) -> None:
    """泳道图：每条泳道一个参与方，每列一步。"""
    steps = swimlane_steps(block)
    lanes = [(index, name) for index, name in lane_names() if index not in _NO_LANE]
    body = _current_body_width_cm(doc)
    landscape = body > PORTRAIT_BODY_CM + 1
    limit = int(_lw("swimlane.max_steps_portrait")) * (2 if landscape else 1)
    label_cm = _lw("swimlane.label_cm")
    gap_cm = _lw("swimlane.gap_cm")
    box_rule = int(_lw("swimlane.box_rule"))
    head_vertical = _twips(_lw("swimlane.header_cell_vertical_pt"))
    lane_vertical = _twips(_lw("swimlane.cell_vertical_pt"))
    lane_side = _twips(_lw("swimlane.cell_side_pt"))
    box_vertical = _twips(_lw("swimlane.box_vertical_pt"))
    box_side = _twips(_lw("swimlane.box_side_pt"))
    size = WORD_PT["swimlane"]
    chunks = [steps[start:start + limit] for start in range(0, len(steps), limit)]
    caption = safe_text(block.get("caption"))
    for chunk_index, chunk in enumerate(chunks):
        first_step = chunk_index * limit
        if caption:
            _add_table_caption(doc, caption + ("（续）" if chunk_index else ""))
        n = len(chunk)
        step_cm = (body - label_cm - gap_cm * n) / n
        widths = [label_cm] + [w for _ in range(n) for w in (gap_cm, step_cm)]
        table = doc.add_table(rows=1 + len(lanes), cols=len(widths))
        set_table_geometry(table, widths)
        for row_index, row in enumerate(table.rows):
            trpr = row._tr.get_or_add_trPr()
            if trpr.find(qn("w:cantSplit")) is None:
                set_property_child(trpr, OxmlElement("w:cantSplit"))
            lane = lanes[row_index - 1] if row_index else None
            tinted = bool(lane) and row_index % 2 == 0
            last = row_index == len(lanes)
            for col_index, cell in enumerate(row.cells):
                cell.text = ""
                set_cell_width_cm(cell, widths[col_index])
                vertical = lane_vertical if row_index else head_vertical
                set_cell_margins(cell, top=vertical, bottom=vertical,
                                  start=0 if col_index == 0 else lane_side, end=lane_side)
                cell.vertical_alignment = WD_ALIGN_VERTICAL.CENTER
                if row_index == 0:
                    bottom = (INK, RULE["table_header_bottom"])
                else:
                    bottom = (INK, RULE["table_frame"]) if last else (LINE, RULE["table_row"])
                set_cell_borders(cell, bottom=bottom)
                if tinted:
                    set_cell_fill(cell, TINT)
                p = cell.paragraphs[0]
                p.style = doc.styles["Table Text"]
                if row_index == 0:
                    if col_index and col_index % 2 == 0:
                        number = first_step + col_index // 2
                        set_run_font(p.add_run(f"{number:02d}"), FONT_TABLE, size, color=MUTED)
                    continue
                if col_index == 0:
                    _add_party_dot(p, lane[1], size=WORD_PT["table"])
                    set_run_font(p.add_run(lane[1]), FONT_TABLE, WORD_PT["table"], bold=True, color=INK)
                    continue
                if col_index % 2 == 1:
                    continue
                party, role, text = chunk[col_index // 2 - 1]
                if party != lane[0]:
                    continue
                color = STYLE["categorical"][f"party_{party}"]
                box = cell.add_table(rows=1, cols=1)
                set_table_geometry(box, [widths[col_index] - _lw("swimlane.box_inset_cm")])
                inner = box.rows[0].cells[0]
                set_cell_margins(inner, top=box_vertical, bottom=box_vertical, start=box_side, end=box_side)
                edge = (color, box_rule)
                set_cell_borders(inner, top=edge, bottom=edge, start=edge, end=edge)
                set_cell_fill(inner, WHITE)
                first = inner.paragraphs[0]
                # 框内文字字号小，用紧凑版行距。
                first.style = doc.styles["Table Text Compact"]
                if role:
                    set_run_font(first.add_run(role), FONT_TABLE, size, bold=True, color=color)
                    text_p = inner.add_paragraph(style="Table Text Compact")
                else:
                    text_p = first
                set_run_font(text_p.add_run(text), FONT_TABLE, size, color=INK)
                # 单元格首段在嵌套表之前，留着会多出一行空白；末段是 Word 要求的收尾段，压到最小。
                cell._tc.remove(p._p)
                tail = cell.paragraphs[-1]
                tail.style = doc.styles["Table Text"]
                tail.paragraph_format.line_spacing = Pt(_lw("swimlane.tail_line_pt"))
        # 泳道图不拆页：除末行外每段都与下一段同页，表头跨页重复。
        _repeat_header(table.rows[0])
        for row in table.rows[:-1]:
            for paragraph in row._tr.iter(qn("w:p")):
                ppr = paragraph.get_or_add_pPr()
                if ppr.find(qn("w:keepNext")) is None:
                    set_property_child(ppr, OxmlElement("w:keepNext"))
    if block.get("note"):
        note = doc.add_paragraph(style="Quote Note")
        note.paragraph_format.space_before = Pt(_lw("notes.block_note_space_before_pt"))
        note.paragraph_format.space_after = Pt(_lw("notes.block_note_space_after_pt"))
        note.add_run(safe_text(block["note"]))


def _add_quote(doc: Document, block: dict[str, Any]) -> None:
    p = doc.add_paragraph()
    clear_indent(p)
    p.paragraph_format.left_indent = Cm(_lw("quote.indent_left_cm"))
    p.paragraph_format.right_indent = Cm(_lw("quote.indent_right_cm"))
    p.paragraph_format.space_before = Pt(_lw("quote.space_before_pt"))
    p.paragraph_format.space_after = Pt(_lw("quote.space_after_pt"))
    _set_line_spacing_at_least(p, WORD_PARAGRAPH["body_line_pt"])
    _paragraph_border(p, side="left", color=ACCENT, size=RULE["quote_left"], space=_lw("quote.rule_space_pt"))
    text = f"“{safe_text(block.get('text', ''))}”"
    set_run_font(p.add_run(text), FONT_BODY, WORD_PT["body"], color=INK)
    attribution = "｜".join(filter(None, [
        safe_text(block.get("speaker", "")),
        safe_text(block.get("timestamp", "")),
        safe_text(block.get("source_id", "")),
    ]))
    if attribution:
        p2 = doc.add_paragraph()
        clear_indent(p2)
        p2.alignment = WD_ALIGN_PARAGRAPH.RIGHT
        p2.paragraph_format.space_after = Pt(_lw("quote.attribution_space_after_pt"))
        set_run_font(p2.add_run(attribution), FONT_BODY, WORD_PT["caption"], color=MUTED)


def _add_notes(doc: Document, block: dict[str, Any], *, table_note: bool = False) -> None:
    """Render a notes block as a numbered, hanging-indent list.

    ``Quote Note`` is 8.5pt — the size of a table footnote.  It belongs to notes
    that qualify the table right above them.  A standalone notes block (an
    appendix's 术语说明, a closing caveat) is ordinary prose and must read at body
    weight, otherwise a whole appendix ends up set in caption grey.

    每条说明是一条独立条款，读者要能按号引用，所以三件事必须同时成立：行首排
    序号、冒号前的标签加粗、回行悬挂缩进到正文左边界。缺任何一条，六七条并
    列的说明就读成一段连续文字。正文颜色用 ``INK`` 而不是 ``MUTED``：脚注灰是
    给一句话的表注用的，用在整块商务条款上会把可读性压到最低。

    序号是字面前缀，不是 Word 自动编号——理由见 :func:`notes.note_ordinal_prefix`。
    逐条比对说明文字时，先用 :func:`notes.strip_note_ordinal` 去掉序号再比。
    """
    items = [safe_text(value).strip() for value in block.get("items", [])]
    items = [value for value in items if value]
    if not items:
        return
    title = doc.add_paragraph()
    clear_indent(title)
    title.paragraph_format.space_before = Pt(_lw("notes.title_space_before_pt"))
    title.paragraph_format.space_after = Pt(_lw("notes.title_space_after_pt"))
    title.paragraph_format.keep_with_next = True
    set_run_font(
        title.add_run(safe_text(block.get("title") or "说明")),
        FONT_BODY, WORD_PT["body"], bold=True, color=INK,
    )
    is_table_note = bool(block.get("table_note", table_note))
    size = WORD_PT["caption"] if is_table_note else WORD_PT["body"]
    hang = Cm(_lw("notes.hanging_cm"))
    for index, value in enumerate(items, start=1):
        paragraph = doc.add_paragraph(style="Quote Note" if is_table_note else "Normal")
        paragraph_format = paragraph.paragraph_format
        paragraph_format.left_indent = hang
        paragraph_format.first_line_indent = -hang
        paragraph_format.space_before = Pt(0)
        paragraph_format.space_after = Pt(_lw("notes.space_after_pt"))
        paragraph_format.keep_together = True
        # 序号用标题字体槽：阿拉伯数字走 ascii 那一路，全角空格走 eastAsia 那一路。
        set_run_font(
            paragraph.add_run(note_ordinal_prefix(index)),
            FONT_HEADING, size, bold=True, color=INK,
        )
        label, body = split_note_label(value)
        if label:
            set_run_font(paragraph.add_run(label), FONT_HEADING, size, bold=True, color=INK)
        set_run_font(paragraph.add_run(body), FONT_BODY, size, color=INK)


def render_block(doc: Document, block: dict[str, Any], base_dir: Path,
                  previous_kind: str = "") -> None:
    kind = safe_text(block.get("type", "paragraph")).lower()
    if kind in {"paragraph", "text"}:
        before = len(doc.paragraphs)
        add_body(doc, block.get("text", ""), indent=bool(block.get("indent", True)),
                  bold_prefix=block.get("bold_prefix"))
        if previous_kind == "table" and len(doc.paragraphs) > before:
            # 表格下框线与紧随的正文之间留出段前距，避免正文贴住粗线。
            doc.paragraphs[before].paragraph_format.space_before = Pt(_lw("paragraph.after_table_space_before_pt"))
    elif kind in {"lead", "callout"}:
        # tone=risk：需客户决策的风险提示；tone=key：必须遵守的处理规则。
        # 两者上线与标签都用重点色，其余提示条用主色。
        tone = safe_text(block.get("tone", "")).lower()
        if tone == "risk":
            add_lead(doc, block.get("label", "风险提示"), block.get("text", ""), tone="risk")
        elif tone in {"key", "rule"}:
            add_lead(doc, block.get("label", "规则"), block.get("text", ""), tone="key")
        else:
            add_lead(doc, block.get("label", "说明"), block.get("text", ""))
    elif kind in {"bullets", "list"}:
        add_list(
            doc,
            block.get("items", []),
            ordered=bool(block.get("ordered", False)),
            start=int(block.get("start", 1) or 1),
        )
    elif kind == "table":
        add_table(doc, block)
    elif kind in {"figure", "image", "gallery", "svg"}:
        if kind == "svg" and not block.get("svg"):
            block = {**block, "svg": block.get("path"), "path": block.get("png")}
        _add_figure(doc, block, base_dir)
    elif kind == "swimlane":
        _add_swimlane(doc, block)
    elif kind == "quote":
        _add_quote(doc, block)
    elif kind == "notes":
        _add_notes(doc, block, table_note=previous_kind == "table")
    elif kind == "subheading":
        add_heading(
            doc,
            display_heading(block),
            int(block.get("_resolved_level") or block.get("level", 2)),
        )
    elif kind == "page_break":
        _add_page_break(doc)
    elif kind == "spacer":
        _add_spacer(doc, float(block.get("points", _lw("paragraph.spacer_default_pt"))))
    elif kind in _BLOCK_RENDERERS:
        _BLOCK_RENDERERS[kind](doc, block, base_dir, previous_kind)
    else:
        add_body(doc, f"［待补充］未识别的内容块类型：{kind}", indent=False)


def normalize_formal_numbering(path: Path) -> None:
    """Remove the Symbol-font bullet definition bundled by python-docx.

    Formal lists use literal U+2022, but leaving the unused U+F0B7/Symbol
    numbering definition in OOXML makes cross-host font inspection ambiguous.

    The edit is a surgical text substitution rather than a parse/serialize
    round-trip.  Re-serializing with ElementTree drops namespace declarations
    that the root only declares for Markup Compatibility (w14, wp14, ...)
    while keeping ``mc:Ignorable`` pointing at them.  A ``mc:Ignorable`` prefix
    with no in-scope binding is an MCE violation, and Word rejects the whole
    part with "unreadable content".
    """
    with zipfile.ZipFile(path, "r") as source:
        names = source.namelist()
        payloads = {name: source.read(name) for name in names}
    numbering = payloads.get("word/numbering.xml")
    if numbering is not None:
        text = numbering.decode("utf-8")
        namespace = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
        match = re.search(r'xmlns:([A-Za-z0-9_]+)="%s"' % re.escape(namespace), text)
        prefix = match.group(1) if match else "w"

        def rewrite_fonts(hit: re.Match[str]) -> str:
            attrs = hit.group(2)
            attrs = re.sub(r'\s+[A-Za-z0-9_]+:(?:[A-Za-z]+Theme|cstheme)="[^"]*"', "", attrs)
            for slot in ("ascii", "hAnsi", "eastAsia", "cs"):
                pattern = r'\s%s:%s="[^"]*"' % (re.escape(prefix), slot)
                family = FONT_BODY if slot == "eastAsia" else FONT_LATIN
                replacement = ' %s:%s="%s"' % (prefix, slot, family)
                attrs = re.sub(pattern, replacement, attrs) if re.search(pattern, attrs) else attrs + replacement
            return "<%s:rFonts%s/>" % (prefix, attrs)

        text = re.sub(r"<(%s):rFonts((?:\s[^/>]*)?)/>" % re.escape(prefix), rewrite_fonts, text)
        text = re.sub(
            r'(<%s:lvlText\s[^>]*?%s:val=")([^"]*)(")' % (re.escape(prefix), re.escape(prefix)),
            lambda hit: hit.group(1) + hit.group(2).replace("\uf0b7", "\u2022") + hit.group(3),
            text,
        )
        if "Symbol" in text or "\uf0b7" in text:
            raise ValueError("Word numbering 仍包含 Symbol 字体")
        payloads["word/numbering.xml"] = text.encode("utf-8")
        with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as target:
            for name in names:
                target.writestr(name, payloads[name])

