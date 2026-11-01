"""aham-ppt 引擎的取值检查，由原 aham-ppt 仓库的 tests/test_tokens.py 改写。

取值只在插件根的 tokens.json（color.ppt、size.ppt、layout.ppt、font.family）。本测试确认：
- references/style-tokens.md 表格里的键名和取值与 tokens.json 一致；
- references/html-slides.md 写的画布和字体与 tokens.json 一致；
- 读不到 tokens.json 的 runtime.js、给用户复制的 check_deck_visual.example.json 与它一致；
- 引擎脚本里没有写死色值、画布尺寸和字体名，预览页不从网络加载字体，数字不用等宽字体；
- 决议表的 PPT 取值：墨三 6B7482、橙 CE8422、底一 F6F8FB、蓝浅底 EEF2FC、青绿 17998A 保留；
- 有 Node.js 时，tokens.js、components.js 引出的常量与 tokens.json 一致，环境变量 AHAM_DESIGN_TOKENS 生效，示例生成两次一致。
用法：python3 -m unittest discover -s plugins/aham-design/tests
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

PLUGIN = Path(__file__).resolve().parents[1]
SKILL = PLUGIN / "skills" / "aham-ppt"
ENGINE = SKILL / "assets" / "html2pptx"
TOOLS = SKILL / "assets" / "tools"
DOC = (SKILL / "references" / "style-tokens.md").read_text("utf-8")
sys.path.insert(0, str(PLUGIN / "skills/aham-word/scripts"))

from aham_doc import tokens as T  # noqa: E402

RAW = json.loads((PLUGIN / "tokens.json").read_text("utf-8"))
RES = T.resolve(RAW)
PPT_COLOR = RES["color"]["ppt"]
SIZE = RES["size"]["ppt"]
LAYOUT = RES["layout"]["ppt"]
FONT = RES["font"]["family"]
# color.ppt 的键与引擎常量名的对应，与 tokens.js 的换算一致
NAMES = {"service": "svc", "service_bg": "svcBg", "product": "prod", "product_bg": "prodBg", "ai_bg": "aiBg"}
C = {NAMES.get(k, k.replace("_", "")): v for k, v in PPT_COLOR.items()}
HAS_NODE = shutil.which("node") and (ENGINE / "node_modules" / "pptxgenjs").exists()


def section(text: str, title: str) -> str:
    """取「## 标题」到下一个「## 」之间的正文。"""
    m = re.search(rf"^## {re.escape(title)}\n(.*?)(?=^## |\Z)", text, re.S | re.M)
    if not m:
        raise AssertionError(f"style-tokens.md 里找不到「## {title}」")
    return m.group(1)


def numbers(cell: str) -> list[float]:
    return [float(x) for x in re.findall(r"\d+(?:\.\d+)?", cell)]


def resolved(dotted: str):
    node = RES
    for part in dotted.split("."):
        node = node[part]
    return node


class TokenValuesTest(unittest.TestCase):
    def test_decision_table(self):
        self.assertEqual(C["ink3"], "#6B7482")
        self.assertEqual(C["prod"], "#CE8422")
        self.assertEqual(C["svc"], "#17998A")
        self.assertEqual(C["bg1"], "#F6F8FB")
        self.assertEqual(C["aiBg"], "#EEF2FC")
        self.assertEqual(C["ai"], resolved("color.blue.base"))
        for old in ("#7D8695", "#D4892A", "#F6F7F9", "#EAF0FD"):
            self.assertNotIn(old, C.values())
        self.assertEqual(FONT["file"], "微软雅黑")

    def test_neutrals_reference_cool_gray(self):
        refs = {"ink_1": 17, "ink_2": 15, "ink_3": 13, "mute": 10, "line_1": 5, "line_2": 9, "bg_1": 1, "bg_2": 3, "white": 0}
        for key, step in refs.items():
            self.assertEqual(RAW["color"]["ppt"][key]["$value"], f"{{color.gray.{step}}}", key)

    def test_constant_names(self):
        self.assertEqual(list(C), ["ink1", "ink2", "ink3", "slate", "mute", "line1", "line2", "bg1", "bg2", "white",
                                   "ai", "aiBg", "svc", "svcBg", "prod", "prodBg"])

    def test_layout_group(self):
        self.assertEqual(LAYOUT["canvas"], {"width": 1920, "height": 1080, "px_per_pt": 2})
        self.assertEqual(LAYOUT["radius"], {"box": RES["radius"]["control"], "card": RES["radius"]["panel"]})
        f = LAYOUT["frame"]
        self.assertTrue(f["margin"] < f["right"] < LAYOUT["canvas"]["width"])
        self.assertTrue(f["header_top"] < f["title_top"] < f["sub_top"] < f["main_top"] < f["main_bottom"]
                        < f["attr_top"] < f["attr_bottom"] < f["foot_line"] < f["foot_top"] < LAYOUT["canvas"]["height"])
        self.assertEqual(f["margin"], LAYOUT["canvas"]["width"] - f["right"])


