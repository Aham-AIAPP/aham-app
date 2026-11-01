"""整份 Word 文档的组装：封面、页眉页脚、目录、文首、章节和保存后的检查。

内容写成一个 JSON 对象，格式见技能的 references/content-format.md。本模块只做通用组装；
业务专有的内容块和表格规则由调用方经 word 模块的扩展点登记后再调用 build_document。

命令行用法：
    python3 scripts/build_docx.py 内容.json 输出.docx
"""

from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any

from . import word as W
from .brand import current_brand
from .docx_ooxml import audit_docx_property_order, normalize_docx_property_order, summarize_violations
from .outline import display_heading, flatten_numbered_chapters

__all__ = ["DocumentError", "build_document", "check_limits", "load_content", "main"]


class DocumentError(ValueError):
    pass


def load_content(path: Path) -> dict[str, Any]:
    try:
        data = json.loads(Path(path).read_text("utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise DocumentError(f"无法读取内容文件：{path}: {exc}") from exc
    if not isinstance(data, dict):
        raise DocumentError("内容文件的根节点必须是对象")
    return data


def _meta(content: dict[str, Any]) -> dict[str, Any]:
    meta = dict(content.get("meta") or {})
    if not str(meta.get("title") or "").strip():
        raise DocumentError("meta.title 必填：文档类型或文档名")
    if not str(meta.get("date") or "").strip():
        # 不用运行当天的日期：同一份内容两次生成要得到同一份文件。
        raise DocumentError("meta.date 必填：文档日期，写成 2026-11-01")
    meta.setdefault("version", "V1.0")
    return meta


def _risk_callouts(content: dict[str, Any]) -> int:
    """全文风险条（tone 为 risk 的提示条）的条数，含下级章节。"""
    def count(chapters: list[Any]) -> int:
        total = 0
        for chapter in chapters or []:
            if not isinstance(chapter, dict):
                continue
            for block in chapter.get("blocks") or []:
                if (isinstance(block, dict)
                        and str(block.get("type", "paragraph")).lower() in {"callout", "lead"}
                        and str(block.get("tone", "")).lower() == "risk"):
                    total += 1
            total += count(chapter.get("chapters") or chapter.get("children") or [])
        return total

    return count(content.get("chapters") or [])


def check_limits(content: dict[str, Any]) -> None:
    """全文版式上限：风险条条数不超过 tokens.json 的 layout.limits.risk_callouts_per_document。"""
    limit = int(W.STYLE["limits"]["risk_callouts_per_document"])
    risks = _risk_callouts(content)
    if risks > limit:
        raise DocumentError(f"风险条 {risks} 条，超过上限 {limit} 条：把次要风险并入正文或合并成一条")


def build_document(content: dict[str, Any], out_path: Path, base_dir: Path | None = None) -> Path:
    """按内容生成 .docx，返回文件路径。base_dir 是图片等相对路径的起点，缺省为输出目录。"""
    meta = _meta(content)
    check_limits(content)
    out_path = Path(out_path)
    base = Path(base_dir) if base_dir else out_path.parent
    chapters = content.get("chapters") or []
    flattened = flatten_numbered_chapters(chapters)

    W.configure_typography()
    W.set_numeric_facts(W.numeric_fact_values(content))
    W.configure_parties(content)
    doc = W.new_document()

    with_cover = bool(content.get("cover", True))
    with_toc = bool(content.get("toc", len(chapters) >= 4))
    if with_cover:
        W.add_cover(doc, meta)
    else:
        doc.sections[0].different_first_page_header_footer = False
    W.add_header_footer(doc.sections[0], meta)
    if with_toc:
        W.add_toc(doc, flattened)
    W.add_inner_title(doc, meta)
    if not with_cover:
        # 没有封面时，第一页就是目录或文首，不在它前面分页。
        doc.paragraphs[0].paragraph_format.page_break_before = None

    intro = content.get("intro")
    if intro:
        W.add_lead(doc, intro.get("label", "文档用途"), intro.get("text", ""))

    pending_break = False
    for index, (chapter, level) in enumerate(flattened, start=1):
        orientation = W.normalize_orientation(chapter.get("orientation", "portrait"))
        if orientation != W.section_orientation(doc.sections[-1]):
            W.start_section(doc, orientation, meta)
        elif chapter.get("page_break_before") and index > 1:
            pending_break = True
        W.add_heading(doc, display_heading(chapter), level)
        if pending_break:
            doc.paragraphs[-1].paragraph_format.page_break_before = True
            pending_break = False
        if chapter.get("summary"):
            W.add_chapter_summary(doc, chapter.get("summary_label", "本章要点"), chapter["summary"])
        previous_kind = ""
        for block in chapter.get("blocks") or []:
            W.render_block(doc, block, base, previous_kind)
            previous_kind = str(block.get("type", "paragraph") if isinstance(block, dict) else "").lower()

    if content.get("closing_note"):
        if W.section_orientation(doc.sections[-1]) != "portrait":
            W.start_section(doc, "portrait", meta)
        W.add_lead(doc, content.get("closing_label", "说明"), content["closing_note"])

    brand = current_brand()
    doc.core_properties.title = str(meta["title"])
    doc.core_properties.author = brand.company
    doc.core_properties.comments = ""

    out_path.parent.mkdir(parents=True, exist_ok=True)
    doc.save(out_path)
    W.normalize_formal_numbering(out_path)
    normalize_docx_property_order(out_path)
    violations = audit_docx_property_order(out_path)
    if violations:
        out_path.unlink(missing_ok=True)
        raise DocumentError("Word OOXML 属性顺序检查失败：" + "；".join(summarize_violations(violations)[:24]))
    return out_path


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print(__doc__, file=sys.stderr)
        return 2
    source, target = Path(argv[0]), Path(argv[1])
    try:
        path = build_document(load_content(source), target, source.parent)
    except (DocumentError, ValueError) as exc:
        print(f"生成失败：{exc}", file=sys.stderr)
        return 1
    print(path)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
