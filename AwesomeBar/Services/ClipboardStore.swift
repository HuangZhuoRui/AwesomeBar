import Foundation
import Combine
import SwiftUI

/// 剪贴板单一响应式数据流状态中心（Single Source of Truth）
/// 负责内存增量流式更新、主线程实时广播，并异步后台持久化至本地 SQLite 数据库
public final class ClipboardStore: ObservableObject {
    /// 全局共享单例
    public static let shared = ClipboardStore()
    
    /// 内存中维护的全部剪贴板历史记录数组（按置顶与时间有序维护）
    @Published public private(set) var allItems: [ClipboardItem] = []
    /// 各分类下的实时条目数量映射
    @Published public private(set) var filterCounts: [ClipboardFilter: Int] = [:]
    
    /// 私有初始化方法，启动时从 SQLite 预加载全部历史记录至内存流
    private init() {
        loadInitialDataFromDatabase()
    }
    
    // MARK: - 初始化加载
    
    /// 从数据库初始化加载历史记录到内存数据流（自动过滤并清理已在磁盘被删除的失效临时文件）
    public func loadInitialDataFromDatabase() {
        let loadedItems = DatabaseManager.shared.fetchItems(filter: .all, limit: AppSettings.shared.maxHistoryCount)
        
        var validItems: [ClipboardItem] = []
        var deadItemIds: [UUID] = []
        
        for item in loadedItems {
            var isFileValid = true
            if item.type == .file {
                if let firstPath = item.filePaths?.first, !FileManager.default.fileExists(atPath: firstPath) {
                    isFileValid = false
                }
            } else if item.type == .image {
                if let path = item.imagePath, path.hasPrefix("/"), !FileManager.default.fileExists(atPath: path) {
                    isFileValid = false
                }
            }
            
            if isFileValid {
                validItems.append(item)
            } else {
                deadItemIds.append(item.id)
            }
        }
        
        let loadedCounts = computeFilterCounts(from: validItems)
        
        DispatchQueue.main.async {
            self.allItems = validItems
            self.filterCounts = loadedCounts
        }
        
        // 后台异步从 SQLite 清除已在物理磁盘被删除的失效文件记录
        if !deadItemIds.isEmpty {
            DispatchQueue.global(qos: .background).async {
                for id in deadItemIds {
                    DatabaseManager.shared.deleteItem(id: id)
                }
            }
        }
    }
    
    /// 动态清理失效文件记录
    public func cleanupDeletedFileItems() {
        var validItems: [ClipboardItem] = []
        var deadItemIds: [UUID] = []
        
        for item in allItems {
            var isFileValid = true
            if item.type == .file {
                if let firstPath = item.filePaths?.first, !FileManager.default.fileExists(atPath: firstPath) {
                    isFileValid = false
                }
            } else if item.type == .image {
                if let path = item.imagePath, path.hasPrefix("/"), !FileManager.default.fileExists(atPath: path) {
                    isFileValid = false
                }
            }
            
            if isFileValid {
                validItems.append(item)
            } else {
                deadItemIds.append(item.id)
            }
        }
        
        guard !deadItemIds.isEmpty else { return }
        
        let updatedCounts = computeFilterCounts(from: validItems)
        self.allItems = validItems
        self.filterCounts = updatedCounts
        
        DispatchQueue.global(qos: .background).async {
            for id in deadItemIds {
                DatabaseManager.shared.deleteItem(id: id)
            }
        }
    }
    
    // MARK: - 增量响应式数据流操作
    
