#!/usr/bin/env python3
"""公开检查：仓库里不得出现私有名称、真实客户、真实人员和私有域名。

本仓库公开，私有名称本身也不能写进仓库，所以检查分三部分：

1. 内置词：只存小写后的 SHA-256 摘要，按长度扫描每个子串的摘要，大小写不敏感。
   内置词包括私有公司名和英文品牌名，品牌名同时覆盖其域名。
2. 私有词表：环境变量 AHAM_PRIVATE_TERMS（每行一个词，CI 从仓库密钥读入），
   以及环境变量 AHAM_PRIVATE_TERMS_FILE 指向的文件，缺省为 ~/.aham/private-terms.txt，每行一个词，# 开头为注释。
   真实客户名、员工名写在词表里，大小写不敏感。
3. 结构规则：中文企业名称（以「有限公司」结尾）必须带「示例」「测试」或「回归」。

检查范围：已跟踪文件的路径和内容；.docx、.xlsx、.pptx 解压后检查其中的 XML 文字；其他二进制文件跳过。

用法：
    python3 scripts/check_public.py                  检查全部已跟踪文件
    python3 scripts/check_public.py --staged         只检查暂存区（pre-commit 钩子用）
    python3 scripts/check_public.py --message 文件   检查提交说明（commit-msg 钩子用）
    python3 scripts/check_public.py --history        另外检查全部提交说明
    python3 scripts/check_public.py --require-terms  没有私有词表时报错（CI 用）

命中时只显示词的首字，避免把名称再写进日志。
"""

from __future__ import annotations

import hashlib
import io
import os
import re
import subprocess
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BUILT_IN = {
    3: {"651d6a4a2cda37568a6deb127c8d20cf3ff0eb188e989de3fe47948e20052645"},
    8: {"b01373274e8601d784062cfd3c9a55dcc8482199163c39c58c0cc0677cbcadc1"},
}
COMPANY = re.compile(r"[一-龥A-Za-z0-9（）()]{2,16}?(?:股份)?有限公司")
COMPANY_ALLOWED = ("示例", "测试", "回归")
OFFICE = {".docx", ".xlsx", ".pptx"}
SKIP_SUFFIXES = {".png", ".jpg", ".jpeg", ".gif", ".ico", ".pdf", ".glb", ".woff", ".woff2", ".ttf", ".zip"}


def _split(text: str) -> list[str]:
    words = []
    for line in text.splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            words.extend(part.strip() for part in line.split(",") if part.strip())
    return words


def load_terms() -> list[str]:
    terms = _split(os.environ.get("AHAM_PRIVATE_TERMS", ""))
    file = Path(os.environ.get("AHAM_PRIVATE_TERMS_FILE") or Path.home() / ".aham/private-terms.txt").expanduser()
    if file.is_file():
        terms += _split(file.read_text("utf-8"))
    # 一个字的词误报太多，不查。
    return sorted({t.lower() for t in terms if len(t) >= 2}, key=len, reverse=True)


def _git(*args: str) -> str:
    return subprocess.run(["git", *args], cwd=ROOT, capture_output=True, text=True, check=True).stdout


def _git_bytes(*args: str) -> bytes:
    return subprocess.run(["git", *args], cwd=ROOT, capture_output=True, check=True).stdout


def _office_text(data: bytes) -> str:
    with zipfile.ZipFile(io.BytesIO(data)) as archive:
        parts = [archive.read(name).decode("utf-8", errors="ignore")
                 for name in archive.namelist() if name.endswith((".xml", ".rels"))]
    # 去掉标签，相邻 run 的文字拼起来，名称被拆进两个 run 时也能查到。
    return "\n".join(re.sub(r"<[^>]+>", "", part) for part in parts)


def tracked_files(staged: bool) -> list[tuple[str, str]]:
    if staged:
        names = _git("diff", "--cached", "--name-only", "--diff-filter=ACMR").splitlines()
        read = lambda name: _git_bytes("show", f":{name}")  # noqa: E731
    else:
        names = _git("ls-files").splitlines()
        read = lambda name: (ROOT / name).read_bytes()  # noqa: E731
    files = []
    for name in names:
        files.append((f"{name}（路径）", name))
        suffix = Path(name).suffix.lower()
        if suffix in SKIP_SUFFIXES:
            continue
        try:
            data = read(name)
        except (OSError, subprocess.CalledProcessError):
            continue
        files.append((name, _office_text(data) if suffix in OFFICE else data.decode("utf-8", errors="ignore")))
    return files


def commit_messages() -> list[tuple[str, str]]:
    log = _git("log", "--format=%H%x00%B%x01") if _git("rev-parse", "--verify", "-q", "HEAD").strip() else ""
    result = []
    for entry in filter(None, (item.strip() for item in log.split("\x01"))):
        sha, _, body = entry.partition("\x00")
        result.append((f"提交 {sha[:8]}", body))
    return result


def _mask(term: str) -> str:
    return term[0] + "＊" * (len(term) - 1)


def _built_in_hits(line: str) -> list[str]:
    lowered = line.lower()
    hits = []
    for length, digests in BUILT_IN.items():
        for start in range(0, len(lowered) - length + 1):
            piece = lowered[start:start + length]
            if hashlib.sha256(piece.encode("utf-8")).hexdigest() in digests:
                hits.append(piece)
    return hits


def scan(files: list[tuple[str, str]], terms: list[str]) -> list[str]:
    errors = []
    for name, text in files:
        for number, line in enumerate(text.splitlines(), 1):
            lowered = line.lower()
            for hit in _built_in_hits(line):
                errors.append(f"{name}:{number}: 含内置私有词「{_mask(hit)}」")
            for term in terms:
                if term in lowered:
                    errors.append(f"{name}:{number}: 含私有词表里的词「{_mask(term)}」")
            for match in COMPANY.finditer(line):
                if not any(mark in match.group(0) for mark in COMPANY_ALLOWED):
                    errors.append(f"{name}:{number}: 企业名称「{_mask(match.group(0))}」不带「示例」，仓库只放虚构企业")
    return errors


def main(argv: list[str]) -> int:
    terms = load_terms()
    if "--require-terms" in argv and not terms:
        print("没有找到私有词表：设置 AHAM_PRIVATE_TERMS 或 AHAM_PRIVATE_TERMS_FILE。", file=sys.stderr)
        return 1
    if "--message" in argv:
        path = Path(argv[argv.index("--message") + 1])
        files = [("提交说明", path.read_text("utf-8", errors="ignore"))]
    else:
        files = tracked_files("--staged" in argv)
        if "--history" in argv:
            files += commit_messages()
    errors = scan(files, terms)
    for error in errors:
        print(error, file=sys.stderr)
    source = f"内置词和私有词表 {len(terms)} 个词" if terms else "只有内置词，没有私有词表"
    if errors:
        print(f"公开检查未通过：{len(errors)} 处（{source}）。", file=sys.stderr)
        return 1
    print(f"公开检查通过：{len(files)} 项（{source}）")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
