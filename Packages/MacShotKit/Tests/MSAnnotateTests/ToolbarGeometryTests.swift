import CoreGraphics
import Testing
@testable import MSAnnotate

/// 动作格的几何只有一个家（`MSAnnotationToolbar`），遮罩与贴图两侧都从这里取——
/// 绘制与命中读同一份，才不会"画在一处、点在另一处"（`V-043` 给 ✕ 立的规矩，`V-055` 用到条上）。
struct ToolbarGeometryTests {
    @Test("工具条动作格：四格排在条内、互不重叠、总宽不超过 actionWidth")
    func actionBoxesFitTheBar() {
        let rect = CGRect(x: 100, y: 200, width: 654, height: MSAnnotationToolbar.height)
        let labels = Dictionary(uniqueKeysWithValues: MSAnnotationToolbar.BarAction.allCases.map { ($0, $0.label(verb: "贴出")) })
        let boxes = MSAnnotationToolbar.actionBoxes(rect: rect, labels: labels)
        #expect(boxes.count == 4)

        let total = boxes.reduce(CGFloat(0)) { $0 + $1.rect.width } + 12 * 3
        #expect(total <= MSAnnotationToolbar.actionWidth,
                "四段文字加起来 \(total)pt 超过预留的 \(MSAnnotationToolbar.actionWidth)pt ⇒ 会挤到色板上")
        #expect(boxes.allSatisfy { rect.contains($0.rect.insetBy(dx: -0.5, dy: -0.5)) },
                "有格子超出条的范围：\(boxes.map { ($0.action.rawValue, $0.rect) })")
        let xs = boxes.map(\.rect.minX)
        #expect(xs == xs.sorted(), "格子必须从左到右排：\(xs)")
        for i in 1..<boxes.count {
            #expect(boxes[i - 1].rect.maxX <= boxes[i].rect.minX, "相邻两格重叠")
        }
    }

    @Test("三档提交动词（贴出/复制/保存）都必须排在条内且总宽不超过预留的 actionWidth")
    func everyVerbFitsTheBar() {
        let rect = CGRect(x: 100, y: 200, width: 654, height: MSAnnotationToolbar.height)
        for verb in ["贴出", "复制", "保存"] {
            let labels = Dictionary(uniqueKeysWithValues: MSAnnotationToolbar.BarAction.allCases.map { ($0, $0.label(verb: verb)) })
            let boxes = MSAnnotationToolbar.actionBoxes(rect: rect, labels: labels)
            let total = boxes.reduce(CGFloat(0)) { $0 + $1.rect.width } + 12 * 3
            #expect(total <= MSAnnotationToolbar.actionWidth, "动词「\(verb)」时四段共 \(total)pt > 预留 \(MSAnnotationToolbar.actionWidth)pt ⇒ 挤到色板")
            #expect(boxes.allSatisfy { rect.contains($0.rect.insetBy(dx: -0.5, dy: -0.5)) }, "动词「\(verb)」时有格子出条")
        }
        // 长文案（设置窗那套）确实会溢出——短动词档不是洁癖，是判据
        let longLabels = Dictionary(uniqueKeysWithValues: MSAnnotationToolbar.BarAction.allCases.map { ($0, $0.label(verb: "保存到文件")) })
        let longBoxes = MSAnnotationToolbar.actionBoxes(rect: rect, labels: longLabels)
        let longTotal = longBoxes.reduce(CGFloat(0)) { $0 + $1.rect.width } + 12 * 3
        #expect(longTotal > MSAnnotationToolbar.actionWidth,
                "长文案居然也放得下 ⇒ 短动词档这条判据是空的")
    }

    @Test("近似字宽：中文按 1em、字母数字按 0.6em（格子只会富不会缺）")
    func textWidthApproximation() {
        #expect(MSAnnotationToolbar.textWidth("贴出", pointSize: 11) == 22)
        #expect(MSAnnotationToolbar.textWidth("Esc", pointSize: 11) == 11 * 0.6 * 3)
        #expect(MSAnnotationToolbar.textWidth("⌘C 复制", pointSize: 11)
                < MSAnnotationToolbar.textWidth("⌘C 复制复制", pointSize: 11))
        #expect(MSAnnotationToolbar.isWide("贴") && !MSAnnotationToolbar.isWide("C"))
    }
}
