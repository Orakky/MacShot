# spikes/ —— 未裁决代码的停放处

**这里的任何内容都不是真源，不可作为实现依据。**

当前状态：目录为空。裁决前写过一版骨架（`Packages/MacShotKit` 10 模块 + 3 个 MSCore 文件 + `App/` 空壳，共 9 个文件 / 874 行），已用可逆方式收起：

```sh
git stash list
# stash@{0}: On main: architecture-spike: Packages/MacShotKit + App (未裁决，暂缓)
```

为什么不直接删、也不 pop 回来：
- 删：几何与渲染接口的那次尝试有参考价值（它已经在 `modules.md` §12 被逐条核对成 3 处不符）。
- pop：会把"未经裁决的既成事实"放回工作树，后续 agent 极可能把它当依据继续写。

处置决定挂在 `T-018`（对照 accepted ADR 逐条给"复用 / 参考重写"结论）。已知 3 处必须改才能用（见 `docs/architecture/modules.md` §12）：
1. `AnnotationDocument` 缺 `schemaVersion`（违 ADR-009 / D-04）。
2. `PinContent` 当时定为位图（违 ADR-005 / D-04）。
3. 颜色与类型命名与 `modules.md` 不同源（会在文档与代码之间造出两套名字）。

以后若需要写探路代码（验证 API 行为、试渲染效果），一律放本目录的**子文件夹**并在 `docs/tasks/todo.md` 登记一行；子文件夹内必须有 `README.md` 写明"验证什么、结论去向哪个 ADR"。验证完要么转成正式实现（走任务卡），要么删掉并把结论写进 ADR/问题库——**不允许长期半活在本目录**。
