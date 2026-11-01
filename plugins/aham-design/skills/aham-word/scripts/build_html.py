#!/usr/bin/env python3
"""按网页内容 JSON 生成单文件网页。

用法：python3 scripts/build_html.py 内容.json 输出.html [--fragment]
内容格式见 references/web-format.md。
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from aham_doc.html import main  # noqa: E402

if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
