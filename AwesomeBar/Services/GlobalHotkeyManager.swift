import Foundation
import AppKit
import Carbon
import Combine

/// AwesomeBar 专属 Carbon 快捷键签名常量 ('AWSM')
private let kAwesomeBarCarbonSignature: OSType = 0x4157534D

/// Carbon 全局快捷键 C 语言底层回调函数（内核级拦截，100% 跨任意第三方应用生效，无需辅助功能权限）
private func carbonHotKeyCallback(
    nextHandler: EventHandlerCallRef?,
    event: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event = event else { return OSStatus(eventNotHandledErr) }
    
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    
    guard status == noErr, hotKeyID.signature == kAwesomeBarCarbonSignature else {
        return OSStatus(eventNotHandledErr)
    }
    
    let hotKeyId = hotKeyID.id
    DispatchQueue.main.async {
        GlobalHotkeyManager.shared.handleCarbonHotKeyTriggered(id: hotKeyId)
    }
    
    return noErr
}

/// 全局快捷键与修饰键事件监听管理器（基于 Carbon 原生系统级全局 HotKey 与 AppKit 事件监听双通道架构）
public final class GlobalHotkeyManager {
    /// 全局共享单例
    public static let shared = GlobalHotkeyManager()
    
    /// Carbon 事件处理器引用
    private var eventHandlerRef: EventHandlerRef?
    /// 已注册的 Carbon 全局快捷键引用映射表 (HotKeyID -> EventHotKeyRef)
    private var registeredCarbonHotKeys: [UInt32: EventHotKeyRef] = [:]
    /// Combine 响应式订阅集合
    private var cancellables = Set<AnyCancellable>()
    
    /// 全局修饰键状态监听句柄（用于单击/双击 Option 监听）
    private var globalFlagsMonitor: Any?
    /// 局部修饰键状态监听句柄
    private var localFlagsMonitor: Any?
    
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
    
    /// 数字键 1~9 对应的 macOS 物理虚拟键码
    private let numberKeyCodes: [UInt32: UInt32] = [
        1: 18, // 1
        2: 19, // 2
        3: 20, // 3
        4: 21, // 4
        5: 23, // 5
        6: 22, // 6
        7: 26, // 7
        8: 28, // 8
        9: 25  // 9
    ]
    
    /// 私有初始化方法
    private init() {
        installCarbonEventHandler()
        bindSettingsAutoReload()
    }
    
