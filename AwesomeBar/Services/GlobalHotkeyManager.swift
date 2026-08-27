import Foundation
import AppKit

/// 全局快捷键与物理左 Option 键（KeyCode 58）事件监听器
public final class GlobalHotkeyManager {
    /// 全局共享单例
    public static let shared = GlobalHotkeyManager()
    
    /// 全局修饰键状态监听句柄（其他应用处于前台时生效）
    private var globalFlagsMonitor: Any?
    /// 局部修饰键状态监听句柄（当前应用处于前台时生效）
    private var localFlagsMonitor: Any?
    /// 全局普通按键监听句柄
    private var globalKeyMonitor: Any?
    /// 局部普通按键监听句柄
    private var localKeyMonitor: Any?
    
    /// 记录左 Option 键按下时的时间戳
    private var leftOptionPressedTimestamp: Date?
    /// 记录上一次完成单击释放的时间戳（用于双击判定）
    private var lastTapTimestamp: Date?
    /// 在 Option 键按压期间是否有其他普通按键被按下（组合键防误触标记）
    private var keyComboInterrupted: Bool = false
    
    /// macOS 物理左侧 Option 键的虚拟键码 (KeyCode: 58 / 0x3A)
    private let leftOptionKeyCode: UInt16 = 58
    
    /// 私有初始化方法
    private init() {}
    
    /// 注册并启动全局与局部事件监听
    public func start() {
        stop()
        
        // 1. 监听全局修饰键状态变化
        globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event: event)
        }
        
        // 2. 监听应用内局部修饰键状态变化
        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event: event)
            return event
        }
        
        // 3. 监听按键按下事件，用于判断是否是在输入组合快捷键（如 Option+C / Option+V）
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyDown(event: event)
        }
        
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyDown(event: event)
            return event
        }
    }
    
    /// 注销所有事件监听句柄
    public func stop() {
        if let monitor = globalFlagsMonitor { NSEvent.removeMonitor(monitor); globalFlagsMonitor = nil }
        if let monitor = localFlagsMonitor { NSEvent.removeMonitor(monitor); localFlagsMonitor = nil }
        if let monitor = globalKeyMonitor { NSEvent.removeMonitor(monitor); globalKeyMonitor = nil }
        if let monitor = localKeyMonitor { NSEvent.removeMonitor(monitor); localKeyMonitor = nil }
    }
    
    /// 处理普通按键按下事件
    private func handleKeyDown(event: NSEvent) {
        // 在 Option 按下期间触发了其他字符键，标记为组合键打断
        keyComboInterrupted = true
        
        // 如果用户选择了 Option + V 快捷键模式
        if AppSettings.shared.hotkeyMode == .optionV {
            if event.keyCode == 9 && event.modifierFlags.contains(.option) {
                DispatchQueue.main.async {
                    FloatingPanelController.shared.toggle()
                }
            }
        }
    }
    
    /// 处理修饰键状态变化事件
    private func handleFlagsChanged(event: NSEvent) {
        // 仅处理物理左侧 Option 键 (KeyCode: 58)
        guard event.keyCode == leftOptionKeyCode else { return }
        
        let isOptionKeyDown = event.modifierFlags.contains(.option)
        let currentTime = Date()
        
        if isOptionKeyDown {
            // 左 Option 键按下
            leftOptionPressedTimestamp = currentTime
            keyComboInterrupted = false
        } else {
            // 左 Option 键抬起释放
            guard let pressTimestamp = leftOptionPressedTimestamp else { return }
            leftOptionPressedTimestamp = nil
            
            let holdDuration = currentTime.timeIntervalSince(pressTimestamp)
            
            // 如果按压时间过长（> 0.45s）或在此期间按下了其他键，则判定为非呼出意图，予以忽略
            guard !keyComboInterrupted && holdDuration < 0.45 else { return }
            
            switch AppSettings.shared.hotkeyMode {
            case .singleOption:
                DispatchQueue.main.async {
                    FloatingPanelController.shared.toggle()
                }
                
            case .doubleOption:
                if let previousTap = lastTapTimestamp, currentTime.timeIntervalSince(previousTap) < 0.35 {
                    lastTapTimestamp = nil
                    DispatchQueue.main.async {
                        FloatingPanelController.shared.toggle()
                    }
                } else {
                    lastTapTimestamp = currentTime
                }
                
            case .optionV:
                break
            }
        }
    }
}
