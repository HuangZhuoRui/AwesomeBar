import Foundation
import AppKit
import Carbon

/// 剪贴板写回与模拟系统自动粘贴服务（内置高频连击防抖防重复粘贴机制、窗口即刻让焦与互斥锁）
public final class PasteSimulator {
    /// 全局共享单例
    public static let shared = PasteSimulator()
    
    /// 记录最近一次触发粘贴的时间戳（用于防抖防重复粘贴）
    private var lastPasteTimestamp: Date = Date.distantPast
    /// 当前排队执行的异步粘贴任务
    private var currentPasteWorkItem: DispatchWorkItem?
    /// 是否正有粘贴工作正在前台派发中（互斥锁）
    private var isPastingInProgress: Bool = false
    
    /// 私有初始化方法
    private init() {}
    
    /// 将目标条目数据写回系统通用剪贴板 NSPasteboard
    /// - Parameter item: 待写回的剪贴板条目
    public func copyToClipboard(item: ClipboardItem) {
        let generalPasteboard = NSPasteboard.general
        generalPasteboard.clearContents()
        
        switch item.type {
        case .image:
            if let imageFileName = item.imagePath,
               let nsImage = ImageStorageManager.shared.loadImage(filename: imageFileName) {
                generalPasteboard.writeObjects([nsImage])
            } else {
                generalPasteboard.setString(item.contentText, forType: .string)
            }
        case .file:
            if let filePaths = item.filePaths {
                let nsUrls = filePaths.map { URL(fileURLWithPath: $0) as NSURL }
                generalPasteboard.writeObjects(nsUrls)
            } else {
                generalPasteboard.setString(item.contentText, forType: .string)
            }
        case .richText:
            if let html = item.htmlContent {
                generalPasteboard.setString(html, forType: .html)
            }
            generalPasteboard.setString(item.contentText, forType: .string)
        case .text, .code, .color, .url:
            generalPasteboard.setString(item.contentText, forType: .string)
        }
        
        // 告知监控服务同步当前变更计数值，避免自身写回被当作新复制捕获
        ClipboardMonitor.shared.markCurrentChangeAsInternal()
        
        SoundManager.shared.playCopySound()
    }
    
    /// 复制条目并自动唤醒前台应用模拟按下 Cmd+V（带防抖防重机制，短时间多次点击仅粘贴一次）
    /// - Parameters:
    ///   - item: 待粘贴的剪贴板条目
    ///   - targetApplication: 目标应用（若为 nil 则自动使用之前记录的前台应用）
    public func pasteItem(item: ClipboardItem, targetApplication: NSRunningApplication? = nil) {
        let now = Date()
        
        // 核心防重判定：如果在 0.3 秒内重复连点，或当前已有粘贴流程在进行中，阻断多余的重复注入
        if now.timeIntervalSince(lastPasteTimestamp) < 0.3 || isPastingInProgress {
            // 依然同步最新剪贴板内容，但绝不发送重复的 ⌘V 模拟按键
            copyToClipboard(item: item)
            return
        }
        
        lastPasteTimestamp = now
        isPastingInProgress = true
        
        // 1. 写回系统剪贴板
        copyToClipboard(item: item)
        
        guard AppSettings.shared.autoPasteOnSelect else {
            isPastingInProgress = false
            return
        }
        
        // 2. 如果未开启置顶，立即隐藏主浮动面板以迅速将输入焦点让出给目标应用
        if !AppSettings.shared.isPinnedToTop {
            FloatingPanelController.shared.hide(animated: false)
        }
        
        // 取消前序尚未完成的任务
        currentPasteWorkItem?.cancel()
        
        // 智能定位目标前台应用
        let targetApp = targetApplication
            ?? FloatingPanelController.shared.previousFrontmostApplication
            ?? NSWorkspace.shared.frontmostApplication
        
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            
            // 激活前台应用
            if let application = targetApp, application.bundleIdentifier != Bundle.main.bundleIdentifier {
                application.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
            }
            
            // 给予系统 100ms 调度窗口，确保目标应用已完全获得焦点与文本光标第一响应者
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) { [weak self] in
                guard let self = self else { return }
                self.simulatePasteKeystroke()
                SoundManager.shared.playPasteSound()
                
                // 粘贴完成微延迟后释放互斥锁
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) { [weak self] in
                    self?.isPastingInProgress = false
                }
            }
        }
        
        self.currentPasteWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: workItem)
    }
    
    /// 发送虚拟 Command + V 组合键
    private func simulatePasteKeystroke() {
        let eventSource = CGEventSource(stateID: .combinedSessionState)
        let vKeyCode: CGKeyCode = 9 // macOS 键盘 'v' 键虚拟键码为 9
        
        guard let keyDownEvent = CGEvent(keyboardEventSource: eventSource, virtualKey: vKeyCode, keyDown: true),
              let keyUpEvent = CGEvent(keyboardEventSource: eventSource, virtualKey: vKeyCode, keyDown: false) else {
            return
        }
        
        keyDownEvent.flags = .maskCommand
        keyUpEvent.flags = .maskCommand
        
        // 同时向 session 与 hid 事件总线广播，确保在各种终端/Electron/原生 App 中均能 100% 收到 ⌘V
        keyDownEvent.post(tap: .cgSessionEventTap)
        keyUpEvent.post(tap: .cgSessionEventTap)
        keyDownEvent.post(tap: .cghidEventTap)
        keyUpEvent.post(tap: .cghidEventTap)
    }
}
