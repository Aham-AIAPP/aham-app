#!/usr/bin/env python3
"""生成 Aham Word 样张：examples/aham-word-demo.docx 和同一份内容的网页预览 examples/aham-word-demo.html。

内容在 examples/demo-content.json，介绍本技能自身；排版全部由引擎 aham_doc 按 tokens.json 完成。
用法：python3 examples/build_examples.py [输出目录]
要导出带目录页码的 PDF，再运行：python3 scripts/update_toc_export.py examples/aham-word-demo.docx
"""

from __future__ import annotations

import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "scripts"))

from aham_doc.document import build_document, load_content  # noqa: E402
from aham_doc.preview import build_preview  # noqa: E402

CONTENT = HERE / "demo-content.json"
NAME = "aham-word-demo.docx"
HTML_NAME = "aham-word-demo.html"


def build(out_dir: Path = HERE) -> Path:
    return build_document(load_content(CONTENT), Path(out_dir) / NAME, HERE)


def build_html(out_dir: Path = HERE) -> Path:
    target = Path(out_dir) / HTML_NAME
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(build_preview(load_content(CONTENT), HERE), "utf-8")
    return target


if __name__ == "__main__":
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else HERE
    print(build(out))
    print(build_html(out))
