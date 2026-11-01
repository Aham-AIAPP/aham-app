# -*- coding: utf-8 -*-
"""
PPT 成品自查（读 .pptx，不改文件）。阶段 6 的样页和阶段 8 交付前各跑一次。
用法：
    python check_deck.py <方案.pptx> [--config 项目配置.json] [--out 报告.md]

本入口按页依次调用两个模块，合成一份报告：
- 视觉检查：aham-design 插件 aham-ppt 引擎的 assets/tools/check_deck_visual.py。查字号下限、字号层级、
  强调色和图例、色表外的颜色，列出每页强调色（人工核对四）。
- 文字检查：本目录的 deck_text.py。查分句、禁用词、口语词、观察词、页码引用、内部编号、编号跳号、术语、
  价格说法、汉字数量和标题形式，列出标题通读、页码引用和数量说法（人工核对一至三）。
每页的调用顺序与拆分前的 check_deck.py 相同，所以同一份 PPTX 的报告与拆分前一致。

项目配置是一个 JSON 文件，两个模块各读自己的键：视觉键见引擎的 check_deck_visual.example.json，
文字键见本目录的 check_deck.example.json。引擎目录由 find_engine.py 查找。
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import deck_text  # noqa: E402
from find_engine import engine_dir  # noqa: E402

sys.path.insert(0, str(engine_dir() / "assets" / "tools"))
import check_deck_visual as visual  # noqa: E402

from pptx import Presentation  # noqa: E402  引擎模块已检查 python-pptx 是否安装


def main(argv=None):
    ap = argparse.ArgumentParser(description="PPT 成品自查：视觉检查加文字检查")
    ap.add_argument("pptx")
    ap.add_argument("--config")
    ap.add_argument("--out")
    a = ap.parse_args(argv)
    user = json.load(open(a.config, encoding="utf-8")) if a.config else None
    prs = Presentation(a.pptx)
    N = len(prs.slides)

    out = visual.Findings()
    vis = visual.VisualCheck(visual.load_config(user))
    txt = deck_text.TextCheck(deck_text.load_config(user), N)
    for idx, s in enumerate(prs.slides, 1):
        data = visual.read_slide(s, prs.slide_height)
        txt.slide_title(idx, data)
        vis.slide_colors(idx, data, out)
        txt.slide_commerce(idx, data, out)
        vis.slide_accent_table(idx, out)
        txt.slide_wording(idx, data, out)
    vis.finish(out)

    lines = [f"# 方案 PPT 自查报告\n\n文件：{a.pptx}　共 {N} 页\n",
             f"ERROR {len(out.err)} 条　WARNING {len(out.warn)} 条　INFO {len(out.info)} 条\n"]
    lines += visual.findings_lines(out) + txt.manual_sections() + vis.manual_sections()
    visual.write_report("\n".join(lines) + "\n", a.out, out)
    return 1 if out.err else 0


if __name__ == "__main__":
    sys.exit(main())
