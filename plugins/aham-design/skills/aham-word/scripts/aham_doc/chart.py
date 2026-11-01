"""生成分组柱状图 SVG，供网页的 svg 内容块使用。

SVG 只用 web/base.css 里 .flow 的类（pt-1 至 pt-4、ln、t2b、t3），不写色值和字号，颜色和字号随 tokens.json 变化。
画布尺寸、绘图区边界、柱宽和图例间距读 tokens.json 的 layout.web.chart。
每组最多 layout.web.chart.max_series 个系列，对应参与方颜色。刻度按最大值自动取整：最大值不超过 6 时步长 1，否则步长 5。

用法：python3 scripts/bar_chart.py 数据.json 输出.svg

数据文件：
{
  "aria": "本周新增对比：……",            图的文字说明，读屏软件用
  "groups": ["甲", "乙", "丙"],            横轴各组名称
  "series": [{"name": "新增", "values": [0, 3, 0]}, ...]
}
也可以在代码里调用 render(data) 直接得到 SVG 文字。
"""

from __future__ import annotations

import html
import json
import sys
from pathlib import Path
from typing import Any

from .tokens import value

__all__ = ["ChartError", "main", "render"]


class ChartError(ValueError):
    pass


def _geometry() -> dict[str, float]:
    chart = value("layout.web.chart")
    return {key: float(number) for key, number in chart.items()}


def _num(x: float) -> str:
    """整数写成不带小数的形式，与手写坐标一致。"""
    return str(int(x)) if float(x).is_integer() else str(x)


def _scale(values: list[int]) -> tuple[int, int]:
    raw = max(3, max(values) if values else 0)
    step = 1 if raw <= 6 else 5
    vmax = -(-raw // step) * step
    return vmax, step


def render(data: dict[str, Any]) -> str:
    g = _geometry()
    groups = list(data["groups"])
    series = list(data["series"])
    max_series = int(g["max_series"])
    if not 1 <= len(series) <= max_series:
        raise ChartError(f"系列数量须为 1 到 {max_series} 个，对应参与方颜色")
    for s in series:
        if len(s["values"]) != len(groups):
            raise ChartError(f"系列「{s['name']}」的数值个数与组数不一致")
        if any((not isinstance(v, int)) or v < 0 for v in s["values"]):
            raise ChartError(f"系列「{s['name']}」的数值须为非负整数")
    left, right, top, base = g["left"], g["right"], g["top"], g["baseline"]
    bar, gap = g["bar"], g["bar_gap"]
    vmax, step = _scale([v for s in series for v in s["values"]])
    unit = (base - top) / vmax
    group_w = (right - left) / len(groups)
    cluster = bar * len(series) + gap * (len(series) - 1)
    aria = html.escape(str(data.get("aria", "分组柱状图")), quote=True)
    p = [f'<svg viewBox="0 0 {_num(g["width"])} {_num(g["height"])}" role="img" aria-label="{aria}">']
    x = left
    swatch, legend_top = g["legend_swatch"], g["legend_top"]
    for i, s in enumerate(series, 1):
        p.append(f'<rect class="pt-{i}" x="{_num(x)}" y="{_num(legend_top)}" width="{_num(swatch)}" height="{_num(swatch)}"/>')
        p.append(f'<text class="t2b" x="{_num(x + swatch * 1.5)}" y="{_num(legend_top + swatch - 1)}">{html.escape(str(s["name"]))}</text>')
        x += g["legend_step"]
    for v in range(0, vmax + 1, step):
        y = base - v * unit
        dash = "" if v == 0 else ' stroke-dasharray="2 4"'
        width = "1" if v == 0 else "0.5"
        p.append(f'<path class="ln" d="M{_num(left)} {y:.1f} H{_num(right)}" stroke-width="{width}"{dash}/>')
        p.append(f'<text class="t3" x="{_num(left - 12)}" y="{y + 4:.1f}" text-anchor="end">{v}</text>')
    for gi, name in enumerate(groups):
        gx = left + gi * group_w + (group_w - cluster) / 2
        for i, s in enumerate(series, 1):
            v = s["values"][gi]
            bx = gx + (i - 1) * (bar + gap)
            h = v * unit
            if v > 0:
                p.append(f'<rect class="pt-{i}" x="{bx:.1f}" y="{base - h:.1f}" width="{_num(bar)}" height="{h:.1f}"/>')
            p.append(f'<text class="t3" x="{bx + bar / 2:.1f}" y="{base - h - 6:.1f}" text-anchor="middle">{v}</text>')
        p.append(f'<text class="t2b" x="{left + gi * group_w + group_w / 2:.1f}" y="{_num(base + 26)}" text-anchor="middle">{html.escape(str(name))}</text>')
    p.append("</svg>")
    return "\n".join(p)


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print(__doc__)
        return 2
    data = json.loads(Path(argv[0]).read_text("utf-8"))
    Path(argv[1]).write_text(render(data), "utf-8")
    print(argv[1])
    return 0
