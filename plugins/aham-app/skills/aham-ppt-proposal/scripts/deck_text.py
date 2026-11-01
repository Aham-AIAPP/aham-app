# -*- coding: utf-8 -*-
"""
PPT 成品的文字检查（读 .pptx，不改文件）。由同目录的 check_deck.py 调用，与引擎的视觉检查合成一份报告。

规则出处：references/wording-rules.md、references/solution-deck.md 第六节。只查机器能判断的项，
「人工核对」各节要逐条对照页面看。页面由引擎的 check_deck_visual.read_slide 读出，本模块不再解析 PPTX。

机器检查（ERROR / WARNING）
  1. 页面文字一段里用逗号或分号连了两个分句
  2. 禁用词、口语词、观察词（页面与讲稿分开统计）
  3. 「第 N 页」引用超出总页数
  4. 内部编号（如 C01、A20）、代码标识符（如 search_knowledge）出现在页面上
  5. 同一组编号跳号（01、03、04）
  6. 术语表里的非标准写法
  7. 标题以句号结尾；title_style 为 noun 时查子标题不以句号结尾、超过 40 字
  8. 页面上出现免费、赠送、折扣说法（ERROR）；出现金额（WARNING，业务数据可保留）。讲稿不查
  9. 数量用汉字数字写（如「三项」「五个」），应写阿拉伯数字（WARNING）
 10. 标题形式（WARNING）。title_style 为 noun（方案类，默认）时查标题像结论句（含「是」「能」「可以」「已」「将」等判断词，
     或长于 20 字）；为 conclusion（汇报类）时查标题超过 24 字或含数字

人工核对清单（INFO，逐条看）
  - 标题与子标题一列（通读用）
  - 每处「第 N 页」引用及其指向页的标题
  - 全册带数量词的说法（N 项、N 个、N 类……），用于前后页数量对照

配置文件里本模块读的键（全部可选）：
{
  "banned": ["〈禁用词〉"],                       // 追加到默认禁用词
  "colloquial": [...],                            // 口语词，给出时替换默认表
  "watch": ["免费", "打样", "〈其他客户名〉"],      // 观察词，追加到默认表：出现即列出，由人判断
  "terms": {"〈主系统〉（含〈子模块〉）": ["〈子模块〉系统"]},  // 标准名: [非标准写法]
  "internal_code": "\\b[A-Z]{1,2}\\d{2}\\b",     // 内部编号正则，可改
  "title_style": "noun"                           // noun：名词标题加结论子标题（方案类）；conclusion：结论式标题（汇报类）
}
示例见同目录的 check_deck.example.json。
"""
from __future__ import annotations

import collections
import re

DEFAULTS = {
    "banned": (
        "承接 赋能 沉淀 落地 抓手 闭环 粒度 颗粒度 归集 收敛 下沉 对位 波次 地基 命脉 灰度 旁路 水位 卡位 "
        "落库 对齐 原生 前置 全域 打通 颠覆 一站式 全链路 最佳实践 "
        "值得注意的是 需要指出的是 事实上 坦白说 总而言之 简而言之 一句话总结 "
        "撑不撑得住 对得起来 说不清 准不准 记得住 跟得上 划得来 值不值 一条链 一盘棋 一本账 全量检查"
    ).split(),
    # 口语词：方案页面不用，客户原话除外
    "colloquial": "干活 坐下来 兜底 露馅 放水 做砸 硬推 松口 长什么样 小工具 聊天窗口".split(),
    "watch": ["免费", "打样", "赠送", "价格", "待定", "待补充", "待现场确认"],
    "terms": {},
    "internal_code": r"(?<![A-Za-z0-9])[A-Z]{1,2}\d{2}(?![A-Za-z0-9])",
    "title_style": "noun",
}
KEYS = tuple(DEFAULTS)
APPEND = ("banned", "watch")

SNAKE = re.compile(r"\b[a-z]+(?:_[a-z0-9]+)+\b")          # search_knowledge
PAGE_REF = re.compile(r"第\s*(\d+)\s*(?:[—–-]\s*(\d+)\s*)?页")
QTY = re.compile(r"(\d+)\s*(项|个|类|条|步|层|组|台|人|款|种|批)")
SPLIT = re.compile(r"[，；;]|,(?!\d{3})")
SEQ = re.compile(r"^\s*0?(\d{1,2})\s*$")
PRICE = re.compile(r"(?:不|免)收费|免费|赠送|折扣|优惠价|报价\s*\d")
MONEY = re.compile(r"\d+(?:\.\d+)?\s*[万千百]?元|[¥￥]\s*\d|RMB")
CN_QTY = re.compile(r"(?<![第之一])([二三四五六七八九十两]|十[一二三四五六七八九])\s*(项|个|类|条|步|层|组|台|款|种|批|页|次|套)")
VERDICT = re.compile(r"是|(?<![功智性技])能(?!力)|可以|已经|已(?!有)|将|必须|应当|实现|提升|降低")


def load_config(user: dict | None) -> dict:
    """从项目配置里取本模块的键。banned、watch 追加到默认表，其他键替换默认值。"""
    cfg = {k: (list(v) if isinstance(v, list) else (dict(v) if isinstance(v, dict) else v)) for k, v in DEFAULTS.items()}
    for k, v in (user or {}).items():
        if k in APPEND:
            cfg[k] += v
        elif k in KEYS:
            cfg[k] = v
    return cfg


def guess_title(paras):
    """标题 = 页面上部 30% 内字号最大的段落；子标题 = 标题之后、上部 35% 内的第一段 12–20pt 文字。
    这是启发式判断，封面、章节页与特殊版式会猜错，报告里只作通读用。"""
    top = [(i, p) for i, p in enumerate(paras) if p[2] < 0.30 and p[1] >= 18]
    if not top:
        return None, None
    i, t = max(top, key=lambda x: x[1][1])
    sub = None
    for j in range(i + 1, len(paras)):
        tx, pt, tp = paras[j]
        if tp < 0.35 and 11 <= pt < 18 and len(tx) > 4:
            sub = tx
            break
    return t[0], sub


