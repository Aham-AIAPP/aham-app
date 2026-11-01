#!/usr/bin/env python3
"""按 Word 内容 JSON 生成网页预览，与 build_docx.py 读同一份内容。

用法：python3 scripts/build_preview.py 内容.json 输出.html
内容格式见 references/content-format.md。
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from aham_doc.preview import main  # noqa: E402

if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
