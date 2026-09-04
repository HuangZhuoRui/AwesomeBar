import Foundation

/// 剪贴板支持的内容格式类型枚举
/// 标记为 nonisolated：纯值类型 / 无状态工具，需在数据库与后台队列等非主线程上下文中自由使用。
public nonisolated enum ClipboardContentType: String, Codable, CaseIterable {
    /// 纯文本格式
    case text = "text"
    /// 富文本格式（含 HTML / RTF）
    case richText = "richText"
    /// 代码片段（自动语法特征识别）
    case code = "code"
    /// 颜色色值（十六进制 HEX 或 RGB）
    case color = "color"
    /// 网络链接或统一资源定位符 URL
    case url = "url"
    /// 图像数据（PNG / JPEG / TIFF 截图）
    case image = "image"
    /// 本地文件或文件夹路径
    case file = "file"
    
    /// 获取该类型的中文显示名称
    public var displayName: String {
        switch self {
        case .text:
            return "文本"
        case .richText:
            return "富文本"
        case .code:
            return "代码"
        case .color:
            return "颜色"
        case .url:
            return "链接"
        case .image:
            return "图片"
        case .file:
            return "文件"
        }
    }
    
    /// 获取对应的 SF Symbol 系统图标名称
    public var iconName: String {
        switch self {
        case .text:
            return "doc.text.fill"
        case .richText:
            return "text.alignleft"
        case .code:
            return "chevron.left.forwardslash.chevron.right"
        case .color:
            return "paintpalette.fill"
        case .url:
            return "link"
        case .image:
            return "photo.fill"
        case .file:
            return "folder.fill"
        }
    }
}
