import SwiftUI

/// 粘贴板偏好键：记录各个卡片在滚动视口内的几何坐标
public struct StickyRowFramePreference: PreferenceKey {
    public static var defaultValue: [UUID: CGRect] = [:]
    public static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

/// 粘贴板模式主视图（纯净轻量独立粘贴板浮窗，支持屏幕边缘甩动吸附露角、复制无焦点弹出冒泡、无分类全量滚动展示与 ⌘1-9 快捷键）
public struct StickyNoteView: View {
    /// 绑定的剪贴板数据流中心
    @ObservedObject private var store = ClipboardStore.shared
    /// 绑定的偏好设置单例
    @ObservedObject private var settings = AppSettings.shared
    /// 显式注入的窗口控制器引用
    @ObservedObject public var controller: StickyNoteWindowController
    /// 当前计算得到的条目与 ⌘1-9 快捷键映射（仅分配给可见比例大于 2/3 的条目）
    @State private var itemShortcuts: [UUID: Int] = [:]
    /// 滚动视口实际高度
    @State private var scrollViewportHeight: CGFloat = 330
    /// 是否正处于鼠标悬浮在边角手柄上
    @State private var isHandleHovered: Bool = false
    /// 关闭/隐藏粘贴板浮窗的回调
    public let onClose: () -> Void
    
    public init(
        controller: StickyNoteWindowController,
        onClose: @escaping () -> Void
    ) {
        self.controller = controller
        self.onClose = onClose
    }
    
    /// 当前是否处于边缘吸附只露小角收缩形态（只有收缩贴边时才为 true；复制冒出或完全展开时为 false）
    private var isPeekingDocked: Bool {
        return (controller.dockState == .dockedLeft || controller.dockState == .dockedRight) && controller.isPeekingCollapsed
    }
    
    public var body: some View {
        ZStack {
            // 完整主内容视图（包含顶部栏与全部剪贴板滚动条目）
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
            .opacity(isPeekingDocked ? 0.0 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isPeekingDocked)
            
            // 边缘吸附露小角时的手柄视觉覆盖层（仅在收缩贴边时展示）
            if isPeekingDocked {
                peekingHandleOverlay
                    .transition(.opacity)
            }
        }
        .frame(width: controller.panelWidth, height: controller.panelHeight)
        .background(LiquidGlassBackground(cornerRadius: 20))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
    
    // MARK: - 辅助子视图：边缘吸附手柄
    
    private var peekingHandleOverlay: some View {
        HStack {
            if controller.dockState == .dockedRight {
                // 吸附在右边缘时，露在屏幕上的是窗口最左侧 24px
                VStack(spacing: 8) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.primary.opacity(isHandleHovered ? 1.0 : 0.6))
                    
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.primary.opacity(isHandleHovered ? 1.0 : 0.7))
                }
                .frame(width: controller.peekWidth)
                .frame(maxHeight: .infinity)
                .background(Color.primary.opacity(isHandleHovered ? 0.08 : 0.02))
                .contentShape(Rectangle())
                .onTapGesture {
                    controller.expandFromDock()
                }
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        self.isHandleHovered = hovering
                    }
                }
                
                Spacer()
            } else if controller.dockState == .dockedLeft {
                // 吸附在左边缘时，露在屏幕上的是窗口最右侧 24px
                Spacer()
                
                VStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.primary.opacity(isHandleHovered ? 1.0 : 0.6))
                    
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.primary.opacity(isHandleHovered ? 1.0 : 0.7))
                }
                .frame(width: controller.peekWidth)
                .frame(maxHeight: .infinity)
                .background(Color.primary.opacity(isHandleHovered ? 0.08 : 0.02))
                .contentShape(Rectangle())
                .onTapGesture {
                    controller.expandFromDock()
                }
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        self.isHandleHovered = hovering
                    }
                }
            }
        }
        .help("点击展开或直接按住拖动小角拉回屏幕")
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
            
            // 吸附状态徽标提示
            if controller.dockState == .dockedLeft || controller.dockState == .dockedRight {
                Text("已吸附")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(Color.primary.opacity(0.05))
                    .clipShape(Capsule())
            }
            
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
            
            let visibleTop = max(0, frame.minY)
            let visibleBottom = min(viewportHeight, frame.maxY)
            let visibleHeight = max(0, visibleBottom - visibleTop)
            
            let visibleRatio = visibleHeight / frame.height
            
            if visibleRatio >= 0.666 {
                qualifiedVisibleItems.append((item: item, minY: frame.minY))
            }
        }
        
        qualifiedVisibleItems.sort { $0.minY < $1.minY }
        
        var newShortcuts: [UUID: Int] = [:]
        var newShortcutMap: [Int: ClipboardItem] = [:]
        
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
