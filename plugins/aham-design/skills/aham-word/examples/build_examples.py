#!/usr/bin/env python3
"""生成 Aham Word 样张 examples/aham-word-demo.docx。

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

CONTENT = HERE / "demo-content.json"
NAME = "aham-word-demo.docx"


def build(out_dir: Path = HERE) -> Path:
    return build_document(load_content(CONTENT), Path(out_dir) / NAME, HERE)


if __name__ == "__main__":
    print(build(Path(sys.argv[1]) if len(sys.argv) > 1 else HERE))
