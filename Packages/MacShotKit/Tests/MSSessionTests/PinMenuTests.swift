import AppKit
import Testing
@testable import MSSession
import MSPin

/// 用户 11-19：**贴图右键菜单里不要出现组合键**，菜单只当鼠标出口。
/// 这条测试钉两件事：标题干净，以及"动作还在"——摘掉装饰文字不许顺手把功能摘掉。
struct PinMenuTests {
    @MainActor
    @Test("贴图右键菜单：标题不含任何组合键字样，动作与选择器一个不少")
    func menuHasNoChordHintsButKeepsActions() throws {
        let menu = MSSessionCoordinator.makePinMenu()
        let titles = menu.items.compactMap { $0.isSeparatorItem ? nil : $0.title }
        #expect(titles == ["复制", "保存", "关闭贴图"], "菜单项文案变了：\(titles)")
        for item in menu.items where !item.isSeparatorItem {
            #expect(!item.title.contains("⌘") && !item.title.contains("⌥") && !item.title.contains("Esc"),
                    "标题里还留着组合键提示：\(item.title)")
            #expect(item.keyEquivalent.isEmpty, "keyEquivalent 必须是空串——菜单不参与按键，显示了就是假承诺")
            #expect(item.action != nil, "\(item.title) 没有动作，点了不会有任何反应")
            #expect(item.target == nil, "\(item.title) 的 target 被钉死了，走不到响应链")
        }
        let selectors = menu.items.compactMap(\.action)
        #expect(selectors.contains(#selector(MSPinView.menuCopy(_:)))
                && selectors.contains(#selector(MSPinView.menuQuickSave(_:)))
                && selectors.contains(#selector(MSPinView.menuClose(_:))), "got=\(selectors)")
    }
}
