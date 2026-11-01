"""网页输出的测试：样式取值来源、渲染器扩展点、Word 内容的网页预览、柱状图和网页审计。

用法：python3 -m unittest discover -s plugins/aham-design/tests
"""

from __future__ import annotations

import re
import sys
import tempfile
import unittest
from pathlib import Path

PLUGIN = Path(__file__).resolve().parents[1]
REPO = PLUGIN.parents[1]
SKILL = PLUGIN / "skills/aham-word"
LIB = SKILL / "scripts/aham_doc"
sys.path.insert(0, str(SKILL / "scripts"))
sys.path.insert(0, str(SKILL / "examples"))
sys.path.insert(0, str(REPO / "scripts"))

from aham_doc import chart, checks, html, preview, tokens, webstyle  # noqa: E402
from aham_doc.document import DocumentError  # noqa: E402

import compare_outputs  # noqa: E402

BASE_CSS = (LIB / "web" / "base.css").read_text("utf-8")
META = {"title": "示例文档", "date": "2026-11-01"}


def _page(chapters, **extra):
    content = {"meta": {"customer": "", "title": "示例", "version": "V1.0", "date": "2026-11-01"},
               "chapters": chapters, **extra}
    return html.Builder(content, Path(".")).build()


def _audit(markup: str) -> list[str]:
    outline = checks.Outline()
    outline.feed(markup)
    return checks.audit_layout(markup, outline) + checks.audit_wording(outline)


class StyleSourceTests(unittest.TestCase):
    def test_base_css_has_no_colors_or_font_sizes(self):
        self.assertEqual(re.findall(r"#[0-9A-Fa-f]{3,6}\b", BASE_CSS), [])
        self.assertEqual(re.findall(r"rgba?\(", BASE_CSS), [])
        sizes = set(re.findall(r"font-size:([^;}]+)", BASE_CSS))
        self.assertTrue(all(s.startswith("var(--fs-") for s in sizes), sizes)
        weights = set(re.findall(r"font-weight:([^;}]+)", BASE_CSS))
        self.assertTrue(weights <= {"400", "var(--fw-heading)", "var(--fw-strong)", "var(--fw-row-label)"}, weights)
        radii = set(re.findall(r"border-radius:([^;}]+)", BASE_CSS))
        self.assertTrue(radii <= {"var(--radius)", "var(--radius-pill)", "50%"}, radii)

    def test_every_css_variable_is_defined(self):
        defined = set(re.findall(r"--([a-z0-9-]+):", webstyle.tokens_css()))
        used = set(re.findall(r"var\(--([a-z0-9-]+)[,)]", BASE_CSS))
        # --n 和 --lanes 是泳道图的步数和泳道数，渲染器写在元素的 style 属性里。
        self.assertEqual(used - defined, {"n", "lanes"})

    def test_root_values_come_from_tokens_json(self):
        resolved = tokens.resolve(tokens.load_tokens())
        css = webstyle.tokens_css()
        self.assertIn(f"--ink:{resolved['role']['document']['color']['ink']};", css)
        self.assertIn(f"--fs-body:{resolved['size']['web']['body']}px;", css)
        self.assertIn(f"--fs-control:{resolved['size']['web']['control']}px;", css)
        self.assertIn(f"--radius:{resolved['radius']['control']}px;", css)
        self.assertIn(f"--font-stack:{resolved['font']['family']['ui']};", css)
        phone = resolved["layout"]["web"]["phone_breakpoint_px"]
        self.assertIn(f"@media (max-width:{phone}px)", webstyle.stylesheet())
        self.assertNotIn("{{", webstyle.stylesheet())

    def test_standalone_svg_inlines_values(self):
        svg = webstyle.standalone_svg('<svg viewBox="0 0 100 50"><text class="t1">甲</text></svg>')
        self.assertIn('width="100" height="50"', svg)
        self.assertNotIn("var(--", svg)


class RendererTests(unittest.TestCase):
    def tearDown(self):
        html._BLOCK_RENDERERS.clear()
        html._ROW_RENDERERS.clear()
        html._STYLESHEETS.clear()
        html._REQUIRED.clear()

    def test_punctuation_is_normalized_and_codebox_kept(self):
        page = _page([{"title": "范围", "blocks": [
            {"type": "paragraph", "text": "中文,逗号"}, {"type": "codebox", "text": "a,b"}]}])
        self.assertIn("中文，逗号", page)
        self.assertIn("<pre>a,b</pre>", page)

    def test_quote_blocks_are_not_in_the_public_renderer(self):
        with self.assertRaises(html.HtmlError):
            _page([{"title": "费用", "blocks": [{"type": "amounts", "items": []}]}])
        with self.assertRaises(html.HtmlError):
            _page([{"title": "费用", "blocks": [{"type": "table", "columns": ["项目", "金额"],
                                                "rows": [{"cells": ["合计", "1"], "kind": "total"}]}]}])

    def test_extension_points(self):
        html.register_block("note_box", lambda b, block, ctx: f'<p class="note-box">{html.inline(block["text"])}</p>',
                            required=("text",))
        html.register_row("total", lambda b, row, cols, amount: f'<tr class="total"><td colspan="{len(cols)}">合计</td></tr>')
        html.register_stylesheet("total", ".tbl tr.total>*{font-weight:var(--fw-strong)}")
        page = _page([{"title": "费用", "blocks": [
            {"type": "note_box", "text": "说明"},
            {"type": "table", "columns": ["项目", "金额"], "rows": [["甲", "1"], {"cells": [], "kind": "total"}]}]}])
        self.assertIn('<p class="note-box">说明</p>', page)
        self.assertIn('<tr class="total"><td colspan="2">合计</td></tr>', page)
        self.assertIn(".tbl tr.total>*{font-weight:var(--fw-strong)}", page)
        with self.assertRaises(html.HtmlError):
            _page([{"title": "费用", "blocks": [{"type": "note_box"}]}])

    def test_placeholders_in_text_are_not_replaced(self):
        page = _page([{"title": "范围", "blocks": [{"type": "paragraph", "text": "{{STYLE}}"}]}])
        self.assertIn("{{STYLE}}", page)


