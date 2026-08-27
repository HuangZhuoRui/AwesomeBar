import Foundation
import AppKit

/// 自定义透明液态玻璃 NSPanel 浮动面板子类（支持中文输入法 IME 组合态智能放行、原生安全窗口拖拽移动、高优先全局键盘拦截、ProMotion 120Hz 硬件加速与异步图层绘制）
public final class CustomGlassPanel: NSPanel {
    /// 键盘按键事件前置拦截器（返回 true 表示已消费事件，阻断向下传递）
    public var onKeyDownInterceptor: ((NSEvent) -> Bool)?
    
    public override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.contentView?.wantsLayer = true
        self.contentView?.layer?.drawsAsynchronously = true
    }
    
    /// 允许作为 Key 窗口以接收键盘焦点与快捷键
    public override var canBecomeKey: Bool {
        return true
    }
    
    /// 允许作为 Main 主窗口
    public override var canBecomeMain: Bool {
        return true
    }
    
    /// 检测当前系统输入法是否正处于拼音/日文等组合输入状态（未回车上屏或空格选字）
    public var isIMEComposing: Bool {
        if let textInputClient = self.firstResponder as? NSTextInputClient {
            return textInputClient.hasMarkedText()
        }
        return false
    }
    
    /// 支持在非文字输入和非按钮等空白背景区域按住鼠标进行窗口拖拽移动（100% 不破坏输入光标）
    public override func mouseDown(with event: NSEvent) {
        if let contentView = self.contentView {
            let locationInWindow = event.locationInWindow
            let hitView = contentView.hitTest(locationInWindow)
            
            // 如果命中输入框文字视图或控件，交由子视图处理正常交互
            if hitView is NSTextView || hitView is NSButton || hitView is NSControl {
                super.mouseDown(with: event)
                return
            }
        }
        
        // 在背景与非输入区域触发窗口原生拖动
        self.performDrag(with: event)
    }
    
    /// 全局事件分发总入口：优先判定输入法状态，非组合态时执行前置键盘事件拦截
    public override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown {
            // 当输入法正在输入拼音（Marked Text 组合态）时，完全放行给输入法引擎，绝不拦截回车/空格/数字/方向键
            if isIMEComposing {
                super.sendEvent(event)
                return
            }
            
            if let interceptor = onKeyDownInterceptor, interceptor(event) {
                return
            }
        }
        super.sendEvent(event)
    }
    
    /// 响应 Esc 取消操作，自动关闭面板
    public override func cancelOperation(_ sender: Any?) {
        FloatingPanelController.shared.hide()
    }
}
