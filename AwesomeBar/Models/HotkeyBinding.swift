import Foundation
import AppKit

/// 全局快捷键与修饰键唤起绑定模型
public struct HotkeyBinding: Codable, Equatable, Hashable {
    /// 触发机制类别
    public enum TriggerKind: String, Codable {
        /// 单击物理左侧 Option 键
        case singleOption = "singleOption"
        /// 连按两下物理左侧 Option 键
        case doubleOption = "doubleOption"
        /// 组合键（如 Option+V、Cmd+Shift+V、Option+Space 等）
        case keyCombination = "keyCombination"
        /// 禁用唤起
        case none = "none"
    }
    
    /// 触发类型
    public var kind: TriggerKind
    /// 虚拟按键码（KeyCode，仅在 keyCombination 时生效）
    public var keyCode: UInt16?
    /// 修饰键标志位整数值（NSEvent.ModifierFlags rawValue）
    public var modifierRawValue: UInt?
    /// 用户界面展示文本
    public var displayTitle: String
    
    public init(
        kind: TriggerKind,
        keyCode: UInt16? = nil,
        modifierRawValue: UInt? = nil,
        displayTitle: String
    ) {
        self.kind = kind
        self.keyCode = keyCode
        self.modifierRawValue = modifierRawValue
        self.displayTitle = displayTitle
    }
    
    // MARK: - 常用标准预设
    
    /// 预设：按一下左 Option (⌥)
    public static let singleOption = HotkeyBinding(
        kind: .singleOption,
        displayTitle: "按一下左 Option (⌥)"
    )
    
    /// 预设：连按两下左 Option (⌥⌥)
    public static let doubleOption = HotkeyBinding(
        kind: .doubleOption,
        displayTitle: "连按两下左 Option (⌥⌥)"
    )
    
    /// 预设：Option + Space (⌥ Space)
    public static let optionSpace = HotkeyBinding(
        kind: .keyCombination,
        keyCode: 49,
        modifierRawValue: NSEvent.ModifierFlags.option.rawValue,
        displayTitle: "⌥ Space"
    )
    
    /// 预设：Option + V (⌥ V)
    public static let optionV = HotkeyBinding(
        kind: .keyCombination,
        keyCode: 9,
        modifierRawValue: NSEvent.ModifierFlags.option.rawValue,
        displayTitle: "⌥ V"
    )
    
    /// 预设：Option + B (⌥ B)
    public static let optionB = HotkeyBinding(
        kind: .keyCombination,
        keyCode: 11,
        modifierRawValue: NSEvent.ModifierFlags.option.rawValue,
        displayTitle: "⌥ B"
    )
    
    /// 预设：Command + Shift + V (⇧ ⌘ V)
    public static let cmdShiftV = HotkeyBinding(
        kind: .keyCombination,
        keyCode: 9,
        modifierRawValue: NSEvent.ModifierFlags([.command, .shift]).rawValue,
        displayTitle: "⇧ ⌘ V"
    )
    
    /// 预设：Command + Shift + B (⇧ ⌘ B)
    public static let cmdShiftB = HotkeyBinding(
        kind: .keyCombination,
        keyCode: 11,
        modifierRawValue: NSEvent.ModifierFlags([.command, .shift]).rawValue,
        displayTitle: "⇧ ⌘ B"
    )
    
    /// 预设：无 / 禁用
    public static let none = HotkeyBinding(
        kind: .none,
        displayTitle: "未设置 / 禁用"
    )
    
    // MARK: - 按键码与符号格式化转换辅助
    
    /// 将键盘事件解析为 HotkeyBinding
    public static func fromEvent(_ event: NSEvent) -> HotkeyBinding? {
        let rawModifiers = event.modifierFlags.intersection([.command, .option, .shift, .control])
        let keyCode = event.keyCode
        
        // 忽略纯修饰键按压
        if [54, 55, 56, 57, 58, 59, 60, 61, 62, 63].contains(keyCode) {
            return nil
        }
        
        var symbols: [String] = []
        if rawModifiers.contains(.control) { symbols.append("⌃") }
        if rawModifiers.contains(.option) { symbols.append("⌥") }
        if rawModifiers.contains(.shift) { symbols.append("⇧") }
        if rawModifiers.contains(.command) { symbols.append("⌘") }
        
        let keyChar = keycodeToString(keyCode: keyCode)
        symbols.append(keyChar)
        
        let fullTitle = symbols.joined(separator: " ")
        return HotkeyBinding(
            kind: .keyCombination,
            keyCode: keyCode,
            modifierRawValue: rawModifiers.rawValue,
            displayTitle: fullTitle
        )
    }
    
    /// 键码转字符串符号
    public static func keycodeToString(keyCode: UInt16) -> String {
        switch keyCode {
        case 0: return "A"
        case 1: return "S"
        case 2: return "D"
        case 3: return "F"
        case 4: return "H"
        case 5: return "G"
        case 6: return "Z"
        case 7: return "X"
        case 8: return "C"
        case 9: return "V"
        case 11: return "B"
        case 12: return "Q"
        case 13: return "W"
        case 14: return "E"
        case 15: return "R"
        case 16: return "Y"
        case 17: return "T"
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 22: return "6"
        case 23: return "5"
        case 24: return "="
        case 25: return "9"
        case 26: return "7"
        case 27: return "-"
        case 28: return "8"
        case 29: return "0"
        case 30: return "]"
        case 31: return "O"
        case 32: return "U"
        case 33: return "["
        case 34: return "I"
        case 35: return "P"
        case 36: return "Return"
        case 37: return "L"
        case 38: return "J"
        case 39: return "'"
        case 40: return "K"
        case 41: return ";"
        case 42: return "\\"
        case 43: return ","
        case 44: return "/"
        case 45: return "N"
        case 46: return "M"
        case 47: return "."
        case 48: return "Tab"
        case 49: return "Space"
        case 50: return "`"
        case 51: return "Delete"
        case 53: return "Esc"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default: return "Key(\(keyCode))"
        }
    }
}
