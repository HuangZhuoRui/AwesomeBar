import SwiftUI

/// 主界面顶部导航栏组件（标题严格相对于窗口总宽度居中，点击搜索时以 Apple 液态玻璃动效向左流体展开）
public struct HeaderBarView: View {
    /// 搜索框绑定的输入文本
    @Binding public var searchText: String
    /// 是否展开了搜索栏
    @Binding public var isSearchExpanded: Bool
    /// 置顶状态引用
    @ObservedObject public var settings: AppSettings
    /// 清空搜索回调
    public var onClearSearch: () -> Void
    /// 触发清空历史弹窗回调
    public var onTriggerClearHistory: () -> Void
    /// 打开偏好设置窗口回调
    public var onOpenSettings: () -> Void
    
    @Namespace private var headerAnimationNamespace
    @Environment(\.colorScheme) private var colorScheme
    
    public init(
        searchText: Binding<String>,
        isSearchExpanded: Binding<Bool>,
        settings: AppSettings,
        onClearSearch: @escaping () -> Void,
        onTriggerClearHistory: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void
    ) {
        self._searchText = searchText
        self._isSearchExpanded = isSearchExpanded
        self.settings = settings
        self.onClearSearch = onClearSearch
        self.onTriggerClearHistory = onTriggerClearHistory
        self.onOpenSettings = onOpenSettings
    }
    
    public var body: some View {
        ZStack {
            // MARK: 1. 绝对中心标题（静息状态下严格相对于整个 720px 窗口总宽度绝对居中）
            if !isSearchExpanded {
                Text("AwesomeBar")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .allowsHitTesting(false)
                    .matchedGeometryEffect(id: "HeaderAppNameTitle", in: headerAnimationNamespace)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            
            // MARK: 2. 水平内容层：展开时标题移至最左侧，右侧始终对齐功能圆形液态玻璃按钮群
            HStack(spacing: 12) {
                if isSearchExpanded {
                    Text("AwesomeBar")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                        .allowsHitTesting(false)
                        .matchedGeometryEffect(id: "HeaderAppNameTitle", in: headerAnimationNamespace)
                    
                    SearchBarView(
                        searchText: $searchText,
                        autoFocus: true,
                        onClear: {
                            onClearSearch()
                        }
                    )
                    .matchedGeometryEffect(id: "HeaderSearchBarCapsule", in: headerAnimationNamespace)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.95, anchor: .trailing).combined(with: .opacity),
                        removal: .scale(scale: 0.95, anchor: .trailing).combined(with: .opacity)
                    ))
                } else {
                    Spacer()
                }
                
                // 右侧功能按钮群：搜索、置顶、清空、设置
                actionButtonsGroup(isExpanded: isSearchExpanded)
                    .matchedGeometryEffect(id: "HeaderActionButtonsGroup", in: headerAnimationNamespace)
            }
        }
        .frame(height: 36)
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: isSearchExpanded)
    }
    
    // MARK: - 辅助子视图：液态玻璃圆形按钮组
    
    private func actionButtonsGroup(isExpanded: Bool) -> some View {
        HStack(spacing: 8) {
            // 1. 搜索圆形玻璃按钮
            CircularGlassButton(
                iconName: "magnifyingglass",
                isActive: isExpanded,
                activeTintColor: .primary,
                helpText: isExpanded ? "收起搜索 (Esc)" : "展开搜索 (点击或直接输入)"
            ) {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                    if isExpanded {
                        if !searchText.isEmpty {
                            searchText = ""
                            onClearSearch()
                        }
                        isSearchExpanded = false
                    } else {
                        isSearchExpanded = true
                    }
                }
            }
            
            // 2. 置顶图钉圆形玻璃按钮
            CircularGlassButton(
                iconName: settings.isPinnedToTop ? "pin.fill" : "pin",
                isActive: settings.isPinnedToTop,
                activeTintColor: .orange,
                helpText: settings.isPinnedToTop ? "取消置顶（失焦将自动收起）" : "钉在最上层（始终浮动显示）"
            ) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                    settings.isPinnedToTop.toggle()
                    SoundManager.shared.playPinSound()
                }
            }
            
            // 3. 清空历史圆形玻璃按钮
            CircularGlassButton(
                iconName: "trash",
                helpText: "清空剪贴板历史记录"
            ) {
                onTriggerClearHistory()
            }
            
            // 4. 便签模式圆形玻璃按钮
            CircularGlassButton(
                iconName: "note.text",
                helpText: "便签模式（小便签独立浮窗）"
            ) {
                StickyNoteWindowController.shared.toggle()
            }
            
            // 5. 打开偏好设置圆形玻璃按钮
            CircularGlassButton(
                iconName: "gearshape.fill",
                helpText: "偏好设置"
            ) {
                onOpenSettings()
            }
        }
    }
}
