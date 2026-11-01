# -*- coding: utf-8 -*-
"""
PPT 成品的视觉检查（读 .pptx，不改文件）：字号、强调色、图例和色表。

两种用法：
1. 单独运行，只出视觉检查报告：
       python check_deck_visual.py <文稿.pptx> [--config 项目配置.json] [--out 报告.md]
2. 作为模块，由方案流程技能的 check_deck.py 调用。check_deck.py 同时调用文字检查，报告与拆分前的 check_deck.py 相同。

机器检查
  1. 字号小于下限（ERROR）。下限默认取 tokens.json 的 size.ppt.body 按 layout.ppt.canvas.px_per_pt 换算成磅，即 9pt；
     全册字号超过 8 级（WARNING）
  2. 页面用了 2 种以上强调色却找不到图例色块（WARNING，启发式）；配了色表时列出色表外的颜色（INFO）
  3. 配了语义色表时，页面用了色表外的强调色（WARNING）

人工核对：每页用到的强调色，用于对照项目色表检查一色一义。

配置文件（JSON，全部可选）。本模块只读下面四个键，其他键留给文字检查：
{
  "min_font": 9,                                  // 最小字号（pt），缺省按 tokens.json 换算
  "max_levels": 8,                                // 全册字号层级上限，默认 8
  "palette": ["1F2633", "4A5363", ...],          // 项目色表，色表外的颜色列为 INFO
  "accents": {"336EE8": "AI", "17998A": "我方服务", "CE8422": "我方产品"}  // 语义色表：色值: 含义
}
示例见同目录的 check_deck_visual.example.json，色值与 tokens.json 的 color.ppt 一致。
"""
from __future__ import annotations

import argparse
import collections
import json
import os
import re
import sys
from pathlib import Path

try:
    from pptx import Presentation
    from pptx.util import Emu
except ImportError:  # pragma: no cover
    sys.exit("缺少 python-pptx：pip install python-pptx")

TOKENS_ENV = "AHAM_DESIGN_TOKENS"
_REFERENCE = re.compile(r"^\{([A-Za-z0-9_.\-]+)\}$")


def tokens_path() -> Path:
    """与 html2pptx/tokens.js 相同的查找顺序：环境变量 AHAM_DESIGN_TOKENS，再从本文件向上找插件根目录。"""
    if os.environ.get(TOKENS_ENV):
        return Path(os.environ[TOKENS_ENV]).expanduser().resolve()
    for parent in Path(__file__).resolve().parents:
        if (parent / "tokens.json").is_file() and (parent / ".claude-plugin" / "plugin.json").is_file():
            return parent / "tokens.json"
    raise SystemExit(f"找不到 tokens.json：本脚本不在 aham-design 插件目录里，也没有设置 {TOKENS_ENV}")


TOKENS = json.loads(tokens_path().read_text(encoding="utf-8"))


def token(dotted: str, seen: tuple[str, ...] = ()):
    """取一个取值，解析 {组.名} 引用。"""
    if dotted in seen:
        raise SystemExit(f"tokens.json 循环引用：{' → '.join(seen + (dotted,))}")
    node = TOKENS
    for part in dotted.split("."):
        node = node[part]
    value = node["$value"]
    m = _REFERENCE.match(value) if isinstance(value, str) else None
    return token(m.group(1), seen + (dotted,)) if m else value


# 最小字号 = 正文字号（px）换算成磅
_MIN_PT = token("size.ppt.body") / token("layout.ppt.canvas.px_per_pt")

DEFAULTS = {
    "min_font": int(_MIN_PT) if float(_MIN_PT).is_integer() else _MIN_PT,
    "max_levels": 8,
    "palette": [],
    "accents": {},
}
KEYS = tuple(DEFAULTS)


def load_config(user: dict | None) -> dict:
    """从项目配置里取本模块的键，缺的用 DEFAULTS。色表统一成去掉 # 的大写色值集合。"""
    cfg = {k: (list(v) if isinstance(v, list) else (dict(v) if isinstance(v, dict) else v)) for k, v in DEFAULTS.items()}
    for k, v in (user or {}).items():
        if k in KEYS:
            cfg[k] = v
    cfg["palette"] = {c.upper().lstrip("#") for c in cfg["palette"]}
    return cfg