    /// 安装 Carbon 原生全局事件处理器
    private func installCarbonEventHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        
        InstallEventHandler(
            GetApplicationEventTarget(),
            carbonHotKeyCallback,
            1,
            &eventType,
            nil,
            &eventHandlerRef
        )
    }
    
    /// 监听设置变化，自动刷新注册全局快捷键
    private func bindSettingsAutoReload() {
        AppSettings.shared.$mainAppHotkey
            .sink { [weak self] _ in self?.reloadHotkeys() }
            .store(in: &cancellables)
        
        AppSettings.shared.$stickyNoteHotkey
            .sink { [weak self] _ in self?.reloadHotkeys() }
            .store(in: &cancellables)
            
        AppSettings.shared.$quickSelectModifier
            .sink { [weak self] _ in self?.reloadHotkeys() }
            .store(in: &cancellables)
    }
    
    /// 注册并启动全局快捷键与修饰键监听
    public func start() {
        stop()
        
        // 1. 注册原生 Carbon 全局快捷键（本体、小粘贴板与 1~9 直选）
        reloadHotkeys()
        
        // 2. 监听修饰键状态（用于独立单击/双击 Option 呼出）
        globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event: event)
        }
        
        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event: event)
            return event
        }
    }
    
    /// 注销并重载所有全局快捷键
    public func reloadHotkeys() {
        unregisterAllCarbonHotKeys()
        
        let settings = AppSettings.shared
        
        // 1. 注册主面板本体组合快捷键 (ID: 100)
        if settings.mainAppHotkey.kind == .keyCombination,
           let keyCode = settings.mainAppHotkey.keyCode,
           let rawMod = settings.mainAppHotkey.modifierRawValue {
            let carbonMods = convertAppKitModifierToCarbon(NSEvent.ModifierFlags(rawValue: rawMod))
            registerCarbonHotKey(id: 100, keyCode: UInt32(keyCode), carbonModifiers: carbonMods)
        }
        
        // 2. 注册快捷粘贴板组合快捷键 (ID: 101)
        if settings.stickyNoteHotkey.kind == .keyCombination,
           let keyCode = settings.stickyNoteHotkey.keyCode,
           let rawMod = settings.stickyNoteHotkey.modifierRawValue {
            let carbonMods = convertAppKitModifierToCarbon(NSEvent.ModifierFlags(rawValue: rawMod))
            registerCarbonHotKey(id: 101, keyCode: UInt32(keyCode), carbonModifiers: carbonMods)
        }
        
        // 3. 注册 1~9 数字条目全局直选快捷键 (ID: 1 ~ 9)
        if let carbonMods = settings.quickSelectModifier.carbonModifiers {
            for (num, keyCode) in numberKeyCodes {
                registerCarbonHotKey(id: num, keyCode: keyCode, carbonModifiers: carbonMods)
            }
        }
    }
    
    /// 注册单个 Carbon 全局快捷键
    private func registerCarbonHotKey(id: UInt32, keyCode: UInt32, carbonModifiers: UInt32) {
        let hotKeyID = EventHotKeyID(signature: kAwesomeBarCarbonSignature, id: id)
        var hotKeyRef: EventHotKeyRef?
        
        let status = RegisterEventHotKey(
            keyCode,
            carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        
        if status == noErr, let ref = hotKeyRef {
            registeredCarbonHotKeys[id] = ref
        }
    }
    
    /// 注销所有已注册的 Carbon 全局快捷键
    private func unregisterAllCarbonHotKeys() {
        for (_, ref) in registeredCarbonHotKeys {
            UnregisterEventHotKey(ref)
        }
        registeredCarbonHotKeys.removeAll()
    }
    
    /// 注销所有事件监听句柄
    public func stop() {
        unregisterAllCarbonHotKeys()
        
        if let monitor = globalFlagsMonitor { NSEvent.removeMonitor(monitor); globalFlagsMonitor = nil }
        if let monitor = localFlagsMonitor { NSEvent.removeMonitor(monitor); localFlagsMonitor = nil }
    }
    
    /// 将 AppKit 修饰键标志转换为 Carbon 原生修饰键标志
    private func convertAppKitModifierToCarbon(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var carbonFlags: UInt32 = 0
        if flags.contains(.command) { carbonFlags |= UInt32(cmdKey) }
        if flags.contains(.option) { carbonFlags |= UInt32(optionKey) }
        if flags.contains(.control) { carbonFlags |= UInt32(controlKey) }
        if flags.contains(.shift) { carbonFlags |= UInt32(shiftKey) }
        return carbonFlags
    }
    
    // MARK: - Carbon 快捷键事件派发中枢
    
    /// 处理由操作系统内核直接派发的 Carbon 全局快捷键（无论前台激活的是任何第三方 App 均 100% 触发）
    public func handleCarbonHotKeyTriggered(id: UInt32) {
        if id == 100 {
            // 主面板本体唤起/切换
            FloatingPanelController.shared.toggle()
        } else if id == 101 {
            // 快捷粘贴板浮窗唤起/切换
            StickyNoteWindowController.shared.toggle()
        } else if (1...9).contains(id) {
            // 1~9 数字条目全局直选复制/粘贴
            let number = Int(id)
            if StickyNoteWindowController.shared.isVisible {
                _ = StickyNoteWindowController.shared.triggerShortcut(index: number)
            } else if FloatingPanelController.shared.isVisible {
                let allItems = ClipboardStore.shared.allItems
                let targetIndex = number - 1
                if targetIndex >= 0 && targetIndex < allItems.count {
                    PasteSimulator.shared.pasteItem(item: allItems[targetIndex])
                }
            }
        }
    }
    
    // MARK: - 单击/双击 Option 修饰键状态监听
    
    /// 处理修饰键状态变化事件（智能区分是否需要双击等待，无双击时 0 毫秒即刻呼出）
    private func handleFlagsChanged(event: NSEvent) {
        let keyCode = event.keyCode
        let isOptionKeyDown = event.modifierFlags.contains(.option)
        let currentTime = Date()
        
        // 1. 处理左 Option 键 (KeyCode: 58)
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
                    if settings.mainAppHotkey.kind == .singleOption {
                        DispatchQueue.main.async { FloatingPanelController.shared.toggle() }
                    } else if settings.stickyNoteHotkey.kind == .singleOption {
                        DispatchQueue.main.async { StickyNoteWindowController.shared.toggle() }
                    }
                }
            }
        }
        
        // 2. 处理右 Option 键 (KeyCode: 61)
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
