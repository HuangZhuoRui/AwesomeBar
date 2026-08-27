import Foundation
import AppKit
import QuickLookUI

/// macOS 官方原生 Quick Look 快速预览管理器（支持图片、PDF、文档、音视频、3D 等全格式原生系统级预览）
public final class QuickLookManager: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    public static let shared = QuickLookManager()
    
    /// 当前正在快速预览的文件 URL 列表
    private var previewUrls: [URL] = []
    
    private override init() {
        super.init()
    }
    
    /// 根据剪贴板条目呼出 macOS 官方 Quick Look 预览面板
    public func preview(item: ClipboardItem) {
        // 1. 优先获取物理文件路径（如 QQ、微信、Finder 复制的图片或文档）
        if let firstPath = item.filePaths?.first, FileManager.default.fileExists(atPath: firstPath) {
            previewFile(at: firstPath)
            return
        }
        
        // 2. 获取应用内部持久化保存的图片
        if let imageFilename = item.imagePath {
            let fullPath = ImageStorageManager.shared.getImageFullPath(filename: imageFilename)
            if FileManager.default.fileExists(atPath: fullPath) {
                previewFile(at: fullPath)
                return
            }
        }
        
        // 3. 检查文本内容是否本身为有效本地文件路径
        if FileManager.default.fileExists(atPath: item.contentText) {
            previewFile(at: item.contentText)
            return
        }
        
        // 若所有物理路径均已在磁盘上失效（如 QQ/沙盒临时文件已被清理），自动从数据库与列表中移除该失效记录
        ClipboardStore.shared.deleteItem(id: item.id)
    }
    
    /// 切换 Quick Look 预览窗口的显示与关闭状态（按空格打开/收起，与 Finder 行为完全一致）
    public func togglePreview(item: ClipboardItem) {
        if let panel = QLPreviewPanel.shared(), panel.isVisible {
            panel.orderOut(nil)
        } else {
            preview(item: item)
        }
    }
    
    /// 打开指定物理路径的文件预览
    public func previewFile(at path: String) {
        guard FileManager.default.fileExists(atPath: path) else {
            print("QuickLook 目标文件不存在: \(path)")
            return
        }
        
        let fileUrl = URL(fileURLWithPath: path)
        self.previewUrls = [fileUrl]
        
        DispatchQueue.main.async {
            guard let panel = QLPreviewPanel.shared() else { return }
            panel.dataSource = self
            panel.delegate = self
            panel.reloadData()
            panel.makeKeyAndOrderFront(nil)
        }
    }
    
    // MARK: - QLPreviewPanelDataSource
    
    public func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        return previewUrls.count
    }
    
    public func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        guard index >= 0 && index < previewUrls.count else { return nil }
        return previewUrls[index] as NSURL
    }
}
