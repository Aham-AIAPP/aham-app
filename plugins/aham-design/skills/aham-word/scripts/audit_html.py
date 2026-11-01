#!/usr/bin/env python3
"""检查网页的色值、字体、外部资源、荧光标记、风险条和用词。

用法：python3 scripts/audit_html.py 网页.html
全部通过时退出码为 0。
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from aham_doc.checks import main  # noqa: E402

if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
