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
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
    
    /// 跳转打开系统「隐私与安全性 -> 辅助功能」设置面板
    public static func openAccessibilityPreferences() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
