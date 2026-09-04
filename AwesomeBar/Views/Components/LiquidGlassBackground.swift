import SwiftUI
import AppKit

/// 面板主背景液态玻璃组件
///
/// - macOS 26 Tahoe 及以上：使用 Apple 原生 NSGlassEffectView 真·液态玻璃，
///   具备实时镜面折射、边缘光学畸变与动态高光，随桌面背景实时反应。
/// - macOS 25 及以下：自动回退到 NSVisualEffectView 高斯模糊 + 纯色微透方案。
public struct LiquidGlassBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    /// 连续大圆角半径
    public var cornerRadius: CGFloat

    public init(cornerRadius: CGFloat = 24) {
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        if #available(macOS 26.0, *) {
            // 原生液态玻璃：系统自行处理材质、折射与明暗自适应，无需任何手工填充与描边
            NativeGlassEffectView(cornerRadius: cornerRadius, style: .regular)
        } else {
            legacyGlassBody
        }
    }

    /// macOS 25 及以下的传统磨砂玻璃回退实现
    private var legacyGlassBody: some View {
        let roundedShape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        return ZStack {
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
