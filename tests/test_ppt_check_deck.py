"""PPT 自查的拆分检查：aham-app 的 check_deck.py 调用 aham-design 引擎的视觉检查和本技能的文字检查。

- 用 python-pptx 造一份两页的 PPTX，触发视觉和文字两类规则。入口的报告与 fixtures/ppt_check_deck_expected.md 逐字一致。
  这份期望报告由拆分前的 check_deck.py 在同一份 PPTX 和同一份配置上生成，所以一致即说明拆分没有改变结果和顺序。
- 引擎的视觉检查可以单独运行，只报视觉项。
- find_engine.py 能在仓库结构、插件缓存结构和安装记录三种情况下找到 aham-design，找不到时报错并列出查过的位置。
用法：python3 -m unittest discover -s tests
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FLOW = ROOT / "plugins" / "aham-app" / "skills" / "aham-ppt-proposal"
ENGINE = ROOT / "plugins" / "aham-design" / "skills" / "aham-ppt"
EXPECTED = Path(__file__).parent / "fixtures" / "ppt_check_deck_expected.md"

try:
    import pptx  # noqa: F401
    HAS_PPTX = True
except ImportError:
    HAS_PPTX = False


def make_deck(path: Path) -> None:
    from pptx import Presentation
    from pptx.dml.color import RGBColor
    from pptx.util import Inches, Pt

    prs = Presentation()
    prs.slide_width, prs.slide_height = Inches(13.333), Inches(7.5)

    def text(s, y, value, size, color="1F2633"):
        frame = s.shapes.add_textbox(Inches(0.5), Inches(y), Inches(6), Inches(0.6)).text_frame
        run = frame.paragraphs[0].add_run()
        run.text, run.font.size = value, Pt(size)
        run.font.color.rgb = RGBColor.from_string(color)

    def rect(s, x, y, w, h, fill, line=None):
        shape = s.shapes.add_shape(1, Inches(x), Inches(y), Inches(w), Inches(h))
        shape.fill.solid()
        shape.fill.fore_color.rgb = RGBColor.from_string(fill)
        if line:
            shape.line.color.rgb = RGBColor.from_string(line)

    blank = prs.slide_layouts[6]
    s = prs.slides.add_slide(blank)
    text(s, 0.4, "平台能实现全链路打通", 26)
    text(s, 1.1, "子标题没有句号，而且写得非常非常长，超过了四十个字的上限，用来触发检查规则的一句话吧", 13)
    text(s, 3, "免费赠送三项服务，报价 5 万元，见第 9 页", 9)
    text(s, 4, "调用 search_knowledge 和 C01 接口，干活", 8, "D4892A")
    for y, no in ((5, "01"), (5.6, "03"), (6.2, "04")):
        text(s, y, no, 10)
    rect(s, 7, 2, 2, 1, "336EE8")
    rect(s, 7, 3.5, 2, 1, "17998A", line="CE8422")
    s.notes_slide.notes_text_frame.text = "讲稿里有赋能和待定，见第 1—2 页，共 4 项"
    s = prs.slides.add_slide(blank)
    text(s, 0.4, "AI 平台架构", 26)
    text(s, 1.1, "原始单据停在企业网络内。", 13)
    text(s, 3, "〈子模块〉系统接入 3 套，第 1 页", 10, "123456")
    rect(s, 7, 2, 2, 1, "336EE8")
    rect(s, 7, 3.5, 0.2, 0.2, "17998A")
    rect(s, 7, 4, 2, 1, "E04020")
    for size in (11, 12, 14, 15, 16, 17, 19, 20):
        text(s, 6, "字", size)
    prs.save(path)


def project_config() -> dict:
    """项目配置 = 引擎的视觉示例键 + 本技能的文字示例键。"""
    cfg = json.loads((ENGINE / "assets/tools/check_deck_visual.example.json").read_text("utf-8"))
    cfg.update(json.loads((FLOW / "scripts/check_deck.example.json").read_text("utf-8")))
    return cfg


@unittest.skipUnless(HAS_PPTX, "没有 python-pptx")
class CheckDeckSplitTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        cls.dir = Path(cls.tmp.name)
        make_deck(cls.dir / "t.pptx")
        (cls.dir / "cfg.json").write_text(json.dumps(project_config(), ensure_ascii=False), "utf-8")

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def run_script(self, script: Path, *extra: str) -> subprocess.CompletedProcess:
        env = {k: v for k, v in os.environ.items() if k not in ("AHAM_DESIGN_ROOT", "AHAM_DESIGN_TOKENS")}
        return subprocess.run([sys.executable, str(script), "t.pptx", "--config", "cfg.json", *extra],
                              cwd=self.dir, capture_output=True, text=True, encoding="utf-8", env=env)

    def test_entry_matches_report_before_split(self):
        proc = self.run_script(FLOW / "scripts" / "check_deck.py")
        self.assertEqual(proc.returncode, 1, proc.stderr)
        self.assertEqual(proc.stdout, EXPECTED.read_text("utf-8") + "\n")

    def test_entry_writes_report_file(self):
        proc = self.run_script(FLOW / "scripts" / "check_deck.py", "--out", "r.md")
        self.assertIn("ERROR 9", proc.stdout)
        self.assertEqual((self.dir / "r.md").read_text("utf-8"), EXPECTED.read_text("utf-8"))

    def test_visual_alone(self):
        proc = self.run_script(ENGINE / "assets" / "tools" / "check_deck_visual.py")
        out = proc.stdout
        self.assertEqual(proc.returncode, 1, proc.stderr)
        self.assertIn("# PPT 视觉检查报告", out)
        self.assertIn("字号 8.0pt 小于下限 9pt", out)
        self.assertIn("用了语义色表外的强调色 #D4892A", out)
        self.assertIn("全册用了 13 级字号", out)
        self.assertIn("人工核对四", out)
        for text_rule in ("禁用词", "价格", "人工核对一", "代码标识符"):
            self.assertNotIn(text_rule, out)


class FindEngineTest(unittest.TestCase):
    def make_plugin(self, root: Path, name: str, version: str, skill: str) -> None:
        (root / ".claude-plugin").mkdir(parents=True)
        (root / ".claude-plugin" / "plugin.json").write_text(json.dumps({"name": name, "version": version}), "utf-8")
        (root / "skills" / skill).mkdir(parents=True)
        (root / "skills" / skill / "SKILL.md").write_text("---\nname: x\n---\n", "utf-8")

    def install_app(self, app_root: Path) -> Path:
        self.make_plugin(app_root, "aham-app", "1.0.0", "aham-ppt-proposal")
        script = app_root / "skills" / "aham-ppt-proposal" / "scripts" / "find_engine.py"
        script.parent.mkdir(parents=True)
        shutil.copy(FLOW / "scripts" / "find_engine.py", script)
        return script

    def run_find(self, script: Path, config: Path, extra_env=None, *args):
        env = {k: v for k, v in os.environ.items() if k != "AHAM_DESIGN_ROOT"}
        env.update({"CLAUDE_CONFIG_DIR": str(config), **(extra_env or {})})
        return subprocess.run([sys.executable, str(script), *args], capture_output=True, text=True, encoding="utf-8", env=env)

    def test_repository_layout(self):
        proc = subprocess.run([sys.executable, str(FLOW / "scripts" / "find_engine.py")], capture_output=True, text=True)
        self.assertEqual(Path(proc.stdout.strip()), ENGINE)

    def test_cache_layout_picks_highest_compatible_version(self):
        with tempfile.TemporaryDirectory() as tmp:
            cache = Path(tmp) / "cache" / "aham-plugins"
            script = self.install_app(cache / "aham-app" / "1.2.0")
            self.make_plugin(cache / "aham-design" / "1.0.0", "aham-design", "1.0.0", "aham-ppt")
            self.make_plugin(cache / "aham-design" / "1.3.0", "aham-design", "1.3.0", "aham-ppt")
            self.make_plugin(cache / "aham-design" / "2.0.0", "aham-design", "2.0.0", "aham-ppt")
            proc = self.run_find(script, Path(tmp) / "config")
            self.assertEqual(Path(proc.stdout.strip()), (cache / "aham-design" / "1.3.0" / "skills" / "aham-ppt").resolve())

    def test_installed_plugins_record(self):
        with tempfile.TemporaryDirectory() as tmp:
            script = self.install_app(Path(tmp) / "apps" / "aham-app")
            design = Path(tmp) / "elsewhere" / "aham-design-1.0.1"
            self.make_plugin(design, "aham-design", "1.0.1", "aham-ppt")
            record = Path(tmp) / "config" / "plugins" / "installed_plugins.json"
            record.parent.mkdir(parents=True)
            record.write_text(json.dumps({"version": 2, "plugins": {
                "aham-design@aham-plugins": [{"scope": "user", "installPath": str(design), "version": "1.0.1"}]}}), "utf-8")
            proc = self.run_find(script, Path(tmp) / "config", None, "--root")
            self.assertEqual(Path(proc.stdout.strip()), design.resolve())

    def test_environment_variable_first_and_checked(self):
        with tempfile.TemporaryDirectory() as tmp:
            script = self.install_app(Path(tmp) / "apps" / "aham-app")
            wrong = Path(tmp) / "wrong"
            self.make_plugin(wrong, "other-plugin", "1.0.0", "aham-ppt")
            proc = self.run_find(script, Path(tmp) / "config", {"AHAM_DESIGN_ROOT": str(wrong)})
            self.assertNotEqual(proc.returncode, 0)
            self.assertIn("插件名是 other-plugin", proc.stderr)
            self.assertIn("AHAM_DESIGN_ROOT", proc.stderr)
            right = Path(tmp) / "right"
            self.make_plugin(right, "aham-design", "1.0.0", "aham-ppt")
            proc = self.run_find(script, Path(tmp) / "config", {"AHAM_DESIGN_ROOT": str(right)}, "--root")
            self.assertEqual(Path(proc.stdout.strip()), right.resolve())


if __name__ == "__main__":
    unittest.main()
