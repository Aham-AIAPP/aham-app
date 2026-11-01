#!/usr/bin/env python3
"""Schema-order helpers and hard validation for Word property containers.

WordprocessingML property containers use ``xsd:sequence``.  A DOCX can be a
valid ZIP whose XML parses successfully and still be rejected by Microsoft
Word when children such as ``w:tcBorders`` and ``w:tcW`` are out of order.
This module is shared by the builder and QA so authoring and verification use
one exhaustive order contract.
"""

from __future__ import annotations

from collections import Counter
from pathlib import Path
import tempfile
from typing import Any
from zipfile import ZIP_DEFLATED, ZipFile

from lxml import etree

__all__ = [
    "W_NS",
    "audit_docx_property_order",
    "local_name",
    "normalize_docx_property_order",
    "normalize_property_order",
    "property_order_violations",
    "set_property_child",
    "summarize_violations",
]


W_NS = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"


# WordprocessingML Transitional sequences, aligned with ECMA-376 and the
# python-docx CT_* tag sequences used by this skill's runtime.
PROPERTY_ORDERS: dict[str, tuple[str, ...]] = {
    "tcPr": (
        "cnfStyle", "tcW", "gridSpan", "hMerge", "vMerge", "tcBorders",
        "shd", "noWrap", "tcMar", "textDirection", "tcFitText", "vAlign",
        "hideMark", "headers", "cellIns", "cellDel", "cellMerge", "tcPrChange",
    ),
    "tblPr": (
        "tblStyle", "tblpPr", "tblOverlap", "bidiVisual",
        "tblStyleRowBandSize", "tblStyleColBandSize", "tblW", "jc",
        "tblCellSpacing", "tblInd", "tblBorders", "shd", "tblLayout",
        "tblCellMar", "tblLook", "tblCaption", "tblDescription", "tblPrChange",
    ),
    "trPr": (
        "cnfStyle", "divId", "gridBefore", "gridAfter", "wBefore", "wAfter",
        "cantSplit", "trHeight", "tblHeader", "tblCellSpacing", "jc", "hidden",
        "ins", "del", "trPrChange",
    ),
    "pPr": (
        "pStyle", "keepNext", "keepLines", "pageBreakBefore", "framePr",
        "widowControl", "numPr", "suppressLineNumbers", "pBdr", "shd", "tabs",
        "suppressAutoHyphens", "kinsoku", "wordWrap", "overflowPunct",
        "topLinePunct", "autoSpaceDE", "autoSpaceDN", "bidi", "adjustRightInd",
        "snapToGrid", "spacing", "ind", "contextualSpacing", "mirrorIndents",
        "suppressOverlap", "jc", "textDirection", "textAlignment",
        "textboxTightWrap", "outlineLvl", "divId", "cnfStyle", "rPr", "sectPr",
        "pPrChange",
    ),
    "rPr": (
        "rStyle", "rFonts", "b", "bCs", "i", "iCs", "caps", "smallCaps",
        "strike", "dstrike", "outline", "shadow", "emboss", "imprint",
        "noProof", "snapToGrid", "vanish", "webHidden", "color", "spacing", "w",
        "kern", "position", "sz", "szCs", "highlight", "u", "effect", "bdr",
        "shd", "fitText", "vertAlign", "rtl", "cs", "em", "lang",
        "eastAsianLayout", "specVanish", "oMath",
    ),
    "sectPr": (
        "headerReference", "footerReference", "footnotePr", "endnotePr", "type",
        "pgSz", "pgMar", "paperSrc", "pgBorders", "lnNumType", "pgNumType",
        "cols", "formProt", "vAlign", "noEndnote", "titlePg", "textDirection",
        "bidi", "rtlGutter", "docGrid", "printerSettings", "sectPrChange",
    ),
}


def local_name(tag: str) -> str:
    return tag.rsplit("}", 1)[-1]


