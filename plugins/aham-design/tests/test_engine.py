"""排版引擎 aham_doc 的测试：文字规范化、规则读取、块校验、公开接口、依赖方向、品牌参数化和 Word 渲染。

用法：python3 -m unittest discover -s plugins/aham-design/tests
"""

from __future__ import annotations

import ast
import importlib
import json
import re
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

PLUGIN = Path(__file__).resolve().parents[1]
REPO = PLUGIN.parents[1]
SKILL = PLUGIN / "skills/aham-word"
LIB = SKILL / "scripts/aham_doc"
sys.path.insert(0, str(SKILL / "scripts"))
sys.path.insert(0, str(REPO / "scripts"))

import aham_doc  # noqa: E402
from aham_doc import blocks, brand, document, text, tokens  # noqa: E402
from aham_doc import word as W  # noqa: E402
from aham_doc.paths import layout_rule, writing_rules  # noqa: E402

import compare_outputs  # noqa: E402

# 引擎可以导入的顶层模块：标准库以外只有这些。
ALLOWED_THIRD_PARTY = {"docx", "lxml"}


def _imports(path: Path) -> list[tuple[str, tuple[str, ...], int]]:
    tree = ast.parse(path.read_text("utf-8"), filename=str(path))
    found = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            found += [(alias.name, (), 0) for alias in node.names]
        elif isinstance(node, ast.ImportFrom):
            found.append((node.module or "", tuple(alias.name for alias in node.names), node.level))
    return found


def _document_xml(path: Path, part: str = "word/document.xml") -> str:
    with zipfile.ZipFile(path) as archive:
        return archive.read(part).decode("utf-8")


def _build(content: dict, name: str = "t.docx") -> Path:
    tmp = Path(tempfile.mkdtemp(prefix="aham-test-"))
    return document.build_document(content, tmp / name, tmp)


BASE_META = {"title": "示例文档", "date": "2026-11-01"}


# ---------- 移植自原引擎测试 ----------

class TextTests(unittest.TestCase):
    def test_cjk_punct_in_chinese_context(self):
        self.assertEqual(text.cjk_punct("报价不含硬件,需另购"), "报价不含硬件，需另购")
        self.assertEqual(text.cjk_punct("说明:如下;另见附件"), "说明：如下；另见附件")
        self.assertEqual(text.cjk_punct("金额(元)"), "金额（元）")
        self.assertEqual(text.cjk_punct("ERP (金蝶) 系统"), "ERP（金蝶）系统")

    def test_cjk_punct_leaves_latin_and_numbers(self):
        for value in ("Hello, world", "10:30 开会", "1, 2, 3", "https://a.b/c?x=1", "A (B) C"):
            self.assertEqual(text.cjk_punct(value), value)

    def test_money(self):
        self.assertEqual(text.money(780800), "780,800.00")
        self.assertEqual(text.money("51700.005"), "51,700.01")

    def test_rmb_upper(self):
        cases = {
            51700: "伍万壹仟柒佰元整", 8800: "捌仟捌佰元整", 100500.5: "壹拾万零伍佰元伍角",
            10010: "壹万零壹拾元整", 1000000: "壹佰万元整", 120003.07: "壹拾贰万零叁元零柒分",
            100000000: "壹亿元整", 1001000: "壹佰万壹仟元整", 0.05: "零元零伍分",
        }
        for value, expected in cases.items():
            self.assertEqual(text.rmb_upper(value), expected, value)

    def test_ordered_prefix_follows_gb_t_9704(self):
        self.assertEqual(text.ordered_prefix(3), "3. ")
        self.assertEqual(text.ordered_prefix(2, level=2), "（2）")
        self.assertEqual(writing_rules()["numbering"]["list"], "1.")


class RuleTests(unittest.TestCase):
    def test_layout_rules_have_basis_and_strength(self):
        rules = json.loads((SKILL / "config/layout-rules.json").read_text("utf-8"))
        for rule in rules["rules"]:
            self.assertTrue(rule["basis"], rule["id"])
            self.assertIn(rule["strength"], rules["strength_levels"], rule["id"])

    def test_layout_rule_lookup(self):
        self.assertEqual(layout_rule("keep_small_tables")["max_rows"], 8)
        with self.assertRaises(KeyError):
            layout_rule("no-such-rule")


