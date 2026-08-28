import SwiftUI

/// 偏好设置面板主视图（支持全量触控板与鼠标滚轮平滑滚动）
public struct SettingsView: View {
    /// 绑定的用户偏好设置单例
    @ObservedObject private var applicationSettings = AppSettings.shared
    /// 绑定的剪贴板数据流中心
    @ObservedObject private var store = ClipboardStore.shared
    /// 绑定的在线更新服务单例
    @ObservedObject private var updater = AppUpdaterService.shared
    
    /// 是否弹出清理普通历史确认警告
    @State private var isShowingClearConfirmAlert: Bool = false
    /// 是否弹出全部清空确认警告
    @State private var isShowingClearAllConfirmAlert: Bool = false
    /// 当前唤起更新弹窗的目标版本
    @State private var selectedReleaseForSheet: GitHubRelease? = nil
    @Environment(\.colorScheme) private var colorScheme
    
    public init() {}
    
    public var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 18) {
                // 1. 快捷键与唤起配置
                settingsSectionContainer(title: "唤起与快捷键", icon: "keyboard") {
                    VStack(alignment: .leading, spacing: 14) {
                        // 1.1 主窗口本体唤起快捷键
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("本体唤起快捷键（主面板）")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.primary)
                                Text("用于呼出主剪贴板面板，搜索与全功能浏览")
                                    .font(.system(size: 10.5))
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            HotkeyRecorderView(
                                binding: $applicationSettings.mainAppHotkey,
                                presets: [
                                    .singleOption,
                                    .doubleOption,
                                    .optionSpace,
                                    .optionV,
                                    .cmdShiftV,
                                    .none
                                ]
                            )
                        }
                        
                        Divider()
                            .opacity(0.3)
                        
                        // 1.2 快捷粘贴板浮窗唤起快捷键
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("快捷粘贴板唤起快捷键（小浮窗）")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.primary)
                                Text("用于呼出轻量独立小悬浮窗，支持 ⌘1-9 直选复制")
                                    .font(.system(size: 10.5))
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            HotkeyRecorderView(
                                binding: $applicationSettings.stickyNoteHotkey,
                                presets: [
                                    .optionSpace,
                                    .doubleOption,
                                    .optionB,
                                    .cmdShiftB,
                                    .singleOption,
                                    .none
                                ]
                            )
                        }
                        
                        Divider()
                            .opacity(0.3)
                        
                        // 1.3 历史记录数字直选快捷键修饰键
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("条目数字直选修饰键（1~9）")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.primary)
                                Text("在主面板或小粘贴板中按下 [修饰键]+数字 快速复制前 1~9 项")
                                    .font(.system(size: 10.5))
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Picker("", selection: $applicationSettings.quickSelectModifier) {
                                ForEach(QuickSelectModifier.allCases) { modifier in
                                    Text(modifier.title).tag(modifier)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 230)
                        }
                        
                        Divider()
                            .opacity(0.3)
                        
                        Text("💡 提示：点击按键胶囊可直接在键盘上按下任意组合键进行自定义录制；点击右侧箭头可快速选用推荐预设。")
                            .font(.system(size: 10.5))
                            .foregroundColor(.secondary)
                            .lineSpacing(2)
                    }
                }
                
                // 2. 交互与窗口行为
                settingsSectionContainer(title: "交互与窗口行为", icon: "macwindow") {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("钉在最上层 (置顶保持)", isOn: $applicationSettings.isPinnedToTop)
                            .help("开启后窗口始终悬浮在其他窗口上方，不会因失去焦点而隐藏")
                        
                        Toggle("记住上次窗口停留位置", isOn: $applicationSettings.rememberLastPosition)
                            .help("开启后每次唤起将保持在上一次拖拽停留的屏幕位置；关闭则始终在鼠标所在屏幕正中央唤起")
                        
                        Toggle("选中条目后直接自动粘贴 (Cmd+V)", isOn: $applicationSettings.autoPasteOnSelect)
                            .help("开启后点击项目或按快捷键将自动回填到当前活动应用")
                        
                        Divider()
                            .opacity(0.3)
                        
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("系统辅助功能权限 (用于自动执行 Cmd+V 粘贴)")
                                    .font(.system(size: 12))
                                Text("如点击卡片未自动粘贴，请在此检查并开启权限")
                                    .font(.system(size: 10.5))
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            if AccessibilityManager.isAccessibilityTrusted {
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                    Text("已授权")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.secondary)
                                }
                            } else {
                                Button("去系统设置授权") {
                                    AccessibilityManager.openAccessibilityPreferences()
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            }
                        }
                        
                        Divider()
                            .opacity(0.3)
                        
                        Toggle("播放操作反馈音效", isOn: $applicationSettings.playSoundEffects)
                        
                        Toggle("在菜单栏显示状态图标", isOn: $applicationSettings.showMenuBarIcon)
                    }
                }
                
                // 3. 历史与数据存储
                settingsSectionContainer(title: "历史与数据存储", icon: "internaldrive") {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("最大历史记录保留条数", selection: $applicationSettings.maxHistoryCount) {
                            Text("100 条").tag(100)
                            Text("300 条").tag(300)
                            Text("500 条").tag(500)
                            Text("1000 条").tag(1000)
                            Text("2000 条").tag(2000)
                        }
                        
                        Divider()
                            .opacity(0.3)
                        
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("当前已存储数据")
                                    .font(.system(size: 12, weight: .medium))
                                Text("\(store.allItems.count) 条记录（SQLite 本地安全持久化）")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Button("清除普通历史") {
                                isShowingClearConfirmAlert = true
                            }
                            .buttonStyle(.bordered)
                            
                            Button("清空全部") {
                                isShowingClearAllConfirmAlert = true
                            }
                            .buttonStyle(.bordered)
                            .foregroundColor(.red)
                        }
                    }
                }
                
                // 4. 版本与在线更新
                settingsSectionContainer(title: "版本与在线更新", icon: "arrow.triangle.2.circlepath.circle") {
                    VStack(alignment: .leading, spacing: 14) {
                        // 4.1 当前版本与快速检查栏
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text("AwesomeBar")
                                        .font(.system(size: 12.5, weight: .semibold))
                                    Text("v\(updater.currentAppVersion) (Build \(updater.currentAppBuild))")
                                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                                Text("纯 Swift 原生开发 • 120Hz ProMotion • 纯本地 SQLite 安全存储")
                                    .font(.system(size: 10.5))
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            switch updater.checkState {
                            case .checking:
                                HStack(spacing: 6) {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text("检查中...")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }
                            case .hasUpdate(let release, _, _):
                                Button(action: {
                                    selectedReleaseForSheet = release
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "arrow.down.circle.fill")
                                        Text("下载安装 (\(release.tagName))")
                                    }
                                    .font(.system(size: 11, weight: .medium))
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            case .alreadyLatest(let release, _):
                                HStack(spacing: 8) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                        Text("已是最新版本")
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    if let rel = release ?? updater.releaseHistory.first {
                                        Button("重新安装") {
                                            selectedReleaseForSheet = rel
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                    }
                                }
                            case .error(let msg):
                                HStack(spacing: 4) {
                                    Text(msg)
                                        .font(.system(size: 10.5))
                                        .foregroundColor(.red)
                                    Button("重试") {
                                        updater.checkForUpdates()
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.mini)
                                }
                            case .idle:
                                Button("检查更新") {
                                    updater.checkForUpdates()
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                        
                        Divider()
                            .opacity(0.3)
                        
                        Toggle("启动时自动检查更新", isOn: $applicationSettings.automaticallyCheckForUpdates)
                            .font(.system(size: 11.5))
                        
                        Divider()
                            .opacity(0.3)
                        
                        // 4.2 历史版本发布与更新日志列表
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("版本发布历史与更新日志")
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .foregroundColor(.primary)
                                
                                Spacer()
                                
                                Button(action: {
                                    Task {
                                        await updater.loadReleaseHistory()
                                    }
                                }) {
                                    HStack(spacing: 3) {
                                        Image(systemName: "arrow.clockwise")
                                        Text("刷新日志")
                                    }
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            
                            if updater.isLoadingHistory && updater.releaseHistory.isEmpty {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text("正在同步版本发布日志...")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }
                                .padding(.vertical, 8)
                            } else if updater.releaseHistory.isEmpty {
                                HStack {
                                    Text("暂未拉取到远端发布记录")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                    
                                    Spacer()
                                    
                                    Button("在 GitHub 查看") {
                                        if let url = URL(string: "https://github.com/\(updater.repoOwner)/\(updater.repoName)/releases") {
                                            NSWorkspace.shared.open(url)
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.mini)
                                }
                                .padding(10)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(colorScheme == .dark ? Color.white.opacity(0.03) : Color.black.opacity(0.02))
                                )
                            } else {
                                VStack(spacing: 8) {
                                    ForEach(updater.releaseHistory) { release in
                                        let isCurrent = release.tagName.lowercased() == "v\(updater.currentAppVersion)".lowercased() || release.tagName.lowercased() == updater.currentAppVersion.lowercased()
                                        let isNewer = updater.isNewerVersion(latestTagName: release.tagName, currentVersion: updater.currentAppVersion)
                                        
                                        ReleaseHistoryRowView(
                                            release: release,
                                            isCurrentVersion: isCurrent,
                                            isNewer: isNewer,
                                            onSelectForUpdate: { rel in
                                                selectedReleaseForSheet = rel
                                            }
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            // 每次打开偏好设置窗口时，重置检查更新按钮状态并同步版本历史
            updater.resetCheckState()
            if updater.releaseHistory.isEmpty {
                Task {
                    await updater.loadReleaseHistory()
                }
            }
        }
        .sheet(item: $selectedReleaseForSheet) { release in
            UpdateSheetView(
                release: release,
                currentVersion: updater.currentAppVersion,
                acceleratedUrl: updater.getAcceleratedDownloadUrl(directUrl: release.macOSDownloadUrl ?? ""),
                onDismiss: {
                    selectedReleaseForSheet = nil
                }
            )
        }
        .onChange(of: updater.checkState) { _, newState in
            if case .hasUpdate(let release, _, _) = newState {
                selectedReleaseForSheet = release
            }
        }
        .alert("确定清除普通历史记录吗？", isPresented: $isShowingClearConfirmAlert) {
            Button("取消", role: .cancel) {}
            Button("确定清除", role: .destructive) {
                store.clearAll(exceptPinned: true)
                SoundManager.shared.playDeleteSound()
            }
        } message: {
            Text("已固定的置顶条目将继续保留。")
        }
        .alert("确定清空全部历史记录吗？", isPresented: $isShowingClearAllConfirmAlert) {
            Button("取消", role: .cancel) {}
            Button("全部清空", role: .destructive) {
                store.clearAll(exceptPinned: false)
                SoundManager.shared.playDeleteSound()
            }
        } message: {
            Text("包含所有已固定与本地缓存均将被彻底清除。")
        }
    }
    
    // MARK: - 辅助子视图：分组卡片容器
    
    private func settingsSectionContainer<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(.primary)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                content()
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.035))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06), lineWidth: 0.8)
            )
        }
    }
}

