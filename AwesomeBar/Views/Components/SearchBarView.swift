import SwiftUI
import AppKit

/// 主界面顶部 Apple 液态玻璃灵动搜索输入栏组件（纯色极简设计，完全去除渐变）
public struct SearchBarView: View {
    /// 绑定的搜索输入文本
    @Binding public var searchText: String
    /// 是否自动获得焦点
    public var autoFocus: Bool
    /// 清空搜索时的回调处理
    public var onClear: () -> Void
    /// 焦点控制状态
    @FocusState private var isFieldFocused: Bool
    @Environment(\.colorScheme) private var colorScheme
    
    public init(
        searchText: Binding<String>,
        autoFocus: Bool = true,
        onClear: @escaping () -> Void = {}
    ) {
        self._searchText = searchText
        self.autoFocus = autoFocus
        self.onClear = onClear
    }
    
    public var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(isFieldFocused ? .primary : .secondary)
                .allowsHitTesting(false)
            
            TextField("搜索剪贴历史、代码、链接、应用...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .regular))
                .focused($isFieldFocused)
            
            if !searchText.isEmpty {
                Button(action: {
                    searchText = ""
                    onClear()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary.opacity(0.8))
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .scale))
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(
            ZStack {
                // 1. 纯色背景填充（无渐变）
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .fill(
                        colorScheme == .dark
                            ? Color.white.opacity(isFieldFocused ? 0.14 : 0.08)
                            : (isFieldFocused ? Color.white.opacity(0.95) : Color.black.opacity(0.045))
                    )
                
                // 2. 纯色边框描边（无渐变）
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .strokeBorder(
                        colorScheme == .dark
                            ? Color.white.opacity(isFieldFocused ? 0.40 : 0.15)
                            : (isFieldFocused ? Color.black.opacity(0.18) : Color.black.opacity(0.08)),
                        lineWidth: 1.0
                    )
            }
        )
        .shadow(
            color: Color.black.opacity(colorScheme == .dark ? (isFieldFocused ? 0.25 : 0.12) : (isFieldFocused ? 0.06 : 0.02)),
            radius: isFieldFocused ? 3 : 1.5,
            x: 0,
            y: 1
        )
        .animation(.spring(response: 0.28, dampingFraction: 0.8), value: isFieldFocused)
        .onAppear {
            if autoFocus {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.isFieldFocused = true
                }
            }
        }
    }
}