class StyleTokensDocTest(unittest.TestCase):
    def test_canvas(self):
        m = re.search(r"画布 (\d+) × (\d+) 像素，1px 等于 ([\d.]+)pt", DOC)
        self.assertIsNotNone(m, "style-tokens.md 开头应写画布尺寸和 px 与 pt 的换算")
        c = LAYOUT["canvas"]
        self.assertEqual((int(m.group(1)), int(m.group(2))), (c["width"], c["height"]))
        self.assertEqual(float(m.group(3)), 1 / c["px_per_pt"])

    def test_font_size(self):
        rows = re.findall(r"^\| ([\d.]+)px \| `FS\.(\w+)` \| `size\.ppt\.(\w+)` \|", section(DOC, "一、字号"), re.M)
        self.assertEqual({k: float(v) for v, k, _ in rows}, {k: float(v) for k, v in SIZE.items()})
        self.assertTrue(all(k == key for _, k, key in rows))

    def test_fonts(self):
        body = section(DOC, "二、字体")
        for const, key in (("FONT_FACE", "file"), ("FONT_STACK", "ui"), ("CODE", "code")):
            self.assertRegex(body, rf"`{const}`.*`font\.family\.{key}`")
        self.assertNotIn("等宽字体 `", body)

    def test_colors(self):
        body = section(DOC, "三、颜色")
        doc = {}
        for name, key, value, light in re.findall(
                r"`C\.(\w+)` \| `color\.ppt\.(\w+)` \| `(#[0-9A-Fa-f]{6})` \|(?: `(#[0-9A-Fa-f]{6})` \|)?", body):
            self.assertEqual(NAMES.get(key, key.replace("_", "")), name, key)
            self.assertEqual(PPT_COLOR[key], value.upper(), key)
            doc[name] = value.upper()
            if light:
                doc[name + "Bg"] = light.upper()
        self.assertEqual(doc, C)
        for key in ("ai_bg", "service_bg", "product_bg"):
            self.assertIn(f"`color.ppt.{key}`", body)

    def test_line_width(self):
        rows = re.findall(r"^\| ([\d.]+)px \| `LW\.(\w+)` \| `layout\.ppt\.stroke\.(\w+)` \|", section(DOC, "四、线宽"), re.M)
        self.assertEqual({k: float(v) for v, k, _ in rows}, {k: float(v) for k, v in LAYOUT["stroke"].items()})
        self.assertTrue(all(k == key for _, k, key in rows))

    def test_radius(self):
        body = section(DOC, "五、圆角与形状")
        m = re.search(r"方框 (\d+)px，卡片 (\d+)px", body)
        self.assertEqual({"box": int(m.group(1)), "card": int(m.group(2))}, LAYOUT["radius"])
        self.assertIn("`layout.ppt.radius.box`", body)

    def test_frame(self):
        f, fs, lw, rad = LAYOUT["frame"], SIZE, LAYOUT["stroke"], LAYOUT["radius"]
        # 每行「数值」一栏里的数字按出现顺序，「tokens.json」一栏的键名
        expected = {
            "左右边距": ([f["margin"], f["right"]], ["margin", "right"]),
            "页眉左": ([fs["body"], f["header_top"]], ["header_top"]),
            "页眉右": ([fs["body"], f["right"]], ["right"]),
            "标题": ([fs["title"], 700, f["title_top"]], ["title_top"]),
            "子标题": ([fs["sub"], f["sub_top"]], ["sub_top"]),
            "提供方胶囊": ([], ["provider_top"]),
            "主图区": ([f["main_top"], f["main_bottom"]], ["main_top", "main_bottom"]),
            "属性带": ([f["attr_top"], f["attr_bottom"], rad["box"]], ["attr_top", "attr_bottom"]),
            "页脚线": ([f["foot_line"], lw["struct"]], ["foot_line"]),
            "页脚左": ([fs["body"]], ["foot_top"]),
            "页脚右": ([fs["body"]], ["foot_top"]),
        }
        rows = {}
        for line in section(DOC, "六、页面框架").splitlines():
            cells = [c.strip() for c in line.strip().strip("|").split("|")]
            if len(cells) == 4 and cells[0] in expected:
                rows[cells[0]] = (numbers(cells[2]), re.findall(r"`(\w+)`", cells[3]))
        self.assertEqual(set(rows), set(expected), "页面框架表的行与检查项不符")
        for name, (want, keys) in expected.items():
            with self.subTest(row=name):
                self.assertEqual(rows[name], ([float(x) for x in want], keys))
                for key in keys:
                    self.assertIn(key, f)


