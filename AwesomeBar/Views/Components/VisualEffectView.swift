import SwiftUI
import AppKit

/// 封装 macOS AppKit 原生 NSVisualEffectView 的 SwiftUI 模糊毛玻璃组件（原生支持连续大圆角裁剪）
public struct VisualEffectView: NSViewRepresentable {
    /// 毛玻璃材质类型（如：.hudWindow, .popover, .menu）
    public var material: NSVisualEffectView.Material
    /// 混合模式（如：.behindWindow）
    public var blendingMode: NSVisualEffectView.BlendingMode
    /// 激活状态（如：.active）
    public var state: NSVisualEffectView.State
    /// 连续大圆角半径
    public var cornerRadius: CGFloat
    
    public init(
        material: NSVisualEffectView.Material = .hudWindow,
        blendingMode: NSVisualEffectView.BlendingMode = .behindWindow,
        state: NSVisualEffectView.State = .active,
        cornerRadius: CGFloat = 24
    ) {
        self.material = material
        self.blendingMode = blendingMode
        self.state = state
        self.cornerRadius = cornerRadius
    }
    
    public func makeNSView(context: Context) -> NSVisualEffectView {
        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = material
        visualEffectView.blendingMode = blendingMode
        visualEffectView.state = state
        visualEffectView.wantsLayer = true
        visualEffectView.layer?.cornerRadius = cornerRadius
        visualEffectView.layer?.cornerCurve = .continuous
        visualEffectView.layer?.masksToBounds = true
        return visualEffectView
    }
    
    public func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
        nsView.wantsLayer = true
        nsView.layer?.cornerRadius = cornerRadius
        nsView.layer?.cornerCurve = .continuous
        nsView.layer?.masksToBounds = true
    }
}
