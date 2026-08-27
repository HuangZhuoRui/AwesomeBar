import Foundation
import AppKit
import SwiftUI
import Combine

/// 粘贴板模式专属独立浮动小窗口控制器（生命周期、置顶层级、位置记忆与平滑动画管理）
public final class StickyNoteWindowController: NSObject, NSWindowDelegate {
    /// 全局共享单例
    public static let shared = StickyNoteWindowController()
    
    /// 粘贴板浮动 NSPanel 实例
    private var stickyPanel: CustomGlassPanel?
    /// Combine 响应式订阅集合
    private var cancellables = Set<AnyCancellable>()
    
    /// 粘贴板浮窗当前是否处于可见状态
    @Published public var isVisible: Bool = false
    
    private override init() {
        super.init()
        buildStickyPanel()
        bindSettingsObservers()
    }
    
    /// 构建并配置轻量无边框透明粘贴板 NSPanel
    private func buildStickyPanel() {
        let panel = CustomGlassPanel(
            contentRect: NSRect(x: 0, y: 0, width: 270, height: 390),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = AppSettings.shared.isStickyNotePinned ? .floating : .normal
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.delegate = self
        
        let hostingView = NSHostingView(rootView: StickyNoteView(onClose: { [weak self] in
            self?.hide()
        }))
        hostingView.wantsLayer = true
        hostingView.layer?.cornerRadius = 20
        hostingView.layer?.cornerCurve = .continuous
        hostingView.layer?.masksToBounds = false
        panel.contentView = hostingView
        
        self.stickyPanel = panel
    }
    
    /// 监听用户粘贴板置顶设置变更，实时同步窗口层级
    private func bindSettingsObservers() {
        AppSettings.shared.$isStickyNotePinned
            .sink { [weak self] isPinned in
                self?.stickyPanel?.level = isPinned ? .floating : .normal
            }
            .store(in: &cancellables)
    }
    
    /// 切换粘贴板窗口的显示与隐藏
    public func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }
    
    /// 灵动呼出粘贴板浮窗（优先恢复上次停靠位置或智能停靠在屏幕右上角）
    public func show() {
        guard let panel = stickyPanel else { return }
        
        // 强制刷新剪贴板数据
        ClipboardMonitor.shared.checkNow()
        
        // 1. 尝试恢复上次停留坐标
        var positionRestored = false
        if let savedX = AppSettings.shared.stickyNoteOriginX,
           let savedY = AppSettings.shared.stickyNoteOriginY {
            let savedPoint = NSPoint(x: savedX, y: savedY)
            let panelRect = NSRect(origin: savedPoint, size: panel.frame.size)
            
            let isVisibleOnScreen = NSScreen.screens.contains { screen in
                screen.frame.intersects(panelRect)
            }
            
            if isVisibleOnScreen {
                panel.setFrameOrigin(savedPoint)
                positionRestored = true
            }
        }
        
        // 2. 若无历史坐标，默认停靠在主屏幕右上角（优雅小便签/浮窗挂载位）
        if !positionRestored {
            let activeScreen = NSScreen.main ?? NSScreen.screens.first
            if let screen = activeScreen {
                let screenFrame = screen.visibleFrame
                let originX = screenFrame.maxX - panel.frame.width - 24.0
                let originY = screenFrame.maxY - panel.frame.height - 48.0
                panel.setFrameOrigin(NSPoint(x: originX, y: originY))
            }
        }
        
        panel.alphaValue = 0.0
        panel.invalidateShadow()
        panel.makeKeyAndOrderFront(nil)
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1.0
        }
        
        isVisible = true
    }
    
    /// 优雅缩放淡出隐藏粘贴板浮窗
    public func hide() {
        guard let panel = stickyPanel, isVisible else { return }
        
        saveStickyNotePosition()
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0.0
        }, completionHandler: {
            panel.orderOut(nil)
            self.isVisible = false
        })
    }
    
    /// 记录并保存粘贴板浮窗当前的坐标
    private func saveStickyNotePosition() {
        guard let panel = stickyPanel else { return }
        AppSettings.shared.stickyNoteOriginX = panel.frame.origin.x
        AppSettings.shared.stickyNoteOriginY = panel.frame.origin.y
    }
    
    // MARK: - NSWindowDelegate 委托
    
    public func windowDidMove(_ notification: Notification) {
        saveStickyNotePosition()
    }
}
