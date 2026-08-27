import SwiftUI
import AppKit

/// Apple 液态玻璃纯色磨砂主背景组件（纯色极简设计语言，彻底去除渐变，纯净 24px 连续大圆角）
public struct LiquidGlassBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    /// 连续大圆角半径
    public var cornerRadius: CGFloat
    
    public init(cornerRadius: CGFloat = 24) {
        self.cornerRadius = cornerRadius
    }
    
    public var body: some View {
        let roundedShape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        
        ZStack {
            // 1. 底层硬件高斯模糊材质（内置连续大圆角硬件裁剪）
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow, cornerRadius: cornerRadius)
            
            // 2. 纯色背景填充（浅色纯白微透，深色深灰微透，完全无渐变）
            roundedShape
                .fill(
                    colorScheme == .dark
                        ? Color(NSColor.windowBackgroundColor).opacity(0.80)
                        : Color.white.opacity(0.88)
                )
            
            // 3. 纯色极细边缘描边（纯色无渐变）
            roundedShape
                .strokeBorder(
                    colorScheme == .dark
                        ? Color.white.opacity(0.12)
                        : Color.white.opacity(0.80),
                    lineWidth: 1.0
                )
        }
        .clipShape(roundedShape)
    }
}