class BlockTests(unittest.TestCase):
    def test_unknown_block_type(self):
        with self.assertRaises(blocks.BlockError):
            blocks.validate([{"type": "banner", "text": "x"}])

    def test_missing_field(self):
        with self.assertRaises(blocks.BlockError) as ctx:
            blocks.validate([{"type": "callout", "tone": "lead", "text": "x"}], "第 1 章")
        self.assertIn("label", str(ctx.exception))

    def test_paragraph_is_default_type(self):
        blocks.validate([{"text": "正文"}])


class PublicInterfaceTests(unittest.TestCase):
    def test_every_listed_module_has_a_consistent_all(self):
        modules = sorted(p.stem for p in LIB.glob("*.py") if p.stem != "__init__")
        self.assertEqual(sorted(aham_doc.__all__), modules)
        for name in modules:
            module = importlib.import_module(f"aham_doc.{name}")
            self.assertTrue(hasattr(module, "__all__"), f"{name} 缺少 __all__")
            missing = [item for item in module.__all__ if not hasattr(module, item)]
            self.assertEqual(missing, [], f"{name}.__all__ 列了不存在的名字")

    def test_skill_scripts_only_use_public_names(self):
        problems = []
        callers = [*SKILL.glob("scripts/*.py"), *SKILL.glob("examples/*.py")]
        self.assertTrue(callers)
        for path in callers:
            for module, names, _ in _imports(path):
                if module == "aham_doc":
                    problems += [f"{path.name}: {n}" for n in names if n not in aham_doc.__all__]
                elif module.startswith("aham_doc."):
                    public = importlib.import_module(module).__all__
                    problems += [f"{path.name}: {module}.{n}" for n in names if n not in public]
        self.assertEqual(problems, [])


class DependencyDirectionTests(unittest.TestCase):
    def test_engine_imports_only_stdlib_docx_lxml_and_itself(self):
        stdlib = set(sys.stdlib_module_names)
        problems = []
        for path in sorted(LIB.glob("*.py")):
            for module, _, level in _imports(path):
                top = module.split(".")[0]
                if level > 0 or top in stdlib or top in ALLOWED_THIRD_PARTY or top == "__future__":
                    continue
                problems.append(f"{path.name}: {module}")
        self.assertEqual(problems, [])


class BrandTests(unittest.TestCase):
    def tearDown(self):
        brand.reset_brand()

    def test_engine_source_has_no_brand_values(self):
        current = brand.load_brand(SKILL / "config/brand.json", SKILL)
        for path in sorted(LIB.glob("*.py")):
            source = path.read_text("utf-8")
            for value in (current.company, current.mark_style):
                self.assertFalse(value in source, f"{path.name} 写死了品牌取值「{value}」")

    def test_footer_follows_the_brand_passed_in(self):
        brand.set_brand(brand.Brand(company="示例公司", short_name="示例", wordmark="Example", mark_style="Example Mark"))
        path = _build({"meta": BASE_META, "chapters": [{"title": "范围", "blocks": [{"text": "正文"}]}]})
        footers = "".join(_document_xml(path, name) for name in ("word/footer1.xml", "word/footer2.xml"))
        self.assertIn("示例公司 · Example", footers)
        self.assertNotIn("Aham", footers)

    def test_skill_brand_file_is_the_default(self):
        brand.reset_brand()
        self.assertEqual(brand.current_brand().logo, SKILL / "assets/aham-logo.png")
        self.assertTrue(brand.current_brand().logo.is_file())


# ---------- 新增：取值来源、扩展点和产出 ----------

