import Foundation
import AppKit

/// 物理拖拽释放运动信息结构体（包含速度与加速度）
public struct DragPhysicsReleaseInfo {
    /// 释放时的最终窗口几何外框
    public let finalFrame: NSRect
    /// 释放瞬间的横向速度（像素/秒，> 0 表示向右甩，< 0 表示向左甩）
    public let velocityX: CGFloat
    /// 释放瞬间的纵向速度（像素/秒）
    public let velocityY: CGFloat
    /// 释放瞬间的横向加速度（像素/秒²）
    public let accelerationX: CGFloat
}

/// 自定义透明液态玻璃 NSPanel 浮动面板子类（支持物理运动学加速度与速度追踪、中文输入法 IME 组合态智能放行、原生安全窗口拖拽移动、高优先全局键盘拦截、ProMotion 120Hz 硬件加速与异步图层绘制）
public final class CustomGlassPanel: NSPanel {
    /// 键盘按键事件前置拦截器（返回 true 表示已消费事件，阻断向下传递）
    public var onKeyDownInterceptor: ((NSEvent) -> Bool)?
    /// 拖拽开始回调
    public var onDragStarted: ((CustomGlassPanel) -> Void)?
    /// 窗口拖拽释放完成后的物理运动学回调处理闭包（用于物理加速度吸附判定）
    public var onDragEndedWithPhysics: ((CustomGlassPanel, DragPhysicsReleaseInfo) -> Void)?
    /// 常规拖拽结束回调
    public var onDragFinished: ((CustomGlassPanel) -> Void)?
    
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
    
    /// 支持在非文字输入和非按钮等空白背景区域按住鼠标进行带物理运动学计算的窗口拖拽移动
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
        
        // 1. 触发拖拽开始回调
        self.onDragStarted?(self)
        
        let initialWindowOrigin = self.frame.origin
        let initialMouseLocation = NSEvent.mouseLocation
        
        struct MotionSample {
            let point: NSPoint
            let time: Date
        }
        
        var samples: [MotionSample] = [MotionSample(point: initialMouseLocation, time: Date())]
        var hasMoved = false
        
        // 2. 连续跟踪鼠标拖拽轨迹并计算实时物理运动参数
        while true {
            guard let nextEvent = self.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) else { break }
            
            if nextEvent.type == .leftMouseDragged {
                let currentMouseLocation = NSEvent.mouseLocation
                let deltaX = currentMouseLocation.x - initialMouseLocation.x
                let deltaY = currentMouseLocation.y - initialMouseLocation.y
                
                if abs(deltaX) > 2 || abs(deltaY) > 2 {
                    hasMoved = true
                }
                
                let newOrigin = NSPoint(x: initialWindowOrigin.x + deltaX, y: initialWindowOrigin.y + deltaY)
                self.setFrameOrigin(newOrigin)
                
                let now = Date()
                samples.append(MotionSample(point: currentMouseLocation, time: now))
                // 仅保留最近 120ms 内的运动采样，以便精准计算释放瞬间的真实速度与加速度
                samples.removeAll { now.timeIntervalSince($0.time) > 0.12 }
            } else if nextEvent.type == .leftMouseUp {
                break
            }
        }
        
        // 3. 计算松手瞬间的横向速度 (Velocity) 与横向加速度 (Acceleration)
        var velocityX: CGFloat = 0
        var velocityY: CGFloat = 0
        var accelerationX: CGFloat = 0
        
        if hasMoved && samples.count >= 2, let first = samples.first, let last = samples.last {
            let dt = CGFloat(max(0.008, last.time.timeIntervalSince(first.time)))
            velocityX = (last.point.x - first.point.x) / dt
            velocityY = (last.point.y - first.point.y) / dt
            
            if samples.count >= 3 {
                let mid = samples[samples.count / 2]
                let dt1 = CGFloat(max(0.005, mid.time.timeIntervalSince(first.time)))
                let dt2 = CGFloat(max(0.005, last.time.timeIntervalSince(mid.time)))
                let v1 = (mid.point.x - first.point.x) / dt1
                let v2 = (last.point.x - mid.point.x) / dt2
                accelerationX = (v2 - v1) / dt2
            }
        }
        
        let releaseInfo = DragPhysicsReleaseInfo(
            finalFrame: self.frame,
            velocityX: velocityX,
            velocityY: velocityY,
            accelerationX: accelerationX
        )
        
        self.onDragEndedWithPhysics?(self, releaseInfo)
        self.onDragFinished?(self)
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