class Findings:
    """检查结果：每条是 (页码, 说明)。报告按页码排序，同一页按加入的先后。"""

    def __init__(self):
        self.err, self.warn, self.info = [], [], []


def is_accent(c):
    """饱和度和明度都够的颜色算强调色；灰、灰蓝、浅底不算。"""
    r, g, b = (int(c[i:i + 2], 16) / 255 for i in (0, 2, 4))
    mx, mn = max(r, g, b), min(r, g, b)
    return mx > 0.35 and (mx - mn) / mx > 0.45 if mx else False


def iter_shapes(shapes):
    for sh in shapes:
        if sh.shape_type == 6:  # group
            yield from iter_shapes(sh.shapes)
        else:
            yield sh


def color_of(obj):
    try:
        if obj.type is not None and obj.rgb is not None:
            return str(obj.rgb).upper()
    except Exception:
        pass
    return None


def read_slide(slide, h):
    """返回 段落列表[(text, max_pt, top_ratio)]、字号计数、颜色计数、讲稿、图例色块。文字检查也用本函数读页面。"""
    paras, sizes, colors = [], collections.Counter(), collections.Counter()
    swatches = set()
    for sh in iter_shapes(slide.shapes):
        try:
            if sh.fill.type == 1:
                c = color_of(sh.fill.fore_color)
                if c:
                    colors[("填充", c)] += 1
                    # 图例色块：边长不超过 0.3 英寸的小方块或圆点
                    if c and (sh.width or 0) <= Emu(274320) and (sh.height or 0) <= Emu(274320):
                        swatches.add(c)
        except Exception:
            pass
        try:
            if sh.line.fill.type == 1:
                c = color_of(sh.line.color)
                if c:
                    colors[("线条", c)] += 1
                    # 描边色块和短线段也算图例：边长不超过 0.3 英寸
                    if (sh.width or 0) <= Emu(274320) and (sh.height or 0) <= Emu(274320):
                        swatches.add(c)
        except Exception:
            pass
        if sh.shape_type == 13:  # 图片：图内颜色读不到，单独计数
            colors[("图片", "")] += 1
            continue
        top = (sh.top or 0) / h if h else 0
        frames = []
        if sh.has_text_frame:
            frames.append(sh.text_frame)
        if getattr(sh, "has_table", False) and sh.has_table:
            for row in sh.table.rows:
                for cell in row.cells:
                    frames.append(cell.text_frame)
        for tf in frames:
            for p in tf.paragraphs:
                text = "".join(r.text for r in p.runs).strip()
                if not text:
                    continue
                pmax = 0
                for r in p.runs:
                    if not r.text.strip():
                        continue
                    if r.font.size:
                        pt = round(r.font.size.pt, 2)
                        sizes[pt] += len(r.text)
                        pmax = max(pmax, pt)
                    c = color_of(r.font.color) if r.font.color else None
                    if c:
                        colors[("文字", c)] += len(r.text)
                paras.append((text, pmax, top))
    notes = ""
    if slide.has_notes_slide:
        notes = slide.notes_slide.notes_text_frame.text
    return paras, sizes, colors, notes, swatches


def fmt(pages):
    p = sorted(pages)
    return "、".join(map(str, p[:12])) + ("…" if len(p) > 12 else "")


