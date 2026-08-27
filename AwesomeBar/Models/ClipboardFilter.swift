import Foundation

/// 剪贴板主面板顶部分类过滤标签枚举
public enum ClipboardFilter: String, CaseIterable, Identifiable {
    /// 显示全部历史条目
    case all = "all"
    /// 仅显示用户手动置顶固定条目
    case pinned = "pinned"
    /// 仅显示用户星标收藏条目
    case favorites = "favorites"
    /// 仅显示文本及富文本
    case text = "text"
    /// 仅显示图片与截图
    case image = "image"
    /// 仅显示网络链接
    case url = "url"
    /// 仅显示代码片段
    case code = "code"
    /// 仅显示颜色色值
    case color = "color"
    /// 仅显示文件及文件夹
    case file = "file"
    
    /// 唯一标识符
    public var id: String {
        return rawValue
    }
    
    /// 胶囊标签展示标题
    public var title: String {
        switch self {
        case .all:
            return "全部"
        case .pinned:
            return "已置顶"
        case .favorites:
            return "已收藏"
        case .text:
            return "文本"
        case .image:
            return "图片"
        case .url:
            return "链接"
        case .code:
            return "代码"
        case .color:
            return "颜色"
        case .file:
            return "文件"
        }
    }
    
    /// 对应的 SF Symbol 图标名称
    public var iconName: String {
        switch self {
        case .all:
            return "square.grid.2x2"
        case .pinned:
            return "pin.fill"
        case .favorites:
            return "star.fill"
        case .text:
            return "doc.text"
        case .image:
            return "photo"
        case .url:
            return "link"
        case .code:
            return "chevron.left.forwardslash.chevron.right"
        case .color:
            return "paintpalette"
        case .file:
            return "folder"
        }
    }
    
    /// 分类在标签栏中的水平顺序索引（用于判定左右切换方向）
    public var orderIndex: Int {
        switch self {
        case .all: return 0
        case .pinned: return 1
        case .favorites: return 2
        case .text: return 3
        case .image: return 4
        case .url: return 5
        case .code: return 6
        case .color: return 7
        case .file: return 8
        }
    }
}
