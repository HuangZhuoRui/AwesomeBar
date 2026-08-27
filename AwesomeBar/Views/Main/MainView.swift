import SwiftUI
import AppKit
import Combine

/// 水平方向切换动效朝向枚举
public enum HorizontalSlideDirection {
    /// 无水平位移（垂直上浮入场）
    case none
    /// 从右侧向左惯性滑入
    case fromRight
    /// 从左侧向右惯性滑入
    case fromLeft
}

/// 剪贴板主面板核心容器视图（订阅单一响应式数据流 ClipboardStore，支持居中标题、流体液态玻璃展开搜索、左右惯性位移、macOS 原生分段控制器与卡片默认均一态）
public struct MainView: View {
    /// 剪贴板单一响应式数据流状态中心
    @ObservedObject private var store = ClipboardStore.shared
    /// 全局用户偏好设置
    @ObservedObject private var applicationSettings = AppSettings.shared
    
    /// 搜索框输入的关键词
    @State private var searchKeyword: String = ""
    /// 搜索栏是否处于展开状态（默认静息居中）
    @State private var isSearchExpanded: Bool = false
    /// 当前选中的分类过滤器
    @State private var activeFilter: ClipboardFilter = .all
    /// 键盘导航当前选中的行索引（默认为 nil，所有卡片保持均一初始形态）
    @State private var selectedRowIndex: Int? = nil
    /// 当前正在深入检查与格式转换的条目
    @State private var inspectingClipboardItem: ClipboardItem?
    /// 是否在应用内弹出偏好设置浮层
    @State private var isSettingsSheetPresented: Bool = false
    /// 是否弹出清空历史确认浮层
    @State private var isClearConfirmationPresented: Bool = false
    /// 级联阶梯式瀑布流动画触发唯一标识
    @State private var cascadeTriggerId: UUID = UUID()
    /// 当前左右切换的方向
    @State private var slideDirection: HorizontalSlideDirection = .none
    /// 控制卡片逐个上浮滑入与归位的布尔动效开关
    @State private var animateCards: Bool = false
    
    @Environment(\.colorScheme) private var colorScheme
    
    public init() {}
    
    /// 从单一响应式数据流中瞬时检索符合分类与关键词的条目（零磁盘 I/O，极速渲染）
    private var displayedItems: [ClipboardItem] {
        return store.queryFilteredItems(filter: activeFilter, searchQuery: searchKeyword)
    }
    
