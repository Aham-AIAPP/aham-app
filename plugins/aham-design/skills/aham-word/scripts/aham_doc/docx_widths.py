# -*- coding: utf-8 -*-
"""内容驱动的表格列宽算法。

替代技能 build_word_documents.py 中 _normalize_widths 的表头长度启发式。
原算法只看表头字数：weight = min(4, max(1, sqrt(len(header))))，
导致「编号」(2字→1.41) 与「本项目应用说明」(7字→2.65) 权重只差 1.9 倍，
而真实内容需求差约 20 倍，短列必然偏胖、长列必然被挤。

本算法：显示宽度 → 自然单行宽 → 短列封顶 → 长列阻尼分配 → 最小宽兜底。
"""
from __future__ import annotations
import math
import re
import unicodedata

__all__ = [
    "CELL_PAD",
    "MIN_COL",
    "REGULAR_CELL_PAD",
    "auto_widths",
    "disp_w",
    "imbalance_report",
    "unbreakable_cm",
]

# 9pt 宋体/Arial 的度量（cm）。6.0 起文档改用微软雅黑，这组常量尚未按微软雅黑重测，
# 生成环境里没有该字体可供测量；出现列宽不足时先核对这里。旧常量按「半角一律 0.175cm」估算，于是
# 「REQ-REG-001」这类全大写+数字的编号被算窄了三成，分到的列宽放不下，
# Word 只能在连字符处折行。西文按两档计：大写字母与数字明显比小写宽。
CH_FULL = 0.3400      # 全角
CH_WIDE = 0.2200      # 大写字母与数字
CH_HALF = 0.2000      # 其余半角
# 单元格左右内边距从 tokens.json 读：缺省单元格取 layout.word.table.default_cell.side_pt，
# 常规版表格取 layout.word.table.regular.cell_side_pt。左右两侧相加，再加两条边框线宽 0.04cm。
# 缺省单元格的值也用于紧凑版表格的列宽估算；Word 常规版表格用 REGULAR_CELL_PAD。


def _cell_pad(token: str) -> float:
    """读不到 tokens.json 时报错，不退回写死的内边距。"""
    from .tokens import value

    side_pt = float(value(token))
    return round(side_pt * 2 / 72 * 2.54 + 0.04, 4)


CELL_PAD = _cell_pad("layout.word.table.default_cell.side_pt")
REGULAR_CELL_PAD = _cell_pad("layout.word.table.regular.cell_side_pt")
MIN_COL = 1.20        # 最小列宽：保证 2 个汉字表头不被压成竖排
# 短列阈值：自然单行宽 ≤ 此值的列按需给宽，不参与剩余分配。
# 2.60 会把「本分类含税合计」「按厂商授权」这类刚过阈值的列判成长列再被阻尼压回去，
# 留 0.3cm 余量让它们稳定落在短列一侧。
SHORT_CAP = 2.90
# 长列阻尼指数。0.55 压得太狠：最长的说明列拿到的宽度与次长列几乎相同，
# 真实需求相差三四倍时仍被摊平。0.7 让长列按需求拉开差距又不至于吞掉整行。
DAMP = 0.70
P_HIGH = 0.90         # 用 P90 而非 max，避免单个超长单元格绑架整表


def _char_cm(char: str) -> float:
    if unicodedata.east_asian_width(char) in ("W", "F", "A"):
        return CH_FULL
    return CH_WIDE if (char.isdigit() or char.isupper()) else CH_HALF


def disp_w(text) -> int:
    """显示宽度：全角/宽字符记 2，其余记 1。"""
    s = "" if text is None else str(text)
    return sum(2 if unicodedata.east_asian_width(c) in ("W", "F", "A") else 1 for c in s)


def _nat_cm(text, pad: float = CELL_PAD) -> float:
    """单行排下该文本所需的宽度（cm）。"""
    s = "" if text is None else str(text)
    return sum(_char_cm(c) for c in s) + pad


def unbreakable_cm(text, pad: float = CELL_PAD) -> float:
    """最长不可断片段所需宽度：连续 ASCII 词不能拆，中文可任意断行。"""
    s = "" if text is None else str(text)
    words = re.findall(r"[A-Za-z0-9]+(?:[._%/\-][A-Za-z0-9]+)*", s)
    if not words:
        return MIN_COL
    # 编号/型号（REQ-REG-001、TA8218N5xx）几乎全是大写字母与数字，按宽档计。
    longest = max(words, key=len)
    return len(longest) * CH_WIDE + pad


