import Foundation
import Combine
import SwiftUI

/// 应用程序全局用户偏好设置管理单例类
public final class AppSettings: ObservableObject {
    /// 全局共享单例
    public static let shared = AppSettings()
    
    /// UserDefaults 标准持久化实例
    private let userDefaults = UserDefaults.standard
    
    /// UserDefaults 存储键名常量定义
    private enum StorageKeys {
        static let isPinnedToTop = "AwesomeBar.isPinnedToTop"
        static let hotkeyMode = "AwesomeBar.hotkeyMode"
        static let autoPasteOnSelect = "AwesomeBar.autoPasteOnSelect"
        static let playSoundEffects = "AwesomeBar.playSoundEffects"
        static let maxHistoryCount = "AwesomeBar.maxHistoryCount"
        static let startAtLogin = "AwesomeBar.startAtLogin"
        static let showMenuBarIcon = "AwesomeBar.showMenuBarIcon"
        static let hideAfterCopy = "AwesomeBar.hideAfterCopy"
        static let rememberLastPosition = "AwesomeBar.rememberLastPosition"
        static let lastWindowOriginX = "AwesomeBar.lastWindowOriginX"
        static let lastWindowOriginY = "AwesomeBar.lastWindowOriginY"
        static let isStickyNotePinned = "AwesomeBar.isStickyNotePinned"
        static let stickyNoteOriginX = "AwesomeBar.stickyNoteOriginX"
        static let stickyNoteOriginY = "AwesomeBar.stickyNoteOriginY"
        static let mainAppHotkey = "AwesomeBar.mainAppHotkey"
        static let stickyNoteHotkey = "AwesomeBar.stickyNoteHotkey"
    }
    
    /// 是否开启主窗口置顶钉在最上层
    @Published public var isPinnedToTop: Bool {
        didSet {
            userDefaults.set(isPinnedToTop, forKey: StorageKeys.isPinnedToTop)
        }
    }
    
    /// 主窗口本体自定义唤起快捷键
    @Published public var mainAppHotkey: HotkeyBinding {
        didSet {
            if let data = try? JSONEncoder().encode(mainAppHotkey) {
                userDefaults.set(data, forKey: StorageKeys.mainAppHotkey)
            }
        }
    }
    
    /// 快捷粘贴板浮窗自定义唤起快捷键
    @Published public var stickyNoteHotkey: HotkeyBinding {
        didSet {
            if let data = try? JSONEncoder().encode(stickyNoteHotkey) {
                userDefaults.set(data, forKey: StorageKeys.stickyNoteHotkey)
            }
        }
    }
    
    /// 全局快捷唤起触发模式（兼容保留）
    @Published public var hotkeyMode: HotkeyTriggerMode {
        didSet {
            userDefaults.set(hotkeyMode.rawValue, forKey: StorageKeys.hotkeyMode)
        }
    }
    
    /// 选中条目后是否自动通过 Cmd+V 粘贴至前台应用
    @Published public var autoPasteOnSelect: Bool {
        didSet {
            userDefaults.set(autoPasteOnSelect, forKey: StorageKeys.autoPasteOnSelect)
        }
    }
    
    /// 是否播放操作提示音效
    @Published public var playSoundEffects: Bool {
        didSet {
            userDefaults.set(playSoundEffects, forKey: StorageKeys.playSoundEffects)
        }
    }
    
    /// 剪贴板历史记录最大存储条数限制
    @Published public var maxHistoryCount: Int {
        didSet {
            userDefaults.set(maxHistoryCount, forKey: StorageKeys.maxHistoryCount)
        }
    }
    
    /// 是否开机自动启动
    @Published public var startAtLogin: Bool {
        didSet {
            userDefaults.set(startAtLogin, forKey: StorageKeys.startAtLogin)
        }
    }
    
    /// 是否在 macOS 顶部菜单栏显示常驻图标
    @Published public var showMenuBarIcon: Bool {
        didSet {
            userDefaults.set(showMenuBarIcon, forKey: StorageKeys.showMenuBarIcon)
        }
    }
    
    /// 复制后是否自动隐藏窗口
    @Published public var hideAfterCopy: Bool {
        didSet {
            userDefaults.set(hideAfterCopy, forKey: StorageKeys.hideAfterCopy)
        }
    }
    
    /// 是否记住主窗口上次停留位置开关
    @Published public var rememberLastPosition: Bool {
        didSet {
            userDefaults.set(rememberLastPosition, forKey: StorageKeys.rememberLastPosition)
        }
    }
    
    /// 上次主窗口所在的 X 轴坐标
    @Published public var lastWindowOriginX: Double? {
        didSet {
            if let x = lastWindowOriginX {
                userDefaults.set(x, forKey: StorageKeys.lastWindowOriginX)
            } else {
                userDefaults.removeObject(forKey: StorageKeys.lastWindowOriginX)
            }
        }
    }
    