    /// 处理新捕获到的剪贴板条目（主线程即时增量更新 + 后台异步落盘）
    /// - Parameter newItem: 新捕获的条目
    public func handleNewCapturedItem(_ newItem: ClipboardItem) {
        let performUpdate = {
            var currentItems = self.allItems
            
            // 1. 检查与内存中最新一条记录是否为连续重复复制
            if let firstItem = currentItems.first(where: { !$0.isPinned }) ?? currentItems.first,
               firstItem.type == newItem.type,
               firstItem.contentText == newItem.contentText {
                
                // 连续重复复制：内存中就地更新计数与时间戳（O(1) 增量更新）
                if let targetIndex = currentItems.firstIndex(where: { $0.id == firstItem.id }) {
                    currentItems[targetIndex].copiedCount += 1
                    currentItems[targetIndex].updatedAt = Date()
                    if let sourceApplicationName = newItem.sourceAppName {
                        currentItems[targetIndex].sourceAppName = sourceApplicationName
                    }
                    if let bundleIdentifier = newItem.sourceAppBundleId {
                        currentItems[targetIndex].sourceAppBundleId = bundleIdentifier
                    }
                    if let imagePath = newItem.imagePath {
                        currentItems[targetIndex].imagePath = imagePath
                    }
                    if let htmlContent = newItem.htmlContent {
                        currentItems[targetIndex].htmlContent = htmlContent
                    }
                }
            } else {
                // 2. 非连续复制（或首次复制）：直接向内存流头部插入新记录（O(1) 增量插入）
                currentItems.insert(newItem, at: 0)
            }
            
            // 3. 内存重新排序（置顶项在前，时间戳降序）
            currentItems.sort { lhs, rhs in
                if lhs.isPinned != rhs.isPinned {
                    return lhs.isPinned && !rhs.isPinned
                }
                return lhs.updatedAt > rhs.updatedAt
            }
            
            // 4. 超出历史上限则裁切尾部未置顶记录
            let maxCount = AppSettings.shared.maxHistoryCount
            if currentItems.count > maxCount {
                let unpinnedIndices = currentItems.indices.filter { !currentItems[$0].isPinned }
                if let lastUnpinnedIndex = unpinnedIndices.last {
                    currentItems.remove(at: lastUnpinnedIndex)
                }
            }
            
            // 5. 增量计算分类数量
            let updatedCounts = self.computeFilterCounts(from: currentItems)
            
            // 6. 即时更新状态（驱动所有 UI 瞬间同步渲染）
            self.allItems = currentItems
            self.filterCounts = updatedCounts
            
            // 7. 异步在后台持久化写入 SQLite 数据库
            DispatchQueue.global(qos: .background).async {
                DatabaseManager.shared.saveItem(newItem)
                DatabaseManager.shared.cleanupOldItems(maxCount: maxCount)
            }
            
            // 8. 广播新条目捕获通知（用于驱动小号粘贴板在边缘吸附态无焦点瞬时冒出）
            NotificationCenter.default.post(name: .clipboardItemDidCapture, object: newItem)
        }
        
        if Thread.isMainThread {
            performUpdate()
        } else {
            DispatchQueue.main.async {
                performUpdate()
            }
        }
    }
    
    /// 切换条目的置顶固定状态（置顶 <-> 解除置顶）
    /// - Parameter id: 目标条目 UUID
    public func togglePin(id: UUID) {
        guard let targetIndex = allItems.firstIndex(where: { $0.id == id }) else { return }
        
        var currentItems = allItems
        currentItems[targetIndex].isPinned.toggle()
        currentItems[targetIndex].updatedAt = Date()
        
        // 内存重新排序
        currentItems.sort { lhs, rhs in
            if lhs.isPinned != rhs.isPinned {
                return lhs.isPinned && !rhs.isPinned
            }
            return lhs.updatedAt > rhs.updatedAt
        }
        
        let updatedCounts = computeFilterCounts(from: currentItems)
        
        self.allItems = currentItems
        self.filterCounts = updatedCounts
        
        // 后台异步持久化
        DispatchQueue.global(qos: .background).async {
            _ = DatabaseManager.shared.togglePin(id: id)
        }
    }
    
    /// 切换条目的收藏状态（收藏 <-> 取消收藏）
    /// - Parameter id: 目标条目 UUID
    public func toggleFavorite(id: UUID) {
        guard let targetIndex = allItems.firstIndex(where: { $0.id == id }) else { return }
        
        var currentItems = allItems
        currentItems[targetIndex].isFavorite.toggle()
        let updatedCounts = computeFilterCounts(from: currentItems)
        
        self.allItems = currentItems
        self.filterCounts = updatedCounts
        
        // 后台异步持久化
        DispatchQueue.global(qos: .background).async {
            _ = DatabaseManager.shared.toggleFavorite(id: id)
        }
    }
    
