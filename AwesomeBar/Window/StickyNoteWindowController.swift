import Foundation
import AppKit
import SwiftUI
import Combine

/// 粘贴板模式专属独立浮动小窗口控制器（生命周期、置顶层级、位置记忆、⌘1-9 快捷键分发与平滑动画管理）
public final class StickyNoteWindowController: NSObject, ObservableObject, NSWindowDelegate {
    /// 全局共享单例
    public static let shared = StickyNoteWindowController()
    
    /// 粘贴板浮动 NSPanel 实例
    private var stickyPanel: CustomGlassPanel?
    /// Combine 响应式订阅集合
    private var cancellables = Set<AnyCancellable>()
    /// 本地键盘事件监听器
    private var localKeyDownMonitor: Any?
    
    /// 粘贴板浮窗当前是否处于可见状态
    @Published public var isVisible: Bool = false
    /// 当前视口内 > 2/3 可见的条目与 ⌘1-9 快捷键序号映射表
    @Published public var currentVisibleShortcutMap: [Int: ClipboardItem] = [:]
    /// 最近一次被复制的条目 ID（用于驱动列表行触发「已复制」高亮动效）
    @Published public var lastCopiedItemId: UUID? = nil
    
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
        
        // 配置窗口级别前置键盘拦截器（支持 ⌘1-9 与 Esc）
        panel.onKeyDownInterceptor = { [weak self] event in
            guard let self = self else { return false }
            return self.handleKeyDownEvent(event)
        }
        
        let hostingView = NSHostingView(rootView: StickyNoteView(
            controller: self,
            onClose: { [weak self] in
                self?.hide()
            }
        ))
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
        
        panel.alphaValue = 1.0
        panel.invalidateShadow()
        panel.makeKeyAndOrderFront(nil)
        
        isVisible = true
        startLocalKeyMonitor()
    }
    
    /// 优雅缩放淡出隐藏粘贴板浮窗
    public func hide() {
        guard let panel = stickyPanel, isVisible else { return }
        
        stopLocalKeyMonitor()
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
    
    // MARK: - 快捷键事件处理与分发
    
    /// 启动本地键盘快捷键监听
    private func startLocalKeyMonitor() {
        stopLocalKeyMonitor()
        
        localKeyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.isVisible else { return event }
            if self.handleKeyDownEvent(event) {
                return nil // 已消费事件，阻断后续派发
            }
            return event
        }
    }
    
    /// 停止本地键盘快捷键监听
    private func stopLocalKeyMonitor() {
        if let monitor = localKeyDownMonitor {
            NSEvent.removeMonitor(monitor)
            localKeyDownMonitor = nil
        }
    }
    
    /// 统一按键事件判断与处理
    private func handleKeyDownEvent(_ event: NSEvent) -> Bool {
        // 1. Esc 快捷关闭
        if event.keyCode == 53 {
            self.hide()
            return true
        }
        
        // 2. Command + 1..9 快捷复制当前视口动态编号项
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command),
           let characters = event.charactersIgnoringModifiers,
           let number = Int(characters),
           (1...9).contains(number) {
            return self.triggerShortcut(index: number)
        }
        
        return false
    }
    
    /// 触发指定序号的快捷复制
    public func triggerShortcut(index: Int) -> Bool {
        guard let targetItem = currentVisibleShortcutMap[index] else { return false }
        triggerItemCopy(item: targetItem)
        return true
    }
    
    /// 执行条目复制与反馈
    public func triggerItemCopy(item: ClipboardItem) {
        PasteSimulator.shared.copyToClipboard(item: item)
        
        self.lastCopiedItemId = item.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            if self?.lastCopiedItemId == item.id {
                self?.lastCopiedItemId = nil
            }
        }
    }
    
    // MARK: - NSWindowDelegate 委托
    
    public func windowDidMove(_ notification: Notification) {
        saveStickyNotePosition()
    }
}