    /// 上次主窗口所在的 Y 轴坐标
    @Published public var lastWindowOriginY: Double? {
        didSet {
            if let y = lastWindowOriginY {
                userDefaults.set(y, forKey: StorageKeys.lastWindowOriginY)
            } else {
                userDefaults.removeObject(forKey: StorageKeys.lastWindowOriginY)
            }
        }
    }
    
    /// 便签/粘贴板模式浮窗是否置顶钉在最上层
    @Published public var isStickyNotePinned: Bool {
        didSet {
            userDefaults.set(isStickyNotePinned, forKey: StorageKeys.isStickyNotePinned)
        }
    }
    
    /// 便签/粘贴板模式浮窗上次停留的 X 轴坐标
    @Published public var stickyNoteOriginX: Double? {
        didSet {
            if let x = stickyNoteOriginX {
                userDefaults.set(x, forKey: StorageKeys.stickyNoteOriginX)
            } else {
                userDefaults.removeObject(forKey: StorageKeys.stickyNoteOriginX)
            }
        }
    }
    
    /// 便签/粘贴板模式浮窗上次停留的 Y 轴坐标
    @Published public var stickyNoteOriginY: Double? {
        didSet {
            if let y = stickyNoteOriginY {
                userDefaults.set(y, forKey: StorageKeys.stickyNoteOriginY)
            } else {
                userDefaults.removeObject(forKey: StorageKeys.stickyNoteOriginY)
            }
        }
    }
    
    /// 私有初始化方法，从 UserDefaults 中加载初始数据
    private init() {
        self.isPinnedToTop = userDefaults.bool(forKey: StorageKeys.isPinnedToTop)
        
        if let modeString = userDefaults.string(forKey: StorageKeys.hotkeyMode),
            let mode = HotkeyTriggerMode(rawValue: modeString) {
            self.hotkeyMode = mode
        } else {
            self.hotkeyMode = .singleOption
        }
        
        // 1. 加载主窗口本体快捷键绑定（默认按一下左 Option）
        if let data = userDefaults.data(forKey: StorageKeys.mainAppHotkey),
           let binding = try? JSONDecoder().decode(HotkeyBinding.self, from: data) {
            self.mainAppHotkey = binding
        } else {
            self.mainAppHotkey = .singleOption
        }
        
        // 2. 加载快捷粘贴板浮窗快捷键绑定（默认 Option + Space）
        if let data = userDefaults.data(forKey: StorageKeys.stickyNoteHotkey),
           let binding = try? JSONDecoder().decode(HotkeyBinding.self, from: data) {
            self.stickyNoteHotkey = binding
        } else {
            self.stickyNoteHotkey = .optionSpace
        }
        
        self.autoPasteOnSelect = userDefaults.object(forKey: StorageKeys.autoPasteOnSelect) == nil ? true : userDefaults.bool(forKey: StorageKeys.autoPasteOnSelect)
        self.playSoundEffects = userDefaults.object(forKey: StorageKeys.playSoundEffects) == nil ? true : userDefaults.bool(forKey: StorageKeys.playSoundEffects)
        self.maxHistoryCount = userDefaults.integer(forKey: StorageKeys.maxHistoryCount) == 0 ? 500 : userDefaults.integer(forKey: StorageKeys.maxHistoryCount)
        self.startAtLogin = userDefaults.bool(forKey: StorageKeys.startAtLogin)
        self.showMenuBarIcon = userDefaults.object(forKey: StorageKeys.showMenuBarIcon) == nil ? true : userDefaults.bool(forKey: StorageKeys.showMenuBarIcon)
        self.hideAfterCopy = userDefaults.object(forKey: StorageKeys.hideAfterCopy) == nil ? true : userDefaults.bool(forKey: StorageKeys.hideAfterCopy)
        
        self.rememberLastPosition = userDefaults.object(forKey: StorageKeys.rememberLastPosition) == nil ? true : userDefaults.bool(forKey: StorageKeys.rememberLastPosition)
        
        if userDefaults.object(forKey: StorageKeys.lastWindowOriginX) != nil {
            self.lastWindowOriginX = userDefaults.double(forKey: StorageKeys.lastWindowOriginX)
        } else {
            self.lastWindowOriginX = nil
        }
        
        if userDefaults.object(forKey: StorageKeys.lastWindowOriginY) != nil {
            self.lastWindowOriginY = userDefaults.double(forKey: StorageKeys.lastWindowOriginY)
        } else {
            self.lastWindowOriginY = nil
        }
        
        self.isStickyNotePinned = userDefaults.object(forKey: StorageKeys.isStickyNotePinned) == nil ? true : userDefaults.bool(forKey: StorageKeys.isStickyNotePinned)
        
        if userDefaults.object(forKey: StorageKeys.stickyNoteOriginX) != nil {
            self.stickyNoteOriginX = userDefaults.double(forKey: StorageKeys.stickyNoteOriginX)
        } else {
            self.stickyNoteOriginX = nil
        }
        
        if userDefaults.object(forKey: StorageKeys.stickyNoteOriginY) != nil {
            self.stickyNoteOriginY = userDefaults.double(forKey: StorageKeys.stickyNoteOriginY)
        } else {
            self.stickyNoteOriginY = nil
        }
    }
}
