import SwiftUI
import AppKit

/// macOS 26 Tahoe 原生「液态玻璃」(Liquid Glass) 运行时能力探测
public enum LiquidGlassSupport {
    /// 当前系统是否支持 Apple 原生液态玻璃材质（macOS 26.0+）
    public static var isAvailable: Bool {
        if #available(macOS 26.0, *) {
            return true
        }
        return false
    }
}

/// 封装 macOS 26 原生 NSGlassEffectView 的 SwiftUI 液态玻璃组件
///
/// 与旧版 NSVisualEffectView（仅高斯模糊 + 材质染色）不同，NSGlassEffectView 由系统实时渲染，
/// 具备镜面折射（lensing）、边缘光学畸变、动态高光与随背景内容实时反应的特性，
/// 是 Apple 液态玻璃设计语言的官方实现。
@available(macOS 26.0, *)
public struct NativeGlassEffectView: NSViewRepresentable {
    /// 连续大圆角半径
    public var cornerRadius: CGFloat
    /// 玻璃染色（nil 表示不染色，保持纯净透明玻璃）
    public var tintColor: NSColor?
    /// 玻璃样式：.regular 标准玻璃（自适应背景明暗）；.clear 通透玻璃（更透，折射更强）
    public var style: NSGlassEffectView.Style

    public init(
        cornerRadius: CGFloat = 24,
        tintColor: NSColor? = nil,
        style: NSGlassEffectView.Style = .regular
    ) {
        self.cornerRadius = cornerRadius
        self.tintColor = tintColor
        self.style = style
    }

    public func makeNSView(context: Context) -> NSGlassEffectView {
        let glassView = NSGlassEffectView()
        glassView.cornerRadius = cornerRadius
        glassView.tintColor = tintColor
        glassView.style = style
        return glassView
    }

    public func updateNSView(_ nsView: NSGlassEffectView, context: Context) {
        nsView.cornerRadius = cornerRadius
        nsView.tintColor = tintColor
        nsView.style = style
    }
}
