"""读取 aham-design 插件根目录的 tokens.json，解析引用，生成排版引擎用的文档取值视图。

tokens.json 是全部视觉取值的唯一来源。引擎不写死颜色和字号，只从这里读。

查找顺序：
1. 环境变量 AHAM_DESIGN_TOKENS 指向的文件。
2. 从本包所在目录向上找，第一个同时有 tokens.json 和 .claude-plugin/plugin.json 的目录，即插件根目录。

tokens.json 的写法：每个取值是 {"$value": 值, "$description": 用途}；以 $ 开头的键是说明，不是取值；
值写成 "{组.名}" 时引用另一个取值。
"""

from __future__ import annotations

import copy
import json
import os
import re
from functools import lru_cache
from pathlib import Path
from typing import Any

__all__ = [
    "TOKENS_ENV",
    "TokenError",
    "document_style",
    "flatten",
    "load_tokens",
    "resolve",
    "tokens_path",
    "value",
]

TOKENS_ENV = "AHAM_DESIGN_TOKENS"
_PACKAGE = Path(__file__).resolve().parent
_REFERENCE = re.compile(r"^\{([A-Za-z0-9_.\-]+)\}$")


class TokenError(ValueError):
    pass


def tokens_path() -> Path:
    override = os.environ.get(TOKENS_ENV)
    if override:
        return Path(override).expanduser().resolve()
    for parent in _PACKAGE.parents:
        if (parent / "tokens.json").is_file() and (parent / ".claude-plugin" / "plugin.json").is_file():
            return parent / "tokens.json"
    raise TokenError(f"找不到 tokens.json：本包不在 aham-design 插件目录里，也没有设置 {TOKENS_ENV}")


def load_tokens(path: Path | None = None) -> dict[str, Any]:
    target = Path(path) if path else tokens_path()
    try:
        data = json.loads(target.read_text("utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise TokenError(f"无法读取 tokens.json：{target}: {exc}") from exc
    if not isinstance(data, dict):
        raise TokenError(f"tokens.json 根节点必须是对象：{target}")
    return data


def _is_leaf(node: Any) -> bool:
    return isinstance(node, dict) and "$value" in node


def _lookup(raw: dict[str, Any], dotted: str) -> Any:
    node: Any = raw
    for part in dotted.split("."):
        if not isinstance(node, dict) or part not in node:
            raise TokenError(f"引用的取值不存在：{{{dotted}}}")
        node = node[part]
    if not _is_leaf(node):
        raise TokenError(f"引用的不是取值：{{{dotted}}}")
    return node["$value"]


def _resolve_value(raw: dict[str, Any], value: Any, seen: tuple[str, ...]) -> Any:
    if isinstance(value, str):
        match = _REFERENCE.match(value)
        if match:
            target = match.group(1)
            if target in seen:
                raise TokenError("引用成环：" + " → ".join((*seen, target)))
            return _resolve_value(raw, _lookup(raw, target), (*seen, target))
    return value


def resolve(raw: dict[str, Any]) -> dict[str, Any]:
    """去掉说明键，只留取值，引用换成被引用的值。返回与 tokens.json 同结构的嵌套字典。"""

    def walk(node: Any, path: str) -> Any:
        if _is_leaf(node):
            return _resolve_value(raw, node["$value"], (path,))
        if isinstance(node, dict):
            return {key: walk(child, f"{path}.{key}" if path else key)
                    for key, child in node.items() if not key.startswith("$")}
        return node

    return walk(raw, "")


def flatten(raw: dict[str, Any]) -> dict[str, dict[str, Any]]:
    """全部取值的「点分路径 → 取值节点」，测试和检查用。"""
    found: dict[str, dict[str, Any]] = {}

    def walk(node: Any, path: str) -> None:
        if _is_leaf(node):
            found[path] = node
            return
        if isinstance(node, dict):
            for key, child in node.items():
                if not key.startswith("$"):
                    walk(child, f"{path}.{key}" if path else key)

    walk(raw, "")
    return found


@lru_cache(maxsize=None)
def _resolved(path: str) -> dict[str, Any]:
    return resolve(load_tokens(Path(path)))


def value(dotted: str, path: Path | None = None) -> Any:
    """按点分路径取一个解析后的取值，例如 value("color.blue.text")。"""
    node: Any = _resolved(str(Path(path) if path else tokens_path()))
    for part in dotted.split("."):
        node = node[part]
    return copy.deepcopy(node)


def _hex(value: str) -> str:
    """Word 的 OOXML 色值不带 #。"""
    return value.lstrip("#").upper()


def document_style(path: Path | None = None) -> dict[str, Any]:
    """文档取值视图：Word 渲染器和表格列宽计算读的字典。

    每一项都来自 tokens.json；这里只改结构和色值写法，不加取值。
    """
    raw = load_tokens(path)
    data = resolve(raw)
    try:
        role = data["role"]["document"]
        family = data["font"]["family"]
        weight = data["font"]["weight"]
        file_font = family["file"]
        return {
            "version": raw["$meta"]["version"],
            "colors": {name: _hex(color) for name, color in role["color"].items()},
            "categorical": {name: _hex(color) for name, color in role["party"].items()},
            "fonts": {
                "heading": file_font,
                "body": file_font,
                "table": file_font,
                "latin": file_font,
                "web_stack": family["ui"],
                "code_stack": family["code"],
                "weights": dict(weight["document"]),
                "web_weights": dict(weight["web"]),
            },
            "word_pt": dict(data["size"]["word"]),
            "excel_pt": dict(data["size"]["excel"]),
            "web_px": dict(data["size"]["web"]),
            "rules": {
                "word_eighth_pt": dict(data["line"]["word"]),
                "web_px": dict(data["line"]["web"]),
                "excel": dict(data["line"]["excel"]),
                "colors": dict(role["rule_color"]),
            },
            "page": dict(data["layout"]["page"]),
            "web": copy.deepcopy(data["layout"]["web"]),
            "word": copy.deepcopy(data["layout"]["word"]),
            "excel": copy.deepcopy(data["layout"]["excel"]),
            "limits": dict(data["layout"]["limits"]),
            "radius": dict(data["radius"]),
        }
    except KeyError as exc:
        raise TokenError(f"tokens.json 缺少文档取值：{exc}") from exc
