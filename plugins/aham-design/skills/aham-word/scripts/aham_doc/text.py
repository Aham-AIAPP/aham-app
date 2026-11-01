"""文字规范化：渲染时直接执行，生成的文字即符合规则，不靠事后检查。

- 中文标点：中文语境里的半角标点转全角（GB/T 15834-2011，layout 规则 cjk_punctuation）。
- 金额：千分位、两位小数（AGENTS.md 文档样式标准）。
- 人民币大写（GB/T 15835-2011，layout 规则 amount_rmb_upper）。
- 有序编号（GB/T 9704-2012 第 7.3.3 条，writing 规则 numbering）。
"""

from __future__ import annotations

import re
from decimal import ROUND_HALF_UP, Decimal
from typing import Any

__all__ = ["cjk_punct", "money", "ordered_prefix", "rmb_upper"]

_CJK = "[㐀-鿿　-〿＀-￯]"
_HALF_TO_FULL = {",": "，", ";": "；", ":": "：", "?": "？", "!": "！", "(": "（", ")": "）"}
_OPEN_PAREN = re.compile(rf"\((?=[^()]*{_CJK}[^()]*\))")
_CLOSE_PAREN = re.compile(rf"(?<=（)([^()（）]*)\)")


def cjk_punct(text: str) -> str:
    """把中文语境里的半角逗号、分号、冒号、问号、叹号和括号转成全角。

    判定：标点紧跟汉字或全角符号之后（逗号等），或括号内含汉字（括号）。网址、时间（10:30）、
    英文句子和数字列表（1, 2）不在中文语境里，保持原样。
    """
    if not text:
        return text
    out = re.sub(rf"(?<={_CJK})\s?([,;:?!])(?![0-9/])", lambda m: _HALF_TO_FULL[m.group(1)], text)
    out = _OPEN_PAREN.sub("（", out)
    out = _CLOSE_PAREN.sub(lambda m: m.group(1) + "）", out)
    # 全角括号自带字距，两侧不留空格（W3C《中文排版需求》3.1）。
    return re.sub(r" ?（ ?", "（", re.sub(r" ?） ?", "）", out))


def money(value: Any) -> str:
    """金额写成千分位、两位小数，例如 780800 → 780,800.00。"""
    amount = Decimal(str(value)).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)
    return f"{amount:,.2f}"


def rmb_upper(value: Any) -> str:
    """金额转人民币大写，例如 51700 → 伍万壹仟柒佰元整，100500.5 → 壹拾万零伍佰元伍角。"""
    amount = Decimal(str(value)).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)
    if amount < 0:
        raise ValueError("人民币大写不支持负数")
    digits = "零壹贰叁肆伍陆柒捌玖"
    units = ("", "拾", "佰", "仟")
    sections = ("", "万", "亿", "万亿")
    integer = int(amount)
    jiao = int(amount * 10) % 10
    fen = int(amount * 100) % 10
    if integer == 0:
        words = "零"
    else:
        groups = []
        while integer:
            groups.append(integer % 10000)
            integer //= 10000
        words = ""
        zero_pending = False
        for index in range(len(groups) - 1, -1, -1):
            group = groups[index]
            if group == 0:
                zero_pending = bool(words)
                continue
            if words and (zero_pending or group < 1000):
                words += "零"
            zero_pending = False
            part = ""
            gap = False
            for position in range(3, -1, -1):
                digit = group // (10 ** position) % 10
                if digit == 0:
                    gap = bool(part)
                    continue
                if gap:
                    part += "零"
                    gap = False
                part += digits[digit] + units[position]
            words += part + sections[index]
    words += "元"
    if jiao == 0 and fen == 0:
        return words + "整"
    if jiao:
        words += digits[jiao] + "角"
    elif fen:
        words += "零"
    if fen:
        words += digits[fen] + "分"
    return words


def ordered_prefix(position: int, level: int = 1) -> str:
    """有序编号前缀：第 1 级「1. 」，第 2 级「（1）」。"""
    return f"{position}. " if level <= 1 else f"（{position}）"
