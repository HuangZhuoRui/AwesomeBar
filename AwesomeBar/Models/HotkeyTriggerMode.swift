import Foundation

/// 全局快捷键与修饰键触发唤起模式
/// 标记为 nonisolated：纯值类型 / 无状态工具，需在数据库与后台队列等非主线程上下文中自由使用。
public nonisolated enum HotkeyTriggerMode: String, Codable, CaseIterable, Identifiable {
    /// 单击物理左侧 Option 键
    case singleOption = "singleOption"
    /// 连按两下物理左侧 Option 键
    case doubleOption = "doubleOption"
    /// 传统全局组合键 Option + V
    case optionV = "optionV"
    
    /// 唯一标识符
    public var id: String {
        return rawValue
    }
    
    /// 设置界面中的完整标题描述
    public var title: String {
        switch self {
        case .singleOption:
            return "按一下左 Option (⌥)"
        case .doubleOption:
            return "连按两下左 Option (⌥⌥)"
        case .optionV:
            return "快捷键 Option + V"
        }
    }
    
    /// 紧凑简短的快捷键标记文本
    public var shortDescription: String {
        switch self {
        case .singleOption:
            return "⌥ (左键)"
        case .doubleOption:
            return "⌥ ⌥ (连按)"
        case .optionV:
            return "⌥ + V"
        }
    }
}
