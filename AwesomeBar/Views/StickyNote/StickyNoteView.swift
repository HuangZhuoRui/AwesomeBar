import SwiftUI

/// 粘贴板偏好键：记录各个卡片在滚动视口内的几何坐标
public struct StickyRowFramePreference: PreferenceKey {
    public static var defaultValue: [UUID: CGRect] = [:]
    public static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

/// 粘贴板模式主视图（纯净轻量独立粘贴板浮窗，无分类全量滚动展示，支持 ⌘1-9 动态可见性映射快捷键与常驻置顶）
public struct StickyNoteView: View {
    /// 绑定的剪贴板数据流中心
    @ObservedObject private var store = ClipboardStore.shared
    /// 绑定的偏好设置单例
    @ObservedObject private var settings = AppSettings.shared
    /// 显式注入的窗口控制器引用（彻底避免在 init 期间重入访问单例造成 Deadlock Crash）
    @ObservedObject public var controller: StickyNoteWindowController
    /// 当前计算得到的条目与 ⌘1-9 快捷键映射（仅分配给可见比例大于 2/3 的条目）
    @State private var itemShortcuts: [UUID: Int] = [:]
    /// 滚动视口实际高度
    @State private var scrollViewportHeight: CGFloat = 330
    /// 关闭/隐藏粘贴板浮窗的回调
    public let onClose: () -> Void
    
    public init(
        controller: StickyNoteWindowController,
        onClose: @escaping () -> Void
    ) {
        self.controller = controller
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
            .help("关闭粘贴板浮窗 (Esc)")
        }
    }
    
    // MARK: - 辅助子视图：滚动条目列表与动态视口几何计算
    
    private var itemsScrollView: some View {
        GeometryReader { viewportGeo in
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(spacing: 6) {
                    ForEach(store.allItems) { item in
                        StickyNoteRowView(
                            item: item,
                            shortcutIndex: itemShortcuts[item.id],
                            isCopiedExternal: controller.lastCopiedItemId == item.id
                        ) {
                            controller.triggerItemCopy(item: item)
                        }
                        .background(
                            GeometryReader { rowGeo in
                                Color.clear.preference(
                                    key: StickyRowFramePreference.self,
                                    value: [item.id: rowGeo.frame(in: .named("StickyNoteScrollViewSpace"))]
                                )
                            }
                        )
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            .coordinateSpace(name: "StickyNoteScrollViewSpace")
            .onAppear {
                self.scrollViewportHeight = viewportGeo.size.height
            }
            .onChange(of: viewportGeo.size.height) { newHeight in
                self.scrollViewportHeight = newHeight
            }
            .onPreferenceChange(StickyRowFramePreference.self) { frames in
                DispatchQueue.main.async {
                    recalculateVisibleItemShortcuts(frames: frames, viewportHeight: scrollViewportHeight)
                }
            }
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
    
    // MARK: - 核心算法：按视口大于 2/3 可见性动态分配 ⌘1 - ⌘9
    
    private func recalculateVisibleItemShortcuts(frames: [UUID: CGRect], viewportHeight: CGFloat) {
        guard viewportHeight > 0 else { return }
        
        var qualifiedVisibleItems: [(item: ClipboardItem, minY: CGFloat)] = []
        
        for item in store.allItems {
            guard let frame = frames[item.id], frame.height > 0 else { continue }
            
            // 计算条目与可视视口区域 [0, viewportHeight] 的交集高度
            let visibleTop = max(0, frame.minY)
            let visibleBottom = min(viewportHeight, frame.maxY)
            let visibleHeight = max(0, visibleBottom - visibleTop)
            
            let visibleRatio = visibleHeight / frame.height
            
            // 关键业务要求：显示内容必须大于 2/3 (即 visibleRatio >= 0.666)
            if visibleRatio >= 0.666 {
                qualifiedVisibleItems.append((item: item, minY: frame.minY))
            }
        }
        
        // 按照在视口中的物理 Y 坐标从上至下严格排序
        qualifiedVisibleItems.sort { $0.minY < $1.minY }
        
        var newShortcuts: [UUID: Int] = [:]
        var newShortcutMap: [Int: ClipboardItem] = [:]
        
        // 为前 9 个有效可见条目动态授予 ⌘1 ~ ⌘9
        for (index, entry) in qualifiedVisibleItems.prefix(9).enumerated() {
            let shortcutNumber = index + 1
            newShortcuts[entry.item.id] = shortcutNumber
            newShortcutMap[shortcutNumber] = entry.item
        }
        
        self.itemShortcuts = newShortcuts
        self.controller.currentVisibleShortcutMap = newShortcutMap
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
