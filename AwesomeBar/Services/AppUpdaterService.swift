import Foundation
import AppKit
import Combine

/// 结构化更新日志解析模型（智能识别 Conventional Commits 规范，分类展示特性、修复与优化）
public struct ParsedChangelog: Equatable {
    public let features: [String]
    public let fixes: [String]
    public let improvements: [String]
    public let others: [String]
    
    public var hasCategorized: BooleanLiteralType {
        return !features.isEmpty || !fixes.isEmpty || !improvements.isEmpty || !others.isEmpty
    }
    
    public static func parse(rawBody: String) -> ParsedChangelog {
        var features: [String] = []
        var fixes: [String] = []
        var improvements: [String] = []
        var others: [String] = []
        
        let pattern = try? NSRegularExpression(
            pattern: #"^(?:[-*]\s*)?(feat|feature|fix|bugfix|hotfix|perf|refactor|style|docs|chore|test|revert)(?:\(([^)]+)\))?[:：\s]\s*(.+)$"#,
            options: .caseInsensitive
        )
        
        let lines = rawBody.components(separatedBy: .newlines)
        for rawLine in lines {
            var line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") { continue }
            
            if line.hasPrefix("- ") || line.hasPrefix("* ") {
                line = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            }
            if line.isEmpty { continue }
            
            let lower = line.lowercased()
            if lower.hasPrefix("tmp:") || lower.hasPrefix("tmp：") || lower.hasPrefix("temp:") || lower.hasPrefix("temp：") {
                continue
            }
            
            if let regex = pattern,
               let match = regex.firstMatch(in: line, options: [], range: NSRange(location: 0, length: line.utf16.count)) {
                let typeRange = Range(match.range(at: 1), in: line)
                let scopeRange = Range(match.range(at: 2), in: line)
                let descRange = Range(match.range(at: 3), in: line)
                
                let type = typeRange != nil ? String(line[typeRange!]).lowercased() : ""
                let scope = scopeRange != nil ? String(line[scopeRange!]).trimmingCharacters(in: .whitespaces) : nil
                let desc = descRange != nil ? String(line[descRange!]).trimmingCharacters(in: .whitespaces) : ""
                
                let formattedItem: String
                if let s = scope, !s.isEmpty {
                    formattedItem = "[\(s.uppercased())] \(desc)"
                } else {
                    formattedItem = desc
                }
                
                switch type {
                case "feat", "feature":
                    features.append(formattedItem)
                case "fix", "bugfix", "hotfix":
                    fixes.append(formattedItem)
                case "perf", "refactor", "style":
                    improvements.append(formattedItem)
                case "docs", "chore", "test", "revert":
                    others.append(formattedItem)
                default:
                    others.append(formattedItem)
                }
            } else {
                others.append(line)
            }
        }
        
        return ParsedChangelog(
            features: features,
            fixes: fixes,
            improvements: improvements,
            others: others
        )
    }
}

/// GitHub Release 附件实体模型
public struct GitHubAsset: Codable, Identifiable, Equatable {
    public let id: Int
    public let name: String
    public let size: Int64
    public let browserDownloadUrl: String
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case size
        case browserDownloadUrl = "browser_download_url"
    }
    
    public var formattedSize: String {
        guard size > 0 else { return "" }
        let mb = Double(size) / (1024.0 * 1024.0)
        return String(format: "%.1f MB", mb)
    }
}

/// GitHub Release 发布版本实体模型
public struct GitHubRelease: Codable, Identifiable, Equatable {
    public let id: Int
    public let tagName: String
    public let name: String
    public let body: String
    public let publishedAt: String
    public let assets: [GitHubAsset]
    
    enum CodingKeys: String, CodingKey {
        case id
        case tagName = "tag_name"
        case name
        case body
        case publishedAt = "published_at"
        case assets
    }
    
    /// 获取 macOS 安装包附件（优先 .dmg，其次 .zip）
    public var macOSAsset: GitHubAsset? {
        return assets.first { $0.name.lowercased().hasSuffix(".dmg") }
            ?? assets.first { $0.name.lowercased().hasSuffix(".zip") }
    }
    
    public var macOSDownloadUrl: String? {
        return macOSAsset?.browserDownloadUrl
    }
    
    public var parsedChangelog: ParsedChangelog {
        return ParsedChangelog.parse(rawBody: body)
    }
    
    /// 格式化发布日期（如 2026-08-28）
    public var formattedDate: String {
        if publishedAt.count >= 10 {
            return String(publishedAt.prefix(10))
        }
        return publishedAt
    }
}

