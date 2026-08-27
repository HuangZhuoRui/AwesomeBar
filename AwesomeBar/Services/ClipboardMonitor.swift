import Foundation
import AppKit
import Combine

/// 系统剪贴板内容后台监听服务（实时捕获并向单一响应式数据流管道推送）
public final class ClipboardMonitor {
    /// 全局共享单例
    public static let shared = ClipboardMonitor()
    
    /// 系统通用剪贴板引用
    private let systemPasteboard: NSPasteboard = .general
    /// 记录最近一次处理的剪贴板变更计数值
    private var lastChangeCount: Int = 0
    /// 高性能底层 GCD 轮询定时源
    private var backgroundTimerSource: DispatchSourceTimer?
    /// 专用独立后台监控队列
    private let monitoringQueue = DispatchQueue(label: "com.awesomebar.clipboard.monitor.queue", qos: .userInteractive)
    
    /// 私有初始化方法
    private init() {
        self.lastChangeCount = systemPasteboard.changeCount
    }
    
    /// 启动剪贴板轮询监听（50ms 高频无感检测，极速实时同步）
    public func startMonitoring() {
        stopMonitoring()
        self.lastChangeCount = systemPasteboard.changeCount
        
        let timer = DispatchSource.makeTimerSource(queue: monitoringQueue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(50), leeway: .milliseconds(10))
        timer.setEventHandler { [weak self] in
            self?.inspectPasteboardChanges()
        }
        timer.resume()
        self.backgroundTimerSource = timer
    }
    
    /// 停止剪贴板轮询监听
    public func stopMonitoring() {
        backgroundTimerSource?.cancel()
        backgroundTimerSource = nil
    }
    
    /// 立即强制异步检查剪贴板最新状态（用于窗口呼出瞬间无阻塞即时刷新）
    public func checkNow() {
        monitoringQueue.async { [weak self] in
            self?.inspectPasteboardChanges()
        }
    }
    
    /// 同步标记当前剪贴板状态为应用内主动操作，避免重复捕获
    public func markCurrentChangeAsInternal() {
        self.lastChangeCount = systemPasteboard.changeCount
    }
    
    /// 检查剪贴板是否有新变化
    private func inspectPasteboardChanges() {
        let currentChangeCount = systemPasteboard.changeCount
        guard currentChangeCount != lastChangeCount else { return }
        lastChangeCount = currentChangeCount
        
        processCurrentPasteboardData()
    }
    
    /// 解析并处理当前剪贴板中的最新内容（按 文件 -> 文本/链接/代码/颜色 -> 纯图片 优先层级解析）
    private func processCurrentPasteboardData() {
        var applicationName: String?
        var bundleIdentifier: String?
        
        // 获取当前前台产生复制事件的来源应用信息
        if Thread.isMainThread {
            let frontmostApplication = NSWorkspace.shared.frontmostApplication
            applicationName = frontmostApplication?.localizedName
            bundleIdentifier = frontmostApplication?.bundleIdentifier
        } else {
            DispatchQueue.main.sync {
                let frontmostApplication = NSWorkspace.shared.frontmostApplication
                applicationName = frontmostApplication?.localizedName
                bundleIdentifier = frontmostApplication?.bundleIdentifier
            }
        }
        
        // 1. 优先检测是否包含文件/文件夹路径（Finder 复制文件或 QQ/微信等聊天软件复制图片/文件）
        if let fileUrls = systemPasteboard.readObjects(forClasses: [NSURL.self], options: [NSPasteboard.ReadingOptionKey.urlReadingFileURLsOnly: true]) as? [URL],
           !fileUrls.isEmpty {
            let pathList = fileUrls.map { $0.path }
            let firstFilePath = pathList.first ?? ""
            let firstFileName = (firstFilePath as NSString).lastPathComponent
            
            // 智能识别：若为单文件且扩展名为图片格式（如 QQ/微信/浏览器/Finder 中复制的图片文件）
            let imageExtensions = ["jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "tiff", "tif", "bmp", "svg", "ico"]
            let pathExtension = (firstFilePath as NSString).pathExtension.lowercased()
            
            if pathList.count == 1 && imageExtensions.contains(pathExtension) {
                // 零冗余存储：直接存储原文件的物理路径，绝不重复生成磁盘副本，节约双倍存储空间
                let imageItem = ClipboardItem(
                    type: .image,
                    contentText: firstFileName,
                    imagePath: firstFilePath,
                    filePaths: pathList,
                    sourceAppName: applicationName,
                    sourceAppBundleId: bundleIdentifier
                )
                ClipboardStore.shared.handleNewCapturedItem(imageItem)
                return
            }
            
            let summaryText = pathList.count > 1 ? "\(firstFileName) 等 \(pathList.count) 个文件" : firstFileName
            
            let fileItem = ClipboardItem(
                type: .file,
                contentText: summaryText,
                filePaths: pathList,
                sourceAppName: applicationName,
                sourceAppBundleId: bundleIdentifier
            )
            ClipboardStore.shared.handleNewCapturedItem(fileItem)
            return
        }
        
        // 2. 检测文本类数据（纯文本、代码、URL、HEX/RGB 颜色、富文本）
        if let rawString = systemPasteboard.string(forType: .string) {
            let trimmedString = rawString.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedString.isEmpty {
                let optionalHtml = systemPasteboard.string(forType: .html)
                let detectedType = ContentClassifier.classifyText(rawString)
                
                let textItem = ClipboardItem(
                    type: detectedType,
                    contentText: rawString,
                    htmlContent: optionalHtml,
                    sourceAppName: applicationName,
                    sourceAppBundleId: bundleIdentifier
                )
                ClipboardStore.shared.handleNewCapturedItem(textItem)
                return
            }
        }
        
        // 3. 检测纯图片数据（截图、浏览器中复制图片等无文本的情况）
        if let capturedImage = NSImage(pasteboard: systemPasteboard) {
            if let savedFileName = ImageStorageManager.shared.saveImage(image: capturedImage) {
                let imageItem = ClipboardItem(
                    type: .image,
                    contentText: "图片 (\(Int(capturedImage.size.width)) × \(Int(capturedImage.size.height)))",
                    imagePath: savedFileName,
                    sourceAppName: applicationName,
                    sourceAppBundleId: bundleIdentifier
                )
                ClipboardStore.shared.handleNewCapturedItem(imageItem)
                return
            }
        }
    }
}
