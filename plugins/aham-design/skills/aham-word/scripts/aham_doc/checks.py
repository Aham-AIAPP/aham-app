"""网页审计：检查色值、字体、外部资源、荧光标记、风险条、用词和标题。

渲染器已在生成时执行能判定的规则，本模块只核对渲染器保证不了的部分，并作为最后一道防线。
检查分两组：audit_layout 查版式（页面标题、色值、字体、外部资源、图片、荧光标记、风险条），
audit_wording 查文字（禁用词、问句标题、文首工具条页尾的流程用词）。audit 依次运行两组。
色值和字体以 tokens.json 为准，上限读 layout.web.highlight_per_chapter_max 和 layout.limits.risk_callouts_per_document，
用词读技能的 config/writing-rules.json。

用法：python3 scripts/audit_html.py 网页.html
全部通过时退出码为 0；任一项失败时逐条打印并以 1 退出。
"""

from __future__ import annotations

import re
import sys
from html.parser import HTMLParser
from pathlib import Path
from typing import Any

from .paths import writing_rules
from .tokens import document_style

__all__ = ["Outline", "audit", "audit_layout", "audit_wording", "main"]


class Outline(HTMLParser):
    """收集可见文字、标题、图片、章节和门面区块。"""

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.stack: list[tuple[str, dict]] = []
        self.text: list[str] = []
        self.headings: list[str] = []
        self.images: list[str] = []
        self.chapters: list[dict] = []
        self.chrome: list[str] = []
        self.risks = 0
        self._heading: list[str] | None = None
        self._skip = 0

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        cls = (a.get("class", "") or "").split()
        if tag in {"script", "style"}:
            self._skip += 1
        if tag in {"h1", "h2", "h3", "h4", "summary"}:
            self._heading = []
        if tag == "img":
            self.images.append(a.get("src", ""))
        if tag == "section" and "ch" in cls:
            self.chapters.append({"id": a.get("id", ""), "marks": 0})
        if tag == "mark" and self.chapters:
            self.chapters[-1]["marks"] += 1
        if "risk" in cls and ("callout" in cls or "rule" in cls):
            self.risks += 1
        chrome = tag in {"header", "footer"} or "head" in cls
        self.stack.append((tag, {"chrome": chrome}))

    def handle_endtag(self, tag):
        if tag in {"script", "style"}:
            self._skip = max(0, self._skip - 1)
        if tag in {"h1", "h2", "h3", "h4", "summary"} and self._heading is not None:
            self.headings.append("".join(self._heading).strip())
            self._heading = None
        while self.stack:
            t, _ = self.stack.pop()
            if t == tag:
                break

    def handle_data(self, data):
        if self._skip:
            return
        self.text.append(data)
        if self._heading is not None:
            self._heading.append(data)
        if any(info["chrome"] for _, info in self.stack):
            self.chrome.append(data)


def audit(path: Path, style: dict[str, Any] | None = None) -> list[str]:
    page = Path(path).read_text("utf-8")
    outline = Outline()
    outline.feed(page)
    return audit_layout(page, outline, style) + audit_wording(outline)


def _font_stacks(style: dict[str, Any]) -> set[str]:
    fonts = style["fonts"]
    return {re.sub(r"\s+", "", fonts["web_stack"]), re.sub(r"\s+", "", fonts["code_stack"])}


