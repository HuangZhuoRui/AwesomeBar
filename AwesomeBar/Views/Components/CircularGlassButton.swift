import SwiftUI
import AppKit

/// Apple 液态玻璃纯色圆形功能按钮组件（纯色极简设计语言，完全去除渐变）
public struct CircularGlassButton: View {
    /// SF Symbol 系统图标名称
    public let iconName: String
    /// 按钮直径尺寸（默认 34px）
    public let size: CGFloat
    /// 图标字体字号
    public let iconSize: CGFloat
    /// 是否处于激活高亮状态（如：置顶中、搜索展开中）
    public let isActive: Bool
    /// 激活时的高亮强调色（默认系统主前景色）
    public let activeTintColor: Color
    /// 鼠标悬停提示文本
    public let helpText: String
    /// 点击触发动作
    public let action: () -> Void
    
    @State private var isHovered: Bool = false
    @Environment(\.colorScheme) private var colorScheme
    
    public init(
        iconName: String,
        size: CGFloat = 34,
        iconSize: CGFloat = 13,
        isActive: Bool = false,
        activeTintColor: Color = .primary,
        helpText: String = "",
        action: @escaping () -> Void
    ) {
        self.iconName = iconName
        self.size = size
        self.iconSize = iconSize
        self.isActive = isActive
        self.activeTintColor = activeTintColor
        self.helpText = helpText
        self.action = action
    }
    
    public var body: some View {
        Button(action: action) {
            if #available(macOS 26.0, *) {
                nativeGlassContent
            } else {
                legacyGlassContent
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            self.isHovered = hovering
        }
        .help(helpText)
    }

    // MARK: - macOS 26 原生液态玻璃按钮

    /// 原生液态玻璃按钮内容（.interactive() 提供按压实时形变、高光跟随与弹性回弹）
    @available(macOS 26.0, *)
    private var nativeGlassContent: some View {
        Image(systemName: iconName)
            .font(.system(size: iconSize, weight: isActive ? .bold : .medium))
            .foregroundStyle(isActive ? AnyShapeStyle(activeTintColor) : AnyShapeStyle(.primary))
            .frame(width: size, height: size)
            .glassEffect(
                isActive
                    ? .regular.tint(activeTintColor.opacity(0.28)).interactive()
                    : .regular.interactive(),
                in: .circle
            )
            .animation(.spring(response: 0.28, dampingFraction: 0.8), value: isActive)
    }

    // MARK: - macOS 25 及以下传统磨砂回退实现

    private var legacyGlassContent: some View {
        ZStack {
            // 1. 纯色背景填充（无渐变）
            Circle()
                .fill(
                    isActive
                        ? activeTintColor.opacity(colorScheme == .dark ? 0.25 : 0.12)
                        : (colorScheme == .dark
                            ? Color.white.opacity(isHovered ? 0.16 : 0.08)
                            : Color.black.opacity(isHovered ? 0.08 : 0.04))
                )

            // 2. 纯色精细边缘描边（无渐变）
            Circle()
                .strokeBorder(
                    isActive
                        ? activeTintColor.opacity(colorScheme == .dark ? 0.50 : 0.25)
                        : (colorScheme == .dark
                            ? Color.white.opacity(isHovered ? 0.35 : 0.14)
                            : Color.black.opacity(isHovered ? 0.16 : 0.08)),
                    lineWidth: 1.0
                )

            // 3. 核心功能图标
            Image(systemName: iconName)
                .font(.system(size: iconSize, weight: isActive ? .bold : .medium))
                .foregroundColor(
                    isActive
                        ? activeTintColor
                        : (colorScheme == .dark
                            ? Color.white.opacity(isHovered ? 1.0 : 0.85)
                            : Color.primary.opacity(isHovered ? 1.0 : 0.75))
                )
        }
        .frame(width: size, height: size)
        .shadow(
            color: Color.black.opacity(colorScheme == .dark ? 0.15 : 0.04),
            radius: isHovered ? 3 : 1.5,
            x: 0,
            y: 1
        )
        .scaleEffect(isHovered ? 1.05 : 1.0)
        .animation(.spring(response: 0.24, dampingFraction: 0.75), value: isHovered)
        .animation(.spring(response: 0.28, dampingFraction: 0.8), value: isActive)
    }
}
