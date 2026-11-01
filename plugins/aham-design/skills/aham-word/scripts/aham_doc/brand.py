"""品牌配置：公司名、英文品牌名、logo 和 Word 标记字符样式名。

引擎不写死任何公司的取值。调用方有两种传法：

1. 在技能的 config/brand.json 里写好，引擎第一次用到时自动读取。
2. 调用 set_brand(Brand(...)) 显式传入，优先于 config/brand.json。

config/brand.json 的字段：company、short_name、wordmark、mark_style、logo。
logo 写相对技能目录的路径；文件不存在时，Word 页眉改印英文品牌名，封面改留空白。
"""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from .paths import CONFIG, SKILL

__all__ = ["Brand", "BrandError", "current_brand", "load_brand", "reset_brand", "set_brand"]

BRAND_FILE = "brand.json"
FIELDS = ("company", "short_name", "wordmark", "mark_style")


class BrandError(ValueError):
    pass


@dataclass(frozen=True)
class Brand:
    company: str
    short_name: str
    wordmark: str
    mark_style: str
    logo: Path | None = None

    @property
    def logo_title(self) -> str:
        return f"{self.wordmark} Logo"


def load_brand(path: Path, base: Path | None = None) -> Brand:
    """读取品牌配置文件。logo 按 base（缺省为文件所在技能目录）解析。"""
    try:
        data: dict[str, Any] = json.loads(Path(path).read_text("utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise BrandError(f"无法读取品牌配置：{path}: {exc}") from exc
    missing = [key for key in FIELDS if not str(data.get(key) or "").strip()]
    if missing:
        raise BrandError(f"品牌配置缺少字段：{'、'.join(missing)}（{path}）")
    root = base if base is not None else Path(path).resolve().parent.parent
    logo = data.get("logo")
    return Brand(
        company=str(data["company"]),
        short_name=str(data["short_name"]),
        wordmark=str(data["wordmark"]),
        mark_style=str(data["mark_style"]),
        logo=(root / logo) if logo else None,
    )


_current: Brand | None = None


def set_brand(brand: Brand) -> None:
    global _current
    _current = brand


def reset_brand() -> None:
    """清除显式传入的品牌配置，下次使用时重新读技能的 config/brand.json。"""
    global _current
    _current = None


def current_brand() -> Brand:
    """返回调用方传入的品牌配置；没有传入时读技能的 config/brand.json。"""
    global _current
    if _current is None:
        path = CONFIG / BRAND_FILE
        if not path.is_file():
            raise BrandError(f"调用方没有传入品牌配置，技能目录里也没有 config/{BRAND_FILE}")
        _current = load_brand(path, SKILL)
    return _current
