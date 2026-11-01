"""tokens.json 的测试：结构完整、取值在范围内、每个取值有用途说明、对比度达标。

对比度按 WCAG 2.x 的相对亮度公式自己计算，不依赖第三方库。
用法：python3 -m unittest discover -s plugins/aham-design/tests
"""

from __future__ import annotations

import json
import re
import sys
import unittest
from pathlib import Path

PLUGIN = Path(__file__).resolve().parents[1]
TOKENS = PLUGIN / "tokens.json"
sys.path.insert(0, str(PLUGIN / "skills/aham-word/scripts"))

from aham_doc import tokens as T  # noqa: E402

RAW = json.loads(TOKENS.read_text("utf-8"))
RESOLVED = T.resolve(RAW)
LEAVES = T.flatten(RAW)
HEX = re.compile(r"^#[0-9A-F]{6}$")


def luminance(hex_color: str) -> float:
    """WCAG 2.x 相对亮度。sRGB 分量先线性化，阈值 0.04045。"""
    value = hex_color.lstrip("#")
    channels = []
    for index in (0, 2, 4):
        c = int(value[index:index + 2], 16) / 255
        channels.append(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4)
    r, g, b = channels
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(a: str, b: str) -> float:
    hi, lo = sorted((luminance(a), luminance(b)), reverse=True)
    return (hi + 0.05) / (lo + 0.05)


def resolved(dotted: str):
    node = RESOLVED
    for part in dotted.split("."):
        node = node[part]
    return node


def color_paths(prefix: str) -> list[str]:
    return [path for path in LEAVES if path.startswith(prefix)]


class StructureTests(unittest.TestCase):
    def test_top_level_groups(self):
        self.assertEqual(
            [key for key in RAW if not key.startswith("$")],
            ["color", "font", "size", "line", "radius", "shadow", "layout", "role"],
        )
        self.assertEqual(RAW["$meta"]["version"], "1.0.0")

    def test_every_value_has_a_description(self):
        missing = [path for path, node in LEAVES.items() if not str(node.get("$description") or "").strip()]
        self.assertEqual(missing, [])

    def test_every_group_has_a_description_or_is_self_explanatory(self):
        for name in ("color", "font", "size", "line", "radius", "shadow", "layout", "role"):
            self.assertTrue(RAW[name].get("$description"), name)

    def test_references_resolve(self):
        for path, node in LEAVES.items():
            T._resolve_value(RAW, node["$value"], (path,))

    def test_decision_table_groups_are_complete(self):
        color = RESOLVED["color"]
        self.assertEqual(set(color["blue"]), {"base", "hover", "text", "strong", "bg", "dark"})
        self.assertEqual(sorted(color["gray"], key=int), [str(i) for i in range(19)])
        self.assertEqual(set(color["gray_dark"]), {
            "bg", "canvas", "fill", "selected", "button", "button_hover", "line", "button_press", "nav_hover",
            "nav_selected", "edge", "line_soft", "line_strong", "pop_bg", "pop_edge", "ink", "ink_2", "muted", "faint"})
        for name in ("success", "warning", "danger"):
            for suffix in ("", "_bg", "_dark"):
                self.assertIn(name + suffix, color["semantic"])
        self.assertIn("hot", color["semantic"])
        self.assertIn("hot_bg", color["semantic"])
        self.assertEqual(sorted(color["categorical"]), ["1", "2", "3", "4", "5", "6"])
        self.assertEqual(color["ppt"]["service"], "#17998A")
        self.assertEqual(color["ppt"]["product"], "#CE8422")
        for medium in ("word", "excel", "web", "ppt", "ui"):
            self.assertTrue(RESOLVED["size"][medium], medium)

    def test_decision_table_values(self):
        expected = {
            "color.blue.base": "#336EE8", "color.blue.hover": "#2A62D6", "color.blue.text": "#2453C7",
            "color.blue.strong": "#1C45AC", "color.blue.bg": "#EEF2FC", "color.blue.dark": "#6C97F0",
            "color.gray.1": "#F6F8FB", "color.gray.7": "#D9DEE5", "color.gray.13": "#6B7482",
            "color.gray.18": "#141A26", "color.gray_dark.bg": "#12151A", "color.gray_dark.faint": "#747B87",
            "color.semantic.danger": "#B42318", "color.semantic.hot": "#C2410C",
            "color.semantic.success_dark": "#6DBE8F", "color.categorical.6": "#C4421A",
            "font.family.file": "微软雅黑",
        }
        for path, value in expected.items():
            self.assertEqual(resolved(path), value, path)
        word = RESOLVED["size"]["word"]
        self.assertEqual([word[k] for k in ("cover_title", "h1", "h2", "h3", "body", "caption")],
                         [28, 16, 14, 12, 10.5, 8.5])


