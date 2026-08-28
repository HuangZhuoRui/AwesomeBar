import SwiftUI
import AppKit

/// 液态毛玻璃新版本更新详情弹窗（支持在线下载、解压、自我替换升级与自动重启）
public struct UpdateSheetView: View {
    @ObservedObject private var updater = AppUpdaterService.shared
    public let release: GitHubRelease
    public let currentVersion: String
    public let acceleratedUrl: String
    public let onDismiss: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    
    private var isCurrentVersion: Bool {
        return release.tagName.lowercased() == "v\(currentVersion)".lowercased() ||
               release.tagName.lowercased() == currentVersion.lowercased()
    }
    
    public init(
        release: GitHubRelease,
        currentVersion: String,
        acceleratedUrl: String,
        onDismiss: @escaping () -> Void
    ) {
        self.release = release
        self.currentVersion = currentVersion
        self.acceleratedUrl = acceleratedUrl
        self.onDismiss = onDismiss
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // 1. 顶部版本概览头部
            headerView
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 14)
            
            Divider()
                .opacity(0.3)
            
            // 2. 结构化更新日志列表
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 14) {
                    let changelog = release.parsedChangelog
                    
                    if !changelog.features.isEmpty {
                        changelogCategorySection(
                            title: "新增特性",
                            icon: "sparkles",
                            color: .green,
                            items: changelog.features
                        )
                    }
                    
                    if !changelog.fixes.isEmpty {
                        changelogCategorySection(
                            title: "问题修复",
                            icon: "wrench.and.screwdriver",
                            color: .blue,
                            items: changelog.fixes
                        )
                    }
                    
                    if !changelog.improvements.isEmpty {
                        changelogCategorySection(
                            title: "体验优化",
                            icon: "bolt.fill",
                            color: .purple,
                            items: changelog.improvements
                        )
                    }
                    
                    if !changelog.others.isEmpty {
                        changelogCategorySection(
                            title: "其他变更",
                            icon: "doc.text",
                            color: .secondary,
                            items: changelog.others
                        )
                    }
                    
                    if !changelog.hasCategorized {
                        Text(release.body.isEmpty ? "暂无详细更新日志。" : release.body)
                            .font(.system(size: 11.5))
                            .foregroundColor(.secondary)
                            .lineSpacing(3)
                            .padding(10)
                    }
                }
                .padding(18)
            }
            .frame(maxHeight: 220)
            
            Divider()
                .opacity(0.3)
            
            // 3. 底部下载与自我替换安装进度栏
            footerActionView
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
        }
        .frame(width: 450)
        .background(LiquidGlassBackground(cornerRadius: 18))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08), lineWidth: 1)
        )
    }
    
    // MARK: - 子视图：头部
    
    private var headerView: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(isCurrentVersion ? "重新安装应用" : "发现新版本")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.primary)
                    
                    Text(release.tagName)
                        .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(isCurrentVersion ? Color.accentColor.opacity(0.15) : Color.green.opacity(0.15))
                        .foregroundColor(isCurrentVersion ? .accentColor : .green)
                        .clipShape(Capsule())
                }
                
                Text("当前版本: v\(currentVersion) • 发布日期: \(release.formattedDate)")
                    .font(.system(size: 10.5))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                    .frame(width: 22, height: 22)
                    .background(Color.primary.opacity(0.04))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }
    
    // MARK: - 子视图：分类日志区
    
    private func changelogCategorySection(
        title: String,
        icon: String,
        color: Color,
        items: [String]
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(color)
                
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(color)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .top, spacing: 6) {
                        Circle()
                            .fill(color.opacity(0.6))
                            .frame(width: 3.5, height: 3.5)
                            .padding(.top, 5.5)
                        
                        Text(item)
                            .font(.system(size: 11))
                            .foregroundColor(.primary.opacity(0.85))
                            .lineSpacing(2)
                    }
                }
            }
            .padding(.leading, 4)
        }
    }
    
    // MARK: - 子视图：底部操作栏
    
    private var footerActionView: some View {
        VStack(spacing: 12) {
            let progress = updater.downloadProgress
            
            switch progress.status {
            case .idle:
                HStack(spacing: 10) {
                    Button(action: {
                        if let url = URL(string: "https://github.com/\(updater.repoOwner)/\(updater.repoName)/releases/tag/\(release.tagName)") {
                            NSWorkspace.shared.open(url)
                        }
                    }) {
                        Text("网页查看")
                            .font(.system(size: 11.5))
                    }
                    .buttonStyle(.bordered)
                    
                    Spacer()
                    
                    Button("稍后再说", action: onDismiss)
                        .buttonStyle(.plain)
                        .foregroundColor(.secondary)
                        .font(.system(size: 11.5))
                    
                    Button(action: {
                        updater.startSelfUpdate(release: release)
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: isCurrentVersion ? "arrow.triangle.2.circlepath" : "arrow.down.circle.fill")
                            Text(isCurrentVersion ? "立即重新安装并重启" : "立即下载安装并重启")
                            if let size = release.macOSAsset?.formattedSize, !size.isEmpty {
                                Text("(\(size))")
                                    .opacity(0.8)
                            }
                        }
                        .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                }
                
            case .downloading:
                VStack(spacing: 6) {
                    ProgressView(value: progress.progress)
                        .progressViewStyle(.linear)
                    
                    HStack {
                        Text(progress.formattedSizeProgress)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Text(progress.formattedSpeed)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(.accentColor)
                        
                        Button("取消") {
                            updater.cancelDownload()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 10))
                        .foregroundColor(.red)
                        .padding(.leading, 8)
                    }
                }
                
            case .extracting(let msg), .restarting(let msg):
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    
                    Text(msg)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(.primary)
                    
                    Spacer()
                }
                .padding(.vertical, 4)
                
            case .completed:
                HStack {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("安装升级完成，正在重启...")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundColor(.green)
                    }
                    Spacer()
                }
                
            case .failed(let errMsg):
                HStack {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text(errMsg)
                            .font(.system(size: 10.5))
                            .foregroundColor(.red)
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    Button("重试") {
                        updater.startSelfUpdate(release: release)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                
            case .canceled:
                HStack {
                    Text("下载已取消")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Button(isCurrentVersion ? "重新安装" : "下载安装") {
                        updater.startSelfUpdate(release: release)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
        }
    }
}
