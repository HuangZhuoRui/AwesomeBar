import SwiftUI

/// 主界面底部信息统计与快捷键图例说明栏组件
public struct FooterBarView: View {
    /// 当前过滤展示的条目总数
    public let itemCount: Int
    
    public init(itemCount: Int) {
        self.itemCount = itemCount
    }
    
    public var body: some View {
        HStack {
            // 1. 条数统计指示器
            Text("共 \(itemCount) 条历史")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
            
            Spacer()
            
            // 2. 常用键盘快捷操作图例提示
            HStack(spacing: 10) {
                ShortcutHintView(keyText: "←→", labelText: "分类")
                ShortcutHintView(keyText: "↑↓", labelText: "浏览")
                ShortcutHintView(keyText: "Space", labelText: "预览")
                ShortcutHintView(keyText: "↵", labelText: "粘贴")
                ShortcutHintView(keyText: "⌘1-9", labelText: "直选")
                ShortcutHintView(keyText: "Esc", labelText: "关闭")
            }
        }
    }
}
