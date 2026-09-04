import SwiftUI

/// 收集各分段在轨道坐标空间中的几何位置，供浮层游标定位与拖拽命中判定使用
private struct SegmentFramesPreferenceKey: PreferenceKey {
    static let defaultValue: [ClipboardFilter: CGRect] = [:]

    static func reduce(
        value: inout [ClipboardFilter: CGRect],
        nextValue: () -> [ClipboardFilter: CGRect]
    ) {
        value.merge(nextValue()) { _, latest in latest }
    }
}

/// 剪贴板分类分段控制器组件（1:1 像素级复刻 macOS 原生分段大胶囊控制器，全宽绝对居中对齐）
///
/// 结构要点：游标是一层**独立的浮层**，位于文字下方而非各分段自身的背景。
/// 这样文字永远压在游标之上、始终清晰可读，游标也得以脱离分段自由定位，从而支持跟手拖拽。
public struct FilterPillView: View {
    /// 绑定的当前选中的分类
    @Binding public var selectedFilter: ClipboardFilter
    /// 各分类下的条目数量映射
    public var filterCounts: [ClipboardFilter: Int]
    /// 选中分类变更时的回调处理
    public var onSelect: (ClipboardFilter) -> Void

    /// 当前鼠标悬停的分类
    @State private var hoveredFilter: ClipboardFilter?
    /// 各分段在轨道坐标空间中的几何位置
    @State private var segmentFrames: [ClipboardFilter: CGRect] = [:]
    /// 拖拽进行中时游标中心的横坐标（nil 表示未处于跟手状态）
    @State private var draggingCursorCenterX: CGFloat?
    /// 拖拽过程中预览选中的分类（松手才真正提交，避免拖拽途中反复触发数据过滤）
    @State private var previewFilter: ClipboardFilter?
    /// 是否正按在游标本体上（按下即成立，无需移动，游标据此立刻放大）
    @State private var isPressingCursor: Bool = false
    /// 本次按压是否已开始处理（用于在 onChanged 中只做一次落点判定）
    @State private var hasBegunPress: Bool = false

    @Environment(\.colorScheme) private var colorScheme

    /// 轨道坐标空间名称
    private static let trackCoordinateSpace = "filterSegmentedTrack"

    public init(
        selectedFilter: Binding<ClipboardFilter>,
        filterCounts: [ClipboardFilter: Int] = [:],
        onSelect: @escaping (ClipboardFilter) -> Void = { _ in }
    ) {
        self._selectedFilter = selectedFilter
        self.filterCounts = filterCounts
        self.onSelect = onSelect
    }

    /// 视觉上应当被高亮的分类（拖拽过程中优先反映预览态）
    private var highlightedFilter: ClipboardFilter {
        previewFilter ?? selectedFilter
    }

    public var body: some View {
        HStack {
            Spacer()

            ZStack(alignment: .topLeading) {
                // 1. 游标浮层：位于文字之下
                cursorLayer

                // 2. 分段文字层：始终压在游标之上，保证任何时刻都清晰可读
                segmentsStack
            }
            .coordinateSpace(name: Self.trackCoordinateSpace)
            .onPreferenceChange(SegmentFramesPreferenceKey.self) { frames in
                segmentFrames = frames
            }
            .padding(3)
            .modifier(SegmentedTrackGlassBackground(colorScheme: colorScheme))
            .contentShape(Capsule())
            .gesture(cursorPointerGesture)

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 2)
    }

    // MARK: - 游标浮层

    /// 游标当前应处的几何位置：拖拽时跟手，其余时候贴合选中分段
    private var cursorFrame: CGRect? {
        guard let highlightedFrame = segmentFrames[highlightedFilter] else { return nil }
        guard let centerX = draggingCursorCenterX else { return highlightedFrame }

        // 跟手拖拽：游标中心跟随指针，并约束在轨道两端之内
        let allFrames = segmentFrames.values
        guard let leftBound = allFrames.map(\.minX).min(),
              let rightBound = allFrames.map(\.maxX).max() else { return highlightedFrame }

        let width = highlightedFrame.width
        let clampedCenter = min(max(centerX, leftBound + width / 2), rightBound - width / 2)

        return CGRect(
            x: clampedCenter - width / 2,
            y: highlightedFrame.minY,
            width: width,
            height: highlightedFrame.height
        )
    }

    @ViewBuilder
    private var cursorLayer: some View {
        if let frame = cursorFrame {
            // 不加隐式动画：切换与吸附的弹簧动画由 withAnimation 显式驱动，
            // 而拖拽途中游标必须实时跟手，任何插值都会让它「拖泥带水」。
            SegmentCursorShape(
                // 按在游标上即刻放大，不必等到真正产生位移
                isDragging: isPressingCursor,
                colorScheme: colorScheme
            )
            .frame(width: frame.width, height: frame.height)
            .offset(x: frame.minX, y: frame.minY)
        }
    }