def _quantize(widths: list[float]) -> list[float]:
    """量化到 0.001cm，且一律向上取整。

    向下取整会把恰好卡在「不可断片段下限」上的列削掉最后一丝——
    「REQ-REG-001」这类编号于是刚好放不下，Word 在连字符处折行。
    多出的总宽不超过列数 × 0.001cm。
    """
    return [math.ceil(value * 1000) / 1000 for value in widths]


def auto_widths(headers, rows, total_cm: float = 16.0, cell_pad: float = CELL_PAD) -> list[float]:
    """返回各列宽度（cm），合计 ≈ total_cm（量化误差 < 列数 × 0.001cm）。"""
    n = len(headers)
    if n == 0:
        return []
    cols = [[(r[i] if i < len(r) else "") for r in rows] for i in range(n)]

    nat, floor = [], []
    for i, head in enumerate(headers):
        cell_nats = sorted(_nat_cm(c, cell_pad) for c in cols[i]) or [0.0]
        idx = min(len(cell_nats) - 1, int(round((len(cell_nats) - 1) * P_HIGH)))
        p90 = cell_nats[idx]
        nat.append(max(_nat_cm(head, cell_pad), p90))
        # 下限三取大：①不可断 ASCII 词 ②表头至少 2 个汉字同行（防竖排） ③全局最小
        ub = max([unbreakable_cm(head, cell_pad)] + [unbreakable_cm(c, cell_pad) for c in cols[i]])
        head_min = min(disp_w(head), 4) * (CH_FULL / 2) + cell_pad
        floor.append(max(MIN_COL, ub, head_min))

    # 短列：自然宽已很窄（序号/编号/数量/状态），直接按需给，封顶不外扩
    is_short = [nat[i] <= SHORT_CAP for i in range(n)]
    width = [0.0] * n
    for i in range(n):
        if is_short[i]:
            width[i] = max(floor[i], min(nat[i], SHORT_CAP))

    fixed = sum(width[i] for i in range(n) if is_short[i])
    rest = total_cm - fixed
    long_idx = [i for i in range(n) if not is_short[i]]

    if not long_idx:                       # 全是短列：按自然宽比例摊满
        s = sum(width) or 1.0
        return _quantize([w * total_cm / s for w in width])

    if rest < sum(floor[i] for i in long_idx):
        # 极端情况：短列已挤占过多，退化为全列按自然宽比例分配
        s = sum(nat) or 1.0
        return _quantize([max(floor[i], nat[i] * total_cm / s) for i in range(n)])

    weights = [nat[i] ** DAMP for i in long_idx]
    ws = sum(weights) or 1.0
    for k, i in enumerate(long_idx):
        width[i] = max(floor[i], rest * weights[k] / ws)

    # 归一化到 total_cm（保留 floor 不被压破）
    for _ in range(6):
        cur = sum(width)
        if abs(cur - total_cm) < 0.01:
            break
        delta = total_cm - cur
        flex = [i for i in long_idx if width[i] + delta * (width[i] / max(sum(width[j] for j in long_idx), 1e-6)) >= floor[i]]
        if not flex:
            break
        base = sum(width[i] for i in flex) or 1.0
        for i in flex:
            width[i] = max(floor[i], width[i] + delta * width[i] / base)

    return _quantize(width)


def imbalance_report(headers, rows, widths_cm):
    """QA 用：返回 (短列虚胖倍数, 长列被压倍数, 是否失衡)。"""
    n = len(headers)
    cols = [[(r[i] if i < len(r) else "") for r in rows] for i in range(n)]
    ratios = []
    for i in range(n):
        cell_nats = sorted(_nat_cm(c) for c in cols[i]) or [0.0]
        idx = min(len(cell_nats) - 1, int(round((len(cell_nats) - 1) * P_HIGH)))
        need = max(_nat_cm(headers[i]), cell_nats[idx])
        ratios.append(widths_cm[i] / max(need, 0.01))
    fat = max(ratios)
    thin = min(ratios)
    # 主判据：存在列宽达到其内容需求 2 倍以上（短列虚胖）；
    # 辅判据：同表存在被压到需求 0.8 倍以下的列（长列被挤）。
    # 长文本列 ratio 天然偏低（必须换行），故不能只看 thin。
    return fat, thin, (fat >= 2.0 and thin < 0.8)
