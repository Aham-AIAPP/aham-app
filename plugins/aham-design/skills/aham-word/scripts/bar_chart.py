#!/usr/bin/env python3
"""按数据 JSON 生成分组柱状图 SVG，供网页的 svg 内容块使用。

用法：python3 scripts/bar_chart.py 数据.json 输出.svg
数据格式见 aham_doc/chart.py。
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from aham_doc.chart import main  # noqa: E402

if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
