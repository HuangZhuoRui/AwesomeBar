import Foundation
import AppKit
import SwiftUI
import Combine

/// 粘贴板模式专属独立浮动小窗口控制器（生命周期、屏幕边缘甩动吸附、复制冒出不抢焦点、置顶层级、⌘1-9 快捷键分发与平滑动画管理）
public final class StickyNoteWindowController: NSObject, ObservableObject, NSWindowDelegate {
    /// 全局共享单例
    public static let shared = StickyNoteWindowController()
    
    /// 屏幕边缘吸附状态
    public enum DockState: String, Codable {
        /// 自由浮动状态
        case floating = "floating"
        /// 吸附在屏幕左边缘（仅露小角）
        case dockedLeft = "dockedLeft"
        /// 吸附在屏幕右边缘（仅露小角）
        case dockedRight = "dockedRight"
    }
    
    /// 粘贴板浮动 NSPanel 实例
    private var stickyPanel: CustomGlassPanel?
    /// Combine 响应式订阅集合
    private var cancellables = Set<AnyCancellable>()
    /// 本地键盘事件监听器
    private var localKeyDownMonitor: Any?
    /// 复制自动冒出后的自动收起工作项
    private var autoCollapseWorkItem: DispatchWorkItem?
    
    /// 浮窗尺寸常量
    public let panelWidth: CGFloat = 270.0
    public let panelHeight: CGFloat = 390.0
    /// 吸附边缘时露出的边角手柄宽度
    public let peekWidth: CGFloat = 24.0
    
    /// 粘贴板浮窗当前是否处于可见状态
    @Published public var isVisible: Bool = false
    /// 当前屏幕边缘吸附状态
    @Published public var dockState: DockState = .floating
    /// 在吸附状态下是否处于手动/快捷键完全展开状态
    @Published public var isDockedExpanded: Bool = false
    /// 当前视口内 > 2/3 可见的条目与 ⌘1-9 快捷键序号映射表
    @Published public var currentVisibleShortcutMap: [Int: ClipboardItem] = [:]
    /// 最近一次被复制的条目 ID（用于驱动列表行触发「已复制」高亮动效）
    @Published public var lastCopiedItemId: UUID? = nil
    
    private override init() {
        super.init()
        if let savedDock = DockState(rawValue: AppSettings.shared.stickyNoteDockState) {
            self.dockState = savedDock
        }
        buildStickyPanel()
        bindSettingsObservers()
        bindClipboardCaptureObserver()
    }
    
    /// 构建并配置轻量无边框透明粘贴板 NSPanel
    private func buildStickyPanel() {
        let panel = CustomGlassPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
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
        
        // 配置拖拽释放监听（甩到屏幕边缘自动吸附）
        panel.onDragFinished = { [weak self] customPanel in
            self?.handlePanelDragFinished(customPanel)
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
    
    /// 监听系统外部复制事件（当处于吸附状态时自动弹出冒泡，且不抢焦点）
    private func bindClipboardCaptureObserver() {
        NotificationCenter.default.publisher(for: .clipboardItemDidCapture)
            .sink { [weak self] _ in
                self?.handleExternalItemCaptured()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - 屏幕边缘甩动吸附算法
    
    /// 拖拽结束时根据最终位置与屏幕边缘距离决定是否吸附
    private func handlePanelDragFinished(_ panel: CustomGlassPanel) {
        let frame = panel.frame
        guard let screen = panel.screen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let screenFrame = screen.visibleFrame
        
        let distToLeft = frame.minX - screenFrame.minX
        let distToRight = screenFrame.maxX - frame.maxX
        
        // 判定阈值：拖拽或快速甩动至距离屏幕边缘 75px 内即刻吸附
        if distToRight < 75 {
            dockTo(side: .dockedRight, screen: screen, currentY: frame.minY)
        } else if distToLeft < 75 {
            dockTo(side: .dockedLeft, screen: screen, currentY: frame.minY)
        } else {
            // 自由停留在屏幕内部悬浮
            self.dockState = .floating
            self.isDockedExpanded = false
            AppSettings.shared.stickyNoteDockState = DockState.floating.rawValue
            saveStickyNotePosition()
        }
    }
    
    /// 执行吸附平滑动画
    public func dockTo(side: DockState, screen: NSScreen, currentY: CGFloat) {
        guard let panel = stickyPanel else { return }
        let screenFrame = screen.visibleFrame
        
        self.dockState = side
        self.isDockedExpanded = false
        AppSettings.shared.stickyNoteDockState = side.rawValue
        
        let clampedY = min(max(currentY, screenFrame.minY + 20), screenFrame.maxY - panelHeight - 20)
        let targetX: CGFloat
        if side == .dockedRight {
            targetX = screenFrame.maxX - peekWidth
        } else {
            targetX = screenFrame.minX - (panelWidth - peekWidth)
        }
        
        let targetFrame = NSRect(x: targetX, y: clampedY, width: panelWidth, height: panelHeight)
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(targetFrame, display: true)
        }
        
        saveStickyNotePosition()
    }
    
    // MARK: - 外部复制触发：冒出但不抢占焦点
    
    /// 外部应用触发了复制事件时的处理
    public func handleExternalItemCaptured() {
        guard let panel = stickyPanel, isVisible else { return }
        
        // 如果当前是吸附状态且未被用户手动展开，则平滑冒出并在 3.2 秒后自动缩回
        if dockState == .dockedLeft || dockState == .dockedRight {
            if !isDockedExpanded {
                popOutTemporarily(duration: 3.2)
            }
        }
    }
    
    /// 平滑冒出且绝对不抢占输入焦点（不调用 makeKey，不调用 NSApp.activate）
    public func popOutTemporarily(duration: Double = 3.2) {
        guard let panel = stickyPanel else { return }
        guard let screen = panel.screen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let screenFrame = screen.visibleFrame
        
        autoCollapseWorkItem?.cancel()
        
        let targetX: CGFloat
        if dockState == .dockedRight {
            targetX = screenFrame.maxX - panelWidth - 12.0
        } else {
            targetX = screenFrame.minX + 12.0
        }
        
        let targetFrame = NSRect(x: targetX, y: panel.frame.minY, width: panelWidth, height: panelHeight)
        
        // 仅仅通过 orderFront 呈现窗口，100% 保持其他第三方应用的选择状态与键盘焦点
        panel.orderFront(nil)
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.24
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(targetFrame, display: true)
        }
        
        // 自动缩回定时器
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self, self.dockState != .floating, !self.isDockedExpanded else { return }
            self.collapseToDock()
        }
        self.autoCollapseWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: workItem)
    }
    
