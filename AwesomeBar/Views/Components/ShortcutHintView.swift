import SwiftUI

/// 快捷键提示标签胶囊组件
public struct ShortcutHintView: View {
    /// 键位字符（例如："↑↓", "↵", "Space", "Esc"）
    public let keyText: String
    /// 功能说明描述（例如："浏览", "粘贴", "详情", "关闭"）
    public let labelText: String
    
    public init(keyText: String, labelText: String) {
        self.keyText = keyText
        self.labelText = labelText
    }
    
    public var body: some View {
        HStack(spacing: 4) {
            Text(keyText)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.primary.opacity(0.07))
                )
            
            Text(labelText)
                .font(.system(size: 10.5))
                .foregroundColor(.secondary)
        }
    }
}
