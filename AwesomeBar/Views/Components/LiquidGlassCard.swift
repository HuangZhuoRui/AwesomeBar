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
