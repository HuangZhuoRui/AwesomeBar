import Foundation
import AppKit

/// macOS 辅助功能（Accessibility）权限管理与状态检测工具
public enum AccessibilityManager {
    /// 当前是否已获得辅助功能授权
    public static var isAccessibilityTrusted: Bool {
        return AXIsProcessTrusted()
    }
    
    /// 主动触发系统授权弹窗（若未授权将弹出「AwesomeBar 想要控制此电脑」系统对话框）
    @discardableResult
    public static func requestAccessibilityPermission() -> Bool {
        // 直接使用常量字符串而非 kAXTrustedCheckOptionPrompt：后者是 C 全局可变量，
        // 在 Swift 6 严格并发检查下不被视为并发安全，其取值本身是稳定的公开约定。
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
    
    /// 跳转打开系统「隐私与安全性 -> 辅助功能」设置面板
    public static func openAccessibilityPreferences() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