    /// 平滑收回吸附边缘状态
    public func collapseToDock() {
        guard let panel = stickyPanel else { return }
        guard let screen = panel.screen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let screenFrame = screen.visibleFrame
        
        autoCollapseWorkItem?.cancel()
        self.isDockedExpanded = false
        
        let targetX: CGFloat
        if dockState == .dockedRight {
            targetX = screenFrame.maxX - peekWidth
        } else {
            targetX = screenFrame.minX - (panelWidth - peekWidth)
        }
        
        let targetFrame = NSRect(x: targetX, y: panel.frame.minY, width: panelWidth, height: panelHeight)
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(targetFrame, display: true)
        }
    }
    
    /// 手动/快捷键完全展开吸附浮窗
    public func expandFromDock() {
        guard let panel = stickyPanel else { return }
        guard let screen = panel.screen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let screenFrame = screen.visibleFrame
        
        autoCollapseWorkItem?.cancel()
        self.isDockedExpanded = true
        
        let targetX: CGFloat
        if dockState == .dockedRight {
            targetX = screenFrame.maxX - panelWidth - 12.0
        } else {
            targetX = screenFrame.minX + 12.0
        }
        
        let targetFrame = NSRect(x: targetX, y: panel.frame.minY, width: panelWidth, height: panelHeight)
        
        panel.makeKeyAndOrderFront(nil)
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(targetFrame, display: true)
        }
    }
    
    // MARK: - 全局唤起与切换
    
    /// 切换粘贴板窗口的显示、展开与收起状态
    public func toggle() {
        if !isVisible {
            show()
            return
        }
        
        // 核心交互：如果在吸附状态，按下唤起和收起快捷键在吸附与唤起完全展开状态流畅切换
        if dockState == .dockedLeft || dockState == .dockedRight {
            if isDockedExpanded {
                collapseToDock()
            } else {
                expandFromDock()
            }
        } else {
            hide()
        }
    }
    
    /// 灵动呼出粘贴板浮窗
    public func show() {
        guard let panel = stickyPanel else { return }
        
        ClipboardMonitor.shared.checkNow()
        
        if dockState == .dockedLeft || dockState == .dockedRight {
            expandFromDock()
        } else {
            // 自由浮动位置恢复
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
            
            if !positionRestored {
                let activeScreen = NSScreen.main ?? NSScreen.screens.first
                if let screen = activeScreen {
                    let screenFrame = screen.visibleFrame
                    let originX = screenFrame.maxX - panelWidth - 24.0
                    let originY = screenFrame.maxY - panelHeight - 48.0
                    panel.setFrameOrigin(NSPoint(x: originX, y: originY))
                }
            }
            
            panel.alphaValue = 1.0
            panel.invalidateShadow()
            panel.makeKeyAndOrderFront(nil)
        }
        
        isVisible = true
        startLocalKeyMonitor()
    }
    
    /// 优雅缩放淡出隐藏粘贴板浮窗
    public func hide() {
        guard let panel = stickyPanel, isVisible else { return }
        
        stopLocalKeyMonitor()
        autoCollapseWorkItem?.cancel()
        saveStickyNotePosition()
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0.0
        }, completionHandler: {
            panel.orderOut(nil)
            self.isVisible = false
            self.isDockedExpanded = false
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
                return nil
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
        // 1. Esc 快捷收起
        if event.keyCode == 53 {
            if dockState == .dockedLeft || dockState == .dockedRight {
                collapseToDock()
            } else {
                self.hide()
            }
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
        if dockState == .floating {
            saveStickyNotePosition()
        }
    }
}
