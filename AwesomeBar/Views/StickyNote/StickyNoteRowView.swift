import SwiftUI
import AppKit

/// 粘贴板模式下专属的紧凑型剪贴板历史卡片行组件（支持一键点击复制、动态 ⌘1-9 快捷键显示与已复制状态反馈）
public struct StickyNoteRowView: View {
    /// 当前呈现的剪贴板数据实体
    public let item: ClipboardItem
    /// 动态分配的 ⌘1-9 快捷键序号（如果可见区域大于 2/3 则分配）
    public let shortcutIndex: Int?
    /// 是否由外部快捷键触发了已复制高亮
    public let isCopiedExternal: Bool
    /// 点击复制触发的回调
    public let onCopy: () -> Void
    
    @State private var isHovered: Bool = false
    @State private var isCopiedInternal: Bool = false
    @Environment(\.colorScheme) private var colorScheme
    
    public init(
        item: ClipboardItem,
        shortcutIndex: Int? = nil,
        isCopiedExternal: Bool = false,
        onCopy: @escaping () -> Void
    ) {
        self.item = item
        self.shortcutIndex = shortcutIndex
        self.isCopiedExternal = isCopiedExternal
        self.onCopy = onCopy
    }
    
    private var isCopied: Bool {
        isCopiedInternal || isCopiedExternal
    }
    
    public var body: some View {
        Button(action: handleCopyAction) {
            HStack(spacing: 8) {
                // 1. 类型特征小图标 / 颜色块 / 图片微缩图
                leadingThumbnailOrIcon
                
                // 2. 核心文本内容摘要
                VStack(alignment: .leading, spacing: 2) {
                    Text(contentPreviewText)
                        .font(.system(size: 11.5, weight: .regular))
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    
                    HStack(spacing: 6) {
                        Text(item.timeAgoDisplay)
                            .font(.system(size: 9.5))
                            .foregroundColor(.secondary)
                        
                        if let sourceApp = item.sourceAppName {
                            Text("•  \(sourceApp)")
                                .font(.system(size: 9.5))
                                .foregroundColor(.secondary.opacity(0.8))
                                .lineLimit(1)
                        }
                    }
                }
                
                Spacer(minLength: 4)
                
                // 3. 右侧状态：已复制高亮 / 动态 ⌘1-9 快捷键序号 / 悬停复制提示
                if isCopied {
                    HStack(spacing: 2) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                        Text("已复制")
                            .font(.system(size: 9.5, weight: .medium))
                    }
                    .foregroundColor(.green)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.14))
                    .clipShape(Capsule())
                    .transition(.scale.combined(with: .opacity))
                } else if let shortcut = shortcutIndex,
                          let badgeText = AppSettings.shared.quickSelectModifier.badgeText(for: shortcut) {
                    Text(badgeText)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(colorScheme == .dark ? Color.white.opacity(0.09) : Color.black.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                } else if isHovered {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .liquidGlassCard(cornerRadius: 11, isHighlighted: isHovered || isCopied)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                self.isHovered = hovering
            }
        }
        .help(shortcutIndex != nil && AppSettings.shared.quickSelectModifier != .none ? "点击或按 \(AppSettings.shared.quickSelectModifier.badgeText(for: shortcutIndex!) ?? "") 复制" : "点击立即复制到剪贴板")
    }
    
    // MARK: - 辅助子视图：前置图标或缩略图
    
    @ViewBuilder
    private var leadingThumbnailOrIcon: some View {
        switch item.effectiveType {
        case .image:
            if let imageFileName = item.imagePath,
               let nsImage = ImageStorageManager.shared.loadImage(filename: imageFileName) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 13))
                    .foregroundColor(.blue)
                    .frame(width: 28, height: 28)
            }
            
        case .color:
            if let hex = item.colorHex {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(hex: hex) ?? Color.secondary)
                    .frame(width: 24, height: 24)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.3), lineWidth: 1)
                    )
            }
            
        case .code:
            Image(systemName: "curlybraces")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.purple)
                .frame(width: 24, height: 24)
                .background(Color.purple.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            
        case .url:
            Image(systemName: "link")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.blue)
                .frame(width: 24, height: 24)
                .background(Color.blue.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            
        case .file:
            Image(systemName: "doc")
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(.orange)
                .frame(width: 24, height: 24)
                .background(Color.orange.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            
        case .text, .richText:
            Image(systemName: "doc.text")
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(.secondary)
                .frame(width: 24, height: 24)
                .background(Color.primary.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }
    
    // MARK: - 文本内容摘要计算
    
    private var contentPreviewText: String {
        switch item.effectiveType {
        case .image:
            return item.previewTitle
        default:
            return item.contentText.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        }
    }
    
    // MARK: - 点击复制处理动作
    
    private func handleCopyAction() {
        onCopy()
        withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
            isCopiedInternal = true
        }
        
        // 0.8 秒后恢复常规状态
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            withAnimation(.easeOut(duration: 0.2)) {
                self.isCopiedInternal = false
            }
        }
    }
}
