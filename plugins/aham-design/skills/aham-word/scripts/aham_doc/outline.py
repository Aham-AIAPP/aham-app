#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Pure Word outline projection shared by authoring, TOC and QA.

The projection assigns one deterministic visible number to every chapter and
every ``subheading`` block.  Consumers must not independently recount headings:
the body, cached TOC and structural QA all use this module.
"""

from __future__ import annotations

import re
from typing import Any, Iterable

__all__ = ["NUMBER_PREFIX", "display_heading", "flatten_numbered_chapters", "outline_entries"]


NUMBER_PREFIX = re.compile(r"^(\d+(?:\.\d+)*)(?=$|\s|[、.．）)])")


def _text(value: Any) -> str:
    return "" if value is None else str(value).strip()


def _explicit_number(value: dict[str, Any]) -> str:
    explicit = _text(value.get("number"))
    if explicit:
        return explicit
    match = NUMBER_PREFIX.match(_text(value.get("title")))
    return match.group(1) if match else ""


def display_heading(value: dict[str, Any]) -> str:
    """Return the numbered visible heading without prefix false positives."""

    title = _text(value.get("title"))
    number = _text(value.get("number") or value.get("_resolved_number"))
    if not number:
        return title
    match = NUMBER_PREFIX.match(title)
    return title if match and match.group(1) == number else f"{number} {title}"


def _number_blocks(
    blocks: Iterable[Any], *, chapter_number: str, chapter_level: int,
) -> list[Any]:
    result: list[Any] = []
    counters: list[int] = []
    for raw in blocks or []:
        if not isinstance(raw, dict):
            result.append(raw)
            continue
        block = dict(raw)
        if _text(block.get("type")).lower() == "subheading" and _text(block.get("title")):
            try:
                requested_level = int(block.get("level", chapter_level + 1))
            except (TypeError, ValueError):
                requested_level = chapter_level + 1
            heading_level = min(3, max(chapter_level + 1, requested_level))
            depth = max(1, heading_level - chapter_level)
            while len(counters) < depth:
                counters.append(0)
            for index in range(depth - 1):
                if counters[index] == 0:
                    counters[index] = 1
            counters[depth - 1] += 1
            del counters[depth:]
            generated = ".".join([chapter_number, *map(str, counters)]) if chapter_number else ""
            block["_resolved_number"] = _explicit_number(block) or generated
            block["_resolved_level"] = heading_level
        result.append(block)
    return result


def flatten_numbered_chapters(
    chapters: Iterable[Any], level: int = 1, parent_number: str = "",
) -> list[tuple[dict[str, Any], int]]:
    """Return copied chapters with numbered subheading blocks included."""

    result: list[tuple[dict[str, Any], int]] = []
    for index, raw in enumerate(chapters or [], start=1):
        if not isinstance(raw, dict):
            continue
        chapter = dict(raw)
        numbered = chapter.get("numbered") is not False and not chapter.get("unnumbered")
        number = _explicit_number(chapter) if numbered else ""
        if numbered and not number:
            number = f"{parent_number}.{index}" if parent_number else str(index)
        chapter["_resolved_number"] = number
        chapter["blocks"] = _number_blocks(
            chapter.get("blocks") or [], chapter_number=number, chapter_level=level,
        )
        result.append((chapter, level))
        children = raw.get("chapters") or raw.get("children") or []
        result.extend(flatten_numbered_chapters(children, level + 1, number))
    return result


def outline_entries(
    flattened: Iterable[tuple[dict[str, Any], int]],
) -> list[tuple[str, int]]:
    """Project the exact visible heading text and Word outline level."""

    result: list[tuple[str, int]] = []
    for chapter, level in flattened:
        heading = display_heading(chapter)
        if heading:
            result.append((heading, min(3, max(1, level))))
        for block in chapter.get("blocks") or []:
            if not isinstance(block, dict) or _text(block.get("type")).lower() != "subheading":
                continue
            heading = display_heading(block)
            if heading:
                result.append((
                    heading,
                    min(3, max(1, int(block.get("_resolved_level") or block.get("level") or 2))),
                ))
    return result
