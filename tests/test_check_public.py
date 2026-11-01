"""scripts/check_public.py 的自测：内置摘要、私有词表和企业名称规则都能查出问题。"""

from __future__ import annotations

import hashlib
import io
import os
import subprocess
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))

import check_public  # noqa: E402


class CheckPublicTests(unittest.TestCase):
    def test_built_in_digest_matches_any_case(self):
        digest = hashlib.sha256("examplebrand".encode()).hexdigest()
        with mock.patch.dict(check_public.BUILT_IN, {12: {digest}}, clear=True):
            errors = check_public.scan([("a.md", "see ExampleBrand.cn for details")], [])
        self.assertEqual(len(errors), 1)
        self.assertNotIn("ExampleBrand", errors[0])

    def test_private_terms_from_environment(self):
        with mock.patch.dict(os.environ, {"AHAM_PRIVATE_TERMS": "示例甲方\nSecretCo", "AHAM_PRIVATE_TERMS_FILE": "/nonexistent"}):
            terms = check_public.load_terms()
        errors = check_public.scan([("b.py", "# secretco 和示例甲方")], terms)
        self.assertEqual(len(errors), 2)

    def test_company_names_must_be_fictional(self):
        # 企业名称后缀分开写，本文件自身才能通过公开检查。
        suffix = "有限" + "公司"
        errors = check_public.scan([("c.md", f"苏州某某精密科技{suffix}；苏州示例精密{suffix}")], [])
        self.assertEqual(len(errors), 1)

    def test_office_files_are_unpacked(self):
        buffer = io.BytesIO()
        with zipfile.ZipFile(buffer, "w") as archive:
            archive.writestr("word/document.xml", "<w:t>Secret</w:t><w:t>Co</w:t>")
        self.assertIn("SecretCo", check_public._office_text(buffer.getvalue()))

    def test_non_ascii_paths_are_read(self):
        # git 默认把中文路径转义成带引号的形式，按那个名字读不到文件，检查会静默跳过。
        with tempfile.TemporaryDirectory() as tmp:
            subprocess.run(["git", "init", "-q", tmp], check=True)
            (Path(tmp) / "部署说明.md").write_text("中文文件名里的内容\n", encoding="utf-8")
            subprocess.run(["git", "-C", tmp, "add", "部署说明.md"], check=True)
            with mock.patch.object(check_public, "ROOT", Path(tmp)):
                files = dict(check_public.tracked_files(staged=False))
        self.assertEqual(files.get("部署说明.md"), "中文文件名里的内容\n")

    def test_repository_passes_built_in_checks(self):
        files = check_public.tracked_files(staged=False)
        self.assertEqual(check_public.scan(files, []), [])


if __name__ == "__main__":
    unittest.main()
