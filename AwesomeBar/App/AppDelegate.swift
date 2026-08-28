import Foundation
import AppKit

/// 应用程序生命周期与系统服务代理类
public final class AppDelegate: NSObject, NSApplicationDelegate {
    /// 应用启动完成回调
    public func applicationDidFinishLaunching(_ notification: Notification) {
        // 配置为 Accessory 模式（常驻顶部菜单栏与浮动面板，不占用 Dock 栏图标）
        NSApp.setActivationPolicy(.accessory)
        
        // 显式加载并配置应用主图标（用于关于面板、系统通知与窗口标识）
        if let appIcon = NSImage(named: "AppIcon") {
            NSApplication.shared.applicationIconImage = appIcon
        }
        
        // 初始化核心后台服务
        MenuBarManager.shared.setup()
        ClipboardMonitor.shared.startMonitoring()
        GlobalHotkeyManager.shared.start()
        
        // 实时追踪外部前台活动应用（当用户在 QQ、Chrome、微信等输入时持续记录最新目标）
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { notification in
            if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
               app.bundleIdentifier != Bundle.main.bundleIdentifier {
                PasteSimulator.shared.lastActiveExternalApp = app
            }
        }
        
        // 首次启动时轻度延迟自动展示浮动面板，便于用户直观体验
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            FloatingPanelController.shared.show()
        }
        
        // 启动后静默检查更新
        if AppSettings.shared.automaticallyCheckForUpdates {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                AppUpdaterService.shared.checkForUpdates(isUserInitiated: false)
            }
        }
    }
    
    /// 应用即将退出回调
    public func applicationWillTerminate(_ notification: Notification) {
        ClipboardMonitor.shared.stopMonitoring()
        GlobalHotkeyManager.shared.stop()
    }
}
