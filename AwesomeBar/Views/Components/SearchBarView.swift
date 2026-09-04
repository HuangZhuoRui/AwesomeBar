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
        .modifier(SearchFieldGlassBackground(isFocused: isFieldFocused, colorScheme: colorScheme))
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

/// 搜索栏胶囊背景（macOS 26 原生液态玻璃，旧系统回退为纯色填充 + 描边）
private struct SearchFieldGlassBackground: ViewModifier {
    /// 输入框当前是否持有键盘焦点
    let isFocused: Bool
    /// 当前明暗外观
    let colorScheme: ColorScheme

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            // 玻璃自带材质与边缘光学，焦点态仅以一圈描边强化，确保无障碍下焦点依然清晰可辨
            content
                .glassEffect(.regular, in: .capsule)
                .overlay(
                    Capsule()
                        .strokeBorder(
                            Color.primary.opacity(isFocused ? 0.35 : 0.0),
                            lineWidth: 1.0
                        )
                )
        } else {
            content
                .background(
                    ZStack {
                        // 1. 纯色背景填充（无渐变）
                        RoundedRectangle(cornerRadius: 17, style: .continuous)
                            .fill(
                                colorScheme == .dark
                                    ? Color.white.opacity(isFocused ? 0.14 : 0.08)
                                    : (isFocused ? Color.white.opacity(0.95) : Color.black.opacity(0.045))
                            )

                        // 2. 纯色边框描边（无渐变）
                        RoundedRectangle(cornerRadius: 17, style: .continuous)
                            .strokeBorder(
                                colorScheme == .dark
                                    ? Color.white.opacity(isFocused ? 0.40 : 0.15)
                                    : (isFocused ? Color.black.opacity(0.18) : Color.black.opacity(0.08)),
                                lineWidth: 1.0
                            )
                    }
                )
                .shadow(
                    color: Color.black.opacity(
                        colorScheme == .dark
                            ? (isFocused ? 0.25 : 0.12)
                            : (isFocused ? 0.06 : 0.02)
                    ),
                    radius: isFocused ? 3 : 1.5,
                    x: 0,
                    y: 1
                )
        }
    }
}
