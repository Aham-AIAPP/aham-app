#!/usr/bin/env python3
"""生成 PPT 基准样张：用 aham-ppt 引擎 demo/build.js 的五页示例走一遍完整流程，把每一步的产出写进同一个目录。

用法：
  python3 scripts/build_ppt_samples.py 输出目录 [--check]

  --check  生成后检查：check_slides.js 为 0 个 ERROR、0 个 WARNING，check_deck.py 为 0 个 ERROR。不满足时返回 1。

输出目录里的样张：
  deck/deck.json、deck/slides/*.html   demo/build.js 写出的网页幻灯片
  preview.html                          preview.js 合成的预览页
  check_slides.md                       check_slides.js 的报告
  png/01.png …                          check_slides.js --png 的逐页截图
  demo.pptx                             html2pptx.js 导出的 PPTX
  项目配置.json                          引擎视觉示例配置与流程文字示例配置合并而成
  check_deck.md                         aham-app 的 check_deck.py 检查 PPTX 的报告

预览、检查和导出要用 Playwright 的 Chromium，先在引擎的 assets/html2pptx 运行 npm install。
导出和截图依赖浏览器排版，样张只在同一台机器上比对：改前、改后各生成一份，再用
scripts/compare_outputs.py diff 列出不同的文件和部件。
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ENGINE = ROOT / "plugins" / "aham-design" / "skills" / "aham-ppt"
FLOW = ROOT / "plugins" / "aham-app" / "skills" / "aham-ppt-proposal"
SUMMARY = re.compile(r"ERROR (\d+) 条　WARNING (\d+) 条")


def run(cmd: list[str], cwd: Path | None = None, ok: tuple[int, ...] = (0,)) -> subprocess.CompletedProcess:
    """运行一条命令；退出码不在 ok 里时打印输出并中止。"""
    print("$", " ".join(cmd), flush=True)
    proc = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, encoding="utf-8")
    if proc.returncode not in ok:
        sys.stdout.write(proc.stdout)
        sys.stderr.write(proc.stderr)
        raise SystemExit(f"命令失败，退出码 {proc.returncode}：{' '.join(cmd)}")
    if proc.stderr.strip():
        sys.stderr.write(proc.stderr)
    return proc


def counts(text: str, name: str) -> tuple[int, int]:
    m = SUMMARY.search(text)
    if not m:
        raise SystemExit(f"{name} 的报告里找不到 ERROR、WARNING 计数")
    return int(m.group(1)), int(m.group(2))


def build(out: Path) -> dict[str, int]:
    js = ENGINE / "assets" / "html2pptx"
    deck = out / "deck"
    run(["node", str(js / "demo" / "build.js"), str(deck)])
    run(["node", str(js / "preview.js"), str(deck), str(out / "preview.html")])

    # check_slides.js 有 ERROR 时退出码为 1，这是检查结论；退出码 2 才是程序出错
    proc = run(["node", str(js / "check_slides.js"), str(deck), "--png", str(out / "png")], ok=(0, 1))
    (out / "check_slides.md").write_text(proc.stdout, "utf-8")
    slides_err, slides_warn = counts(proc.stdout, "check_slides.js")

    run(["node", str(js / "html2pptx.js"), str(deck), str(out / "demo.pptx")])

    config = json.loads((ENGINE / "assets/tools/check_deck_visual.example.json").read_text("utf-8"))
    config.update(json.loads((FLOW / "scripts/check_deck.example.json").read_text("utf-8")))
    (out / "项目配置.json").write_text(json.dumps(config, ensure_ascii=False, indent=2) + "\n", "utf-8")
    # 在输出目录里用相对路径运行，报告第一行的文件名在任何目录下都相同
    run([sys.executable, str(FLOW / "scripts" / "check_deck.py"), "demo.pptx", "--config", "项目配置.json",
         "--out", "check_deck.md"], cwd=out, ok=(0, 1))
    deck_err, deck_warn = counts((out / "check_deck.md").read_text("utf-8"), "check_deck.py")
    return {"slides_error": slides_err, "slides_warning": slides_warn, "deck_error": deck_err, "deck_warning": deck_warn}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("out", type=Path, help="输出目录，必须不存在或为空")
    parser.add_argument("--check", action="store_true", help="检查结果不为 0 时返回 1")
    args = parser.parse_args(argv)

    out = args.out.resolve()
    if out.exists() and any(out.iterdir()):
        raise SystemExit(f"输出目录不为空：{out}")
    out.mkdir(parents=True, exist_ok=True)

    c = build(out)
    files = sorted(p.relative_to(out).as_posix() for p in out.rglob("*") if p.is_file())
    print(f"已生成 {len(files)} 份样张：{out}")
    print(f"check_slides.js：ERROR {c['slides_error']}　WARNING {c['slides_warning']}")
    print(f"check_deck.py：ERROR {c['deck_error']}　WARNING {c['deck_warning']}")
    if args.check and (c["slides_error"] or c["slides_warning"] or c["deck_error"]):
        print("检查未通过：check_slides.js 应为 0 个 ERROR、0 个 WARNING，check_deck.py 应为 0 个 ERROR。")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