/// 下载状态枚举
public enum DownloadStatus: Equatable {
    case idle
    case downloading
    case completed
    case failed(String)
    case canceled
}

/// 下载进度模型
public struct DownloadProgress: Equatable {
    public var receivedBytes: Int64 = 0
    public var totalBytes: Int64 = 0
    public var progress: Float = 0.0
    public var speedBytesPerSecond: Double = 0.0
    public var status: DownloadStatus = .idle
    public var localFilePath: URL? = nil
    
    public var formattedSpeed: String {
        if speedBytesPerSecond >= 1024 * 1024 {
            return String(format: "%.1f MB/s", speedBytesPerSecond / (1024.0 * 1024.0))
        } else if speedBytesPerSecond >= 1024 {
            return String(format: "%.1f KB/s", speedBytesPerSecond / 1024.0)
        } else {
            return String(format: "%.0f B/s", speedBytesPerSecond)
        }
    }
    
    public var formattedSizeProgress: String {
        let currentMb = Double(receivedBytes) / (1024.0 * 1024.0)
        let totalMb = Double(totalBytes) / (1024.0 * 1024.0)
        if totalBytes > 0 {
            return String(format: "%.1f MB / %.1f MB (%.0f%%)", currentMb, totalMb, progress * 100)
        } else {
            return String(format: "%.1f MB", currentMb)
        }
    }
}

/// 检查更新状态
public enum UpdateCheckState: Equatable {
    case idle
    case checking
    case hasUpdate(release: GitHubRelease, currentVersion: String, acceleratedUrl: String)
    case alreadyLatest(currentVersion: String)
    case error(message: String)
}

/// 软件检查更新与高速分发服务 (AppUpdaterService)
public final class AppUpdaterService: NSObject, ObservableObject, URLSessionDownloadDelegate {
    public static let shared = AppUpdaterService()
    
    public let repoOwner: String = "HuangZhuoRui"
    public let repoName: String = "AwesomeBar"
    
    private let accelerateBaseURL: String = "https://update.vincenthzr.org:8443"
    
    @Published public var checkState: UpdateCheckState = .idle
    @Published public var downloadProgress: DownloadProgress = DownloadProgress()
    
    private var downloadTask: URLSessionDownloadTask?
    private var urlSession: URLSession?
    private var lastReportTime: Date = Date()
    private var bytesSinceLastReport: Int64 = 0
    private var destinationFileURL: URL?
    
    public override init() {
        super.init()
    }
    
