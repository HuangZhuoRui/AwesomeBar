import Foundation
import AppKit

/// 剪贴板单条记录核心数据实体模型
public struct ClipboardItem: Identifiable, Hashable, Codable {
    /// 唯一主键标识符
    public let id: UUID
    /// 剪贴板内容类型
    public var type: ClipboardContentType
    /// 原始内容文本或显示标题
    public var contentText: String
    /// 富文本 HTML 内容（如果存在）
    public var htmlContent: String?
    /// 本地图片文件名称（如果为图片类型）
    public var imagePath: String?
    /// 本地文件路径列表（如果为文件类型）
    public var filePaths: [String]?
    /// 复制来源应用程序的本地化名称（例如：Xcode, Safari）
    public var sourceAppName: String?
    /// 复制来源应用程序的 Bundle Identifier
    public var sourceAppBundleId: String?
    /// 总字符数量统计
    public var charCount: Int
    /// 单词数量统计
    public var wordCount: Int
    /// 总行数统计
    public var lineCount: Int
    /// 是否被用户置顶固定（置顶条目在清理时不被删除，且优先置顶展示）
    public var isPinned: Bool
    /// 是否加入收藏
    public var isFavorite: Bool
    /// 重复复制命中次数
    public var copiedCount: Int
    /// 初次创建时间戳
    public var createdAt: Date
    /// 最近一次复制或修改的时间戳
    public var updatedAt: Date
    
    /// 初始化剪贴板条目
    public init(
        id: UUID = UUID(),
        type: ClipboardContentType,
        contentText: String,
        htmlContent: String? = nil,
        imagePath: String? = nil,
        filePaths: [String]? = nil,
        sourceAppName: String? = nil,
        sourceAppBundleId: String? = nil,
        charCount: Int = 0,
        wordCount: Int = 0,
        lineCount: Int = 0,
        isPinned: Bool = false,
        isFavorite: Bool = false,
        copiedCount: Int = 1,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.type = type
        self.contentText = contentText
        self.htmlContent = htmlContent
        self.imagePath = imagePath
        self.filePaths = filePaths
        self.sourceAppName = sourceAppName
        self.sourceAppBundleId = sourceAppBundleId
        self.charCount = charCount == 0 ? contentText.count : charCount
        self.wordCount = wordCount == 0 ? ClipboardItem.calculateWordCount(from: contentText) : wordCount
        self.lineCount = lineCount == 0 ? (contentText.components(separatedBy: .newlines).count) : lineCount
        self.isPinned = isPinned
        self.isFavorite = isFavorite
        self.copiedCount = copiedCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    /// 计算文本的词数
    private static func calculateWordCount(from text: String) -> Int {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedText.isEmpty {
            return 0
        }
        let words = trimmedText.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        return words.count
    }
    
    // MARK: - 计算属性扩展
    
    /// 实际展示的内容类型（自动将图片类文件路径修正为图片类型）
    public var effectiveType: ClipboardContentType {
        if type == .file, let firstPath = filePaths?.first {
            let ext = (firstPath as NSString).pathExtension.lowercased()
            let imageExtensions = ["jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "tiff", "tif", "bmp", "svg", "ico"]
            if imageExtensions.contains(ext) {
                return .image
            }
        }
        return type
    }
    
    /// 卡片首行预览标题
    public var previewTitle: String {
        switch effectiveType {
        case .color:
            return contentText.trimmingCharacters(in: .whitespacesAndNewlines)
        case .url:
            return contentText.trimmingCharacters(in: .whitespacesAndNewlines)
        case .file:
            if let firstFilePath = filePaths?.first {
                return (firstFilePath as NSString).lastPathComponent
            }
            return contentText
        case .image:
            if let firstFilePath = filePaths?.first {
                return (firstFilePath as NSString).lastPathComponent
            }
            return contentText.isEmpty ? "图片剪贴" : contentText
        case .text, .richText, .code:
            let lines = contentText.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            return lines.first ?? "空白内容"
        }
    }
    
    /// 卡片副文本摘要（第二行及之后的内容）
    public var previewSnippet: String {
        let lines = contentText.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if lines.count > 1 {
            return lines.dropFirst().prefix(2).joined(separator: " ")
        }
        return ""
    }
    
    /// 解析颜色 HEX 字符串
    public var colorHex: String? {
        guard type == .color else { return nil }
        let cleanText = contentText.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanText.hasPrefix("#") {
            return cleanText
        }
        return nil
    }
    
    /// 来源应用程序的高清原生图标（内存缓存加速，保证 120Hz 极速丝滑）
    public var sourceAppIcon: NSImage? {
        guard let bundleIdentifier = sourceAppBundleId else { return nil }
        return AppIconCache.shared.icon(for: bundleIdentifier)
    }
    
    /// 友好相对时间展示（例如："刚刚"、"5分钟前"）
    public var timeAgoDisplay: String {
        let timeInterval = Date().timeIntervalSince(updatedAt)
        if timeInterval < 60 {
            return "刚刚"
        } else if timeInterval < 3600 {
            let minutes = Int(timeInterval / 60)
            return "\(minutes)分钟前"
        } else if timeInterval < 86400 {
            let hours = Int(timeInterval / 3600)
            return "\(hours)小时前"
        } else {
            let days = Int(timeInterval / 86400)
            if days == 1 {
                return "昨天"
            } else if days < 30 {
                return "\(days)天前"
            } else {
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "MM-dd HH:mm"
                return dateFormatter.string(from: updatedAt)
            }
        }
    }
    
    /// 完整绝对时间展示
    public var fullTimeDisplay: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return dateFormatter.string(from: createdAt)
    }
}

// MARK: - 应用图标内存高速缓存单例
private final class AppIconCache {
    static let shared = AppIconCache()
    private let cache = NSCache<NSString, NSImage>()
    
    private init() {
        cache.countLimit = 150
    }
    
    func icon(for bundleIdentifier: String) -> NSImage? {
        let key = bundleIdentifier as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        guard let appUrl = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return nil
        }
        let icon = NSWorkspace.shared.icon(forFile: appUrl.path)
        cache.setObject(icon, forKey: key)
        return icon
    }
}
