"""网页样式：把 tokens.json 的文档取值视图转成 CSS 变量，拼上组件样式 web/base.css。

base.css 只引用这里生成的变量，不写色值和字号。网页渲染器 html 和流程图转换都用这份转换。
"""

from __future__ import annotations

import re
from pathlib import Path
from typing import Any

from .tokens import document_style

__all__ = ["BASE_CSS_PATH", "BEHAVIOR_JS_PATH", "behavior_js", "standalone_svg", "stylesheet", "tokens_css"]

WEB = Path(__file__).resolve().parent / "web"
BASE_CSS_PATH = WEB / "base.css"
BEHAVIOR_JS_PATH = WEB / "behavior.js"

# 字号变量名 → size.web 的键。base.css 只用这些变量写字号。
_FONT_SIZES = {
    "fs-title": "document_title", "fs-title-phone": "document_title_phone", "fs-lede": "lede",
    "fs-h1": "h1", "fs-h2": "h2", "fs-h3": "h3", "fs-body": "body", "fs-table": "table",
    "fs-th": "table_header", "fs-caption": "caption", "fs-note": "note", "fs-label": "label",
    "fs-key": "key_value", "fs-control": "control", "fs-compact": "compact", "fs-callout": "callout",
    "fs-tag": "tag", "fs-mini": "mini", "fs-anatomy": "anatomy", "fs-anatomy-phone": "anatomy_phone",
    "fs-svg-title": "svg_title", "fs-svg-label": "svg_label", "fs-svg-small": "svg_small", "fs-svg-tiny": "svg_tiny",
}
# 线宽变量名 → line.web 的键。
_RULES = {
    "rule-chapter": "chapter_top", "rule-frame": "table_frame", "rule-header": "table_header_bottom",
    "rule-row": "table_row", "rule-total": "total_top", "rule-callout": "callout_top",
    "rule-callout-bottom": "callout_bottom", "rule-quote": "quote_left", "rule-key": "key_figure_top",
}
# 版面变量名 → (layout.web 的键, 单位)。
_LAYOUT = {
    "page-max": ("page_max_px", "px"), "measure": ("measure_em", "em"), "gutter": ("gutter_px", "px"),
    "gutter-phone": ("gutter_phone_px", "px"), "chapter-gap": ("chapter_gap_px", "px"),
    "aside": ("aside_px", "px"), "radius": ("radius_px", "px"),
}
_MEDIA_PHONE = "{{phone_breakpoint_px}}"


def _style(style: dict[str, Any] | None) -> dict[str, Any]:
    return style if style is not None else document_style()


def behavior_js() -> str:
    return BEHAVIOR_JS_PATH.read_text("utf-8")


def tokens_css(style: dict[str, Any] | None = None) -> str:
    """:root 取值块。颜色、字体、字号、字重、线宽、版面和圆角都来自 tokens.json。"""
    s = _style(style)
    px = s["web_px"]
    rules = s["rules"]["web_px"]
    web = s["web"]
    weights = s["fonts"]["web_weights"]
    lines = [
        *(f"--{name.replace('_', '-')}:#{value};" for name, value in s["colors"].items()),
        *(f"--party-{name.split('_')[1]}:#{value};" for name, value in s["categorical"].items()),
        f"--font-stack:{s['fonts']['web_stack']};",
        f"--font-code:{s['fonts']['code_stack']};",
        *(f"--{var}:{px[key]}px;" for var, key in _FONT_SIZES.items()),
        f"--fw-heading:{weights['heading']};",
        f"--fw-strong:{weights['strong']};",
        f"--fw-row-label:{weights['row_label']};",
        *(f"--{var}:{rules[key]}px;" for var, key in _RULES.items()),
        *(f"--{var}:{web[key]}{unit};" for var, (key, unit) in _LAYOUT.items()),
        f"--radius-pill:{s['radius']['pill']}px;",
        "color-scheme:light;",
    ]
    body = "\n  ".join(lines)
    return (
        "/* 由 tokens.json 生成，不手改。文档类网页只有浅色一种，与纸面文件一致。 */\n"
        f":root{{\n  {body}\n}}\n"
    )


def _base_css(style: dict[str, Any]) -> str:
    return BASE_CSS_PATH.read_text("utf-8").replace(_MEDIA_PHONE, str(style["web"]["phone_breakpoint_px"]))


def stylesheet(style: dict[str, Any] | None = None, extra: str = "") -> str:
    """完整样式表：取值块、组件样式，再接调用方登记的样式。"""
    s = _style(style)
    return tokens_css(s) + _base_css(s) + extra


_VAR = re.compile(r"var\(--([a-z0-9-]+)\)")


def _variables(style: dict[str, Any]) -> dict[str, str]:
    """:root 里的变量名 → 取值，供独立 SVG 把 var() 换成字面值。"""
    return dict(re.findall(r"--([a-z0-9-]+):([^;]+);", tokens_css(style)))


def standalone_svg(svg: str, style: dict[str, Any] | None = None, scoped: bool = False) -> str:
    """把用 .flow 类名画的流程图转成自带样式的 SVG。

    网页里流程图的颜色和字号由 base.css 的 .flow 规则给出。Word 和其他软件单独显示 SVG 时读不到这些规则，
    也不一定支持 CSS 变量，所以把规则抄进 SVG 自己的 <style>，并把 var() 换成字面值。
    没有 width/height 时按 viewBox 补上，便于转 PNG。

    scoped=True 用于把 SVG 内联进 HTML 页面：规则保留 .flow 前缀，<svg> 加 flow 类，
    样式只作用于图内，不会命中页面里同名的类。
    """
    s = _style(style)
    values = _variables(s)
    rules = []
    for line in _base_css(s).splitlines():
        for selector, body in re.findall(r"\.flow (\.[a-z0-9-]+|text)\{([^}]*)\}", line):
            prefix = ".flow " if scoped else ""
            rules.append(f"{prefix}{selector}{{{_VAR.sub(lambda m: values.get(m.group(1), m.group(0)), body)}}}")
    css = "<style>" + "".join(rules) + "</style>"
    match = re.search(r"<svg\b[^>]*>", svg)
    if not match:
        raise ValueError("不是 SVG 文件：缺少 <svg> 标签")
    tag = match.group(0)
    if scoped:
        cls = re.search(r'\sclass="([^"]*)"', tag)
        if cls:
            if "flow" not in cls.group(1).split():
                tag = tag.replace(cls.group(0), f' class="{cls.group(1)} flow"', 1)
        else:
            tag = tag[:-1] + ' class="flow">'
    if 'xmlns="' not in tag:
        tag = tag[:-1] + ' xmlns="http://www.w3.org/2000/svg">'
    if " width=" not in tag:
        box = re.search(r'viewBox="\s*[-\d.]+[\s,]+[-\d.]+[\s,]+([\d.]+)[\s,]+([\d.]+)', tag)
        if box:
            tag = tag[:-1] + f' width="{box.group(1)}" height="{box.group(2)}">'
    return svg[:match.start()] + tag + css + svg[match.end():]