    /// 删除单个条目
    /// - Parameter id: 目标条目 UUID
    public func deleteItem(id: UUID) {
        var currentItems = allItems
        currentItems.removeAll { $0.id == id }
        let updatedCounts = computeFilterCounts(from: currentItems)
        
        self.allItems = currentItems
        self.filterCounts = updatedCounts
        
        // 后台异步持久化删除
        DispatchQueue.global(qos: .background).async {
            DatabaseManager.shared.deleteItem(id: id)
        }
    }
    
    /// 清空剪贴板历史记录
    /// - Parameter exceptPinned: 是否保留置顶项
    public func clearAll(exceptPinned: Bool = true) {
        var currentItems = allItems
        if exceptPinned {
            currentItems.removeAll { !$0.isPinned }
        } else {
            currentItems.removeAll()
        }
        
        let updatedCounts = computeFilterCounts(from: currentItems)
        
        self.allItems = currentItems
        self.filterCounts = updatedCounts
        
        // 后台异步持久化清空
        DispatchQueue.global(qos: .background).async {
            DatabaseManager.shared.clearAll(exceptPinned: exceptPinned)
        }
    }
    
    // MARK: - 内存快速检索与分类映射
    
    /// 依据分类和关键词快速在内存流中筛选条目（零磁盘 I/O，极速渲染）
    /// - Parameters:
    ///   - filter: 分类过滤枚举
    ///   - searchQuery: 搜索关键词
    /// - Returns: 筛选后的条目数组
    public func queryFilteredItems(filter: ClipboardFilter, searchQuery: String) -> [ClipboardItem] {
        let trimmedQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        return allItems.filter { item in
            // 1. 分类过滤
            let matchesFilter: Bool
            switch filter {
            case .all:
                matchesFilter = true
            case .pinned:
                matchesFilter = item.isPinned
            case .favorites:
                matchesFilter = item.isFavorite
            case .text:
                matchesFilter = (item.effectiveType == .text || item.effectiveType == .richText)
            case .image:
                matchesFilter = (item.effectiveType == .image)
            case .url:
                matchesFilter = (item.effectiveType == .url)
            case .code:
                matchesFilter = (item.effectiveType == .code)
            case .color:
                matchesFilter = (item.effectiveType == .color)
            case .file:
                matchesFilter = (item.effectiveType == .file)
            }
            
            guard matchesFilter else { return false }
            
            // 2. 关键词搜索
            if trimmedQuery.isEmpty {
                return true
            }
            
            let matchesContent = item.contentText.lowercased().contains(trimmedQuery)
            let matchesAppName = (item.sourceAppName ?? "").lowercased().contains(trimmedQuery)
            return matchesContent || matchesAppName
        }
    }
    
    /// 内存中 O(N) 极速计算各分类数量映射
    private func computeFilterCounts(from itemsList: [ClipboardItem]) -> [ClipboardFilter: Int] {
        var counts: [ClipboardFilter: Int] = [
            .all: itemsList.count,
            .pinned: 0,
            .favorites: 0,
            .text: 0,
            .image: 0,
            .url: 0,
            .code: 0,
            .color: 0,
            .file: 0
        ]
        
        for item in itemsList {
            if item.isPinned { counts[.pinned, default: 0] += 1 }
            if item.isFavorite { counts[.favorites, default: 0] += 1 }
            
            switch item.effectiveType {
            case .text, .richText:
                counts[.text, default: 0] += 1
            case .image:
                counts[.image, default: 0] += 1
            case .url:
                counts[.url, default: 0] += 1
            case .code:
                counts[.code, default: 0] += 1
            case .color:
                counts[.color, default: 0] += 1
            case .file:
                counts[.file, default: 0] += 1
            }
        }
        
        return counts
    }
}

extension Notification.Name {
    /// 新剪贴板条目捕获通知
    public static let clipboardItemDidCapture = Notification.Name("AwesomeBar.clipboardItemDidCapture")
}
