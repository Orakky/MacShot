#!/usr/bin/env python3
"""文档一致性门禁（V-031 / V-067 的命令面由 §2 表承担）。

三件事，宁可少而准：
1. `docs/…#ID` 形式的引用必须能解析（文件存在 + 文中出现该 ID）。引用解析失败 = agent 会照旧文档干活。
2. requirements.md §1 的每条 P0 必须有四大件归属（ADR-006 的准入纪律）。
3. 统计数字只许出现在 requirements.md §0（本次审查就是因为别处抄了数字才出错）。
5. `make X` 三处一致：AGENTS.md §2 列出的每条命令必须在 Makefile 里是 target、且在 runbook §1 表里有行；反向也一样。
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

# 6) 台账表格形状（11-19 实测：一次错误替换把 E-095 的行尾和"还没证的"那格一起吃掉，还复制出第二个 E-095；
#    而同一个表里另有 9 行早就是少列的旧伤——两类必须分开对待：形状**超出表头**是当场缺陷，少列是历史欠账，要数出来而不是假装看不见）。
SEP = re.compile(r"(?<!\\)\|")
# 必需列数：verification.md 的「跑法 / 读数」两列是后来加的，老行不留这两列**是合法的**，
# 所以按必需列判少列，别把 48 行历史行误报成缺陷（把可选列算进去就等于制造一个永远不会清的红灯）。
REQUIRED = {"docs/tasks/done.md": 3, "docs/protocol/verification.md": 5}
KNOWN_SHORT = {"docs/tasks/done.md": 9}      # 少列的历史行数：修掉一行就要把这个数改小（T-126）
for rel, header in (("docs/tasks/done.md", "| ID | 条目 | 证据 |"),
                    ("docs/protocol/verification.md",
                     "| ID | 类别 | 对应 | 观察对象 | 通过条件 | 跑法 | 读数 / 已知缺口 |")):
    text = (root / rel).read_text(encoding="utf-8")
    if header not in text:
        fail.append(f"{rel}: 表头与门禁假设不一致（找不到 {header!r}）——表格形状改了要同批改这里")
        continue
    ncol = len(header.strip().strip("|").split("|"))
    seen = []
    short = 0
    for line in text.splitlines():
        if not line.startswith("| E-") and not line.startswith("| V-"):
            continue
        cols = len(SEP.findall(line)) - 1
        ident = line.split("|")[1].strip()
        seen.append(ident)
        if cols > ncol:
            fail.append(f"{rel}: {ident} 有 {cols} 列，比表头的 {ncol} 列多 ⇒ 单元里有未转义的裸竖线（写 `\|`）")
        elif cols < REQUIRED[rel]:
            short += 1
    dup = sorted({i for i in seen if seen.count(i) > 1})
    if dup:
        fail.append(f"{rel}: ID 重复 {dup} —— 台账重复行会让人读到两份互相矛盾的结论")
    expect = KNOWN_SHORT.get(rel, 0)
    if short != expect:
        fail.append(f"{rel}: 少列的行数={short}，门禁登记的是 {expect} ⇒ 修好了就把数字改小，别让它悄悄漂移（T-126）")

# 5) 命令三处一致：AGENTS.md §2 的标题自己声称"与 runbook 一致"，那就必须真一致。
#    11-19 实测有 12 个 target 只在 AGENTS §2 出现、runbook §1 表里根本没有行（其中两个还是我这一轮新加的，
#    写完以为落盘了——文件会退回旧状态，靠人记是记不住的，所以做成门禁）。
ag = (root / "AGENTS.md").read_text(encoding="utf-8")
mkb = (root / "Makefile").read_text(encoding="utf-8")
runbook = (root / "docs/runbook/build-and-verify.md").read_text(encoding="utf-8")
agents_cmds = set(re.findall(r"^make ([a-z][a-z0-9-]*)", ag.split("```sh")[1].split("```")[0], re.M)) \
    if "```sh" in ag else set()
targets = set(re.findall(r"^([a-z][a-z0-9-]*):(?!=)", mkb, re.M))
rb_rows = set(re.findall(r"^\| `make ([a-z][a-z0-9-]*)`", runbook, re.M))
for c in sorted(agents_cmds - targets):
    fail.append(f"AGENTS §2 列了 make {c}，但 Makefile 里没有这个 target")
for c in sorted(agents_cmds - rb_rows):
    fail.append(f"AGENTS §2 列了 make {c}，但 runbook §1 表里没有这一行（§2 声称两边一致）")
for c in sorted(rb_rows - agents_cmds):
    fail.append(f"runbook §1 有 make {c}，却没登记进 AGENTS §2")
for c in sorted(rb_rows - targets):
    fail.append(f"runbook §1 有 make {c}，但 Makefile 里没有这个 target")

if fail:
    print("✗ check-docs 失败")
    for f in fail[:20]:
        print("   ", f)
    if len(fail) > 20:
        print(f"    …共 {len(fail)} 条")
    sys.exit(1)
print("✔ check-docs 通过（引用可解析 / P0 有归属 / 计数单源 / 放大镜默认档同边 / make 命令三处一致）")
