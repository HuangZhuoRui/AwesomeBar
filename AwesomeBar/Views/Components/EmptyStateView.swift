import SwiftUI

/// 剪贴板记录为空时的占位状态视图组件（纯展示型组件，禁用文本拖拽与命中）
public struct EmptyStateView: View {
    /// 当前搜索关键词
    public let searchText: String
    /// 当前选中的分类过滤器
    public let selectedFilter: ClipboardFilter
    
    public init(searchText: String, selectedFilter: ClipboardFilter) {
        self.searchText = searchText
        self.selectedFilter = selectedFilter
    }
    
    public var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.primary.opacity(0.04))
                    .frame(width: 68, height: 68)
                
                Image(systemName: selectedFilter == .pinned ? "pin.slash" : "clipboard")
                    .font(.system(size: 28, weight: .light))
                    .foregroundColor(.secondary)
            }
            
            Text(emptyStateTitle)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.primary)
            
            Text("复制任何文本、图片、代码或链接，将自动在此记录")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .allowsHitTesting(false)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 40)
    }
    
    /// 根据搜索和过滤状态动态计算占位标题
    private var emptyStateTitle: String {
        if !searchText.isEmpty {
            return "未找到与「\(searchText)」匹配的内容"
        }
        if selectedFilter == .pinned {
            return "暂无置顶记录"
        }
        return "剪贴板历史为空"
    }
}