class PreviewTests(unittest.TestCase):
    def test_demo_preview_builds_identically_and_passes_audit(self):
        import build_examples

        with tempfile.TemporaryDirectory() as first, tempfile.TemporaryDirectory() as second:
            a = build_examples.build_html(Path(first))
            b = build_examples.build_html(Path(second))
            self.assertEqual(compare_outputs.file_parts(a), compare_outputs.file_parts(b))
            self.assertEqual(checks.audit(a), [])

    def test_committed_demo_preview_is_current(self):
        import build_examples

        with tempfile.TemporaryDirectory() as tmp:
            fresh = build_examples.build_html(Path(tmp))
            self.assertEqual(fresh.read_text("utf-8"), (SKILL / "examples" / build_examples.HTML_NAME).read_text("utf-8"))

    def test_preview_follows_word_numbering_and_money(self):
        content = {"meta": META, "chapters": [
            {"title": "费用", "blocks": [{"type": "table", "columns": ["项目", "金额"], "rows": [["甲", "1200"]]}],
             "chapters": [{"title": "明细", "blocks": [{"type": "paragraph", "text": "正文"}]}]}]}
        page = preview.build_preview(content, Path("."))
        self.assertIn('<span class="num">1</span>费用', page)
        self.assertIn('<span class="num">1.1</span>明细', page)
        self.assertIn("1,200.00", page)
        self.assertIn("金额（元）", page)

    def test_preview_applies_the_risk_limit(self):
        limit = int(tokens.value("layout.limits.risk_callouts_per_document"))
        risk = {"type": "callout", "tone": "risk", "label": "风险", "text": "说明"}
        with self.assertRaises(DocumentError):
            preview.build_preview({"meta": META, "chapters": [{"title": "范围", "blocks": [risk] * (limit + 1)}]}, Path("."))


class ChartTests(unittest.TestCase):
    def test_chart_reads_geometry_from_tokens(self):
        geometry = tokens.value("layout.web.chart")
        svg = chart.render({"groups": ["甲", "乙"], "series": [{"name": "新增", "values": [1, 3]}]})
        self.assertTrue(svg.startswith(f'<svg viewBox="0 0 {geometry["width"]} {geometry["height"]}"'))
        self.assertIn(f'width="{geometry["bar"]}"', svg)
        self.assertEqual(re.findall(r"#[0-9A-Fa-f]{6}", svg), [])

    def test_chart_series_limit(self):
        too_many = int(tokens.value("layout.web.chart.max_series")) + 1
        with self.assertRaises(chart.ChartError):
            chart.render({"groups": ["甲"], "series": [{"name": str(i), "values": [1]} for i in range(too_many)]})


class AuditTests(unittest.TestCase):
    def test_clean_page_passes(self):
        self.assertEqual(_audit(_page([{"title": "范围", "blocks": [{"type": "paragraph", "text": "正文"}]}])), [])

    def test_risk_callout_limit(self):
        limit = int(tokens.value("layout.limits.risk_callouts_per_document"))
        risk = {"type": "callout", "tone": "risk", "label": "风险", "text": "说明"}
        self.assertEqual(_audit(_page([{"title": "范围", "blocks": [risk] * limit}])), [])
        errors = _audit(_page([{"title": "范围", "blocks": [risk] * (limit + 1)}]))
        self.assertTrue(any("风险条" in e for e in errors), errors)

    def test_stray_color_font_and_external_resource(self):
        page = _page([{"title": "范围", "blocks": [{"type": "paragraph", "text": "正文"}]}])
        page = page.replace("</style>", "p{color:#123456;font-family:Arial}</style>")
        page = page.replace("</body>", '<script src="https://example.com/a.js"></script></body>')
        errors = _audit(page)
        self.assertTrue(any("#123456" in e for e in errors), errors)
        self.assertTrue(any("Arial" in e for e in errors), errors)
        self.assertTrue(any("外部资源" in e for e in errors), errors)

    def test_banned_word_and_question_heading(self):
        page = _page([{"title": "范围是什么", "blocks": [{"type": "paragraph", "text": "形成闭环"}]}])
        errors = _audit(page)
        self.assertTrue(any("闭环" in e for e in errors), errors)
        self.assertTrue(any("问句" in e for e in errors), errors)


if __name__ == "__main__":
    unittest.main()
