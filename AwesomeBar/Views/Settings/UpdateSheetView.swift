import SwiftUI
import AppKit

/// 液态毛玻璃新版本更新详情弹窗（支持在线下载、解压、原地升级与自动重启）
///
/// 展示分为两个独立页面：
/// 1. `releaseNotesPage`：初始态，展示更新日志与「立即更新」操作入口；
/// 2. `updatingProgressPage`：一旦开始下载，整个弹窗切换为专属的更新进度页（不再显示更新日志），
///    依次呈现下载进度条、安装准备与完成状态，全程结束后由 AppUpdaterService 自动拉起新版本。
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

    /// 是否处于更新流程中（一旦离开 idle 即视为进入独立的更新进度页）
    private var isUpdating: Bool {
        updater.downloadProgress.status != .idle
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
        Group {
            if isUpdating {
                updatingProgressPage
            } else {
                releaseNotesPage
            }
        }
        .frame(width: 450)
        .background(LiquidGlassBackground(cornerRadius: 18))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08), lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.25), value: isUpdating)
    }

    // MARK: - 页面一：更新日志与操作入口

    private var releaseNotesPage: some View {
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

            // 3. 底部操作栏（仅初始态：查看网页 / 稍后再说 / 立即更新）
            idleFooterActionView
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
        }
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

    // MARK: - 子视图：初始态底部操作栏

    private var idleFooterActionView: some View {
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
    }

    // MARK: - 页面二：独立的更新进度页

    private var updatingProgressPage: some View {
        VStack(spacing: 20) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                .shadow(color: .black.opacity(0.18), radius: 6, y: 3)

            VStack(spacing: 4) {
                Text(updatingTitle)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.primary)

                Text(release.tagName)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            updatingBodyContent

            if canDismissWhileUpdating {
                Button("关闭", action: onDismiss)
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.top, 36)
        .padding(.bottom, 30)
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity)
    }

    private var updatingTitle: String {
        switch updater.downloadProgress.status {
        case .idle:
            return ""
        case .downloading:
            return "正在下载更新"
        case .extracting, .restarting:
            return "正在安装更新"
        case .completed:
            return "更新完成"
        case .failed:
            return "更新失败"
        case .canceled:
            return "已取消更新"
        }
    }

    private var canDismissWhileUpdating: Bool {
        switch updater.downloadProgress.status {
        case .failed, .canceled:
            return true
        default:
            return false
        }
    }

    @ViewBuilder
    private var updatingBodyContent: some View {
        let progress = updater.downloadProgress

        switch progress.status {
        case .idle:
            EmptyView()

        case .downloading:
            VStack(spacing: 10) {
                ProgressView(value: progress.progress)
                    .progressViewStyle(.linear)
                    .frame(width: 260)

                HStack(spacing: 10) {
                    Text(progress.formattedSizeProgress)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundColor(.secondary)

                    Text(progress.formattedSpeed)
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .foregroundColor(.accentColor)
                }

                Button("取消") {
                    updater.cancelDownload()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundColor(.red)
            }

        case .extracting(let msg), .restarting(let msg):
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.regular)

                Text(msg)
                    .font(.system(size: 11.5))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

        case .completed:
            VStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.green)

                Text("安装完成，即将自动重启...")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(.green)
            }

        case .failed(let errMsg):
            VStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.red)

                Text(errMsg)
                    .font(.system(size: 11))
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)

                Button("重试") {
                    updater.startSelfUpdate(release: release)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

        case .canceled:
            VStack(spacing: 10) {
                Text("下载已取消")
                    .font(.system(size: 11.5))
                    .foregroundColor(.secondary)

                Button(isCurrentVersion ? "重新安装" : "下载安装") {
                    updater.startSelfUpdate(release: release)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
    }
}