class GeneralSpecDocTest(unittest.TestCase):
    """skills/aham-design/references/ppt.md：写到的键都存在，字号和线宽表与 tokens.json 一致。"""
    TEXT = (PLUGIN / "skills" / "aham-design" / "references" / "ppt.md").read_text("utf-8")

    def test_keys_exist(self):
        keys = set(re.findall(r"`((?:color|size|layout|font|radius)\.[\w.]+)`", self.TEXT))
        self.assertGreaterEqual(len(keys), 30)
        for key in keys:
            with self.subTest(key=key):
                resolved(key)
        for key in re.findall(r"^\| [^|]+ \| [^|]+ \| `(\w+)`", section(self.TEXT, "7. 页面框架"), re.M):
            self.assertIn(key, LAYOUT["frame"])

    def test_size_and_stroke_tables(self):
        for title, group in (("3. 字号", "size.ppt"), ("5. 线宽", "layout.ppt.stroke")):
            rows = re.findall(rf"^\| [^|]+ \| ([\d.]+) \| `{re.escape(group)}\.(\w+)` \|", section(self.TEXT, title), re.M)
            self.assertEqual({k: float(v) for v, k in rows}, {k: float(v) for k, v in resolved(group).items()}, title)


class OtherSourcesTest(unittest.TestCase):
    def test_html_slides_doc(self):
        text = (SKILL / "references" / "html-slides.md").read_text("utf-8")
        c = LAYOUT["canvas"]
        self.assertIn(f"画布 {c['width']} × {c['height']} 像素", text)
        self.assertIn("`font.family.ui`", text)
        self.assertIn("`font.family.file`", text)
        self.assertNotIn("Consolas", text)
        self.assertNotIn("Noto Sans SC", text)
        self.assertNotIn("写页顺序", text, "写页顺序归流程技能")
        palette = {v.upper() for v in C.values()}
        for hex_value in re.findall(r"#[0-9A-Fa-f]{6}\b", text):
            self.assertIn(hex_value.upper(), palette, f"html-slides.md 示例里的 {hex_value} 不在 color.ppt")

    def test_runtime_canvas(self):
        # runtime.js 在浏览器里运行，并原样内嵌进预览页，读不到 tokens.json，只能在这里核对
        text = (ENGINE / "runtime.js").read_text("utf-8")
        c = LAYOUT["canvas"]
        self.assertIn(f"width:{c['width']}px;height:{c['height']}px", text)
        self.assertIn(f"width: {c['width']}, height: {c['height']}", text)

    def test_visual_example(self):
        # 示例配置给用户复制成项目配置，保留完整色表；色表和语义色要与 tokens.json 一致
        cfg = json.loads((TOOLS / "check_deck_visual.example.json").read_text("utf-8"))
        colors = {k: v.upper().lstrip("#") for k, v in C.items()}
        self.assertEqual(sorted(cfg["palette"]), sorted(colors.values()))
        self.assertEqual(set(cfg["accents"]), {colors["ai"], colors["svc"], colors["prod"]})
        self.assertEqual(cfg["min_font"], SIZE["body"] / LAYOUT["canvas"]["px_per_pt"])
        self.assertEqual(set(cfg), {"min_font", "max_levels", "palette", "accents"})

    def test_no_hardcoded_values_in_engine(self):
        # runtime.js 见上；demo 是用法示例，只用组件和常量
        palette = {v.upper() for v in C.values()} | {"#7D8695", "#D4892A", "#F6F7F9", "#EAF0FD"}
        c = LAYOUT["canvas"]
        files = [p for p in sorted(ENGINE.rglob("*.js")) if "node_modules" not in p.parts and p.name != "runtime.js"]
        self.assertGreaterEqual(len(files), 9)
        for path in files + [TOOLS / "check_deck_visual.py"]:
            code = "\n".join(re.sub(r"(//|#\s).*$", "", line) for line in path.read_text("utf-8").splitlines())
            with self.subTest(file=path.name):
                found = sorted({h for h in re.findall(r"#[0-9A-Fa-f]{6}\b", code) if h.upper() in palette})
                self.assertEqual(found, [], "色值应从 tokens.json 读取")
                self.assertNotRegex(code, rf"\b({c['width']}|{c['height']})\b", "画布尺寸应从 tokens.json 读取")
                for name in ("Microsoft YaHei", "微软雅黑", "Consolas", "Noto Sans", "googleapis", "monospace"):
                    self.assertNotIn(name, code, f"{name} 应从 tokens.json 读取或去掉")

    def test_numbers_use_body_font(self):
        code = (ENGINE / "components.js").read_text("utf-8")
        self.assertNotIn("mono: true", code)
        self.assertNotIn("MONO", code)


