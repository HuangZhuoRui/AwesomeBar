import SwiftUI

/// 粘贴板模式主视图（纯净轻量独立粘贴板浮窗，无分类全量滚动展示，支持一键点击复制与常驻置顶）
public struct StickyNoteView: View {
    /// 绑定的剪贴板数据流中心
    @ObservedObject private var store = ClipboardStore.shared
    /// 绑定的偏好设置单例
    @ObservedObject private var settings = AppSettings.shared
    /// 关闭/隐藏粘贴板浮窗的回调
    public let onClose: () -> Void
    
    public init(onClose: @escaping () -> Void = { StickyNoteWindowController.shared.hide() }) {
        self.onClose = onClose
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // 1. 粘贴板顶部操作标题栏（支持拖拽、置顶与关闭）
            headerBarView
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 8)
            
            Divider()
                .opacity(0.3)
            
            // 2. 剪贴板历史记录滚动区域（无分类，默认展示全部记录）
            if store.allItems.isEmpty {
                emptyStateView
            } else {
                itemsScrollView
            }
        }
        .frame(width: 270, height: 390)
        .background(LiquidGlassBackground(cornerRadius: 20))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
    
    // MARK: - 辅助子视图：顶部操作标题栏
    
    private var headerBarView: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)
                .allowsHitTesting(false)
            
            Text("粘贴板")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .allowsHitTesting(false)
            
            Spacer()
            
            // 1. 置顶图钉按钮
            Button(action: {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                    settings.isStickyNotePinned.toggle()
                    SoundManager.shared.playPinSound()
                }
            }) {
                Image(systemName: settings.isStickyNotePinned ? "pin.fill" : "pin")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(settings.isStickyNotePinned ? .orange : .secondary)
                    .frame(width: 22, height: 22)
                    .background(settings.isStickyNotePinned ? Color.orange.opacity(0.14) : Color.primary.opacity(0.04))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help(settings.isStickyNotePinned ? "取消置顶" : "置顶悬浮在屏幕最上层")
            
            // 2. 关闭粘贴板按钮
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                    .frame(width: 22, height: 22)
                    .background(Color.primary.opacity(0.04))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("关闭粘贴板浮窗")
        }
    }
    
    // MARK: - 辅助子视图：滚动条目列表
    
    private var itemsScrollView: some View {
        ScrollView(.vertical, showsIndicators: true) {
            LazyVStack(spacing: 6) {
                ForEach(store.allItems) { item in
                    StickyNoteRowView(item: item) {
                        PasteSimulator.shared.copyToClipboard(item: item)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.0),
                    .init(color: .black, location: 0.03),
                    .init(color: .black, location: 0.97),
                    .init(color: .clear, location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
    
    // MARK: - 辅助子视图：空状态占位
    
    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "clipboard")
                .font(.system(size: 24, weight: .light))
                .foregroundColor(.secondary)
            
            Text("暂无剪贴记录")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
        }
        .allowsHitTesting(false)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