class TextCheck:
    """逐页调用 slide_title、slide_commerce、slide_wording。data 是引擎 read_slide 的返回值。"""

    def __init__(self, cfg: dict, n_slides: int):
        self.cfg, self.N = cfg, n_slides
        self.titles, self.refs, self.qtys = [], [], collections.defaultdict(list)
        self._title = {}

    def slide_title(self, idx, data):
        title, sub = guess_title(data[0])
        self._title[idx] = (title, sub)
        self.titles.append((idx, title, sub))

    def slide_commerce(self, idx, data, out):
        """价格、金额和汉字数量。只查页面。"""
        page_text = "\n".join(p[0] for p in data[0])
        for m in PRICE.finditer(page_text):
            out.err.append((idx, f"页面出现价格或免费说法「{m.group(0)}」，商务条款不写在页面上"))
        for m in MONEY.finditer(page_text):
            out.warn.append((idx, f"页面出现金额「{m.group(0)}」：业务数据可保留，我方价格不写在页面上"))
        for m in CN_QTY.finditer(page_text):
            out.warn.append((idx, f"数量用汉字数字「{m.group(0)}」，改为阿拉伯数字"))

    def slide_wording(self, idx, data, out):
        """用词、引用、编号和标题形式。"""
        cfg, paras, notes = self.cfg, data[0], data[3]
        page_text = "\n".join(p[0] for p in paras)
        for where, txt in (("页面", page_text), ("讲稿", notes)):
            for w in cfg["banned"]:
                if w in txt:
                    out.err.append((idx, f"{where}含禁用词「{w}」"))
            for w in cfg["colloquial"]:
                if w in txt:
                    out.warn.append((idx, f"{where}含口语词「{w}」"))
            for w in cfg["watch"]:
                if w in txt:
                    out.info.append((idx, f"{where}出现观察词「{w}」，确认是否该出现"))
            for std, bad in cfg["terms"].items():
                for b in bad:
                    if b in txt:
                        out.warn.append((idx, f"{where}写了「{b}」，术语表标准名为「{std}」"))
            for m in PAGE_REF.finditer(txt):
                n1 = int(m.group(1)); n2 = int(m.group(2) or n1)
                self.refs.append((idx, where, m.group(0), n1, n2))
                if n1 < 1 or n2 > self.N:
                    out.err.append((idx, f"{where}引用「{m.group(0)}」超出总页数 {self.N}"))
            for m in QTY.finditer(txt):
                self.qtys[m.group(2)].append((idx, where, txt[max(0, m.start() - 8):m.end() + 4].replace("\n", " ")))

        for text, pt, top in paras:
            if SPLIT.search(text) and len(text) > 8 and pt < 18:
                out.warn.append((idx, f"一段两个分句：{text[:40]}"))
            for m in re.finditer(cfg["internal_code"], text):
                out.warn.append((idx, f"疑似内部编号「{m.group(0)}」：{text[:30]}"))
            for m in SNAKE.finditer(text):
                out.err.append((idx, f"代码标识符上了页面「{m.group(0)}」"))

        nums = sorted({int(SEQ.match(p[0]).group(1)) for p in paras if SEQ.match(p[0]) and len(p[0].strip()) == 2})
        if len(nums) >= 3:
            gaps = [n for n in range(nums[0], nums[-1] + 1) if n not in nums]
            if gaps and len(gaps) <= 2:
                out.warn.append((idx, f"两位编号疑似跳号：有 {nums}，缺 {gaps}"))

        title, sub = self._title.get(idx, (None, None))
        if cfg["title_style"] == "noun":
            if title and (VERDICT.search(title) or len(title) > 20):
                out.warn.append((idx, f"标题像结论句（应为名词短语，结论写进子标题）：{title}"))
        elif title and (len(title) > 24 or re.search(r"\d", title)):
            out.warn.append((idx, f"结论式标题超过 24 字或含数字：{title}"))
        if title and title.endswith("。"):
            out.warn.append((idx, f"标题以句号结尾：{title}"))
        if sub and cfg["title_style"] == "noun":
            if not sub.endswith("。"):
                out.info.append((idx, f"子标题未以句号结尾：{sub[:40]}"))
            if len(sub) > 40:
                out.warn.append((idx, f"子标题超过 40 字（{len(sub)}）：{sub[:40]}…"))

    def manual_sections(self) -> list[str]:
        N, titles = self.N, self.titles
        out = ["\n\n## 人工核对一　标题与子标题通读\n"]
        out.append("| 页 | 标题 | 子标题 |\n| --- | --- | --- |")
        for i, t, s in titles:
            out.append(f"| {i} | {t or '（未识别）'} | {s or ''} |")
        out.append("\n\n## 人工核对二　页码引用\n")
        out.append("| 所在页 | 位置 | 引用 | 指向页标题 |\n| --- | --- | --- | --- |")
        for i, where, raw, n1, n2 in self.refs:
            tgt = "；".join((titles[k - 1][1] or "（未识别）") for k in range(n1, n2 + 1) if 1 <= k <= N)
            out.append(f"| {i} | {where} | {raw} | {tgt} |")
        out.append("\n\n## 人工核对三　数量说法（前后页对照）\n")
        for unit, lst in sorted(self.qtys.items(), key=lambda x: -len(x[1])):
            out.append(f"\n**「{unit}」**")
            for i, where, ctx in lst:
                out.append(f"- 第 {i} 页 {where}：…{ctx}…")
        return out
