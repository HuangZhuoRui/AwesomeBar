import SwiftUI
import AppKit

/// AwesomeBar 剪贴板应用程序主入口
@main
public struct MyApp: App {
    /// 注入 AppKit 应用程序委托
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    
    public init() {}
    
    public var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}