    public var body: some View {
        ZStack {
            // 1. Apple 液态玻璃通透磨砂主背景
            LiquidGlassBackground(cornerRadius: 24)
            
            VStack(spacing: 0) {
                // 2. 顶部导航与搜索栏（支持居中标题向左流体展开搜索框、全套圆形液态玻璃按钮）
                HeaderBarView(
                    searchText: $searchKeyword,
                    isSearchExpanded: $isSearchExpanded,
                    settings: applicationSettings,
                    onClearSearch: {
                        selectedRowIndex = nil
                        slideDirection = .none
                        triggerCascadeStaggeredAnimation()
                    },
                    onTriggerClearHistory: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            isClearConfirmationPresented = true
                        }
                    },
                    onOpenSettings: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            isSettingsSheetPresented = true
                        }
                    }
                )
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 10)
                
                // 3. 分类分段控制器大胶囊栏（1:1 像素级复刻 macOS 原生分段控制器，绝对居中）
                FilterPillView(
                    selectedFilter: $activeFilter,
                    filterCounts: store.filterCounts
                ) { targetFilter in
                    selectedRowIndex = nil
                    if targetFilter != activeFilter {
                        let isMovingRight = targetFilter.orderIndex > activeFilter.orderIndex
                        self.slideDirection = isMovingRight ? .fromRight : .fromLeft
                        triggerCascadeStaggeredAnimation()
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 6)
                
                // 4. 核心列表区域或空状态占位（全无界通透渐变边缘，卡片默认均一样式）
                ZStack {
                    let items = displayedItems
                    if items.isEmpty {
                        EmptyStateView(
                            searchText: searchKeyword,
                            selectedFilter: activeFilter
                        )
                        .transition(.opacity)
                    } else {
                        buildItemsScrollView(itemsList: items)
                            .id(cascadeTriggerId)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                // 5. 底部统计与快捷键说明栏
                FooterBarView(itemCount: displayedItems.count)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
            }
            
            // 6. 详情检查与全能文本格式转换浮层弹窗
            if let item = inspectingClipboardItem {
                modalBackdropView {
                    inspectingClipboardItem = nil
                }
                
                DetailPreviewSheet(
                    item: item,
                    onClose: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            inspectingClipboardItem = nil
                        }
                    },
                    onPasteAndClose: { updatedItem in
                        withAnimation(.easeInOut(duration: 0.2)) {
                            inspectingClipboardItem = nil
                        }
                        PasteSimulator.shared.pasteItem(item: updatedItem)
                    }
                )
                .transition(.scale(scale: 0.95).combined(with: .opacity))
                .zIndex(100)
            }
            
            // 7. 应用内偏好设置浮层弹窗
            if isSettingsSheetPresented {
                modalBackdropView {
                    isSettingsSheetPresented = false
                }
                
                settingsModalOverlayView
                    .transition(.scale(scale: 0.95).combined(with: .opacity))
                    .zIndex(100)
            }
            
            // 8. 清空历史确认浮层弹窗
            if isClearConfirmationPresented {
                modalBackdropView {
                    isClearConfirmationPresented = false
                }
                
                clearConfirmationModalView
                    .transition(.scale(scale: 0.95).combined(with: .opacity))
                    .zIndex(100)
            }
        }
        .frame(width: 720, height: 490)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onAppear {
            slideDirection = .none
            isSearchExpanded = false
            selectedRowIndex = nil
            triggerCascadeStaggeredAnimation()
            setupGlobalKeyInterceptor()
        }
        .onReceive(NotificationCenter.default.publisher(for: .awesomeBarWindowDidAppear)) { _ in
            slideDirection = .none
            isSearchExpanded = false
            searchKeyword = ""
            selectedRowIndex = nil
            triggerCascadeStaggeredAnimation()
            setupGlobalKeyInterceptor()
        }
        .onChange(of: searchKeyword) { newKeyword in
            if !newKeyword.isEmpty && !isSearchExpanded {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                    isSearchExpanded = true
                }
            }
            selectedRowIndex = nil
            slideDirection = .none
            triggerCascadeStaggeredAnimation()
        }
    }
    
    // MARK: - 键盘高级拦截与导航逻辑
    
    /// 设置全局按键拦截器（解决焦点与全局快捷键调度）
    private func setupGlobalKeyInterceptor() {
        FloatingPanelController.shared.setKeyDownInterceptor { event in
            return handleGlobalKeyDown(event: event)
        }
    }
    
    /// 检测当前窗口是否正在进行拼音/日文等输入法组合输入
    private var isIMEComposing: Bool {
        if let window = NSApp.keyWindow ?? NSApp.mainWindow,
           let textInputClient = window.firstResponder as? NSTextInputClient {
            return textInputClient.hasMarkedText()
        }
        return false
    }
    
    /// 统一全局按键分发处理
    private func handleGlobalKeyDown(event: NSEvent) -> Bool {
        // 当用户正在输入法拼音组合打字时，所有按键（回车上屏、空格选字、数字、方向键）全部放行给输入法
        if isIMEComposing {
            return false
        }
        
        let isSearchEmpty = searchKeyword.isEmpty
        let isModalOpen = inspectingClipboardItem != nil || isSettingsSheetPresented || isClearConfirmationPresented
        let items = displayedItems
        let allFilters = ClipboardFilter.allCases
        
        switch event.keyCode {
        // 1. 空格键 (Space, keyCode 49)：搜索框为空且未展开时，对图片与文件/文档直接唤起 macOS 官方原生 Quick Look 预览
        case 49:
            if !isModalOpen && isSearchEmpty && !isSearchExpanded {
                let targetIndex = selectedRowIndex ?? 0
                if targetIndex >= 0 && targetIndex < items.count {
                    let targetItem = items[targetIndex]
                    if targetItem.effectiveType == .image || targetItem.effectiveType == .file {
                        QuickLookManager.shared.togglePreview(item: targetItem)
                        return true
                    }
                }
            }
            return false
            
        // 2. 左方向键 (Left Arrow, keyCode 123)：搜索框未输入且未开弹窗时向左切换分类
        case 123:
            if !isModalOpen && isSearchEmpty {
                let currentIndex = activeFilter.orderIndex
                let newIndex = (currentIndex - 1 + allFilters.count) % allFilters.count
                let targetFilter = allFilters[newIndex]
                
                selectedRowIndex = nil
                self.slideDirection = .fromLeft
                withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                    self.activeFilter = targetFilter
                }
                self.triggerCascadeStaggeredAnimation()
                return true
            }
            return false
            
        // 3. 右方向键 (Right Arrow, keyCode 124)：搜索框未输入且未开弹窗时向右切换分类
        case 124:
            if !isModalOpen && isSearchEmpty {
                let currentIndex = activeFilter.orderIndex
                let newIndex = (currentIndex + 1) % allFilters.count
                let targetFilter = allFilters[newIndex]
                
                selectedRowIndex = nil
                self.slideDirection = .fromRight
                withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                    self.activeFilter = targetFilter
                }
                self.triggerCascadeStaggeredAnimation()
                return true
            }
            return false
            
        // 4. Tab 键 (keyCode 48)：循环切换分类
        case 48:
            if !isModalOpen {
                let isShiftPressed = event.modifierFlags.contains(.shift)
                let currentIndex = activeFilter.orderIndex
                let newIndex = isShiftPressed
                    ? (currentIndex - 1 + allFilters.count) % allFilters.count
                    : (currentIndex + 1) % allFilters.count
                let targetFilter = allFilters[newIndex]
                
                selectedRowIndex = nil
                self.slideDirection = isShiftPressed ? .fromLeft : .fromRight
                withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                    self.activeFilter = targetFilter
                }
                self.triggerCascadeStaggeredAnimation()
                return true
            }
            return false
            
        // 5. 上方向键 (Up Arrow, keyCode 126)：向上移动高亮光标
        case 126:
            if !isModalOpen && !items.isEmpty {
                if let current = selectedRowIndex {
                    selectedRowIndex = max(0, current - 1)
                } else {
                    selectedRowIndex = max(0, items.count - 1)
                }
                return true
            }
            return false
            
        // 6. 下方向键 (Down Arrow, keyCode 125)：向下移动高亮光标
        case 125:
            if !isModalOpen && !items.isEmpty {
                if let current = selectedRowIndex {
                    selectedRowIndex = min(items.count - 1, current + 1)
                } else {
                    selectedRowIndex = 0
                }
                return true
            }
            return false
            
        // 7. 回车键 (Return / Enter, keyCode 36)：执行粘贴
        case 36:
            if !isModalOpen && !items.isEmpty {
                let targetIndex = selectedRowIndex ?? 0
                if targetIndex >= 0 && targetIndex < items.count {
                    PasteSimulator.shared.pasteItem(item: items[targetIndex])
                    return true
                }
            }
            return false
            
        // 8. Esc 键 (keyCode 53)：层级关闭
        case 53:
            if inspectingClipboardItem != nil {
                withAnimation { inspectingClipboardItem = nil }
                return true
            } else if isSettingsSheetPresented {
                withAnimation { isSettingsSheetPresented = false }
                return true
            } else if isClearConfirmationPresented {
                withAnimation { isClearConfirmationPresented = false }
                return true
            } else if !searchKeyword.isEmpty {
                searchKeyword = ""
                withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                    isSearchExpanded = false
                }
                return true
            } else if isSearchExpanded {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                    isSearchExpanded = false
                }
                return true
            } else if !applicationSettings.isPinnedToTop {
                FloatingPanelController.shared.hide()
                return true
            }
            return false
            
        // 9. ⌘1 ~ ⌘9 直选快捷键
        case 18...21, 23, 22, 26, 28, 25:
            if event.modifierFlags.contains(.command) {
                let keyMapping: [UInt16: Int] = [
                    18: 1, 19: 2, 20: 3, 21: 4, 23: 5,
                    22: 6, 26: 7, 28: 8, 25: 9
                ]
                if let numberValue = keyMapping[event.keyCode] {
                    let targetIndex = numberValue - 1
                    if targetIndex >= 0 && targetIndex < items.count {
                        PasteSimulator.shared.pasteItem(item: items[targetIndex])
                        return true
                    }
                }
            }
            return false
            
        default:
            // 任意普通输入键自动展开搜索框
            if !isSearchExpanded && !event.modifierFlags.contains(.command) && !event.modifierFlags.contains(.control) {
                if let characters = event.characters, !characters.isEmpty {
                    let firstScalar = characters.unicodeScalars.first
                    if let scalar = firstScalar, CharacterSet.alphanumerics.contains(scalar) {
                        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                            isSearchExpanded = true
                        }
                    }
                }
            }
            return false
        }
    }
    
    // MARK: - 辅助方法与子视图
    
    /// 触发方向性惯性位移与错落阶梯瀑布流逐张归位动效
    private func triggerCascadeStaggeredAnimation() {
        animateCards = false
        cascadeTriggerId = UUID()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                self.animateCards = true
            }
        }
    }
    
    private func modalBackdropView(onDismiss: @escaping () -> Void) -> some View {
        Color.black.opacity(0.3)
            .edgesIgnoringSafeArea(.all)
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    onDismiss()
                }
            }
    }
    
    private func buildItemsScrollView(itemsList: [ClipboardItem]) -> some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(itemsList) { item in
                        let itemIndex = itemsList.firstIndex(where: { $0.id == item.id }) ?? 0
                        let staggerDelay = Double(min(itemIndex, 7)) * 0.028
                        
                        // 计算起始方向性惯性偏移量
                        let initialOffsetX: CGFloat = {
                            switch slideDirection {
                            case .fromRight: return 38.0
                            case .fromLeft: return -38.0
                            case .none: return 0.0
                            }
                        }()
                        let initialOffsetY: CGFloat = slideDirection == .none ? 16.0 : 6.0
                        
                        ClipboardRowView(
                            item: item,
                            isSelected: selectedRowIndex == itemIndex,
                            index: itemIndex,
                            onCopyOnly: {
                                PasteSimulator.shared.copyToClipboard(item: item)
                            },
                            onSelectAndPaste: {
                                selectedRowIndex = itemIndex
                                PasteSimulator.shared.pasteItem(item: item)
                            },
                            onTogglePin: {
                                store.togglePin(id: item.id)
                                SoundManager.shared.playPinSound()
                            },
                            onToggleFavorite: {
                                store.toggleFavorite(id: item.id)
                            },
                            onDelete: {
                                withAnimation {
                                    store.deleteItem(id: item.id)
                                    SoundManager.shared.playDeleteSound()
                                }
                            },
                            onInspect: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                    inspectingClipboardItem = item
                                }
                            }
                        )
                        .id(item.id)
                        .offset(
                            x: animateCards ? 0 : initialOffsetX,
                            y: animateCards ? 0 : initialOffsetY
                        )
                        .opacity(animateCards ? 1.0 : 0.0)
                        .scaleEffect(animateCards ? 1.0 : 0.97)
                        .animation(
                            .spring(response: 0.38, dampingFraction: 0.82).delay(staggerDelay),
                            value: animateCards
                        )
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
            }
            .mask(
                LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: .black.opacity(0.15), location: 0.015),
                        .init(color: .black.opacity(0.65), location: 0.05),
                        .init(color: .black, location: 0.09),
                        .init(color: .black, location: 0.91),
                        .init(color: .black.opacity(0.65), location: 0.95),
                        .init(color: .black.opacity(0.15), location: 0.985),
                        .init(color: .clear, location: 1.0)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .onChange(of: selectedRowIndex) { newIndex in
                if let index = newIndex, index >= 0 && index < itemsList.count {
                    withAnimation(.easeInOut(duration: 0.1)) {
                        scrollProxy.scrollTo(itemsList[index].id, anchor: .center)
                    }
                }
            }
        }
    }
    
    // MARK: - 弹窗浮层组件
    
    private var settingsModalOverlayView: some View {
        VStack(spacing: 0) {
            HStack {
                Text("偏好设置")
                    .font(.system(size: 15, weight: .bold))
                Spacer()
                Button(action: {
                    withAnimation { isSettingsSheetPresented = false }
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            
            Divider()
                .opacity(0.3)
            
            SettingsView()
        }
        .frame(width: 520, height: 420)
        .background(LiquidGlassBackground(cornerRadius: 18))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
    
    private var clearConfirmationModalView: some View {
        VStack(spacing: 16) {
            Image(systemName: "trash.circle.fill")
                .font(.system(size: 40))
                .foregroundColor(.red)
            
            Text("清空剪贴板历史记录")
                .font(.system(size: 16, weight: .bold))
            
            Text("请选择清空范围。保留置顶将继续保留所有已固定与星标的重要记录。")
                .font(.system(size: 12.5))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
            
            HStack(spacing: 12) {
                Button("取消") {
                    withAnimation { isClearConfirmationPresented = false }
                }
                .buttonStyle(.bordered)
                
                Button("清除普通记录 (保留置顶)") {
                    store.clearAll(exceptPinned: true)
                    SoundManager.shared.playDeleteSound()
                    withAnimation { isClearConfirmationPresented = false }
                }
                .buttonStyle(.bordered)
                
                Button("全部清空 (彻底删除)") {
                    store.clearAll(exceptPinned: false)
                    SoundManager.shared.playDeleteSound()
                    withAnimation { isClearConfirmationPresented = false }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
        .padding(24)
        .frame(width: 440)
        .background(LiquidGlassBackground(cornerRadius: 18))
    }
}
