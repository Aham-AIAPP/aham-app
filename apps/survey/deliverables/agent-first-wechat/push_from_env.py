#!/usr/bin/env python3
"""Run the bundled Aham push client without placing AHAM_TOKEN in OS process arguments."""
import os
import pathlib
import runpy
import sys

if len(sys.argv) != 3:
    raise SystemExit("usage: push_from_env.py <article-dir> <push.py>")

article_dir = pathlib.Path(sys.argv[1]).resolve()
push_script = pathlib.Path(sys.argv[2]).resolve()
token = os.environ.get("AHAM_TOKEN")
if not token:
    raise SystemExit("AHAM_TOKEN is not available")

sys.argv = [
    str(push_script),
    "--url", "http://127.0.0.1:8788/draft",
    "--token", token,
    "--dir", str(article_dir),
    "--title", "Agent First：App 不再是入口，而是能力载体",
    "--author", "Aham",
    "--digest", "App 不会消失，但会从交互中心退到能力载体。一次关于 Agent、Skill 与 MCP 如何重新分配软件职责的实践。",
]
runpy.run_path(str(push_script), run_name="__main__")