@unittest.skipUnless(HAS_NODE, "没有 Node.js 或没有在 assets/html2pptx 运行 npm install")
class NodeExportsTest(unittest.TestCase):
    SCRIPT = ("const K = require('./components'), T = require('./tokens');"
              "console.log(JSON.stringify({ C: K.C, FS: K.FS, LW: K.LW, RAD: K.RAD, MARGIN: K.MARGIN, RIGHT: K.RIGHT,"
              " MAIN: K.MAIN, MAIN_RECT: T.MAIN_RECT, FONT_FACE: T.FONT_FACE, CODE_FACE: T.CODE_FACE, FONT_STACK: T.FONT_STACK,"
              " PX_PER_IN: T.PX_PER_IN, TOKENS_PATH: T.TOKENS_PATH, DARK: T.DARK }))")

    def run_node(self, env=None):
        proc = subprocess.run(["node", "-e", self.SCRIPT], cwd=ENGINE, check=True, capture_output=True, text=True,
                              env={**os.environ, **(env or {})})
        return json.loads(proc.stdout)

    def test_constants(self):
        env = {k: v for k, v in os.environ.items() if k != "AHAM_DESIGN_TOKENS"}
        out = json.loads(subprocess.run(["node", "-e", self.SCRIPT], cwd=ENGINE, check=True, capture_output=True,
                                        text=True, env=env).stdout)
        f = LAYOUT["frame"]
        self.assertEqual(out["C"], C)
        self.assertEqual(out["FS"], SIZE)
        self.assertEqual(out["LW"], LAYOUT["stroke"])
        self.assertEqual(out["RAD"], LAYOUT["radius"])
        self.assertEqual((out["MARGIN"], out["RIGHT"]), (f["margin"], f["right"]))
        self.assertEqual(out["MAIN"], {"y0": f["main_top"], "y1": f["main_bottom"]})
        self.assertEqual(out["MAIN_RECT"], {"x": 96, "y": 195, "w": 1728, "h": 700})
        self.assertEqual((out["FONT_FACE"], out["CODE_FACE"]), ("微软雅黑", "Consolas"))
        self.assertEqual(out["FONT_STACK"], FONT["ui"])
        self.assertEqual(out["PX_PER_IN"], 144)
        self.assertEqual(Path(out["TOKENS_PATH"]), PLUGIN / "tokens.json")
        self.assertEqual(out["DARK"], {"bg": resolved("color.gray_dark.bg"), "ink": resolved("color.gray_dark.ink"),
                                       "muted": resolved("color.gray_dark.muted")})

    def test_env_override(self):
        raw = json.loads((PLUGIN / "tokens.json").read_text("utf-8"))
        raw["color"]["gray"]["17"]["$value"] = "#000000"
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "tokens.json"
            path.write_text(json.dumps(raw, ensure_ascii=False), "utf-8")
            out = self.run_node({"AHAM_DESIGN_TOKENS": str(path)})
        self.assertEqual(out["C"]["ink1"], "#000000")

    def test_demo_is_deterministic_and_uses_new_values(self):
        with tempfile.TemporaryDirectory() as tmp:
            for name in ("a", "b"):
                subprocess.run(["node", str(ENGINE / "demo" / "build.js"), str(Path(tmp) / name)], check=True, capture_output=True)
                subprocess.run(["node", str(ENGINE / "preview.js"), str(Path(tmp) / name), str(Path(tmp) / name / "preview.html")],
                               check=True, capture_output=True)
            files = sorted(p.relative_to(Path(tmp) / "a") for p in (Path(tmp) / "a").rglob("*") if p.is_file())
            self.assertGreaterEqual(len(files), 7)
            text = ""
            for rel in files:
                a, b = (Path(tmp) / "a" / rel).read_text("utf-8"), (Path(tmp) / "b" / rel).read_text("utf-8")
                self.assertEqual(a, b, str(rel))
                text += a
        for old in ("#7D8695", "#D4892A", "#F6F7F9", "#EAF0FD", "Consolas", "googleapis", "Noto Sans SC"):
            self.assertNotIn(old, text)
        self.assertIn("#CE8422", text)


if __name__ == "__main__":
    unittest.main()