class VisualCheck:
    """逐页调用 slide_colors 和 slide_accent_table，全册读完后调用 finish。"""

    def __init__(self, cfg: dict):
        self.cfg = cfg
        self.size_hits = collections.defaultdict(set)
        self.color_hits = collections.defaultdict(set)
        self.accents = []
        self._acc = {}

    def slide_colors(self, idx, data, out: Findings):
        """字号计数、色表外颜色、强调色和图例。"""
        _, sizes, colors, _, swatches = data
        for pt in sizes:
            self.size_hits[pt].add(idx)
        npic = colors.pop(("图片", ""), 0)
        for (kind, c) in colors:
            if self.cfg["palette"] and c not in self.cfg["palette"]:
                self.color_hits[(kind, c)].add(idx)
        acc = sorted({c for (_, c) in colors if is_accent(c)})
        self._acc[idx] = acc
        self.accents.append((idx, acc, npic))
        if len(acc) >= 2 and not any(is_accent(c) for c in swatches):
            out.warn.append((idx, f"用了 {len(acc)} 种强调色，未找到图例色块（启发式；子标题已写明含义时可忽略）"))

    def slide_accent_table(self, idx, out: Findings):
        """配了语义色表时，查色表外的强调色。"""
        if self.cfg["accents"]:
            known = {c.upper().lstrip("#") for c in self.cfg["accents"]}
            extra = [c for c in self._acc.get(idx, []) if c not in known]
            if extra:
                out.warn.append((idx, f"用了语义色表外的强调色 {' '.join('#' + c for c in extra)}"))

    def finish(self, out: Findings):
        """全册的字号下限、字号层级和色表外颜色。"""
        for pt, pages in sorted(self.size_hits.items()):
            if pt < self.cfg["min_font"]:
                out.err.append((min(pages), f"字号 {pt}pt 小于下限 {self.cfg['min_font']}pt，出现在第 {fmt(pages)} 页"))
        if len(self.size_hits) > self.cfg["max_levels"]:
            out.warn.append((1, f"全册用了 {len(self.size_hits)} 级字号（上限 {self.cfg['max_levels']}）：{', '.join(str(x) for x in sorted(self.size_hits))} pt"))
        for (kind, c), pages in sorted(self.color_hits.items()):
            out.info.append((min(pages), f"{kind}色 #{c} 不在色表内，出现在第 {fmt(pages)} 页"))

    def manual_sections(self) -> list[str]:
        out = ["\n\n## 人工核对四　每页强调色（对照项目色表，一色一义）\n"]
        out.append("图片和图标内的颜色读不到，有图片的页要打开对照。\n")
        out.append("| 页 | 强调色（文字、填充、线条） | 图片和图标数 |\n| --- | --- | --- |")
        for i, acc, npic in self.accents:
            out.append(f"| {i} | {' '.join('#' + c for c in acc) or '无'} | {npic or ''} |")
        return out


def findings_lines(out: Findings) -> list[str]:
    lines = []
    for name, lst in (("ERROR", out.err), ("WARNING", out.warn), ("INFO", out.info)):
        lines.append(f"\n## {name}\n")
        if not lst:
            lines.append("无\n")
        for p, msg in sorted(lst, key=lambda x: x[0]):
            lines.append(f"- 第 {p} 页　{msg}")
    return lines


def write_report(report: str, path, out: Findings) -> None:
    if path:
        open(path, "w", encoding="utf-8").write(report)
        print(f"已写出 {path}：ERROR {len(out.err)}　WARNING {len(out.warn)}　INFO {len(out.info)}")
    else:
        print(report)


def main(argv=None):
    ap = argparse.ArgumentParser(description="PPT 视觉检查：字号、强调色、图例和色表")
    ap.add_argument("pptx")
    ap.add_argument("--config")
    ap.add_argument("--out")
    a = ap.parse_args(argv)
    cfg = load_config(json.load(open(a.config, encoding="utf-8")) if a.config else None)
    prs = Presentation(a.pptx)
    out, check = Findings(), VisualCheck(cfg)
    for idx, s in enumerate(prs.slides, 1):
        data = read_slide(s, prs.slide_height)
        check.slide_colors(idx, data, out)
        check.slide_accent_table(idx, out)
    check.finish(out)
    lines = [f"# PPT 视觉检查报告\n\n文件：{a.pptx}　共 {len(prs.slides)} 页\n",
             f"ERROR {len(out.err)} 条　WARNING {len(out.warn)} 条　INFO {len(out.info)} 条\n"]
    lines += findings_lines(out) + check.manual_sections()
    write_report("\n".join(lines) + "\n", a.out, out)
    return 1 if out.err else 0


if __name__ == "__main__":
    sys.exit(main())