/// 单个历史版本更新卡片组件
struct ReleaseHistoryRowView: View {
    let release: GitHubRelease
    let isCurrentVersion: Bool
    let isNewer: Bool
    let onSelectForUpdate: (GitHubRelease) -> Void
    
    @State private var isExpanded: Bool
    @Environment(\.colorScheme) private var colorScheme
    
    init(
        release: GitHubRelease,
        isCurrentVersion: Bool,
        isNewer: Bool,
        onSelectForUpdate: @escaping (GitHubRelease) -> Void
    ) {
        self.release = release
        self.isCurrentVersion = isCurrentVersion
        self.isNewer = isNewer
        self.onSelectForUpdate = onSelectForUpdate
        // 默认展开最新版本或当前版本
        self._isExpanded = State(initialValue: isCurrentVersion || isNewer)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 卡片头部点击展开/折叠
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.secondary)
                        .frame(width: 12)
                    
                    Text(release.tagName)
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(.primary)
                    
                    if !release.name.isEmpty && release.name != release.tagName {
                        Text(release.name)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    
                    if isCurrentVersion {
                        Text("当前使用")
                            .font(.system(size: 9.5, weight: .semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Color.accentColor.opacity(0.15))
                            .foregroundColor(.accentColor)
                            .clipShape(Capsule())
                    } else if isNewer {
                        Text("最新更新")
                            .font(.system(size: 9.5, weight: .semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Color.green.opacity(0.15))
                            .foregroundColor(.green)
                            .clipShape(Capsule())
                    }
                    
                    Spacer()
                    
                    Text(release.formattedDate)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.8))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            // 展开状态下的结构化更新日志与附件下载
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    let changelog = release.parsedChangelog
                    
                    if !changelog.features.isEmpty {
                        categoryLogSection(title: "新增特性", icon: "sparkles", color: .green, items: changelog.features)
                    }
                    
                    if !changelog.fixes.isEmpty {
                        categoryLogSection(title: "问题修复", icon: "wrench.and.screwdriver", color: .blue, items: changelog.fixes)
                    }
                    
                    if !changelog.improvements.isEmpty {
                        categoryLogSection(title: "体验优化", icon: "bolt.fill", color: .purple, items: changelog.improvements)
                    }
                    
                    if !changelog.others.isEmpty {
                        categoryLogSection(title: "其他变更", icon: "doc.text", color: .secondary, items: changelog.others)
                    }
                    
                    if !changelog.hasCategorized && !release.body.isEmpty {
                        Text(release.body)
                            .font(.system(size: 10.5))
                            .foregroundColor(.secondary)
                            .lineSpacing(2)
                    }
                    
                    HStack(spacing: 8) {
                        Button(action: {
                            if let url = URL(string: "https://github.com/\(AppUpdaterService.shared.repoOwner)/\(AppUpdaterService.shared.repoName)/releases/tag/\(release.tagName)") {
                                NSWorkspace.shared.open(url)
                            }
                        }) {
                            HStack(spacing: 3) {
                                Image(systemName: "safari")
                                Text("在 GitHub 查看 Release")
                            }
                            .font(.system(size: 10))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        
                        if release.macOSAsset != nil {
                            if isCurrentVersion {
                                Button(action: {
                                    onSelectForUpdate(release)
                                }) {
                                    HStack(spacing: 3) {
                                        Image(systemName: "arrow.triangle.2.circlepath")
                                        Text("重新安装")
                                        if let size = release.macOSAsset?.formattedSize, !size.isEmpty {
                                            Text("(\(size))")
                                                .opacity(0.8)
                                        }
                                    }
                                    .font(.system(size: 10, weight: .medium))
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.mini)
                            } else {
                                Button(action: {
                                    onSelectForUpdate(release)
                                }) {
                                    HStack(spacing: 3) {
                                        Image(systemName: "arrow.down.circle.fill")
                                        Text("下载安装")
                                        if let size = release.macOSAsset?.formattedSize, !size.isEmpty {
                                            Text("(\(size))")
                                                .opacity(0.8)
                                        }
                                    }
                                    .font(.system(size: 10, weight: .medium))
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.mini)
                            }
                        }
                    }
                    .padding(.top, 4)
                }
                .padding(.leading, 20)
                .padding(.top, 2)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.02))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05), lineWidth: 0.6)
        )
    }
    
    private func categoryLogSection(title: String, icon: String, color: Color, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(color)
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(color)
            }
            
            VStack(alignment: .leading, spacing: 3) {
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .top, spacing: 5) {
                        Circle()
                            .fill(color.opacity(0.6))
                            .frame(width: 3, height: 3)
                            .padding(.top, 5)
                        Text(item)
                            .font(.system(size: 10.5))
                            .foregroundColor(.primary.opacity(0.85))
                            .lineSpacing(1.5)
                    }
                }
            }
            .padding(.leading, 4)
        }
    }
}