def audit_layout(page: str, outline: Outline, style: dict[str, Any] | None = None) -> list[str]:
    """版式检查：页面标题、色值、字体、外部资源、打印按钮、图片内嵌、荧光标记和风险条数量。"""
    style = style or document_style()
    errors: list[str] = []
    if not re.search(r"<title>[^<]+</title>", page):
        errors.append("缺少页面标题 <title>")

    # 色值只能出现在由 tokens.json 生成的 :root 取值块里。
    root_block = re.search(r":root\{[^}]*\}", page)
    rest = page.replace(root_block.group(0), "", 1) if root_block else page
    rest = re.sub(r"data:[a-z/+.-]+;base64,[A-Za-z0-9+/=]+", "", rest)
    stray = sorted(set(re.findall(r"#[0-9A-Fa-f]{6}\b|#[0-9A-Fa-f]{3}\b(?![0-9A-Za-z-])", rest)))
    stray = [s for s in stray if not re.fullmatch(r"#(c\d+|s\d+|q\d+)", s)]
    if stray:
        errors.append("页面写了取值表以外的色值：" + "、".join(stray[:8]))
    allowed = {v.upper() for group in ("colors", "categorical") for v in style[group].values()}
    if root_block:
        for value in re.findall(r"#([0-9A-Fa-f]{6})\b", root_block.group(0)):
            if value.upper() not in allowed:
                errors.append(f":root 里的色值 {value} 不在 tokens.json 的文档颜色里")

    # 字体只能是 tokens.json 的网页字体栈和代码字体栈，或者引用它们的变量。
    stacks = _font_stacks(style)
    for declared in re.findall(r"font-family\s*:\s*([^;}]+)", page):
        compact = re.sub(r"\s+", "", declared)
        if compact in stacks or compact in {"inherit", "var(--font-stack)", "var(--font-code)"}:
            continue
        errors.append(f"字体「{declared.strip()[:60]}」不是 tokens.json 的字体栈")
    for declared in re.findall(r"--font-(?:stack|code)\s*:\s*([^;]+);", page):
        if re.sub(r"\s+", "", declared) not in stacks:
            errors.append(f"字体变量「{declared.strip()[:60]}」与 tokens.json 不一致")
    for attr in re.findall(r"font-family=\"([^\"]+)\"", page):
        errors.append(f"SVG 写了字体属性「{attr[:40]}」，字体由 .flow text 规则统一给出")

    if re.search(r"<(?:script|link|img|iframe)[^>]+(?:src|href)=[\"']https?://", page):
        errors.append("引用了外部资源，网页必须单文件离线可用")
    if "window.print" in page or "print()" in page:
        errors.append("页面里不放打印按钮，发布后查看器会屏蔽打印对话框")

    for src in outline.images:
        if not src.startswith("data:"):
            errors.append(f"图片没有内嵌：{src[:60]}")
    max_highlight = int(style["web"]["highlight_per_chapter_max"])
    for chapter in outline.chapters:
        if chapter["marks"] > max_highlight:
            errors.append(f"章节 {chapter['id']} 有 {chapter['marks']} 处荧光标记，上限 {max_highlight}")
    max_risk = int(style["limits"]["risk_callouts_per_document"])
    if outline.risks > max_risk:
        errors.append(f"风险条 {outline.risks} 条，上限 {max_risk}")
    return errors


def audit_wording(outline: Outline) -> list[str]:
    """文字检查：禁用词、问句标题、文首工具条页尾的流程用词。"""
    rules = writing_rules()
    allowed_contexts = rules.get("banned_word_allowed_contexts", {})
    errors: list[str] = []
    text = "".join(outline.text)
    for word in rules["banned_words"]:
        stripped = text
        for context in allowed_contexts.get(word, ()):
            stripped = stripped.replace(context, "")
        if word in stripped:
            errors.append(f"出现禁用词「{word}」")
    endings = tuple(rules["heading_forbidden_endings"])
    for heading in outline.headings:
        clean = re.sub(r"\s+", "", heading)
        if "？" in clean or "?" in clean or clean.endswith(endings):
            errors.append(f"标题写成了问句：{heading}")
    chrome = "".join(outline.chrome)
    for word in rules["chrome_words"]:
        if word in chrome:
            errors.append(f"文首、工具条或页尾出现流程用词「{word}」")
    return errors


def main(argv: list[str]) -> int:
    if len(argv) != 1:
        print("用法：python3 scripts/audit_html.py 网页.html", file=sys.stderr)
        return 2
    errors = audit(Path(argv[0]))
    if errors:
        print("网页审计未通过：")
        for error in errors:
            print(f"- {error}")
        return 1
    print("网页审计通过")
    return 0
