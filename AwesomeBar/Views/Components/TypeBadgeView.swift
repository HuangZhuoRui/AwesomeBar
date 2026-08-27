import SwiftUI

/// 剪贴板条目内容类型多彩圆斑徽标组件
public struct TypeBadgeView: View {
    /// 条目内容类型
    public let type: ClipboardContentType
    @Environment(\.colorScheme) private var colorScheme
    
    public init(type: ClipboardContentType) {
        self.type = type
    }
    
    public var body: some View {
        ZStack {
            Circle()
                .fill(badgeColor.opacity(colorScheme == .dark ? 0.25 : 0.12))
                .frame(width: 34, height: 34)
            
            Image(systemName: type.iconName)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(badgeColor)
        }
    }
    
    /// 获取类型对应的代表色彩
    private var badgeColor: Color {
        switch type {
        case .text, .richText:
            return .blue
        case .code:
            return .purple
        case .color:
            return .pink
        case .url:
            return Color(NSColor.systemIndigo)
        case .image:
            return .green
        case .file:
            return .orange
        }
    }
}
