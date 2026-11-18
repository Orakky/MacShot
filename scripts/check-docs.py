#!/usr/bin/env python3
"""文档一致性门禁（V-031）。

三件事，宁可少而准：
1. `docs/…#ID` 形式的引用必须能解析（文件存在 + 文中出现该 ID）。引用解析失败 = agent 会照旧文档干活。
2. requirements.md §1 的每条 P0 必须有四大件归属（ADR-006 的准入纪律）。
3. 统计数字只许出现在 requirements.md §0（本次审查就是因为别处抄了数字才出错）。
4. 改判过的**默认档**必须代码与规格同边，且旧措辞不许残留在活文档里（11-18 放大镜那条就是这么漏的：
   代码翻了默认值、五份文档还写着"自动弹出"，`--snip-then-loupe` 的判据也会跟着失真）。
"""
import pathlib
import re
import sys

root = pathlib.Path(__file__).resolve().parents[1]
docs = [p for p in root.rglob("*.md") if ".build" not in p.parts and "build/" not in str(p)]
fail = []

ref_re = re.compile(r"`?(docs/[A-Za-z0-9_\-./]+\.md|prototypes/[A-Za-z0-9_\-./]+\.html|README\.md|AGENTS\.md)#([A-Za-z]{2,4}[-_][0-9A-Za-z]+)`?")
for p in docs:
    if "templates" in p.parts:
        continue          # 模板里的 ST-00n / UI-00n 是占位符，不是引用
    text = p.read_text(encoding="utf-8", errors="ignore")
    for m in ref_re.finditer(text):
        target, ident = m.group(1), m.group(2)
        tpath = (root / target)
        if not tpath.exists():
            fail.append(f"{p.relative_to(root)}: 引用目标不存在 → {target}")
            continue
        body = tpath.read_text(encoding="utf-8", errors="ignore")
        # IDs appear as "FR-CAP-001" / "UI-001" / anchors "## UI-001" — match the bare token.
        if ident not in body:
            fail.append(f"{p.relative_to(root)}: 锚点不存在 → {target}#{ident}")

req = (root / "docs/requirements/requirements.md").read_text(encoding="utf-8")
body = req.split("## 2. P0 里")[0]
for line in body.splitlines():
    if re.match(r"^\|\s*FR-[A-Z]+-\d+", line):
        cols = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cols) < 3:
            continue
        pillar = cols[2] if len(cols) > 2 else ""
        if not re.match(r"^[①②③④]", pillar) and "支撑" not in pillar:
            fail.append(f"requirements.md: {cols[0]} 无四大件归属（列值={pillar!r}）")

count_re = re.compile(r"P0\s*[=＝]\s*\d+\s*条|P0\s*(\d{2})\s*条")
for p in docs:
    if p.name == "requirements.md":
        continue
    for m in count_re.finditer(p.read_text(encoding="utf-8", errors="ignore")):
        fail.append(f"{p.relative_to(root)}: 复制了 P0 计数（{m.group(0)!r}）——只允许写在 requirements.md §0")

# 4) 放大镜的默认档：代码与规格必须**同边**，且不许有停在改判前的措辞（11-18 用户改判 Q-07 呈现档）。
#    规则本身与方向无关：翻回 true 也必须同步改规格，否则这条一样红。
prefs = (root / "Packages/MacShotKit/Sources/MSSettings/MSAppPreferences.swift").read_text(encoding="utf-8")
auto_default_true = "showMagnifierWhileDragging: Bool = true" in prefs
spec_says_off = "默认**不**自动弹出" in req or "默认不自动弹" in req
if auto_default_true == spec_says_off:
    fail.append("放大镜默认档不一致：代码 auto_default_true=%s、规格'默认不自动弹'=%s —— 改一边必须同批改另一边"
                % (auto_default_true, spec_says_off))
# 短语表只挡"原句照抄"（实测：换一种说法描述同一个旧行为就漏了，反证③），
# 真正兜底的是上面那条代码↔规格同边——它不看措辞，只看两边一致不一致。
stale = ("跟随光标自动出现", "拖拽时自动弹出放大镜", "拖框时放大镜自动出现", "拖拽中自动出现")
for p2 in docs:
    if "tasks/" in str(p2.relative_to(root)) or "snipaste-gap" in p2.name:
        continue                      # 台账是历史、gap 描述的是 Snipaste 自己的行为
    t = p2.read_text(encoding="utf-8", errors="ignore")
    for line in t.splitlines():
        for phrase in stale:
            i = line.find(phrase)
            while i >= 0:
                # 否定词必须**贴着**短语；窗口开大就会被"不复用/避免"这类无关的"不"骗过（反证②第一次就是这么漏的）
                prefix = line[max(0, i - 6):i]
                if not any(n in prefix for n in ("不", "未", "没", "禁止", "撤掉", "去掉")):
                    fail.append(f"{p2.relative_to(root)}: 「{phrase}」停在 11-18 改判前的措辞（行首 {line[:40]}…）")
                i = line.find(phrase, i + len(phrase))

if fail:
    print("✗ check-docs 失败")
    for f in fail[:20]:
        print("   ", f)
    if len(fail) > 20:
        print(f"    …共 {len(fail)} 条")
    sys.exit(1)
print("✔ check-docs 通过（引用可解析 / P0 有归属 / 计数单源 / 放大镜默认档代码与规格同边）")
