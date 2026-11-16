# ADR-002 UI 技术栈：AppKit 优先，SwiftUI 只进设置面板

状态：**proposed** 日期：2026-11-16 相关：ADR-001、FR-PIN-004、FR-SESS-003

## 背景
遮罩、贴图、标注画布三类 UI 都有硬性系统要求：borderless 全屏窗、nonactivating panel、窗口 level 精确控制、`NSView` 级脏区重绘、裸事件路由（`mouseDragged` 期间要拦截并改语义）、`NSTextView` 输入容器。SwiftUI 对这些的覆盖程度决定实现能不能做。

## 决策
- 遮罩 / 贴图 / 标注画布 / 放大镜：**AppKit**（`NSWindow`、`NSPanel`、`NSView` + `CGContext` 自绘）。
- 设置窗（`UI-005`）与右键菜单：**允许 SwiftUI**（`NSHostingView` 宿主），因为它是普通表单，且 SwiftUI 表单在明暗与本地化上省事。
- 状态与数据在 AppKit 侧是值类型 + `didSet` 驱动重绘；不引入 Combine 之外的响应式框架。

## 已考虑并否决的方案
| 方案 | 否决理由 | 什么证据会翻案 |
|---|---|---|
| 全 SwiftUI（`WindowGroup`/`Window` scene） | `LSUIElement` + 无主窗 + 多 Space 贴图 + nonactivating 的语义在 SwiftUI scene 体系里表达不出；画布每帧重绘性能不可控 | 若 M-2 实测证明 SwiftUI 能在不 activate app 的前提下拿到并释放键盘焦点，且 60fps 画布在 4K 选区成立 |
| Metal/`CAMetalLayer` 画布 | 首版元素数量小，CoreGraphics 足够；提前上 GPU 会让"预览=导出"的一致性测试翻倍 | 若元素数 >800 或 4K 全屏遮罩拖拽低于 30fps（NFR 目标值待实测） |
| Electron / Tauri（参考产品自身的技术栈） | 与"原生、常驻内存小、系统级窗口层级"的目标相反 | 不会翻案 |

## 后果
正面：窗口层级与事件路径完全可控；贴图/遮罩的像素级渲染责任清楚。
负面：设置窗混用两种 UI 技术，需在 `modules.md` 里限定宿主位置；AppKit 键盘焦点处理要自己写（`overlay-and-selection.md` §1 风险已记）。

## 判据
M-2 出口必须实拍确认：① 不 activate app 时遮罩能收键；② 贴图出现/关闭不改变 `NSWorkspace.frontmostApplication`；③ 4K 选区拖拽不掉帧（数值进 `done.md`）。

## 受影响
`App/`、`MSOverlay`、`MSPin`、`MSAnnotate` 无视图依赖（`annotate-model.md` §5.5）。