    /// 当前应用版本号（从 Bundle 读取，如 "1.0"）
    public var currentAppVersion: String {
        return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
    
    /// 当前应用构建号（如 "1"）
    public var currentAppBuild: String {
        return Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
    
    // MARK: - 版本检测
    
    /// 触发检查更新（在后台异步拉取）
    public func checkForUpdates(isUserInitiated: Bool = true) {
        checkState = .checking
        
        Task {
            let releases = await fetchReleases()
            await MainActor.run {
                guard let latest = releases.first else {
                    if isUserInitiated {
                        self.checkState = .error(message: "未能获取到版本发布信息，请稍后重试")
                    } else {
                        self.checkState = .idle
                    }
                    return
                }
                
                let current = self.currentAppVersion
                if self.isNewerVersion(latestTagName: latest.tagName, currentVersion: current) {
                    let directUrl = latest.macOSDownloadUrl ?? ""
                    let acceleratedUrl = self.getAcceleratedDownloadUrl(directUrl: directUrl)
                    self.checkState = .hasUpdate(
                        release: latest,
                        currentVersion: current,
                        acceleratedUrl: acceleratedUrl
                    )
                } else {
                    if isUserInitiated {
                        self.checkState = .alreadyLatest(currentVersion: current)
                    } else {
                        self.checkState = .idle
                    }
                }
            }
        }
    }
    
    /// 拉取 Releases 列表（双通道降级策略：优先自建高速镜像，失败则直连官方 GitHub API）
    public func fetchReleases() async -> [GitHubRelease] {
        // 1. 优先尝试自建高速镜像节点
        if let releases = await fetchFromUrl(urlString: "\(accelerateBaseURL)/api/\(repoName)/releases") {
            if !releases.isEmpty { return releases }
        }
        
        // 2. 降级尝试直连 GitHub 官方 API
        if let releases = await fetchFromUrl(urlString: "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases") {
            if !releases.isEmpty { return releases }
        }
        
        return []
    }
    
    private func fetchFromUrl(urlString: String) async -> [GitHubRelease]? {
        guard let url = URL(string: urlString) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8.0
        request.setValue("AwesomeBar-App/\(currentAppVersion)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResp = response as? HTTPURLResponse, (200...299).contains(httpResp.statusCode) else {
                return nil
            }
            let decoder = JSONDecoder()
            return try decoder.decode([GitHubRelease].self, from: data)
        } catch {
            return nil
        }
    }
    
    /// 获取自建服务器镜像加速下载地址
    public func getAcceleratedDownloadUrl(directUrl: String) -> String {
        guard !directUrl.isEmpty else { return directUrl }
        let githubPrefix = "https://github.com/"
        if directUrl.hasPrefix(githubPrefix) {
            let relativePath = String(directUrl.dropFirst(githubPrefix.count))
            return "\(accelerateBaseURL)/download/\(relativePath)"
        }
        return directUrl
    }
    
    /// 语义化版本比对（SemVer）
    public func isNewerVersion(latestTagName: String, currentVersion: String) -> Bool {
        let cleanLatest = cleanVersion(latestTagName)
        let cleanCurrent = cleanVersion(currentVersion)
        
        let latestParts = cleanLatest.split(separator: ".").compactMap { Int($0) }
        let currentParts = cleanCurrent.split(separator: ".").compactMap { Int($0) }
        
        let maxCount = max(latestParts.count, currentParts.count)
        for i in 0..<maxCount {
            let l = i < latestParts.count ? latestParts[i] : 0
            let c = i < currentParts.count ? currentParts[i] : 0
            if l > c { return true }
            if l < c { return false }
        }
        return false
    }
    
    private func cleanVersion(_ v: String) -> String {
        var clean = v.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if clean.hasPrefix("v") {
            clean = String(clean.dropFirst())
        }
        clean = clean.replacingOccurrences(of: "+", with: ".")
        if let hyphenIndex = clean.firstIndex(of: "-") {
            clean = String(clean[..<hyphenIndex])
        }
        return clean
    }
    
    // MARK: - 文件下载与安装
    
    /// 开始下载安装包
    public func startDownload(urlString: String, fileName: String) {
        guard let url = URL(string: urlString) else { return }
        
        let downloadsDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        self.destinationFileURL = downloadsDir.appendingPathComponent(fileName)
        
        downloadProgress = DownloadProgress(
            receivedBytes: 0,
            totalBytes: 0,
            progress: 0,
            speedBytesPerSecond: 0,
            status: .downloading,
            localFilePath: destinationFileURL
        )
        
        let config = URLSessionConfiguration.default
        urlSession = URLSession(configuration: config, delegate: self, delegateQueue: .main)
        
        downloadTask = urlSession?.downloadTask(with: url)
        lastReportTime = Date()
        bytesSinceLastReport = 0
        downloadTask?.resume()
    }
    
    /// 取消下载
    public func cancelDownload() {
        downloadTask?.cancel()
        downloadProgress.status = .canceled
    }
    
    /// 打开已下载的安装包（挂载 DMG 或在 Finder 中定位）
    public func openInstaller() {
        guard let fileURL = destinationFileURL, FileManager.default.fileExists(atPath: fileURL.path) else { return }
        NSWorkspace.shared.open(fileURL)
    }
    
    // MARK: - URLSessionDownloadDelegate
    
    public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        bytesSinceLastReport += bytesWritten
        let now = Date()
        let interval = now.timeIntervalSince(lastReportTime)
        
        if interval >= 0.25 {
            let speed = (Double(bytesSinceLastReport) / interval)
            let progress = totalBytesExpectedToWrite > 0
                ? Float(totalBytesWritten) / Float(totalBytesExpectedToWrite)
                : 0.0
            
            self.downloadProgress.receivedBytes = totalBytesWritten
            self.downloadProgress.totalBytes = totalBytesExpectedToWrite
            self.downloadProgress.progress = progress
            self.downloadProgress.speedBytesPerSecond = speed
            self.downloadProgress.status = .downloading
            
            lastReportTime = now
            bytesSinceLastReport = 0
        }
    }
    
    public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let dest = destinationFileURL else { return }
        
        do {
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.moveItem(at: location, to: dest)
            
            DispatchQueue.main.async {
                self.downloadProgress.progress = 1.0
                self.downloadProgress.status = .completed
                self.downloadProgress.localFilePath = dest
            }
        } catch {
            DispatchQueue.main.async {
                self.downloadProgress.status = .failed("文件保存失败: \(error.localizedDescription)")
            }
        }
    }
    
    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error as NSError?, error.code != NSURLErrorCancelled {
            DispatchQueue.main.async {
                self.downloadProgress.status = .failed(error.localizedDescription)
            }
        }
    }
}
