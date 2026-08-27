import Foundation
import AppKit

/// 全局快捷键与修饰键事件监听管理器（支持左右 Option、修饰单键与组合键 0 延迟极速分发）
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
    /// 记录左 Option 上一次完成单击释放的时间戳
    private var leftOptionLastTapTimestamp: Date?
    
    /// 记录右 Option 键按下时的时间戳
    private var rightOptionPressedTimestamp: Date?
    /// 记录右 Option 上一次完成单击释放的时间戳
    private var rightOptionLastTapTimestamp: Date?
    
    /// 在 Option 键按压期间是否有其他普通按键被按下（组合键防误触标记）
    private var keyComboInterrupted: Bool = false
    
    /// macOS 物理左侧 Option 键的虚拟键码 (KeyCode: 58 / 0x3A)
    private let leftOptionKeyCode: UInt16 = 58
    /// macOS 物理右侧 Option 键的虚拟键码 (KeyCode: 61 / 0x3D)
    private let rightOptionKeyCode: UInt16 = 61
    
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
        
        // 3. 监听普通组合键按下事件（0 毫秒瞬时触发）
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
    
    /// 处理普通组合键按下事件（0 延迟即时响应）
    private func handleKeyDown(event: NSEvent) {
        keyComboInterrupted = true
        
        let settings = AppSettings.shared
        
        // 1. 检测是否命中主面板本体自定义快捷键
        if matchesBinding(event: event, binding: settings.mainAppHotkey) {
            DispatchQueue.main.async {
                FloatingPanelController.shared.toggle()
            }
            return
        }
        
        // 2. 检测是否命中快捷粘贴板自定义快捷键
        if matchesBinding(event: event, binding: settings.stickyNoteHotkey) {
            DispatchQueue.main.async {
                StickyNoteWindowController.shared.toggle()
            }
            return
        }
    }
    
    /// 校验事件是否精确匹配某个 HotkeyBinding 组合键
    private func matchesBinding(event: NSEvent, binding: HotkeyBinding) -> Bool {
        guard binding.kind == .keyCombination,
              let targetKeyCode = binding.keyCode,
              let targetModifierRaw = binding.modifierRawValue else {
            return false
        }
        
        guard event.keyCode == targetKeyCode else { return false }
        
        let eventModifiers = event.modifierFlags.intersection([.command, .option, .shift, .control])
        let targetModifiers = NSEvent.ModifierFlags(rawValue: targetModifierRaw).intersection([.command, .option, .shift, .control])
        
        return eventModifiers == targetModifiers
    }
    
    /// 处理修饰键状态变化事件（智能区分是否需要双击等待，无双击时 0 毫秒即刻呼出）
    private func handleFlagsChanged(event: NSEvent) {
        let keyCode = event.keyCode
        let isOptionKeyDown = event.modifierFlags.contains(.option)
        let currentTime = Date()
        
        // MARK: - 1. 处理左 Option 键 (KeyCode: 58)
        if keyCode == leftOptionKeyCode {
            if isOptionKeyDown {
                leftOptionPressedTimestamp = currentTime
                keyComboInterrupted = false
            } else {
                guard let pressTimestamp = leftOptionPressedTimestamp else { return }
                leftOptionPressedTimestamp = nil
                
                let holdDuration = currentTime.timeIntervalSince(pressTimestamp)
                guard !keyComboInterrupted && holdDuration < 0.45 else { return }
                
                let settings = AppSettings.shared
                let requiresDoubleTap = settings.mainAppHotkey.kind == .doubleOption || settings.stickyNoteHotkey.kind == .doubleOption
                
                if requiresDoubleTap {
                    // 若用户设置了连按两下模式，才进入微小等待窗口
                    if let previousTap = leftOptionLastTapTimestamp, currentTime.timeIntervalSince(previousTap) < 0.25 {
                        leftOptionLastTapTimestamp = nil
                        
                        if settings.mainAppHotkey.kind == .doubleOption {
                            DispatchQueue.main.async { FloatingPanelController.shared.toggle() }
                        } else if settings.stickyNoteHotkey.kind == .doubleOption {
                            DispatchQueue.main.async { StickyNoteWindowController.shared.toggle() }
                        }
                    } else {
                        leftOptionLastTapTimestamp = currentTime
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                            guard let self = self, self.leftOptionLastTapTimestamp == currentTime else { return }
                            self.leftOptionLastTapTimestamp = nil
                            
                            if settings.mainAppHotkey.kind == .singleOption {
                                FloatingPanelController.shared.toggle()
                            } else if settings.stickyNoteHotkey.kind == .singleOption {
                                StickyNoteWindowController.shared.toggle()
                            }
                        }
                    }
                } else {
                    // 无双击模式需求时，按键释放瞬间 0 毫秒即刻唤起！
                    if settings.mainAppHotkey.kind == .singleOption {
                        DispatchQueue.main.async { FloatingPanelController.shared.toggle() }
                    } else if settings.stickyNoteHotkey.kind == .singleOption {
                        DispatchQueue.main.async { StickyNoteWindowController.shared.toggle() }
                    }
                }
            }
        }
        
        // MARK: - 2. 处理右 Option 键 (KeyCode: 61)
        if keyCode == rightOptionKeyCode {
            if isOptionKeyDown {
                rightOptionPressedTimestamp = currentTime
                keyComboInterrupted = false
            } else {
                guard let pressTimestamp = rightOptionPressedTimestamp else { return }
                rightOptionPressedTimestamp = nil
                
                let holdDuration = currentTime.timeIntervalSince(pressTimestamp)
                guard !keyComboInterrupted && holdDuration < 0.45 else { return }
                
                let settings = AppSettings.shared
                let requiresDoubleTap = settings.mainAppHotkey.kind == .doubleRightOption || settings.stickyNoteHotkey.kind == .doubleRightOption
                
                if requiresDoubleTap {
                    if let previousTap = rightOptionLastTapTimestamp, currentTime.timeIntervalSince(previousTap) < 0.25 {
                        rightOptionLastTapTimestamp = nil
                        
                        if settings.mainAppHotkey.kind == .doubleRightOption {
                            DispatchQueue.main.async { FloatingPanelController.shared.toggle() }
                        } else if settings.stickyNoteHotkey.kind == .doubleRightOption {
                            DispatchQueue.main.async { StickyNoteWindowController.shared.toggle() }
                        }
                    } else {
                        rightOptionLastTapTimestamp = currentTime
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                            guard let self = self, self.rightOptionLastTapTimestamp == currentTime else { return }
                            self.rightOptionLastTapTimestamp = nil
                            
                            if settings.mainAppHotkey.kind == .singleRightOption {
                                FloatingPanelController.shared.toggle()
                            } else if settings.stickyNoteHotkey.kind == .singleRightOption {
                                StickyNoteWindowController.shared.toggle()
                            }
                        }
                    }
                } else {
                    // 无双击模式需求时，按键释放瞬间 0 毫秒即刻唤起！
                    if settings.mainAppHotkey.kind == .singleRightOption {
                        DispatchQueue.main.async { FloatingPanelController.shared.toggle() }
                    } else if settings.stickyNoteHotkey.kind == .singleRightOption {
                        DispatchQueue.main.async { StickyNoteWindowController.shared.toggle() }
                    }
                }
            }
        }
    }
}
