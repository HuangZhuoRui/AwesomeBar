import Foundation
import AppKit

/// macOS 辅助功能（Accessibility）权限管理与状态检测工具
public enum AccessibilityManager {
    /// 本次启动是否已经弹出过一次系统授权对话框（避免每次点击粘贴都重复弹窗打扰用户）
    private static var hasPromptedThisLaunch = false

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

    /// 每次应用启动后，最多只主动弹出一次系统授权对话框；
    /// 用户关闭对话框后若仍未授权，后续操作不再重复打断，只静默回退（复制到剪贴板但不自动粘贴），
    /// 需要开启权限时可随时在「设置」里手动前往系统偏好设置授权。
    public static func requestAccessibilityPermissionOnce() {
        guard !isAccessibilityTrusted, !hasPromptedThisLaunch else { return }
        hasPromptedThisLaunch = true
        requestAccessibilityPermission()
    }
    
    /// 跳转打开系统「隐私与安全性 -> 辅助功能」设置面板
    public static func openAccessibilityPreferences() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
