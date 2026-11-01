#!/usr/bin/env python3
"""找到 aham-design 插件里的 aham-ppt 引擎目录。本技能不复制引擎文件，全部从这里调用。

用法：
  python3 find_engine.py           打印引擎目录 <aham-design>/skills/aham-ppt
  python3 find_engine.py --root    打印 aham-design 插件根目录
  python3 find_engine.py --all     列出每个查找位置和结果，找不到时用来排查

两个插件装在不同目录，本技能运行时 CLAUDE_PLUGIN_ROOT 指向 aham-app，不能直接拼出 aham-design 的路径。
按下面的顺序查找，每个候选目录都要通过核对：.claude-plugin/plugin.json 的 name 是 aham-design、
主版本号是 1（与 aham-app 声明的依赖 ^1.0.0 一致），并且有 skills/aham-ppt/SKILL.md。

1. 环境变量 AHAM_DESIGN_ROOT：用户手动指定的插件根目录。
2. 与 aham-app 同级的 aham-design 目录：仓库里的 plugins/aham-app 与 plugins/aham-design，
   或用 --plugin-dir 并排加载的两个目录。
3. Claude Code 的安装记录 <配置目录>/plugins/installed_plugins.json 里 aham-design@<市场> 的 installPath。
   配置目录取环境变量 CLAUDE_CONFIG_DIR，没有时为 ~/.claude。同一市场的条目优先。
4. 插件缓存的同级目录：缓存结构是 <缓存>/<市场>/<插件>/<版本>/，取 <缓存>/<市场>/aham-design/ 下版本号最高的一份。
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
from pathlib import Path

NAME = "aham-design"
MAJOR = 1
ENV = "AHAM_DESIGN_ROOT"
HERE = Path(__file__).resolve()
SKILL_DIR = HERE.parents[1]          # <aham-app>/skills/aham-ppt-proposal
APP_ROOT = HERE.parents[3]           # <aham-app>


def check(root: Path) -> str | None:
    """候选目录合格时返回 None，不合格时返回原因。"""
    manifest = root / ".claude-plugin" / "plugin.json"
    if not manifest.is_file():
        return "没有 .claude-plugin/plugin.json"
    try:
        meta = json.loads(manifest.read_text("utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        return f"plugin.json 读不出：{exc}"
    if meta.get("name") != NAME:
        return f"插件名是 {meta.get('name')}"
    major = re.match(r"(\d+)", str(meta.get("version", "")))
    if not major or int(major.group(1)) != MAJOR:
        return f"版本 {meta.get('version')} 不满足 ^{MAJOR}.0.0"
    if not (root / "skills" / "aham-ppt" / "SKILL.md").is_file():
        return "没有 skills/aham-ppt/SKILL.md"
    return None


def _version_key(path: Path):
    return tuple(int(x) if x.isdigit() else -1 for x in re.split(r"[.\-+]", path.name))


def candidates():
    """按查找顺序给出 (来源, 目录)。"""
    if os.environ.get(ENV):
        yield f"环境变量 {ENV}", Path(os.environ[ENV]).expanduser()
    yield "aham-app 的同级目录", APP_ROOT.parent / NAME
    config = Path(os.environ.get("CLAUDE_CONFIG_DIR") or Path.home() / ".claude").expanduser()
    record = config / "plugins" / "installed_plugins.json"
    if record.is_file():
        try:
            plugins = json.loads(record.read_text("utf-8")).get("plugins", {})
        except (OSError, json.JSONDecodeError):
            plugins = {}
        market = APP_ROOT.parent.parent.name  # 缓存结构下 aham-app 所在的市场名
        keys = sorted((k for k in plugins if k.split("@")[0] == NAME), key=lambda k: k.split("@")[-1] != market)
        for key in keys:
            for entry in plugins[key] or []:
                if entry.get("installPath"):
                    yield f"安装记录 {key}", Path(entry["installPath"])
    cache_dir = APP_ROOT.parent.parent / NAME
    if cache_dir.is_dir():
        for version in sorted((p for p in cache_dir.iterdir() if p.is_dir()), key=_version_key, reverse=True):
            yield "插件缓存的同级目录", version


def find_root() -> Path:
    for _, root in candidates():
        if check(root) is None:
            return root.resolve()
    tried = "\n".join(f"  {src}：{root}（{check(root)}）" for src, root in candidates())
    raise SystemExit(
        "找不到 aham-design 插件。先安装 aham-design，或把环境变量 AHAM_DESIGN_ROOT 设为它的插件根目录。\n"
        f"已查找：\n{tried or '  （没有候选目录）'}")


def engine_dir() -> Path:
    return find_root() / "skills" / "aham-ppt"


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="找到 aham-design 插件里的 aham-ppt 引擎目录")
    ap.add_argument("--root", action="store_true", help="打印插件根目录")
    ap.add_argument("--all", action="store_true", help="列出每个查找位置和结果")
    a = ap.parse_args(argv)
    if a.all:
        for src, root in candidates():
            print(f"{src}：{root}　{check(root) or '可用'}")
        return 0
    print(find_root() if a.root else engine_dir())
    return 0


if __name__ == "__main__":
    sys.exit(main())
