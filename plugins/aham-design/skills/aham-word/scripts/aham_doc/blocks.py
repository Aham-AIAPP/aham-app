"""文档块模型：网页、Word 和 PDF 共用的内容块定义。

一份内容写一次，各渲染器按块类型输出。本模块登记块类型和必填字段，渲染前统一校验，
缺字段在生成那一步报错，不留到事后检查。
"""

from __future__ import annotations

from typing import Any

__all__ = ["BLOCK_TYPES", "BlockError", "validate"]

# 块类型 → 必填字段。Word 能渲染的块和可选字段见技能的 references/content-format.md。
# 表里另有几种只给网页用的块类型，Word 渲染器遇到时印一行「未识别」提示。
BLOCK_TYPES: dict[str, tuple[str, ...]] = {
    "paragraph": ("text",),
    "heading": ("level", "title"),
    "list": ("items",),
    "quote": ("text",),
    "callout": ("tone", "label", "text"),
    "codebox": ("text",),
    "table": ("columns", "rows"),
    "figure": ("path", "caption"),
    "figures": ("items",),
    "svg": ("path", "caption"),
    "anatomy": ("parts", "caption"),
    "amounts": ("items",),
    "notes": ("items",),
    "columns": ("items",),
    "legend": (),
    "with_aside": ("blocks", "aside"),
    "scenes": ("items",),
    "checklist": ("items",),
    "swimlane": ("steps",),
}


class BlockError(ValueError):
    pass


def validate(blocks: list[dict[str, Any]], where: str = "") -> None:
    """检查块类型已登记、必填字段齐全。递归检查 with_aside 和折叠场景里的块。"""
    for index, block in enumerate(blocks or []):
        label = f"{where}第 {index + 1} 块"
        kind = block.get("type", "paragraph")
        if kind not in BLOCK_TYPES:
            raise BlockError(f"{label}：未登记的块类型 {kind!r}")
        missing = [field for field in BLOCK_TYPES[kind] if field not in block]
        if missing:
            raise BlockError(f"{label}（{kind}）缺少字段：{'、'.join(missing)}")
        if kind == "with_aside":
            validate(block.get("blocks") or [], f"{label} 正文")
        if kind == "scenes":
            for scene in block.get("items") or []:
                validate(scene.get("blocks") or [], f"{label} 场景「{scene.get('title', '')}」")
