import SwiftUI

/// 剪贴板分类分段控制器组件（1:1 像素级复刻 macOS 原生分段大胶囊控制器，全宽绝对居中对齐）
public struct FilterPillView: View {
    /// 绑定的当前选中的分类
    @Binding public var selectedFilter: ClipboardFilter
    /// 各分类下的条目数量映射
    public var filterCounts: [ClipboardFilter: Int]
    /// 选中分类变更时的回调处理
    public var onSelect: (ClipboardFilter) -> Void
    
    /// 当前鼠标悬停的分类
    @State private var hoveredFilter: ClipboardFilter?
    @Namespace private var segmentAnimationNamespace
    @Environment(\.colorScheme) private var colorScheme
    
    public init(
        selectedFilter: Binding<ClipboardFilter>,
        filterCounts: [ClipboardFilter: Int] = [:],
        onSelect: @escaping (ClipboardFilter) -> Void = { _ in }
    ) {
        self._selectedFilter = selectedFilter
        self.filterCounts = filterCounts
        self.onSelect = onSelect
    }
    
    public var body: some View {
        HStack {
            Spacer()
            
            HStack(spacing: 2) {
                ForEach(ClipboardFilter.allCases) { filter in
                    let isSelected = selectedFilter == filter
                    let isHovered = hoveredFilter == filter
                    let itemCount = filterCounts[filter] ?? 0
                    
                    Button(action: {
                        if selectedFilter != filter {
                            onSelect(filter)
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
                                selectedFilter = filter
                            }
                        }
                    }) {
                        HStack(spacing: 4) {
                            Text(filter.title)
                                .font(.system(size: 12.5, weight: isSelected ? .medium : .regular))
                                .foregroundColor(isSelected ? .primary : .secondary)
                            
                            if itemCount > 0 {
                                Text("\(itemCount)")
                                    .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                                    .foregroundColor(isSelected ? .primary.opacity(0.8) : .secondary.opacity(0.7))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 0.5)
                                    .background(
                                        Capsule()
                                            .fill(isSelected ? Color.primary.opacity(0.08) : Color.primary.opacity(0.04))
                                    )
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(
                            ZStack {
                                if isSelected {
                                    // macOS 官方原生选中项浅灰/高透胶囊游标（1:1 活动监视器样式）
                                    Capsule()
                                        .fill(
                                            colorScheme == .dark
                                                ? Color.white.opacity(0.18)
                                                : Color.black.opacity(0.075)
                                        )
                                        .shadow(
                                            color: Color.black.opacity(colorScheme == .dark ? 0.2 : 0.03),
                                            radius: 1,
                                            x: 0,
                                            y: 1
                                        )
                                        .matchedGeometryEffect(id: "ActiveSegmentedPill", in: segmentAnimationNamespace)
                                } else if isHovered {
                                    Capsule()
                                        .fill(Color.primary.opacity(colorScheme == .dark ? 0.06 : 0.03))
                                }
                            }
                        )
                    }
                    .id(filter)
                    .buttonStyle(.plain)
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
            .padding(3)
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
            
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 2)
    }
}
