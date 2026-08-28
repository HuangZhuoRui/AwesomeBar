import Foundation
import AppKit
import SwiftUI
import Combine

/// 液态玻璃浮动面板控制器（窗口生命周期、置顶层级控制、位置记忆与动画管理）
public final class FloatingPanelController: NSObject, NSWindowDelegate {
    /// 全局共享单例
    public static let shared = FloatingPanelController()
    
    /// 自定义 NSPanel 浮动窗口实例
    private var floatingPanel: CustomGlassPanel?
    /// 记录面板呼出前处于前台焦点的应用程序
    public private(set) var previousFrontmostApplication: NSRunningApplication?
    /// 外部点击事件全局监听器
    private var outsideClickEventMonitor: Any?
    /// Combine 响应式订阅集合
    private var cancellables = Set<AnyCancellable>()
    
    /// 窗口当前是否处于可见显示状态
    @Published public var isVisible: Bool = false
    
    /// 私有初始化方法
    private override init() {
        super.init()
        buildFloatingPanel()
        bindSettingsObservers()
    }
    
    /// 构建并配置透明无边框 NSPanel
    private func buildFloatingPanel() {
        let panel = CustomGlassPanel(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 490),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = AppSettings.shared.isPinnedToTop ? .floating : .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.delegate = self
        
        let hostingView = NSHostingView(rootView: MainView())
        hostingView.wantsLayer = true
        hostingView.layer?.cornerRadius = 24
        hostingView.layer?.cornerCurve = .continuous
        hostingView.layer?.masksToBounds = false
        panel.contentView = hostingView
        
        self.floatingPanel = panel
    }
    
    /// 监听用户置顶设置变更，实时同步 NSWindow 层级
    private func bindSettingsObservers() {
        AppSettings.shared.$isPinnedToTop
            .sink { [weak self] isPinned in
                self?.floatingPanel?.level = isPinned ? .floating : .statusBar
            }
            .store(in: &cancellables)
    }
    
    /// 设置浮动面板全局按键拦截器
    public func setKeyDownInterceptor(_ interceptor: ((NSEvent) -> Bool)?) {
        self.floatingPanel?.onKeyDownInterceptor = interceptor
    }
    
    /// 切换窗口的显示与隐藏状态
    public func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }
    
    /// 灵动呼出浮动窗口（支持记住上次拖拽位置或智能居中）
    public func show() {
        guard let panel = floatingPanel else { return }
        
        // 记录呼出前的前台活动应用，以便后续精准粘贴
        if let currentApp = NSWorkspace.shared.frontmostApplication,
           currentApp.bundleIdentifier != Bundle.main.bundleIdentifier {
            self.previousFrontmostApplication = currentApp
        }
        
        // 立即强制检查并同步系统剪贴板最新数据（实现 0 毫秒即时刷新）
        ClipboardMonitor.shared.checkNow()
        
        // 1. 若开启了「记住上次位置」且坐标处于有效显示器内，精准恢复上次坐标
        var positionRestored = false
        if AppSettings.shared.rememberLastPosition,
           let savedX = AppSettings.shared.lastWindowOriginX,
           let savedY = AppSettings.shared.lastWindowOriginY {
            let savedPoint = NSPoint(x: savedX, y: savedY)
            let panelRect = NSRect(origin: savedPoint, size: panel.frame.size)
            
            // 校验上次位置是否仍然位于某个连接的屏幕可视范围内
            let isVisibleOnScreen = NSScreen.screens.contains { screen in
                screen.frame.intersects(panelRect)
            }
            
            if isVisibleOnScreen {
                panel.setFrameOrigin(savedPoint)
                positionRestored = true
            }
        }
        
        // 2. 若未开启位置记忆或坐标失效，智能居中在当前鼠标所在屏幕
        if !positionRestored {
            let targetScreen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main
            if let activeScreen = targetScreen {
                let screenVisibleFrame = activeScreen.visibleFrame
                let originX = screenVisibleFrame.midX - panel.frame.width / 2.0
                let originY = screenVisibleFrame.midY - panel.frame.height / 2.0 + 40.0
                panel.setFrameOrigin(NSPoint(x: originX, y: originY))
            }
        }
        
        panel.alphaValue = 1.0
        panel.invalidateShadow()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        isVisible = true
        startOutsideClickMonitor()
        
        // 广播窗口呈现事件，驱动列表流光入场动画
        NotificationCenter.default.post(name: .awesomeBarWindowDidAppear, object: nil)
    }
    
    /// 隐藏浮动窗口（支持动画淡出或快速即刻隐藏以立即让出前台焦点）
    public func hide(animated: Bool = true) {
        guard let panel = floatingPanel, isVisible else { return }
        
        // 关闭前保存当前最新位置
        saveCurrentWindowPosition()
        stopOutsideClickMonitor()
        
        if animated {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.12
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                panel.animator().alphaValue = 0.0
            }, completionHandler: {
                panel.orderOut(nil)
                self.isVisible = false
            })
        } else {
            panel.alphaValue = 0.0
            panel.orderOut(nil)
            self.isVisible = false
        }
    }
    
    /// 记录并保存当前窗口的实际坐标
    private func saveCurrentWindowPosition() {
        guard let panel = floatingPanel else { return }
        if AppSettings.shared.rememberLastPosition {
            AppSettings.shared.lastWindowOriginX = panel.frame.origin.x
            AppSettings.shared.lastWindowOriginY = panel.frame.origin.y
        }
    }
    
    /// 启动外部鼠标点击监听（用于非置顶状态下点击外部自动隐藏）
    private func startOutsideClickMonitor() {
        stopOutsideClickMonitor()
        
        outsideClickEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self, let panel = self.floatingPanel else { return }
            
            // 若开启了置顶，则不自动收起
            if AppSettings.shared.isPinnedToTop { return }
            
            let mouseLocation = NSEvent.mouseLocation
            if !NSPointInRect(mouseLocation, panel.frame) {
                self.hide()
            }
        }
    }
    
    /// 停止外部鼠标点击监听
    private func stopOutsideClickMonitor() {
        if let monitor = outsideClickEventMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickEventMonitor = nil
        }
    }
    
    // MARK: - NSWindowDelegate 委托
    
    public func windowDidMove(_ notification: Notification) {
        // 用户拖动面板停止时，实时保存新位置
        saveCurrentWindowPosition()
    }
    
    public func windowDidResignKey(_ notification: Notification) {
        // 仅依靠全局外部鼠标点击事件判定收起，避免应用内弹出 Sheet、菜单或辅助窗口时意外收起浮动面板
    }
}

// MARK: - 系统通知常量扩展
extension Notification.Name {
    /// AwesomeBar 浮动窗口被呼出并呈现的系统通知（用于驱动列表灵动流光入场动画）
    public static let awesomeBarWindowDidAppear = Notification.Name("awesomeBarWindowDidAppear")
}