class TokenSourceTests(unittest.TestCase):
    def test_renderer_values_come_from_tokens_json(self):
        resolved = tokens.resolve(tokens.load_tokens())
        role = resolved["role"]["document"]["color"]
        self.assertEqual(W.ACCENT, role["accent"].lstrip("#"))
        self.assertEqual(W.INK, resolved["color"]["gray"]["18"].lstrip("#"))
        self.assertEqual(W.FAINT, resolved["color"]["gray"]["13"].lstrip("#"))
        self.assertEqual(W.WORD_PT, resolved["size"]["word"])
        self.assertEqual(W.FONT_BODY, resolved["font"]["family"]["file"])
        self.assertEqual(W.FONT_LATIN, resolved["font"]["family"]["file"])

    def test_engine_source_has_no_color_or_font_size_literals(self):
        hex_color = re.compile(r"[\"'][0-9A-Fa-f]{6}[\"']")
        size_literal = re.compile(r"(?:set_run_font|_set_style_font)\([^)]*?,\s*\d+(?:\.\d+)?\s*[,)]")
        for path in sorted(LIB.glob("*.py")):
            source = path.read_text("utf-8")
            self.assertEqual(hex_color.findall(source), [], f"{path.name} 写死了色值")
            # 唯一的例外是 1pt 的不可见占位字符（_add_spacer），它不是文字字号。
            literals = [m for m in size_literal.findall(source) if m != "set_run_font(run, FONT_BODY, 1,"]
            self.assertEqual(literals, [], f"{path.name} 写死了字号")

    def test_engine_source_has_no_layout_literals(self):
        """段距、缩进、页边距和单元格内边距都读 tokens.json 的 layout 分组；只允许 0 和 1pt 占位行距。"""
        length = re.compile(r"\b(?:Pt|Cm|Mm|Inches)\(\s*-?(\d+(?:\.\d+)?)\s*\)")
        margin = re.compile(r"set_cell_margins\([^)]*?=\s*([1-9]\d*)")
        border = re.compile(r"space=\s*(\d+)")
        for path in sorted(LIB.glob("*.py")):
            source = path.read_text("utf-8")
            literals = [v for v in length.findall(source) if float(v) not in (0.0, 1.0)]
            self.assertEqual(literals, [], f"{path.name} 写死了长度")
            self.assertEqual(margin.findall(source), [], f"{path.name} 写死了单元格内边距")
            self.assertEqual(border.findall(source), [], f"{path.name} 写死了边线间距")

    def test_layout_values_reach_the_document(self):
        resolved = tokens.resolve(tokens.load_tokens())
        word = resolved["layout"]["word"]
        page = resolved["layout"]["page"]
        xml = _document_xml(_build({"meta": BASE_META, "chapters": [{"title": "范围", "blocks": [
            {"type": "list", "items": ["一"]}]}]}))
        self.assertIn(f'w:left="{round(word["list"]["indent_cm"] / 2.54 * 1440)}"', xml)
        self.assertIn(f'w:top="{round(page["top_margin_mm"] / 25.4 * 1440)}"', xml)
        self.assertIn(f'w:header="{round(page["header_distance_mm"] / 25.4 * 1440)}"', xml)

    def test_missing_token_file_fails_loudly(self):
        with self.assertRaises(tokens.TokenError):
            tokens.load_tokens(Path(tempfile.mkdtemp()) / "none.json")

    def test_style_view_matches_engine_contract(self):
        from aham_doc.docx_typography import load_style

        style = load_style()
        for key in ("fonts", "page", "word_pt", "excel_pt", "colors", "word", "excel", "rules", "categorical"):
            self.assertIn(key, style)
        self.assertTrue(all(not v.startswith("#") for v in style["colors"].values()))


