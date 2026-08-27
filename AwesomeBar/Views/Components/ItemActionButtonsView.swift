import SwiftUI

/// 剪贴板条目悬停操作按钮组组件（仅复制、固定、收藏、详情、删除、自动粘贴）
public struct ItemActionButtonsView: View {
    /// 目标剪贴板条目
    public let item: ClipboardItem
    /// 仅复制到剪贴板回调（不关闭窗口）
    public let onCopyOnly: () -> Void
    /// 切换固定置顶回调
    public let onTogglePin: () -> Void
    /// 切换收藏回调
    public let onToggleFavorite: () -> Void
    /// 查看详情回调
    public let onInspect: () -> Void
    /// 删除条目回调
    public let onDelete: () -> Void
    /// 选择并自动粘贴回调（回写并收起窗口）
    public let onSelectAndPaste: () -> Void
    
    @State private var isCopySuccessIndicatorShowing: Bool = false
    
    public init(
        item: ClipboardItem,
        onCopyOnly: @escaping () -> Void,
        onTogglePin: @escaping () -> Void,
        onToggleFavorite: @escaping () -> Void,
        onInspect: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        onSelectAndPaste: @escaping () -> Void
    ) {
        self.item = item
        self.onCopyOnly = onCopyOnly
        self.onTogglePin = onTogglePin
        self.onToggleFavorite = onToggleFavorite
        self.onInspect = onInspect
        self.onDelete = onDelete
        self.onSelectAndPaste = onSelectAndPaste
    }
    
    public var body: some View {
        HStack(spacing: 4) {
            // 1. 仅复制到剪贴板按钮（不退出面板）
            Button(action: {
                onCopyOnly()
                withAnimation {
                    isCopySuccessIndicatorShowing = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    withAnimation {
                        isCopySuccessIndicatorShowing = false
                    }
                }
            }) {
                Image(systemName: isCopySuccessIndicatorShowing ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 11, weight: isCopySuccessIndicatorShowing ? .bold : .regular))
                    .foregroundColor(isCopySuccessIndicatorShowing ? .green : .secondary)
                    .frame(width: 24, height: 24)
                    .background(isCopySuccessIndicatorShowing ? Color.green.opacity(0.15) : Color.primary.opacity(0.06))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("仅复制到系统剪贴板 (不粘贴、不关闭窗口)")
            
            // 2. 置顶固定按钮
            Button(action: onTogglePin) {
                Image(systemName: item.isPinned ? "pin.slash.fill" : "pin.fill")
                    .font(.system(size: 11))
                    .foregroundColor(item.isPinned ? .orange : .secondary)
                    .frame(width: 24, height: 24)
                    .background(item.isPinned ? Color.orange.opacity(0.15) : Color.primary.opacity(0.06))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help(item.isPinned ? "取消固定" : "固定此项")
            
            // 3. 收藏按钮
            Button(action: onToggleFavorite) {
                Image(systemName: item.isFavorite ? "star.fill" : "star")
                    .font(.system(size: 11))
                    .foregroundColor(item.isFavorite ? .yellow : .secondary)
                    .frame(width: 24, height: 24)
                    .background(item.isFavorite ? Color.yellow.opacity(0.15) : Color.primary.opacity(0.06))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help(item.isFavorite ? "取消收藏" : "收藏此项")
            
            // 4. 详情与格式转换按钮
            Button(action: onInspect) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)
                    .frame(width: 24, height: 24)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("查看详情与格式转换 (Space)")
            
            // 5. 删除按钮
            Button(action: onDelete) {
                Image(systemName: "trash.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.red.opacity(0.8))
                    .frame(width: 24, height: 24)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("删除此项")
            
            // 6. 立即粘贴操作按钮（粘贴并关闭窗口）
            Button(action: onSelectAndPaste) {
                Image(systemName: "arrow.turn.down.left")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.accentColor)
                    .frame(width: 24, height: 24)
                    .background(Color.accentColor.opacity(0.12))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("直接粘贴至前台应用并收起窗口 (↵)")
        }
    }
}
