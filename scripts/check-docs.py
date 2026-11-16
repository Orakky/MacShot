#!/usr/bin/env python3
"""文档一致性门禁（V-031）。

三件事，宁可少而准：
1. `docs/…#ID` 形式的引用必须能解析（文件存在 + 文中出现该 ID）。引用解析失败 = agent 会照旧文档干活。
2. requirements.md §1 的每条 P0 必须有四大件归属（ADR-006 的准入纪律）。
3. 统计数字只许出现在 requirements.md §0（本次审查就是因为别处抄了数字才出错）。
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

if fail:
    print("✗ check-docs 失败")
    for f in fail[:20]:
        print("   ", f)
    if len(fail) > 20:
        print(f"    …共 {len(fail)} 条")
    sys.exit(1)
print("✔ check-docs 通过（引用可解析 / P0 有归属 / 计数单源）")