def set_property_child(parent: Any, child: Any) -> Any:
    """Place one property child at its schema position, replacing duplicates."""
    container = local_name(parent.tag)
    name = local_name(child.tag)
    order = PROPERTY_ORDERS.get(container)
    if order is None:
        raise ValueError(f"不支持的 Word 属性容器：{container}")
    if name not in order:
        raise ValueError(f"{container} 不支持的 Word 属性子元素：{name}")

    for existing in list(parent):
        if existing is child:
            parent.remove(existing)
        elif existing.tag == child.tag:
            parent.remove(existing)

    target_index = order.index(name)
    for index, sibling in enumerate(parent):
        sibling_name = local_name(sibling.tag)
        if sibling_name in order and order.index(sibling_name) > target_index:
            parent.insert(index, child)
            return child
    parent.append(child)
    return child


def normalize_property_order(root: Any) -> int:
    """Stably reorder known children in every supported property container."""
    changed = 0
    for container, order in PROPERTY_ORDERS.items():
        rank = {name: index for index, name in enumerate(order)}
        for parent in root.iter(f"{{{W_NS}}}{container}"):
            children = list(parent)
            known_positions = [
                index for index, child in enumerate(children)
                if local_name(child.tag) in rank
            ]
            known_children = [children[index] for index in known_positions]
            sorted_children = sorted(
                known_children, key=lambda child: rank[local_name(child.tag)]
            )
            if known_children == sorted_children:
                continue
            for position, child in zip(known_positions, sorted_children):
                children[position] = child
            parent[:] = children
            changed += 1
    return changed


def property_order_violations(root: Any, *, part: str) -> list[dict[str, str]]:
    violations: list[dict[str, str]] = []
    for container, order in PROPERTY_ORDERS.items():
        rank = {name: index for index, name in enumerate(order)}
        for parent in root.iter(f"{{{W_NS}}}{container}"):
            names = [
                local_name(child.tag) for child in parent
                if local_name(child.tag) in rank
            ]
            for before, after in zip(names, names[1:]):
                if rank[before] > rank[after]:
                    violations.append({
                        "part": part,
                        "container": container,
                        "before": before,
                        "after": after,
                    })
    return violations


def audit_docx_property_order(path: Path) -> list[dict[str, str]]:
    violations: list[dict[str, str]] = []
    with ZipFile(path) as archive:
        for part in archive.namelist():
            if not part.startswith("word/") or not part.endswith(".xml"):
                continue
            root = etree.fromstring(archive.read(part))
            violations.extend(property_order_violations(root, part=part))
    return violations


def summarize_violations(violations: list[dict[str, str]]) -> list[str]:
    counts = Counter(
        (item["part"], item["container"], item["before"], item["after"])
        for item in violations
    )
    return [
        f"{part}｜{container}｜{before}>{after}｜{count}处"
        for (part, container, before, after), count in sorted(counts.items())
    ]


def normalize_docx_property_order(path: Path) -> int:
    """Normalize property order inside a DOCX atomically before QA hashing."""
    replacements: dict[str, bytes] = {}
    changed_containers = 0
    with ZipFile(path) as source:
        for part in source.namelist():
            if not part.startswith("word/") or not part.endswith(".xml"):
                continue
            original = source.read(part)
            root = etree.fromstring(original)
            changed = normalize_property_order(root)
            if not changed:
                continue
            changed_containers += changed
            replacements[part] = etree.tostring(
                root, xml_declaration=True, encoding="UTF-8", standalone=True
            )
        if not replacements:
            return 0
        with tempfile.NamedTemporaryFile(
            prefix=path.stem + "-order-", suffix=".docx",
            dir=path.parent, delete=False,
        ) as handle:
            temp_path = Path(handle.name)
        try:
            with ZipFile(temp_path, "w", compression=ZIP_DEFLATED) as target:
                for info in source.infolist():
                    target.writestr(info, replacements.get(info.filename, source.read(info.filename)))
            temp_path.replace(path)
        finally:
            temp_path.unlink(missing_ok=True)
    return changed_containers
