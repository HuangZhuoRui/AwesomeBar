import Foundation
import AppKit
import Carbon

/// 剪贴板写回与模拟系统自动粘贴服务
public final class PasteSimulator {
    /// 全局共享单例
    public static let shared = PasteSimulator()
    
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
    
    /// 复制条目并自动唤醒前台应用模拟按下 Cmd+V
    /// - Parameters:
    ///   - item: 待粘贴的剪贴板条目
    ///   - targetApplication: 目标应用（若为 nil 则自动使用之前记录的前台应用）
    public func pasteItem(item: ClipboardItem, targetApplication: NSRunningApplication? = nil) {
        copyToClipboard(item: item)
        
        guard AppSettings.shared.autoPasteOnSelect else { return }
        
        // 如果未开启置顶，则自动隐藏浮动面板
        if !AppSettings.shared.isPinnedToTop {
            FloatingPanelController.shared.hide()
        }
        
        // 延迟切回前台应用并发送 Cmd + V 虚拟按键
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if let application = targetApplication ?? FloatingPanelController.shared.previousFrontmostApplication {
                application.activate(options: .activateIgnoringOtherApps)
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.simulatePasteKeystroke()
                SoundManager.shared.playPasteSound()
            }
        }
    }
    
    /// 发送虚拟 Command + V 组合键
    private func simulatePasteKeystroke() {
        let eventSource = CGEventSource(stateID: .combinedSessionState)
        
        // macOS 键盘 'v' 键虚拟键码为 9
        let vKeyCode: CGKeyCode = 9
        
        let keyDownEvent = CGEvent(keyboardEventSource: eventSource, virtualKey: vKeyCode, keyDown: true)
        keyDownEvent?.flags = .maskCommand
        
        let keyUpEvent = CGEvent(keyboardEventSource: eventSource, virtualKey: vKeyCode, keyDown: false)
        keyUpEvent?.flags = .maskCommand
        
        keyDownEvent?.post(tap: .cghidEventTap)
        keyUpEvent?.post(tap: .cghidEventTap)
    }
}
