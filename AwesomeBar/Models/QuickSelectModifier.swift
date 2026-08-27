import Foundation
import AppKit

/// 历史记录条目数字直选快捷键修饰键模式（支持 ⌃⌘1-9、⇧⌘1-9、⌘1-9、⌥1-9 等自定义配置）
public enum QuickSelectModifier: String, Codable, CaseIterable, Identifiable {
    /// 默认: Control + Command (⌃⌘ 1~9)
    case controlCommand = "controlCommand"
    /// Command + Shift (⇧⌘ 1~9)
    case commandShift = "commandShift"
    /// 传统: Command (⌘ 1~9)
    case command = "command"
    /// Option (⌥ 1~9)
    case option = "option"
    /// Control (⌃ 1~9)
    case control = "control"
    /// Control + Option (⌃⌥ 1~9)
    case controlOption = "controlOption"
    /// 禁用数字直选快捷键
    case none = "none"
    
    public var id: String { rawValue }
    
    /// 设置界面的完整标题展示
    public var title: String {
        switch self {
        case .controlCommand:
            return "Control + Command (⌃⌘ 1~9，推荐)"
        case .commandShift:
            return "Command + Shift (⇧⌘ 1~9)"
        case .command:
            return "Command (⌘ 1~9)"
        case .option:
            return "Option (⌥ 1~9)"
        case .control:
            return "Control (⌃ 1~9)"
        case .controlOption:
            return "Control + Option (⌃⌥ 1~9)"
        case .none:
            return "未启用 / 禁用"
        }
    }
    
    /// 前缀快捷键符号组合（如 "⌃⌘"、"⇧⌘"、"⌘" 等）
    public var symbolPrefix: String {
        switch self {
        case .controlCommand:
            return "⌃⌘"
        case .commandShift:
            return "⇧⌘"
        case .command:
            return "⌘"
        case .option:
            return "⌥"
        case .control:
            return "⌃"
        case .controlOption:
            return "⌃⌥"
        case .none:
            return ""
        }
    }
    
    /// 格式化指定数字序号的显示文本（如 "⌃⌘1"、"⇧⌘1"）
    public func badgeText(for index: Int) -> String? {
        guard self != .none else { return nil }
        return "\(symbolPrefix)\(index)"
    }
    
    /// 校验按键事件中的修饰键是否精准匹配本模式
    public func matches(flags: NSEvent.ModifierFlags) -> Bool {
        let cleanFlags = flags.intersection([.command, .option, .shift, .control])
        switch self {
        case .controlCommand:
            return cleanFlags == [.control, .command]
        case .commandShift:
            return cleanFlags == [.command, .shift]
        case .command:
            return cleanFlags == [.command]
        case .option:
            return cleanFlags == [.option]
        case .control:
            return cleanFlags == [.control]
        case .controlOption:
            return cleanFlags == [.control, .option]
        case .none:
            return false
        }
    }
}
