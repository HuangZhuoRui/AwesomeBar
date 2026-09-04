import Foundation
import AppKit
import Carbon
import Combine

/// AwesomeBar 专属 Carbon 快捷键签名常量 ('AWSM')
///
/// 标记为 nonisolated：需要在 Carbon 的 C 回调（非隔离上下文）中读取，其本身是不可变常量，天然并发安全。
private nonisolated let kAwesomeBarCarbonSignature: OSType = 0x4157534D

/// Carbon 全局快捷键 C 语言底层回调函数（内核级拦截，100% 跨任意第三方应用生效，无需辅助功能权限）
///
/// 必须是 nonisolated：由 Carbon 在任意线程直接调用，只有非隔离函数才能取址为 C 函数指针。
private nonisolated func carbonHotKeyCallback(
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
    
    /// 单个物理修饰键的敲击状态追踪
    private struct ModifierTapState {
        /// 该键按下时的时间戳
        var pressedTimestamp: Date?
        /// 该键上一次完成单击释放的时间戳
        var lastTapTimestamp: Date?
    }

    /// 左 Option 键的敲击状态
    private var leftOptionState = ModifierTapState()
    /// 右 Option 键的敲击状态
    private var rightOptionState = ModifierTapState()

    /// 判定为「敲击」而非「按住」的最长按压时长（秒）
    private static let maximumTapHoldDuration: TimeInterval = 0.45
    /// 连按两下的最大判定间隔（秒）
    private static let doubleTapInterval: TimeInterval = 0.25

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
    
    /// 处理修饰键状态变化事件（左右 Option 走同一套逻辑，仅状态与触发类型不同）
    private func handleFlagsChanged(event: NSEvent) {
        let isOptionKeyDown = event.modifierFlags.contains(.option)
        let currentTime = Date()

        switch event.keyCode {
        case leftOptionKeyCode:
            processOptionTap(
                stateKeyPath: \.leftOptionState,
                isKeyDown: isOptionKeyDown,
                currentTime: currentTime,
                singleTapKind: .singleOption,
                doubleTapKind: .doubleOption
            )
        case rightOptionKeyCode:
            processOptionTap(
                stateKeyPath: \.rightOptionState,
                isKeyDown: isOptionKeyDown,
                currentTime: currentTime,
                singleTapKind: .singleRightOption,
                doubleTapKind: .doubleRightOption
            )
        default:
            break
        }
    }

    /// 处理单个 Option 键的一次按下或抬起（智能区分是否需要双击等待，无双击绑定时 0 毫秒即刻呼出）
    /// - Parameters:
    ///   - stateKeyPath: 指向该物理键敲击状态的可写键路径（左键或右键）
    ///   - isKeyDown: 本次事件是按下还是抬起
    ///   - currentTime: 事件发生时刻
    ///   - singleTapKind: 该键「单击」对应的触发类型
    ///   - doubleTapKind: 该键「连按两下」对应的触发类型
    private func processOptionTap(
        stateKeyPath: ReferenceWritableKeyPath<GlobalHotkeyManager, ModifierTapState>,
        isKeyDown: Bool,
        currentTime: Date,
        singleTapKind: HotkeyBinding.TriggerKind,
        doubleTapKind: HotkeyBinding.TriggerKind
    ) {
        // 1. 按下：记录起始时刻并重置组合键防误触标记
        if isKeyDown {
            self[keyPath: stateKeyPath].pressedTimestamp = currentTime
            keyComboInterrupted = false
            return
        }

        // 2. 抬起：必须存在配对的按下事件，且是一次短促敲击而非长按或组合键
        guard let pressTimestamp = self[keyPath: stateKeyPath].pressedTimestamp else { return }
        self[keyPath: stateKeyPath].pressedTimestamp = nil

        let holdDuration = currentTime.timeIntervalSince(pressTimestamp)
        guard !keyComboInterrupted, holdDuration < Self.maximumTapHoldDuration else { return }

        // 3. 无任何双击绑定时无需等待，单击即刻响应
        let settings = AppSettings.shared
        let requiresDoubleTap = settings.mainAppHotkey.kind == doubleTapKind
            || settings.stickyNoteHotkey.kind == doubleTapKind

        guard requiresDoubleTap else {
            triggerWindow(matching: singleTapKind)
            return
        }

        // 4. 已在判定窗口内积累了上一次敲击，构成连按两下
        if let previousTap = self[keyPath: stateKeyPath].lastTapTimestamp,
           currentTime.timeIntervalSince(previousTap) < Self.doubleTapInterval {
            self[keyPath: stateKeyPath].lastTapTimestamp = nil
            triggerWindow(matching: doubleTapKind)
            return
        }

        // 5. 首次敲击：等待判定窗口，超时未等到第二次则按单击处理
        self[keyPath: stateKeyPath].lastTapTimestamp = currentTime
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.doubleTapInterval) { [weak self] in
            guard let self, self[keyPath: stateKeyPath].lastTapTimestamp == currentTime else { return }
            self[keyPath: stateKeyPath].lastTapTimestamp = nil
            self.triggerWindow(matching: singleTapKind)
        }
    }

    /// 将指定触发类型分派到绑定了它的窗口（主面板优先于快捷粘贴板浮窗）
    private func triggerWindow(matching kind: HotkeyBinding.TriggerKind) {
        let settings = AppSettings.shared

        if settings.mainAppHotkey.kind == kind {
            DispatchQueue.main.async { FloatingPanelController.shared.toggle() }
        } else if settings.stickyNoteHotkey.kind == kind {
            DispatchQueue.main.async { StickyNoteWindowController.shared.toggle() }
        }
    }
}
