"""说明条款（表注、费用说明、术语说明）的序号与标签写法，Word、Excel 与 HTML 共用。"""

from __future__ import annotations

import re
from typing import Any

__all__ = [
    "NOTE_LABEL_MAX_CHARS",
    "NOTE_ORDINAL_SEPARATOR",
    "note_ordinal_prefix",
    "safe_text",
    "split_note_label",
    "strip_note_ordinal",
]


def safe_text(value: Any) -> str:
    return "" if value is None else str(value)


NOTE_ORDINAL_SEPARATOR = "\u3000"
NOTE_LABEL_MAX_CHARS = 12
_NOTE_ORDINAL_PREFIX = re.compile(r"^\d{1,2}\u3000")


def note_ordinal_prefix(index: int) -> str:
    """说明条款的可见序号前缀，Word、Excel 与 HTML 预览共用同一形态。

    序号写成字面文本而不是 Word 自动编号：``numPr`` 在 LibreOffice 下会走
    OpenSymbol，破坏四字体槽与配置一致的硬门。分隔符用
    全角空格，避免「1.」与句中的小数点混读。
    """
    return f"{int(index)}{NOTE_ORDINAL_SEPARATOR}"


def strip_note_ordinal(text: Any) -> str:
    """去掉渲染时加上的序号前缀，用于把交付件文本还原成内容底稿文本。"""
    return _NOTE_ORDINAL_PREFIX.sub("", safe_text(text).strip(), count=1)


def split_note_label(text: Any) -> tuple[str, str]:
    """把「标签：正文」拆成加粗标签与正文两段。

    不是标签句，或标签过长（说明它其实是整句而非索引词）时，返回空标签和整句。
    """
    body = safe_text(text).strip()
    label, separator, tail = body.partition("：")
    if separator and 0 < len(label) <= NOTE_LABEL_MAX_CHARS:
        return f"{label}{separator}", tail
    return "", body