class RangeTests(unittest.TestCase):
    def test_colors_are_uppercase_hex(self):
        for path in color_paths("color."):
            self.assertRegex(resolved(path), HEX, path)
        for path in color_paths("role.document.color.") + color_paths("role.document.party."):
            self.assertRegex(resolved(path), HEX, path)

    def test_light_gray_steps_get_darker(self):
        values = [luminance(resolved(f"color.gray.{i}")) for i in range(19)]
        self.assertEqual(values, sorted(values, reverse=True))
        self.assertEqual(len(set(RESOLVED["color"]["gray"].values())), 19)

    def test_font_sizes_in_range(self):
        bounds = {"word": (6, 40), "excel": (6, 40), "web": (10, 48), "ppt": (18, 96), "ui": (12, 32)}
        for medium, (low, high) in bounds.items():
            for key, size in RESOLVED["size"][medium].items():
                self.assertTrue(low <= size <= high, f"size.{medium}.{key} = {size}")
        self.assertGreaterEqual(RESOLVED["size"]["word"]["table"],
                                RESOLVED["layout"]["word"]["table_capacity"]["min_font_pt"])

    def test_radius_has_only_three_values(self):
        self.assertEqual(RESOLVED["radius"], {"control": 6, "panel": 8, "pill": 999})

    def test_shadow_has_only_pop_and_float(self):
        self.assertEqual(set(RESOLVED["shadow"]), {"pop", "float"})
        for value in RESOLVED["shadow"].values():
            self.assertTrue(value.startswith("0 0 0 1px var(--wb-pop-edge)"))

    def test_fonts_are_built_in(self):
        family = RESOLVED["font"]["family"]
        for banned in ("Inter", "JetBrains", "Noto Sans SC", "Arial"):
            for name, value in family.items():
                self.assertNotIn(banned, value, f"font.family.{name}")
        self.assertTrue(family["ui"].startswith('"Microsoft YaHei"'))

    def test_line_widths_positive(self):
        for medium in ("word", "web"):
            for key, width in RESOLVED["line"][medium].items():
                self.assertGreater(width, 0, f"line.{medium}.{key}")

    def test_rule_colors_name_document_colors(self):
        names = set(RESOLVED["role"]["document"]["color"])
        for key, name in RESOLVED["role"]["document"]["rule_color"].items():
            self.assertIn(name, names, key)


class ContrastTests(unittest.TestCase):
    def test_contrast_formula(self):
        self.assertAlmostEqual(contrast("#000000", "#FFFFFF"), 21.0, places=2)
        self.assertAlmostEqual(contrast("#336EE8", "#FFFFFF"), 4.63, places=2)
        self.assertAlmostEqual(contrast("#CE8422", "#FFFFFF"), 3.02, places=2)

    def test_declared_minimums(self):
        """每个写了 $extensions.contrast 的颜色，按它写明的底色和最低值检查。"""
        checked = 0
        for path, node in LEAVES.items():
            rule = (node.get("$extensions") or {}).get("contrast")
            if not rule:
                continue
            on = T._resolve_value(RAW, rule["on"], (path,))
            ratio = contrast(resolved(path), on)
            self.assertGreaterEqual(round(ratio, 2), rule["min"], f"{path} 对 {on} 只有 {ratio:.2f}:1")
            checked += 1
        self.assertGreaterEqual(checked, 30)

    def test_text_colors_need_4_5_and_graphics_3(self):
        text = ["color.blue.base", "color.blue.hover", "color.blue.text", "color.blue.strong",
                *[f"color.gray.{i}" for i in range(13, 19)],
                "color.semantic.success", "color.semantic.warning", "color.semantic.danger", "color.semantic.hot"]
        graphic = ["color.gray.11", "color.gray.12", "color.ppt.service", "color.ppt.product",
                   *[f"color.categorical.{i}" for i in range(1, 7)]]
        for path in text:
            self.assertEqual(LEAVES[path]["$extensions"]["contrast"]["min"], 4.5, path)
            self.assertGreaterEqual(contrast(resolved(path), "#FFFFFF"), 4.5, path)
        for path in graphic:
            self.assertGreaterEqual(LEAVES[path]["$extensions"]["contrast"]["min"], 3, path)
            self.assertGreaterEqual(contrast(resolved(path), "#FFFFFF"), 3.0, path)

    def test_dark_mode_text(self):
        bg = resolved("color.gray_dark.bg")
        for path in ("color.blue.dark", "color.gray_dark.ink", "color.gray_dark.ink_2", "color.gray_dark.muted",
                     "color.semantic.success_dark", "color.semantic.warning_dark", "color.semantic.danger_dark"):
            self.assertGreaterEqual(contrast(resolved(path), bg), 4.5, path)
        for path in ("color.gray_dark.faint", "color.gray_dark.line_strong"):
            self.assertGreaterEqual(contrast(resolved(path), bg), 3.0, path)

    def test_document_text_on_tint(self):
        """文档蓝字放在浅灰底上也要 4.5:1，所以文档的 accent 用 blue.text，不用 blue.base。"""
        tint = resolved("role.document.color.tint")
        self.assertGreaterEqual(contrast(resolved("role.document.color.accent"), tint), 4.5)
        self.assertLess(contrast(resolved("color.blue.base"), tint), 4.5)

    def test_document_roles_meet_their_use(self):
        colors = RESOLVED["role"]["document"]["color"]
        for name in ("ink", "ink_2", "muted", "faint", "accent", "accent_strong", "hot", "success", "warning"):
            self.assertGreaterEqual(contrast(colors[name], "#FFFFFF"), 4.5, name)
        for name, color in RESOLVED["role"]["document"]["party"].items():
            self.assertGreaterEqual(contrast(color, "#FFFFFF"), 3.0, name)


if __name__ == "__main__":
    unittest.main()
