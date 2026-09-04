import SwiftUI
import AppKit

/// 单条剪贴板记录卡片行视图组件
public struct ClipboardRowView: View {
    /// 绑定的剪贴板数据实体
    public let item: ClipboardItem
    /// 是否被键盘选中高亮
    public let isSelected: Bool
    /// 当前在列表中的排序索引（前 9 项显示 ⌘1 - ⌘9）
    public let index: Int
    /// 触发仅复制（不关闭窗口）
    public let onCopyOnly: () -> Void
    /// 触发选中并自动粘贴（执行回写并收起窗口）
    public let onSelectAndPaste: () -> Void
    /// 切换置顶固定状态（置顶与取消置顶二合一）
    public let onTogglePin: () -> Void
    /// 切换收藏状态（收藏与取消收藏二合一）
    public let onToggleFavorite: () -> Void
    /// 删除此条记录
    public let onDelete: () -> Void
    /// 展开详细检查弹窗
    public let onInspect: () -> Void
    
    @State private var isMouseHovering: Bool = false
    /// 所在列表是否正在滚动（滚动中不响应悬停，避免视图结构反复切换造成闪烁）
    @Environment(\.isScrolling) private var isScrolling
    @Environment(\.colorScheme) private var colorScheme
    
    public init(
        item: ClipboardItem,
        isSelected: Bool = false,
        index: Int = 0,
        onCopyOnly: @escaping () -> Void,
        onSelectAndPaste: @escaping () -> Void,
        onTogglePin: @escaping () -> Void,
        onToggleFavorite: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        onInspect: @escaping () -> Void
    ) {
        self.item = item
        self.isSelected = isSelected
        self.index = index
        self.onCopyOnly = onCopyOnly
        self.onSelectAndPaste = onSelectAndPaste
        self.onTogglePin = onTogglePin
        self.onToggleFavorite = onToggleFavorite
        self.onDelete = onDelete
        self.onInspect = onInspect
    }
    
    public var body: some View {
        HStack(spacing: 12) {
            // 1. 左侧分类徽标与中间内容区域（点击此区域触发自动粘贴与收起）
            HStack(spacing: 12) {
                TypeBadgeView(type: item.effectiveType)
                
                VStack(alignment: .leading, spacing: 3) {
                    ContentPreviewView(item: item)
                    
                    // 来源应用与时间信息栏
                    HStack(spacing: 8) {
                        if let applicationIcon = item.sourceAppIcon {
                            Image(nsImage: applicationIcon)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 13, height: 13)
                        }
                        
                        if let applicationName = item.sourceAppName, !applicationName.isEmpty {
                            Text(applicationName)
                                .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                        }
                        
                        Text("•")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary.opacity(0.5))
                        
                        Text(item.timeAgoDisplay)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        
                        if item.copiedCount > 1 {
                            Text("已复制 \(item.copiedCount) 次")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary.opacity(0.8))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(
                                    Capsule()
                                        .fill(Color.primary.opacity(0.06))
                                )
                        }
                        
                        if item.type == .text || item.type == .code {
                            Text("\(item.charCount) 字符")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary.opacity(0.7))
                        }
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                onSelectAndPaste()
            }
            
            Spacer(minLength: 8)
            
            // 2. 右侧操作区：合并单一的置顶/收藏切换按钮、悬停操作组或快捷键
            HStack(spacing: 6) {
                if isMouseHovering || isSelected {
                    // 悬停/选中状态：显示完整的操作按钮组（内置单一的置顶切换、收藏切换、仅复制、详情、删除、粘贴）
                    ItemActionButtonsView(
                        item: item,
                        onCopyOnly: onCopyOnly,
                        onTogglePin: onTogglePin,
                        onToggleFavorite: onToggleFavorite,
                        onInspect: onInspect,
                        onDelete: onDelete,
                        onSelectAndPaste: onSelectAndPaste
                    )
                } else {
                    // 非悬停状态：若已置顶则显示单个可点击的取消置顶按钮，若已收藏则显示单个可点击的取消收藏按钮
                    if item.isPinned {
                        Button(action: onTogglePin) {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.orange)
                                .frame(width: 24, height: 24)
                                .background(Color.orange.opacity(0.15))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .help("已置顶，点击取消置顶")
                    }
                    
                    if item.isFavorite {
                        Button(action: onToggleFavorite) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.yellow)
                                .frame(width: 24, height: 24)
                                .background(Color.yellow.opacity(0.15))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .help("已收藏，点击取消收藏")
                    }
                    
                    if index < 9, let badge = AppSettings.shared.quickSelectModifier.badgeText(for: index + 1) {
                        Text(badge)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.7))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(Color.primary.opacity(0.05))
                            )
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .liquidGlassCard(cornerRadius: 14, isHighlighted: isSelected || isMouseHovering)
        .onHover { isHovering in
            // 滚动期间是内容在鼠标下掠过而非用户主动悬停，忽略之，
            // 否则每行都会被依次误判为悬停并切换视图结构，造成滚动闪烁
            guard !isScrolling else { return }
            self.isMouseHovering = isHovering
        }
        .onChange(of: isScrolling) {
            // 一旦开始滚动，立即清掉遗留的悬停态，避免有行「粘」在悬停外观上
            if isScrolling && isMouseHovering {
                isMouseHovering = false
            }
        }
    }
}
