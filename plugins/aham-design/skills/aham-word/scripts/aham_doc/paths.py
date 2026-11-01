"""引擎在技能里的位置：<技能>/scripts/aham_doc/。规则读 <技能>/config/，视觉取值读插件根的 tokens.json（见 tokens 模块）。"""

from __future__ import annotations

import json
from functools import lru_cache
from pathlib import Path
from typing import Any

__all__ = ["CONFIG", "PACKAGE", "SCRIPTS", "SKILL", "config", "layout_rule", "writing_rules"]

PACKAGE = Path(__file__).resolve().parent
SCRIPTS = PACKAGE.parent
SKILL = SCRIPTS.parent
CONFIG = SKILL / "config"


@lru_cache(maxsize=None)
def config(name: str) -> dict[str, Any]:
    """读取技能 config/ 下的 JSON：writing-rules.json、layout-rules.json、brand.json。"""
    return json.loads((CONFIG / name).read_text("utf-8"))


def writing_rules() -> dict[str, Any]:
    return config("writing-rules.json")


def layout_rule(rule_id: str) -> dict[str, Any]:
    """按 id 取一条版面规则的取值。规则不存在时报错，避免静默退回旧做法。"""
    for rule in config("layout-rules.json")["rules"]:
        if rule["id"] == rule_id:
            return rule["value"]
    raise KeyError(f"layout-rules.json 没有规则 {rule_id}")
