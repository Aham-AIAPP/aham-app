#!/usr/bin/env python3
"""按内容 JSON 生成 Word 文档。

用法：python3 scripts/build_docx.py 内容.json 输出.docx
内容格式见 references/content-format.md。
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from aham_doc.document import main  # noqa: E402

if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
