import Foundation
import AppKit
import SwiftUI
import Combine

/// 粘贴板模式专属独立浮动小窗口控制器（生命周期、物理运动学加速度边缘甩动吸附、动态无溢出物理外框收缩、拖拽解除吸附、复制冒出不抢焦点、置顶层级、⌘1-9 快捷键分发与平滑动画管理）
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
    
    /// 浮窗展开全量尺寸常量
    public let panelWidth: CGFloat = 270.0
    public let panelHeight: CGFloat = 390.0
    /// 吸附边缘时露出的边角手柄宽度（严格适配真实物理窗口外框，杜绝屏幕外溢出大白块）
    public let peekWidth: CGFloat = 28.0
    
    /// 粘贴板浮窗当前是否处于可见状态
    @Published public var isVisible: Bool = false
    /// 当前屏幕边缘吸附状态
    @Published public var dockState: DockState = .floating
    /// 是否正处于吸附只露小角收缩形态（false 表示已滑出展开显示完整剪贴板列表内容）
    @Published public var isPeekingCollapsed: Bool = false
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
            self.isPeekingCollapsed = (savedDock != .floating)
        }
        buildStickyPanel()
        bindSettingsObservers()
        bindClipboardCaptureObserver()
    }
    
    /// 构建并配置轻量无边框透明粘贴板 NSPanel
    private func buildStickyPanel() {
        let initialWidth = isPeekingCollapsed ? peekWidth : panelWidth
        let panel = CustomGlassPanel(
            contentRect: NSRect(x: 0, y: 0, width: initialWidth, height: panelHeight),
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
        
        // 1. 配置窗口级别前置键盘拦截器（支持 ⌘1-9 与 Esc）
        panel.onKeyDownInterceptor = { [weak self] event in
            guard let self = self else { return false }
            return self.handleKeyDownEvent(event)
        }
        
        // 2. 配置拖拽开始监听：一旦被拖拽，立即解除吸附状态，平滑恢复为完整尺寸浮窗跟随鼠标
        panel.onDragStarted = { [weak self] p in
            guard let self = self else { return }
            self.autoCollapseWorkItem?.cancel()
            let wasDocked = (self.dockState != .floating)
            let oldDock = self.dockState
            self.dockState = .floating
            self.isPeekingCollapsed = false
            self.isDockedExpanded = false
            AppSettings.shared.stickyNoteDockState = DockState.floating.rawValue
            
            if wasDocked {
                guard let screen = p.screen ?? NSScreen.main ?? NSScreen.screens.first else { return }
                let screenFrame = screen.visibleFrame
                var newX = p.frame.origin.x
                if oldDock == .dockedRight {
                    newX = screenFrame.maxX - self.panelWidth
                } else if oldDock == .dockedLeft {
                    newX = screenFrame.minX
                }
                p.setFrame(NSRect(x: newX, y: p.frame.minY, width: self.panelWidth, height: self.panelHeight), display: true)
            }
        }
        
        // 3. 配置带物理运动学参数的拖拽释放监听（严格按加速度与速度判定甩动吸附）
        panel.onDragEndedWithPhysics = { [weak self] customPanel, info in
            self?.handlePhysicsDragFinished(customPanel, info: info)
        }
        
        let hostingView = NSHostingView(rootView: StickyNoteView(
            controller: self,
            onClose: { [weak self] in
                self?.hide()
            }
        ))
        
        panel.contentView = hostingView
        self.stickyPanel = panel
    }
    
    // MARK: - 响应式配置与剪贴板监听
    
    private func bindSettingsObservers() {
        AppSettings.shared.$isStickyNotePinned
            .sink { [weak self] isPinned in
                self?.stickyPanel?.level = isPinned ? .floating : .normal
            }
            .store(in: &cancellables)
    }
    
    private func bindClipboardCaptureObserver() {
        NotificationCenter.default.publisher(for: .clipboardItemDidCapture)
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.handleExternalItemCaptured()
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - 物理运动学加速度边缘甩动吸附算法
    
    /// 拖拽结束时根据运动物理加速度、速度与边缘距离严格判定
    private func handlePhysicsDragFinished(_ panel: CustomGlassPanel, info: DragPhysicsReleaseInfo) {
        let frame = panel.frame
        guard let screen = panel.screen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let screenFrame = screen.visibleFrame
        
        let distToLeft = frame.minX - screenFrame.minX
        let distToRight = screenFrame.maxX - frame.maxX
        
        // 核心物理判定指标：
        // 绝不因慢速移动或靠近边缘而吸附，必须满足物理运动的加速度与冲量速度！
        // 1. 向右甩动吸附要求：靠近右边缘 (<= 140px) 且 拥有强劲的向右物理速度 (> 380 px/s) 或加速度 (> 550 px/s²)
        let isFlingingRight = (distToRight < 140) && (info.velocityX > 380 || info.accelerationX > 550)
        
        // 2. 向左甩动吸附要求：靠近左边缘 (<= 140px) 且 拥有强劲的向左物理速度 (< -380 px/s) 或加速度 (< -550 px/s²)
        let isFlingingLeft = (distToLeft < 140) && (info.velocityX < -380 || info.accelerationX < -550)
        
        if isFlingingRight {
            dockTo(side: .dockedRight, screen: screen, currentY: frame.minY)
        } else if isFlingingLeft {
            dockTo(side: .dockedLeft, screen: screen, currentY: frame.minY)
        } else {
            // 未达到物理加速度阈值或常规慢速拖拽：保持自由悬浮，绝不误吸附！
            self.dockState = .floating
            self.isPeekingCollapsed = false
            self.isDockedExpanded = false
            AppSettings.shared.stickyNoteDockState = DockState.floating.rawValue
            saveStickyNotePosition()
        }
    }
    
    /// 执行吸附平滑动画（动态将物理窗口收缩为仅 peekWidth 宽，且 100% 贴附在屏幕可见区域内，彻底杜绝切桌面时露后方大白块）
    public func dockTo(side: DockState, screen: NSScreen, currentY: CGFloat) {
        guard let panel = stickyPanel else { return }
        let screenFrame = screen.visibleFrame
        
        self.dockState = side
        self.isPeekingCollapsed = true
        self.isDockedExpanded = false
        AppSettings.shared.stickyNoteDockState = side.rawValue
        
        let clampedY = min(max(currentY, screenFrame.minY + 20), screenFrame.maxY - panelHeight - 20)
        let targetX: CGFloat
        if side == .dockedRight {
            targetX = screenFrame.maxX - peekWidth
        } else {
            targetX = screenFrame.minX
        }
        
        let targetFrame = NSRect(x: targetX, y: clampedY, width: peekWidth, height: panelHeight)
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(targetFrame, display: true)
        }
        
        saveStickyNotePosition()
    }
    
    // MARK: - 外部复制触发：冒出显示内容且不抢占焦点
    
    /// 外部应用触发了复制事件时的处理
    public func handleExternalItemCaptured() {
        guard isVisible else { return }
        
        if dockState == .dockedLeft || dockState == .dockedRight {
            popOutTemporarily(duration: 3.5)
        }
    }
    
    /// 从吸附边缘临时平滑展开冒出，展示完整内容，几秒后若无交互自动缩回
    public func popOutTemporarily(duration: Double = 3.5) {
        guard let panel = stickyPanel else { return }
        guard let screen = panel.screen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let screenFrame = screen.visibleFrame
        
        autoCollapseWorkItem?.cancel()
        
        // 关键状态切换：解除收缩状态，让完整剪贴板列表内容 100% 显式呈现！
        self.isPeekingCollapsed = false
        
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
    
    /// 平滑收回吸附边缘状态（精准缩减窗口物理 frame 至屏幕边界内，0 像素屏幕外溢出）
    public func collapseToDock() {
        guard let panel = stickyPanel else { return }
        guard let screen = panel.screen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let screenFrame = screen.visibleFrame
        
        autoCollapseWorkItem?.cancel()
        self.isPeekingCollapsed = true
        self.isDockedExpanded = false
        
        let targetX: CGFloat
        if dockState == .dockedRight {
            targetX = screenFrame.maxX - peekWidth
        } else {
            targetX = screenFrame.minX
        }
        
        let targetFrame = NSRect(x: targetX, y: panel.frame.minY, width: peekWidth, height: panelHeight)
        
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
        self.isPeekingCollapsed = false
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
            if isDockedExpanded || !isPeekingCollapsed {
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
            self.isPeekingCollapsed = false
            self.isDockedExpanded = false
            
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
            panel.setFrame(NSRect(origin: panel.frame.origin, size: NSSize(width: panelWidth, height: panelHeight)), display: true)
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
        
        // 2. 动态数字直选快捷键（支持 ⇧⌘1-9、⌘1-9、⌥1-9 等自定义修饰键）
        let modifier = AppSettings.shared.quickSelectModifier
        if modifier != .none,
           modifier.matches(flags: event.modifierFlags),
           let characters = event.charactersIgnoringModifiers,
           let number = Int(characters),
           (1...9).contains(number) {
            return self.triggerShortcut(index: number)
        }
        
        return false
    }
    
    /// 触发指定序号的快捷复制（优先根据视口分配，回退取全局列表）
    public func triggerShortcut(index: Int) -> Bool {
        if let targetItem = currentVisibleShortcutMap[index] {
            triggerItemCopy(item: targetItem)
            return true
        }
        
        let allItems = ClipboardStore.shared.allItems
        let targetIndex = index - 1
        if targetIndex >= 0 && targetIndex < allItems.count {
            triggerItemCopy(item: allItems[targetIndex])
            return true
        }
        
        return false
    }
    
    /// 最近一次触发复制的时间戳（用于连击防抖）
    private var lastCopyTriggerTimestamp: Date = Date.distantPast
    
    /// 执行条目复制与反馈（内置防抖机制与自动粘贴联动）
    public func triggerItemCopy(item: ClipboardItem) {
        let now = Date()
        guard now.timeIntervalSince(lastCopyTriggerTimestamp) > 0.3 else { return }
        lastCopyTriggerTimestamp = now
        
        self.lastCopiedItemId = item.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            if self?.lastCopiedItemId == item.id {
                self?.lastCopiedItemId = nil
            }
        }
        
        if AppSettings.shared.autoPasteOnSelect {
            PasteSimulator.shared.pasteItem(item: item)
        } else {
            PasteSimulator.shared.copyToClipboard(item: item)
        }
    }
    
    // MARK: - NSWindowDelegate 委托
    
    public func windowDidMove(_ notification: Notification) {
        if dockState == .floating {
            saveStickyNotePosition()
        }
    }
}