    // MARK: - 拖拽

    /// 分段控制器的统一指针手势：点击与拖拽由同一个手势处理
    ///
    /// 使用 `minimumDistance: 0` 是关键——只有这样按下的瞬间就能收到回调，
    /// 让游标立刻放大；若要求先位移若干点才触发，按下到放大之间会有一段空档，
    /// 观感就成了「按住之后才慢慢胀大」，与官方按下即响应的手感不符。
    private var cursorPointerGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.trackCoordinateSpace))
            .onChanged { value in
                // 落点判定每次按压只做一次：按在游标本体上才进入可拖拽状态
                if !hasBegunPress {
                    hasBegunPress = true
                    let pressedOnCursor = segmentFrames[selectedFilter]?
                        .insetBy(dx: -2, dy: -2)
                        .contains(value.startLocation) ?? false

                    withAnimation(.spring(response: 0.2, dampingFraction: 0.75)) {
                        isPressingCursor = pressedOnCursor
                    }
                }

                guard isPressingCursor else { return }
                draggingCursorCenterX = value.location.x
                previewFilter = nearestFilter(toX: value.location.x)
            }
            .onEnded { value in
                let movedDistance = hypot(value.translation.width, value.translation.height)

                // 位移极小视作点击：选中落点所在的分段；否则按拖拽吸附到最近分段
                let target: ClipboardFilter? = (isPressingCursor && movedDistance > 4)
                    ? nearestFilter(toX: value.location.x)
                    : filterAt(x: value.location.x)

                // 必须在修改前捕获，否则下方判断恒为假、回调永远不会发出
                let resolved = target ?? selectedFilter
                let didChangeSelection = selectedFilter != resolved

                withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
                    draggingCursorCenterX = nil
                    previewFilter = nil
                    isPressingCursor = false
                    if didChangeSelection {
                        selectedFilter = resolved
                    }
                }
                hasBegunPress = false

                if didChangeSelection {
                    onSelect(resolved)
                }
            }
    }

    /// 找出中心距给定横坐标最近的分段
    private func nearestFilter(toX x: CGFloat) -> ClipboardFilter? {
        segmentFrames
            .min { abs($0.value.midX - x) < abs($1.value.midX - x) }?
            .key
    }

    /// 找出横坐标落在其水平范围内的分段
    private func filterAt(x: CGFloat) -> ClipboardFilter? {
        segmentFrames.first { $0.value.minX <= x && x <= $0.value.maxX }?.key
    }

    // MARK: - 分段文字层

    private var segmentsStack: some View {
        HStack(spacing: 2) {
            ForEach(ClipboardFilter.allCases) { filter in
                let isHighlighted = highlightedFilter == filter
                let isHovered = hoveredFilter == filter

                // 这里刻意不使用 Button：点击与拖拽统一交由轨道上的单一手势处理，
                // 若再套一层 Button，松手时会与手势的点击判定重复触发选中。
                segmentLabel(filter: filter, isHighlighted: isHighlighted)
                    // 横向内边距由 12 收紧到 9：九个分段合计可省下约 54pt，
                    // 正是这点余量把标题从「…」里救回来
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(
                        // 未选中分段的悬停微光；选中态的底色由下层游标负责
                        Capsule()
                            .fill(
                                Color.primary.opacity(
                                    (!isHighlighted && isHovered)
                                        ? (colorScheme == .dark ? 0.06 : 0.03)
                                        : 0.0
                                )
                            )
                    )
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: SegmentFramesPreferenceKey.self,
                                value: [filter: proxy.frame(in: .named(Self.trackCoordinateSpace))]
                            )
                        }
                    )
                    .contentShape(Capsule())
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel(Text(filter.title))
                    .id(filter)
                    .onHover { hovering in
                        withAnimation(.easeInOut(duration: 0.12)) {
                            if hovering {
                                self.hoveredFilter = filter
                            } else if self.hoveredFilter == filter {
                                self.hoveredFilter = nil
                            }
                        }
                    }
            }
        }
    }

    /// 单个分段的文字与计数标签
    ///
    /// 全部文字一律 `fixedSize()`：九个分类在 720pt 宽的面板里本就吃紧，
    /// 一旦 HStack 判定空间不足就会挑几个分段把标题压成「…」，
    /// 而分类名是功能标识，宁可整体更紧凑也不能被截断。
    private func segmentLabel(filter: ClipboardFilter, isHighlighted: Bool) -> some View {
        let itemCount = filterCounts[filter] ?? 0

        return HStack(spacing: 3) {
            Text(filter.title)
                .font(.system(size: 12.5, weight: isHighlighted ? .medium : .regular))
                .foregroundColor(isHighlighted ? .primary : .secondary)
                .fixedSize()

            if itemCount > 0 {
                Text("\(itemCount)")
                    .font(.system(size: 10, weight: isHighlighted ? .semibold : .regular))
                    .foregroundColor(isHighlighted ? .primary.opacity(0.8) : .secondary.opacity(0.7))
                    .fixedSize()
                    .padding(.horizontal, 3.5)
                    .padding(.vertical, 0.5)
                    .background(
                        Capsule()
                            .fill(isHighlighted ? Color.primary.opacity(0.08) : Color.primary.opacity(0.04))
                    )
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

/// 分段选中游标本体
///
/// 对齐 macOS 26 活动监视器分段控制器的官方行为：
/// - **静止与点击切换时**是一枚浅灰实心胶囊，安静地待在轨道内，不使用任何玻璃；
/// - **仅在按住拖拽时**才「拈起」为一块液态玻璃：显著放大到溢出轨道上下边界，
///   `.regular` 厚材质带来内部通透、边缘环绕彩虹色散的镜面折射，并投下柔和阴影。
///
/// 两种形态以交叉淡入淡出切换而非条件分支，既不会重建视图结构，
/// 过渡也更柔和、不突兀。组件内部的动画只作用于自身缩放与透明度，
/// 不会波及调用方用于跟手定位的 offset。
private struct SegmentCursorShape: View {
    /// 是否正被拖拽（拖拽时才化为放大的液态玻璃）
    let isDragging: Bool
    /// 当前明暗外观
    let colorScheme: ColorScheme

    /// 拖拽时的放大倍率
    ///
    /// 取自对官方录屏的逐帧测算：静止游标高约 44pt、轨道内高约 71pt，
    /// 拖拽时实体放大到接近轨道高度，再由玻璃自身的色散光晕向外溢出。
    private static let draggingScale: CGFloat = 1.38

    /// 静止态的浅灰实心游标填充色
    private var idleFillColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.18)
            : Color.black.opacity(0.075)
    }

    var body: some View {
        ZStack {
            // 1. 静止 / 点击切换：浅灰实心胶囊
            Capsule()
                .fill(idleFillColor)
                .shadow(
                    color: Color.black.opacity(colorScheme == .dark ? 0.2 : 0.03),
                    radius: 1,
                    x: 0,
                    y: 1
                )
                .opacity(isDragging ? 0.0 : 1.0)

            // 2. 拖拽：放大的液态玻璃
            draggingGlassCursor
                .opacity(isDragging ? 1.0 : 0.0)
        }
        .scaleEffect(isDragging ? Self.draggingScale : 1.0)
        .animation(.spring(response: 0.32, dampingFraction: 0.72), value: isDragging)
    }

    @ViewBuilder
    private var draggingGlassCursor: some View {
        if #available(macOS 26.0, *) {
            Capsule()
                .fill(Color.clear)
                .glassEffect(.regular.interactive(), in: .capsule)
                .shadow(
                    color: Color.black.opacity(colorScheme == .dark ? 0.34 : 0.15),
                    radius: 9,
                    x: 0,
                    y: 3
                )
        } else {
            // 旧系统没有液态玻璃，拖拽时以更实的填充与更明显的投影表达「浮起」
            Capsule()
                .fill(
                    colorScheme == .dark
                        ? Color.white.opacity(0.26)
                        : Color.white.opacity(0.92)
                )
                .shadow(
                    color: Color.black.opacity(colorScheme == .dark ? 0.3 : 0.12),
                    radius: 6,
                    x: 0,
                    y: 2
                )
        }
    }
}

/// 分段控制器底槽轨道背景
///
/// 刻意**不使用**液态玻璃：Apple 明确不建议玻璃套玻璃，
/// 且底槽若也是玻璃，上方的游标折射到的就只是另一块玻璃，
/// 边缘色散与镜面反射会被显著削弱。让底槽退为半透明轨道，
/// 游标才能折射到真实的窗口内容与桌面背景，呈现官方那种通透的玻璃质感。
private struct SegmentedTrackGlassBackground: ViewModifier {
    /// 当前明暗外观
    let colorScheme: ColorScheme

    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    // 1. 外层全景连续圆角大胶囊底槽轨道
                    Capsule()
                        .fill(
                            colorScheme == .dark
                                ? Color.white.opacity(0.06)
                                : Color.white.opacity(0.55)
                        )

                    // 2. 外层微细轮廓边框
                    Capsule()
                        .strokeBorder(
                            colorScheme == .dark
                                ? Color.white.opacity(0.12)
                                : Color.black.opacity(0.08),
                            lineWidth: 0.8
                        )
                }
            )
    }
}
