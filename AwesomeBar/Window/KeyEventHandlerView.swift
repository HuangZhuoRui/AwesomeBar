import SwiftUI
import AppKit

/// 键盘方向键、回车键与数字快捷键全局事件捕获器（基于 NSView 桥接）
public struct KeyEventHandlerView: NSViewRepresentable {
    /// 向上箭头触发回调
    public var onArrowUp: () -> Void
    /// 向下箭头触发回调
    public var onArrowDown: () -> Void
    /// 回车键触发回调
    public var onReturn: () -> Void
    /// 空格键触发回调
    public var onSpace: () -> Void
    /// ⌘+数字键 (1-9) 触发回调
    public var onNumberKey: (Int) -> Void
    /// Esc 键触发回调
    public var onEscape: () -> Void
    
    public init(
        onArrowUp: @escaping () -> Void,
        onArrowDown: @escaping () -> Void,
        onReturn: @escaping () -> Void,
        onSpace: @escaping () -> Void,
        onNumberKey: @escaping (Int) -> Void,
        onEscape: @escaping () -> Void
    ) {
        self.onArrowUp = onArrowUp
        self.onArrowDown = onArrowDown
        self.onReturn = onReturn
        self.onSpace = onSpace
        self.onNumberKey = onNumberKey
        self.onEscape = onEscape
    }
    
    public func makeNSView(context: Context) -> KeyCaptureNSView {
        let view = KeyCaptureNSView()
        view.onArrowUp = onArrowUp
        view.onArrowDown = onArrowDown
        view.onReturn = onReturn
        view.onSpace = onSpace
        view.onNumberKey = onNumberKey
        view.onEscape = onEscape
        return view
    }
    
    public func updateNSView(_ nsView: KeyCaptureNSView, context: Context) {
        nsView.onArrowUp = onArrowUp
        nsView.onArrowDown = onArrowDown
        nsView.onReturn = onReturn
        nsView.onSpace = onSpace
        nsView.onNumberKey = onNumberKey
        nsView.onEscape = onEscape
    }
    
    /// 底层处理键盘事件的 NSView 实现类
    public final class KeyCaptureNSView: NSView {
        var onArrowUp: (() -> Void)?
        var onArrowDown: (() -> Void)?
        var onReturn: (() -> Void)?
        var onSpace: (() -> Void)?
        var onNumberKey: ((Int) -> Void)?
        var onEscape: (() -> Void)?
        
        public override var acceptsFirstResponder: Bool {
            return true
        }
        
        public override func keyDown(with event: NSEvent) {
            switch event.keyCode {
            case 126: // 向上方向键
                onArrowUp?()
            case 125: // 向下方向键
                onArrowDown?()
            case 36: // 回车 Enter 键
                onReturn?()
            case 49: // 空格 Space 键（在按住 Command/Control 时触发）
                if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control) {
                    onSpace?()
                } else {
                    super.keyDown(with: event)
                }
            case 53: // Esc 退出键
                onEscape?()
            case 18...21, 23, 22, 26, 28, 25: // ⌘+1 至 ⌘+9 直选快捷键
                if event.modifierFlags.contains(.command) {
                    let keyMapping: [UInt16: Int] = [
                        18: 1, 19: 2, 20: 3, 21: 4, 23: 5,
                        22: 6, 26: 7, 28: 8, 25: 9
                    ]
                    if let numberValue = keyMapping[event.keyCode] {
                        onNumberKey?(numberValue)
                        return
                    }
                }
                super.keyDown(with: event)
            default:
                super.keyDown(with: event)
            }
        }
    }
}
