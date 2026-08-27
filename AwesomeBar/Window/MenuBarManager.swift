import Foundation
import AppKit
import SwiftUI

/// macOS 顶部状态栏（Menu Bar）图标与系统菜单管理器
public final class MenuBarManager: NSObject {
    /// 全局共享单例
    public static let shared = MenuBarManager()
    
    /// 系统菜单栏项
    private var statusItem: NSStatusItem?
    /// 偏好设置独立窗口控制器
    private var settingsWindowController: NSWindowController?
    
    /// 私有初始化方法
    private override init() {
        super.init()
    }
    
    /// 初始化并配置顶部菜单栏图标与点击事件
    public func setup() {
        guard statusItem == nil else { return }
        
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let statusBarButton = statusItem?.button {
            let symbolConfig = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            if let iconImage = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "AwesomeBar")?.withSymbolConfiguration(symbolConfig) {
                iconImage.isTemplate = true
                statusBarButton.image = iconImage
            }
            statusBarButton.action = #selector(statusBarButtonClicked(_:))
            statusBarButton.target = self
            statusBarButton.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }
    
    /// 状态栏图标被点击响应
    @objc private func statusBarButtonClicked(_ sender: NSStatusBarButton) {
        guard let currentEvent = NSApp.currentEvent else { return }
        
        if currentEvent.type == .rightMouseUp || currentEvent.modifierFlags.contains(.control) {
            displayContextMenu(sender: sender)
        } else {
            FloatingPanelController.shared.toggle()
        }
    }
    
    /// 弹出上下文快捷功能菜单
    private func displayContextMenu(sender: NSStatusBarButton) {
        let contextMenu = NSMenu()
        
        let toggleMenuItem = NSMenuItem(title: "切换 AwesomeBar (左 ⌥)", action: #selector(toggleApplication), keyEquivalent: "")
        toggleMenuItem.target = self
        contextMenu.addItem(toggleMenuItem)
        
        contextMenu.addItem(NSMenuItem.separator())
        
        let pinMenuItem = NSMenuItem(title: "保持最上层 (置顶)", action: #selector(togglePinState), keyEquivalent: "")
        pinMenuItem.target = self
        pinMenuItem.state = AppSettings.shared.isPinnedToTop ? .on : .off
        contextMenu.addItem(pinMenuItem)
        
        let clearHistoryMenuItem = NSMenuItem(title: "清空剪贴板历史", action: #selector(clearClipboardHistory), keyEquivalent: "")
        clearHistoryMenuItem.target = self
        contextMenu.addItem(clearHistoryMenuItem)
        
        contextMenu.addItem(NSMenuItem.separator())
        
        let openSettingsMenuItem = NSMenuItem(title: "偏好设置...", action: #selector(openSettingsWindow), keyEquivalent: ",")
        openSettingsMenuItem.target = self
        contextMenu.addItem(openSettingsMenuItem)
        
        contextMenu.addItem(NSMenuItem.separator())
        
        let quitMenuItem = NSMenuItem(title: "退出 AwesomeBar", action: #selector(quitApplication), keyEquivalent: "q")
        quitMenuItem.target = self
        contextMenu.addItem(quitMenuItem)
        
        statusItem?.menu = contextMenu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }
    
    @objc private func toggleApplication() {
        FloatingPanelController.shared.toggle()
    }
    
    @objc private func togglePinState() {
        AppSettings.shared.isPinnedToTop.toggle()
        SoundManager.shared.playPinSound()
    }
    
    @objc private func clearClipboardHistory() {
        ClipboardStore.shared.clearAll(exceptPinned: true)
        SoundManager.shared.playDeleteSound()
    }
    
    /// 打开独立的偏好设置窗口
    @objc public func openSettingsWindow() {
        if settingsWindowController == nil {
            let settingsWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 380),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            settingsWindow.title = "AwesomeBar 偏好设置"
            settingsWindow.center()
            settingsWindow.isReleasedWhenClosed = false
            settingsWindow.contentView = NSHostingView(rootView: SettingsView())
            settingsWindowController = NSWindowController(window: settingsWindow)
        }
        
        settingsWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc private func quitApplication() {
        NSApplication.shared.terminate(nil)
    }
}
