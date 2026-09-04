import SwiftUI
import AppKit

/// Apple 液态玻璃卡片 ViewModifier 修饰器（120Hz ProMotion 极速硬件加速与极简高效渲染）
public struct LiquidGlassCard: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    /// 圆角弧度
    public var cornerRadius: CGFloat
    /// 是否处于激活或悬停高亮状态
    public var isHighlighted: Bool
    
    public init(cornerRadius: CGFloat = 16, isHighlighted: Bool = false) {
        self.cornerRadius = cornerRadius
        self.isHighlighted = isHighlighted
    }
    
    private var cardFillColor: Color {
        if colorScheme == .dark {
            return Color(NSColor.controlBackgroundColor).opacity(isHighlighted ? 0.65 : 0.35)
        } else {
            return isHighlighted ? Color.white.opacity(0.95) : Color.white.opacity(0.78)
        }
    }
    
    private var cardStrokeColor: Color {
        if colorScheme == .dark {
            return isHighlighted ? Color.white.opacity(0.4) : Color.white.opacity(0.12)
        } else {
            return isHighlighted ? Color.white.opacity(0.9) : Color.white.opacity(0.5)
        }
    }
    
    private var shadowOpacityValue: Double {
        if colorScheme == .dark {
            return isHighlighted ? 0.12 : 0.04
        } else {
            return isHighlighted ? 0.08 : 0.03
        }
    }
    
    /// 列表行卡片背景
    ///
    /// 这里**刻意不使用**液态玻璃：列表行属于「内容层」，Apple 人机界面指南建议玻璃用于浮在
    /// 内容之上的控制层。更重要的是，滚动列表里每行都做实时折射采样开销极大；而若按选中态
    /// 在「玻璃」与「纯色」两个分支间切换，SwiftUI 会判定为不同的视图结构并重建视图树，
    /// 滚动时随着悬停行不断变化，表现出来就是卡片「原地闪烁」而非平滑滚动。
    /// 因此这里始终采用同一套纯色卡片结构，仅让颜色与阴影随高亮状态变化。
    public func body(content: Content) -> some View {
        let continuousShape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        return content
            .background(
                continuousShape
                    .fill(cardFillColor)
            )
            .overlay(
                continuousShape
                    .strokeBorder(cardStrokeColor, lineWidth: isHighlighted ? 1.2 : 0.8)
            )
            .clipShape(continuousShape)
            .shadow(
                color: Color.black.opacity(shadowOpacityValue),
                radius: isHighlighted ? 5 : 2,
                x: 0,
                y: isHighlighted ? 2 : 1
            )
    }
}

extension View {
    /// 附加液态玻璃卡片容器背景与阴影效果（ProMotion 120Hz 极速优化版）
    /// - Parameters:
    ///   - cornerRadius: 圆角大小（默认 16px）
    ///   - isHighlighted: 是否处于高亮选中或悬停状态
    public func liquidGlassCard(cornerRadius: CGFloat = 16, isHighlighted: Bool = false) -> some View {
        modifier(LiquidGlassCard(cornerRadius: cornerRadius, isHighlighted: isHighlighted))
    }
}
