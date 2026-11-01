"""Typography and layout tokens shared by all renderers.

There is exactly one token file, the aham-design plugin's ``tokens.json``;
``tokens.document_style`` turns it into the dictionary read here.  It declares four
font slots — Chinese body, Chinese heading, Chinese table and Latin/digits —
that every renderer writes as two OOXML routes: ``w:eastAsia`` carries the
Chinese family and ``w:ascii``/``w:hAnsi``/``w:cs`` carry the Latin family.
Since 6.0 all four slots hold 微软雅黑, so Chinese, Latin and digits share one
face; the slots stay separate so a future style can split them again.  No host font is resolved or certified here; the
document declares the fonts and the reader's Office installation renders them.
"""

from __future__ import annotations

import copy
from pathlib import Path
from typing import Any, Mapping


from .tokens import TokenError, document_style, tokens_path

__all__ = [
    "FONT_ROLE_KEYS",
    "RENDER_CONTRACT_SCHEMA_VERSION",
    "TypographyError",
    "font_roles",
    "load_style",
    "paragraph_tokens",
    "resolve_render_typography",
    "style",
    "typography_contract",
]

FONT_ROLE_KEYS = ("heading", "body", "table", "latin")
RENDER_CONTRACT_SCHEMA_VERSION = "4.0"


class TypographyError(ValueError):
    pass


def load_style(path: Path | None = None) -> dict[str, Any]:
    """Read and sanity-check the token file's document view; never cached across edits."""
    target = (path or tokens_path()).resolve()
    try:
        value = document_style(target)
    except TokenError as exc:
        raise TypographyError(str(exc)) from exc
    if not isinstance(value, dict):
        raise TypographyError(f"视觉令牌根节点必须为对象：{target}")
    for key in ("fonts", "page", "word_pt", "excel_pt", "colors", "word", "excel"):
        if not isinstance(value.get(key), dict):
            raise TypographyError(f"视觉令牌缺少 {key}：{target}")
    fonts = value["fonts"]
    missing = [key for key in FONT_ROLE_KEYS if not str(fonts.get(key) or "").strip()]
    if missing:
        raise TypographyError("视觉令牌 fonts 缺少字体槽：" + "、".join(missing))
    spacing = value["word"].get("line_spacing")
    if not isinstance(spacing, dict) or any(
        key not in spacing for key in ("body_pt", "list_pt", "table_pt", "body_space_after_pt")
    ):
        raise TypographyError("视觉令牌 word.line_spacing 不完整")
    return value


def style() -> dict[str, Any]:
    """Defensive copy of the style tokens."""
    return copy.deepcopy(load_style())


def font_roles() -> dict[str, str]:
    """The four font slots: heading/body/table (Chinese) and latin (Western)."""
    fonts = load_style()["fonts"]
    return {key: str(fonts[key]) for key in FONT_ROLE_KEYS}


def typography_contract() -> dict[str, Any]:
    """The host-independent typography identity frozen into a Render Contract."""
    return {
        "style_version": str(load_style()["version"]),
        "font_roles": font_roles(),
    }


def paragraph_tokens() -> dict[str, float]:
    spacing = load_style()["word"]["line_spacing"]
    return {
        "body_line_pt": float(spacing["body_pt"]),
        "list_line_pt": float(spacing["list_pt"]),
        "table_line_pt": float(spacing["table_pt"]),
        "body_space_after_pt": float(spacing["body_space_after_pt"]),
    }


def resolve_render_typography(content: Mapping[str, Any]) -> dict[str, Any]:
    """Resolve renderer settings from a Render Contract or raw content.

    A formal Render Contract must carry the same typography the local style
    file declares; drift fails closed before any output is created.  Raw
    content (unit-level or diagnostic builder use) simply adopts the local
    style.
    """
    expected = typography_contract()
    resolved_style = load_style()
    if content.get("ir_type") == "render-contract":
        if content.get("schema_version") != RENDER_CONTRACT_SCHEMA_VERSION:
            raise TypographyError(
                f"Render Contract schema_version 必须为 {RENDER_CONTRACT_SCHEMA_VERSION}"
            )
        typography = content.get("typography")
        if not isinstance(typography, dict):
            raise TypographyError("Render Contract 缺少 typography")
        if typography.get("style_version") != expected["style_version"]:
            raise TypographyError("Render Contract typography.style_version 与本地样式不一致")
        if typography.get("font_roles") != expected["font_roles"]:
            raise TypographyError("Render Contract typography.font_roles 与本地样式不一致")
        source = "render-contract"
    else:
        source = "local-style"
    return {
        **copy.deepcopy(expected),
        "style": resolved_style,
        "word_layout": copy.deepcopy(resolved_style["word"]),
        "excel_layout": copy.deepcopy(resolved_style["excel"]),
        "source": source,
    }
