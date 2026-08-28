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
            if isPeekingDocked {
                // 边缘吸附露小角时的手柄（精巧 28px 宽贴边手柄，0 屏幕外溢出）
                peekingHandleOverlay
                    .transition(.opacity)
            } else {
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
                .transition(.opacity)
            }
        }
        .frame(
            width: isPeekingDocked ? controller.peekWidth : controller.panelWidth,
            height: controller.panelHeight
        )
        .background(LiquidGlassBackground(cornerRadius: isPeekingDocked ? 12 : 20))
        .clipShape(RoundedRectangle(cornerRadius: isPeekingDocked ? 12 : 20, style: .continuous))
    }
    
    // MARK: - 辅助子视图：边缘吸附手柄
    
    private var peekingHandleOverlay: some View {
        VStack(spacing: 10) {
            Spacer()
            
            Image(systemName: controller.dockState == .dockedRight ? "chevron.left" : "chevron.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.primary.opacity(isHandleHovered ? 1.0 : 0.6))
            
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.primary.opacity(isHandleHovered ? 1.0 : 0.7))
            
            Spacer()
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
        .help("点击展开粘贴板")
    }
    
    // MARK: - 辅助子视图：顶部操作标题栏
    
    private var headerBarView: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.on.clipboard.fill")
                .font(.system(size: 11))
                .foregroundColor(.accentColor)
            
            Text("粘贴板")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.primary)
            
            Text("(\(store.allItems.count))")
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
            
            Spacer()
            
            // 独立置顶切换按钮
            Button(action: {
                settings.isStickyNotePinned.toggle()
                SoundManager.shared.playPinSound()
            }) {
                Image(systemName: settings.isStickyNotePinned ? "pin.fill" : "pin")
                    .font(.system(size: 10))
                    .foregroundColor(settings.isStickyNotePinned ? .orange : .secondary)
                    .frame(width: 22, height: 22)
                    .background(settings.isStickyNotePinned ? Color.orange.opacity(0.15) : Color.primary.opacity(0.04))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help(settings.isStickyNotePinned ? "取消置顶" : "保持最上层置顶")
            
            // 吸附收回按钮（仅在已吸附状态完全展开时呈现）
            if controller.dockState == .dockedLeft || controller.dockState == .dockedRight {
                Button(action: {
                    controller.collapseToDock()
                }) {
                    Image(systemName: controller.dockState == .dockedRight ? "arrow.right.to.line" : "arrow.left.to.line")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .frame(width: 22, height: 22)
                        .background(Color.primary.opacity(0.04))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("缩回屏幕边缘")
            }
            
            // 关闭按钮
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
    
    // MARK: - 辅助计算：视口内可见条目 ⌘1-9 快捷键动态分配算法
    
    private func recalculateVisibleItemShortcuts(frames: [UUID: CGRect], viewportHeight: CGFloat) {
        guard viewportHeight > 0 else { return }
        
        let allItems = store.allItems
        var candidateItems: [(item: ClipboardItem, topY: CGFloat)] = []
        
        for item in allItems {
            if let frame = frames[item.id] {
                let visibleTop = max(frame.minY, 0)
                let visibleBottom = min(frame.maxY, viewportHeight)
                let visibleHeight = max(0, visibleBottom - visibleTop)
                
                // 核心判定指标：可见面积必须严格大于该条目自身高度的 2/3 (0.66)
                if frame.height > 0 && (visibleHeight / frame.height) >= 0.66 {
                    candidateItems.append((item: item, topY: frame.minY))
                }
            }
        }
        
        // 按照在视口中的垂直 Y 坐标从上至下严格排序
        candidateItems.sort { $0.topY < $1.topY }
        
        var newShortcuts: [UUID: Int] = [:]
        var visibleMap: [Int: ClipboardItem] = [:]
        
        // 自上而下连续且稳定地分配 1, 2, 3... 最多至 9
        for (index, pair) in candidateItems.prefix(9).enumerated() {
            let shortcutNumber = index + 1
            newShortcuts[pair.item.id] = shortcutNumber
            visibleMap[shortcutNumber] = pair.item
        }
        
        self.itemShortcuts = newShortcuts
        self.controller.currentVisibleShortcutMap = visibleMap
    }
    
    // MARK: - 空状态占位视图
    
    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Spacer()
            
            Image(systemName: "tray")
                .font(.system(size: 24))
                .foregroundColor(.secondary.opacity(0.5))
            
            Text("暂无剪贴板历史")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
            
            Text("按 ⌘C 复制的内容将即刻在此呈现")
                .font(.system(size: 10.5))
                .foregroundColor(.secondary.opacity(0.7))
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