class TableHookTests(unittest.TestCase):
    def tearDown(self):
        W._TABLE_HOOKS.clear()

    def test_quote_fields_have_no_effect_in_the_public_engine(self):
        content = {"meta": BASE_META, "chapters": [{"title": "费用", "blocks": [
            {"type": "table", "style": "T3", "total_row": True, "primary_total": True,
             "columns": ["项目", "金额"],
             "rows": [{"项目": "甲", "金额": "100", "row_type": "group", "vendor_group_key": "A"},
                      {"项目": "合计", "金额": "100"}]}]}]}
        xml = _document_xml(_build(content))
        self.assertNotIn("w:gridSpan", xml)
        self.assertNotIn("w:vMerge", xml)
        self.assertIn("合计", xml)

    def test_render_row_hook_can_add_a_total_row(self):
        def render_row(ctx):
            if not (isinstance(ctx.source, dict) and ctx.source.get("kind") == "total"):
                return None
            merged = ctx.row.cells[0].merge(ctx.row.cells[len(ctx.headers) - 2])
            cells = [(merged, "合计", 0), (ctx.row.cells[-1], ctx.values[-1], len(ctx.headers) - 1)]
            for cell, value, index in cells:
                paragraph = W.prepare_table_cell(ctx, cell, index)
                paragraph.add_run(W.display_money(value) if index else value).bold = True
                W.set_cell_borders(cell, top=(W.INK, W.RULE["total_top"]), bottom=W.table_row_bottom(ctx))
            return cells

        seen = []
        W.register_table_hooks("total", W.TableHooks(
            render_row=render_row,
            after_table=lambda table, headers, rows, density: seen.append(len(table.rows)),
        ))
        content = {"meta": BASE_META, "chapters": [{"title": "费用", "blocks": [
            {"type": "table", "columns": ["项目", "数量", "金额"],
             "rows": [{"项目": "甲", "数量": "1", "金额": "1200"},
                      {"项目": "", "数量": "", "金额": "1200", "kind": "total"}]}]}]}
        xml = _document_xml(_build(content))
        self.assertIn('w:gridSpan w:val="2"', xml)
        self.assertIn("1,200.00", xml)
        self.assertEqual(seen, [3])

    def test_notes_default_title_is_generic(self):
        content = {"meta": BASE_META, "chapters": [{"title": "附录", "blocks": [
            {"type": "notes", "items": ["标签：第一条"]}]}]}
        xml = _document_xml(_build(content))
        self.assertIn(">说明<", xml)


class DocumentTests(unittest.TestCase):
    def test_date_is_required(self):
        with self.assertRaises(document.DocumentError):
            _build({"meta": {"title": "示例"}, "chapters": []})

    def test_cover_fields_replace_default_rows(self):
        meta = {**BASE_META, "cover_fields": [["文档类型", "说明"], ["版本", "V2.0"]]}
        xml = _document_xml(_build({"meta": meta, "chapters": [{"title": "范围", "blocks": []}]}))
        self.assertIn("文档类型：", xml)
        self.assertNotIn("客户：", xml)

    def test_without_cover_the_first_page_is_not_blank(self):
        path = _build({"meta": BASE_META, "cover": False, "toc": False,
                       "chapters": [{"title": "范围", "blocks": [{"text": "正文"}]}]})
        xml = _document_xml(path)
        first_paragraph = re.search(r"<w:body><w:p[ >].*?</w:p>", xml).group(0)
        self.assertNotIn("w:pageBreakBefore", first_paragraph)

    def test_risk_callouts_are_limited(self):
        limit = int(tokens.value("layout.limits.risk_callouts_per_document"))
        risk = {"type": "callout", "tone": "risk", "label": "风险", "text": "说明"}
        _build({"meta": BASE_META, "chapters": [{"title": "范围", "blocks": [risk] * limit}]})
        content = {"meta": BASE_META, "chapters": [{"title": "范围", "blocks": [risk] * limit,
                                                     "chapters": [{"title": "下级", "blocks": [risk]}]}]}
        with self.assertRaises(document.DocumentError):
            _build(content)

    def test_demo_builds_identically_twice(self):
        sys.path.insert(0, str(SKILL / "examples"))
        import build_examples

        with tempfile.TemporaryDirectory() as first, tempfile.TemporaryDirectory() as second:
            a = build_examples.build(Path(first))
            b = build_examples.build(Path(second))
            self.assertEqual(compare_outputs.file_parts(a), compare_outputs.file_parts(b))


if __name__ == "__main__":
    unittest.main()
