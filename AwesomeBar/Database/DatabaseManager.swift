import Foundation
import SQLite3

/// SQLite3 原生剪贴板持久化数据库管理器
///
/// 标记为 nonisolated 并声明 @unchecked Sendable：本类自带串行队列 databaseQueue，
/// 且以 SQLITE_OPEN_FULLMUTEX 打开连接，线程安全由这两者共同保证，
/// 不依赖工程默认的 MainActor 隔离——它本就应当在后台队列上执行。
public nonisolated final class DatabaseManager: @unchecked Sendable {
    /// 全局共享单例
    public static let shared = DatabaseManager()
    
    /// SQLite 数据库指针引用
    private var databasePointer: OpaquePointer?
    /// 保证数据库读写线程安全的串行队列
    private let databaseQueue = DispatchQueue(label: "com.awesomebar.database.queue", qos: .userInitiated)
    /// 数据库文件路径 URL
    private let databaseFileURL: URL
    
    /// 私有初始化方法，自动在 Application Support 创建数据库并建表
    private init() {
        let fileManager = FileManager.default
        let applicationSupportUrl = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDirectory = applicationSupportUrl.appendingPathComponent("AwesomeBar", isDirectory: true)
        
        try? fileManager.createDirectory(at: appDirectory, withIntermediateDirectories: true, attributes: nil)
        
        self.databaseFileURL = appDirectory.appendingPathComponent("clipboard.sqlite")
        openDatabaseConnection()
        initializeDatabaseTables()
        bootstrapInitialWelcomeData()
    }
    
    deinit {
        if let connection = databasePointer {
            sqlite3_close(connection)
        }
    }
    
    // MARK: - 数据库初始化
    
    /// 打开 SQLite 数据库连接
    private func openDatabaseConnection() {
        var connectionPointer: OpaquePointer?
        let openResult = sqlite3_open_v2(
            databaseFileURL.path,
            &connectionPointer,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        
        if openResult == SQLITE_OK {
            self.databasePointer = connectionPointer
            print("成功连接 SQLite 数据库: \(databaseFileURL.path)")
        } else {
            print("连接 SQLite 数据库失败: 错误码 \(openResult)")
        }
    }
    
    /// 创建数据表与相关性能索引
    private func initializeDatabaseTables() {
        databaseQueue.sync {
            guard let connection = self.databasePointer else { return }
            
            for statementSQL in DatabaseSchema.allTableCreationStatements {
                var errorMessagePointer: UnsafeMutablePointer<CChar>?
                let executionResult = sqlite3_exec(connection, statementSQL, nil, nil, &errorMessagePointer)
                if executionResult != SQLITE_OK {
                    if let errorMessagePointer = errorMessagePointer {
                        let errorMessage = String(cString: errorMessagePointer)
                        print("执行建表 SQL 失败: \(errorMessage)")
                        sqlite3_free(errorMessagePointer)
                    }
                }
            }
        }
    }
    
    /// 首次启动时注入精美初始示范数据
    private func bootstrapInitialWelcomeData() {
        if getItemCount() == 0 {
            let baseDate = Date()
            
            let welcomeItem = ClipboardItem(
                type: .text,
                contentText: "🎉 欢迎使用 AwesomeBar！按下左 Option (⌥) 键即可随时唤起与收起面板。支持置顶、搜索、历史记录与格式转换。",
                sourceAppName: "AwesomeBar",
                isPinned: false,
                createdAt: baseDate.addingTimeInterval(-1),
                updatedAt: baseDate.addingTimeInterval(-1)
            )
            let blueColorItem = ClipboardItem(
                type: .color,
                contentText: "#007AFF",
                sourceAppName: "ColorPicker",
                createdAt: baseDate.addingTimeInterval(-2),
                updatedAt: baseDate.addingTimeInterval(-2)
            )
            let appleUrlItem = ClipboardItem(
                type: .url,
                contentText: "https://developer.apple.com/swift/",
                sourceAppName: "Safari",
                createdAt: baseDate.addingTimeInterval(-3),
                updatedAt: baseDate.addingTimeInterval(-3)
            )
            let codeSnippetItem = ClipboardItem(
                type: .code,
                contentText: "struct AwesomeBar {\n    let isLiquidGlass = true\n    let isPureSwift = true\n    let supportsPinToTop = true\n}",
                sourceAppName: "Xcode",
                createdAt: baseDate.addingTimeInterval(-4),
                updatedAt: baseDate.addingTimeInterval(-4)
            )
            let orangeColorItem = ClipboardItem(
                type: .color,
                contentText: "#FF9500",
                sourceAppName: "Figma",
                createdAt: baseDate.addingTimeInterval(-5),
                updatedAt: baseDate.addingTimeInterval(-5)
            )
            
            saveItem(orangeColorItem)
            saveItem(codeSnippetItem)
            saveItem(appleUrlItem)
            saveItem(blueColorItem)
            saveItem(welcomeItem)
        }
    }
    
    // MARK: - CRUD 增删查改核心业务
    
    /// 保存剪贴板条目（连续去重机制：若与最近一条复制记录的内容及类型完全一致，则视为连续重复复制，仅更新时间戳和计数；若为非连续复制如 A -> B -> A，则作为独立新条目完整保留）
    /// - Parameter item: 待保存的剪贴板条目
    /// - Returns: 保存或更新后的剪贴板条目数据
    @discardableResult
    public func saveItem(_ item: ClipboardItem) -> ClipboardItem {
        return databaseQueue.sync {
            guard let connection = self.databasePointer else { return item }
            
            // 1. 检查数据库中最近一次复制的记录（判断是否为连续重复复制）
            if let mostRecentItem = fetchMostRecentItem(),
               mostRecentItem.type == item.type,
               mostRecentItem.contentText == item.contentText {
                
                let updateSQL = """
                UPDATE clipboard_items SET
                    updated_at = ?,
                    copied_count = copied_count + 1,
                    source_app_name = COALESCE(?, source_app_name),
                    source_app_bundle_id = COALESCE(?, source_app_bundle_id),
                    image_path = COALESCE(?, image_path),
                    html_content = COALESCE(?, html_content)
                WHERE id = ?;
                """
                
                var statementPointer: OpaquePointer?
                if sqlite3_prepare_v2(connection, updateSQL, -1, &statementPointer, nil) == SQLITE_OK {
                    let currentTimestamp = Date().timeIntervalSince1970
                    sqlite3_bind_double(statementPointer, 1, currentTimestamp)
                    
                    if let appName = item.sourceAppName {
                        sqlite3_bind_text(statementPointer, 2, (appName as NSString).utf8String, -1, nil)
                    } else {
                        sqlite3_bind_null(statementPointer, 2)
                    }
                    
                    if let bundleIdentifier = item.sourceAppBundleId {
                        sqlite3_bind_text(statementPointer, 3, (bundleIdentifier as NSString).utf8String, -1, nil)
                    } else {
                        sqlite3_bind_null(statementPointer, 3)
                    }
                    
                    if let imagePath = item.imagePath {
                        sqlite3_bind_text(statementPointer, 4, (imagePath as NSString).utf8String, -1, nil)
                    } else {
                        sqlite3_bind_null(statementPointer, 4)
                    }
                    
                    if let html = item.htmlContent {
                        sqlite3_bind_text(statementPointer, 5, (html as NSString).utf8String, -1, nil)
                    } else {
                        sqlite3_bind_null(statementPointer, 5)
                    }
                    
                    sqlite3_bind_text(statementPointer, 6, (mostRecentItem.id.uuidString as NSString).utf8String, -1, nil)
                    
                    _ = sqlite3_step(statementPointer)
                    sqlite3_finalize(statementPointer)
                }
                
                var updatedItem = mostRecentItem
                updatedItem.updatedAt = Date()
                updatedItem.copiedCount += 1
                if let applicationName = item.sourceAppName { updatedItem.sourceAppName = applicationName }
                if let bundleIdentifier = item.sourceAppBundleId { updatedItem.sourceAppBundleId = bundleIdentifier }
                if let imagePath = item.imagePath { updatedItem.imagePath = imagePath }
                if let html = item.htmlContent { updatedItem.htmlContent = html }
                return updatedItem
            }
            
            // 2. 非连续重复（例如首次复制，或 A -> B -> A 场景），作为独立新记录完整插入
            let insertSQL = """
            INSERT INTO clipboard_items (
                id, type, content_text, html_content, image_path, file_paths,
                source_app_name, source_app_bundle_id, char_count, word_count,
                line_count, is_pinned, is_favorite, copied_count, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
            
            var statementPointer: OpaquePointer?
            if sqlite3_prepare_v2(connection, insertSQL, -1, &statementPointer, nil) == SQLITE_OK {
                sqlite3_bind_text(statementPointer, 1, (item.id.uuidString as NSString).utf8String, -1, nil)
                sqlite3_bind_text(statementPointer, 2, (item.type.rawValue as NSString).utf8String, -1, nil)
                sqlite3_bind_text(statementPointer, 3, (item.contentText as NSString).utf8String, -1, nil)
                
                if let html = item.htmlContent {
                    sqlite3_bind_text(statementPointer, 4, (html as NSString).utf8String, -1, nil)
                } else {
                    sqlite3_bind_null(statementPointer, 4)
                }
                
                if let imagePath = item.imagePath {
                    sqlite3_bind_text(statementPointer, 5, (imagePath as NSString).utf8String, -1, nil)
                } else {
                    sqlite3_bind_null(statementPointer, 5)
                }
                
                if let files = item.filePaths,
                   let filesData = try? JSONEncoder().encode(files),
                   let filesJSONString = String(data: filesData, encoding: .utf8) {
                    sqlite3_bind_text(statementPointer, 6, (filesJSONString as NSString).utf8String, -1, nil)
                } else {
                    sqlite3_bind_null(statementPointer, 6)
                }
                
                if let applicationName = item.sourceAppName {
                    sqlite3_bind_text(statementPointer, 7, (applicationName as NSString).utf8String, -1, nil)
                } else {
                    sqlite3_bind_null(statementPointer, 7)
                }
                
                if let bundleIdentifier = item.sourceAppBundleId {
                    sqlite3_bind_text(statementPointer, 8, (bundleIdentifier as NSString).utf8String, -1, nil)
                } else {
                    sqlite3_bind_null(statementPointer, 8)
                }
                
                sqlite3_bind_int(statementPointer, 9, Int32(item.charCount))
                sqlite3_bind_int(statementPointer, 10, Int32(item.wordCount))
                sqlite3_bind_int(statementPointer, 11, Int32(item.lineCount))
                sqlite3_bind_int(statementPointer, 12, item.isPinned ? 1 : 0)
                sqlite3_bind_int(statementPointer, 13, item.isFavorite ? 1 : 0)
                sqlite3_bind_int(statementPointer, 14, Int32(item.copiedCount))
                sqlite3_bind_double(statementPointer, 15, item.createdAt.timeIntervalSince1970)
                sqlite3_bind_double(statementPointer, 16, item.updatedAt.timeIntervalSince1970)
                
                _ = sqlite3_step(statementPointer)
                sqlite3_finalize(statementPointer)
            }
            
            return item
        }
    }
    
    /// 获取数据库中按创建时间降序排列的最近一条记录（用于比对是否连续复制）
    private func fetchMostRecentItem() -> ClipboardItem? {
        guard let connection = self.databasePointer else { return nil }
        
        let selectSQL = "SELECT * FROM clipboard_items ORDER BY created_at DESC, rowid DESC LIMIT 1;"
        var statementPointer: OpaquePointer?
        var recentItem: ClipboardItem?
        
        if sqlite3_prepare_v2(connection, selectSQL, -1, &statementPointer, nil) == SQLITE_OK {
            if sqlite3_step(statementPointer) == SQLITE_ROW {
                recentItem = parseItemFromStatement(statementPointer)
            }
            sqlite3_finalize(statementPointer)
        }
        return recentItem
    }
    
    /// 依条件查询剪贴板条目列表
    /// - Parameters:
    ///   - filter: 分类过滤枚举
    ///   - searchQuery: 搜索关键词
    ///   - limit: 最大返回条数
    ///   - offset: 分页偏移量
    /// - Returns: 符合条件的条目数组
    public func fetchItems(
        filter: ClipboardFilter = .all,
        searchQuery: String = "",
        limit: Int = 100,
        offset: Int = 0
    ) -> [ClipboardItem] {
        return databaseQueue.sync {
            guard let connection = self.databasePointer else { return [] }
            
            var conditions: [String] = []
            var queryParameters: [(Int32, String)] = []
            var currentParameterIndex: Int32 = 1
            
            switch filter {
            case .all:
                break
            case .pinned:
                conditions.append("is_pinned = 1")
            case .favorites:
                conditions.append("is_favorite = 1")
            case .text:
                conditions.append("(type = 'text' OR type = 'richText')")
            case .image:
                conditions.append("type = 'image'")
            case .url:
                conditions.append("type = 'url'")
            case .code:
                conditions.append("type = 'code'")
            case .color:
                conditions.append("type = 'color'")
            case .file:
                conditions.append("type = 'file'")
            }
            
            let trimmedSearchQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedSearchQuery.isEmpty {
                conditions.append("(content_text LIKE ? OR source_app_name LIKE ?)")
                let wildCardPattern = "%\(trimmedSearchQuery)%"
                queryParameters.append((currentParameterIndex, wildCardPattern))
                currentParameterIndex += 1
                queryParameters.append((currentParameterIndex, wildCardPattern))
                currentParameterIndex += 1
            }
            
            var selectSQL = "SELECT * FROM clipboard_items"
            if !conditions.isEmpty {
                selectSQL += " WHERE " + conditions.joined(separator: " AND ")
            }
            selectSQL += " ORDER BY is_pinned DESC, updated_at DESC, rowid DESC LIMIT ? OFFSET ?;"
            
            var statementPointer: OpaquePointer?
            var itemsList: [ClipboardItem] = []
            
            if sqlite3_prepare_v2(connection, selectSQL, -1, &statementPointer, nil) == SQLITE_OK {
                for (parameterIndex, parameterValue) in queryParameters {
                    sqlite3_bind_text(statementPointer, parameterIndex, (parameterValue as NSString).utf8String, -1, nil)
                }
                sqlite3_bind_int(statementPointer, currentParameterIndex, Int32(limit))
                sqlite3_bind_int(statementPointer, currentParameterIndex + 1, Int32(offset))
                
                while sqlite3_step(statementPointer) == SQLITE_ROW {
                    if let parsedItem = parseItemFromStatement(statementPointer) {
                        itemsList.append(parsedItem)
                    }
                }
                sqlite3_finalize(statementPointer)
            }
            
            return itemsList
        }
    }
    
    /// 获取每个分类下的条目总数量字典（单条 SQL 聚合，超高性能）
    /// - Returns: 分类与对应数量的字典映射
    public func fetchFilterCounts() -> [ClipboardFilter: Int] {
        return databaseQueue.sync {
            guard let connection = self.databasePointer else { return [:] }
            
            var countsDictionary: [ClipboardFilter: Int] = [:]
            
            let querySQL = """
            SELECT 
                COUNT(*),
                COALESCE(SUM(CASE WHEN is_pinned = 1 THEN 1 ELSE 0 END), 0),
                COALESCE(SUM(CASE WHEN is_favorite = 1 THEN 1 ELSE 0 END), 0),
                COALESCE(SUM(CASE WHEN type = 'text' OR type = 'richText' THEN 1 ELSE 0 END), 0),
                COALESCE(SUM(CASE WHEN type = 'image' THEN 1 ELSE 0 END), 0),
                COALESCE(SUM(CASE WHEN type = 'url' THEN 1 ELSE 0 END), 0),
                COALESCE(SUM(CASE WHEN type = 'code' THEN 1 ELSE 0 END), 0),
                COALESCE(SUM(CASE WHEN type = 'color' THEN 1 ELSE 0 END), 0),
                COALESCE(SUM(CASE WHEN type = 'file' THEN 1 ELSE 0 END), 0)
            FROM clipboard_items;
            """
            
            var statementPointer: OpaquePointer?
            if sqlite3_prepare_v2(connection, querySQL, -1, &statementPointer, nil) == SQLITE_OK {
                if sqlite3_step(statementPointer) == SQLITE_ROW {
                    countsDictionary[.all] = Int(sqlite3_column_int(statementPointer, 0))
                    countsDictionary[.pinned] = Int(sqlite3_column_int(statementPointer, 1))
                    countsDictionary[.favorites] = Int(sqlite3_column_int(statementPointer, 2))
                    countsDictionary[.text] = Int(sqlite3_column_int(statementPointer, 3))
                    countsDictionary[.image] = Int(sqlite3_column_int(statementPointer, 4))
                    countsDictionary[.url] = Int(sqlite3_column_int(statementPointer, 5))
                    countsDictionary[.code] = Int(sqlite3_column_int(statementPointer, 6))
                    countsDictionary[.color] = Int(sqlite3_column_int(statementPointer, 7))
                    countsDictionary[.file] = Int(sqlite3_column_int(statementPointer, 8))
                }
                sqlite3_finalize(statementPointer)
            }
            
            return countsDictionary
        }
    }
    
    /// 切换条目的置顶固定状态（置顶 <-> 解除置顶）
    /// - Parameter id: 目标条目 UUID
    /// - Returns: 是否操作成功
    public func togglePin(id: UUID) -> Bool {
        return databaseQueue.sync {
            guard let connection = self.databasePointer else { return false }
            
            let updateSQL = "UPDATE clipboard_items SET is_pinned = CASE WHEN is_pinned = 1 THEN 0 ELSE 1 END WHERE id = ?;"
            var statementPointer: OpaquePointer?
            var isSuccess = false
            
            if sqlite3_prepare_v2(connection, updateSQL, -1, &statementPointer, nil) == SQLITE_OK {
                sqlite3_bind_text(statementPointer, 1, (id.uuidString as NSString).utf8String, -1, nil)
                if sqlite3_step(statementPointer) == SQLITE_DONE {
                    isSuccess = true
                }
                sqlite3_finalize(statementPointer)
            }
            return isSuccess
        }
    }
    
    /// 切换条目的收藏状态（收藏 <-> 取消收藏）
    /// - Parameter id: 目标条目 UUID
    /// - Returns: 是否操作成功
    public func toggleFavorite(id: UUID) -> Bool {
        return databaseQueue.sync {
            guard let connection = self.databasePointer else { return false }
            
            let updateSQL = "UPDATE clipboard_items SET is_favorite = CASE WHEN is_favorite = 1 THEN 0 ELSE 1 END WHERE id = ?;"
            var statementPointer: OpaquePointer?
            var isSuccess = false
            
            if sqlite3_prepare_v2(connection, updateSQL, -1, &statementPointer, nil) == SQLITE_OK {
                sqlite3_bind_text(statementPointer, 1, (id.uuidString as NSString).utf8String, -1, nil)
                if sqlite3_step(statementPointer) == SQLITE_DONE {
                    isSuccess = true
                }
                sqlite3_finalize(statementPointer)
            }
            return isSuccess
        }
    }
    
    /// 删除单个条目及其关联的本地文件
    /// - Parameter id: 目标条目 UUID
    public func deleteItem(id: UUID) {
        databaseQueue.sync {
            guard let connection = self.databasePointer else { return }
            
            // 查询关联的图片文件名
            let selectImageSQL = "SELECT image_path FROM clipboard_items WHERE id = ?;"
            var statementPointer: OpaquePointer?
            var imageFilenameToDelete: String?
            
            if sqlite3_prepare_v2(connection, selectImageSQL, -1, &statementPointer, nil) == SQLITE_OK {
                sqlite3_bind_text(statementPointer, 1, (id.uuidString as NSString).utf8String, -1, nil)
                if sqlite3_step(statementPointer) == SQLITE_ROW {
                    if let cStringPointer = sqlite3_column_text(statementPointer, 0) {
                        imageFilenameToDelete = String(cString: cStringPointer)
                    }
                }
                sqlite3_finalize(statementPointer)
            }
            
            if let imageFilename = imageFilenameToDelete {
                ImageStorageManager.shared.deleteImage(filename: imageFilename)
            }
            
            let deleteSQL = "DELETE FROM clipboard_items WHERE id = ?;"
            if sqlite3_prepare_v2(connection, deleteSQL, -1, &statementPointer, nil) == SQLITE_OK {
                sqlite3_bind_text(statementPointer, 1, (id.uuidString as NSString).utf8String, -1, nil)
                _ = sqlite3_step(statementPointer)
                sqlite3_finalize(statementPointer)
            }
        }
    }
    
    /// 清除历史记录
    /// - Parameter exceptPinned: 是否保留置顶条目
    public func clearAll(exceptPinned: Bool = true) {
        databaseQueue.sync {
            guard let connection = self.databasePointer else { return }
            
            let deleteSQL: String
            if exceptPinned {
                deleteSQL = "DELETE FROM clipboard_items WHERE is_pinned = 0;"
            } else {
                deleteSQL = "DELETE FROM clipboard_items;"
                ImageStorageManager.shared.clearAllImages()
            }
            
            var statementPointer: OpaquePointer?
            if sqlite3_prepare_v2(connection, deleteSQL, -1, &statementPointer, nil) == SQLITE_OK {
                _ = sqlite3_step(statementPointer)
                sqlite3_finalize(statementPointer)
            }
        }
    }
    
    /// 获取当前数据库中总记录数量
    public func getItemCount() -> Int {
        return databaseQueue.sync {
            guard let connection = self.databasePointer else { return 0 }
            let countSQL = "SELECT COUNT(*) FROM clipboard_items;"
            var statementPointer: OpaquePointer?
            var totalCount = 0
            
            if sqlite3_prepare_v2(connection, countSQL, -1, &statementPointer, nil) == SQLITE_OK {
                if sqlite3_step(statementPointer) == SQLITE_ROW {
                    totalCount = Int(sqlite3_column_int(statementPointer, 0))
                }
                sqlite3_finalize(statementPointer)
            }
            return totalCount
        }
    }
    
    /// 清理超出最大数量限制的历史记录（保留置顶项）
    /// - Parameter maxCount: 最大保留数量
    public func cleanupOldItems(maxCount: Int) {
        databaseQueue.sync {
            guard let connection = self.databasePointer else { return }
            
            let countUnpinnedSQL = "SELECT COUNT(*) FROM clipboard_items WHERE is_pinned = 0;"
            var statementPointer: OpaquePointer?
            var unpinnedCount = 0
            
            if sqlite3_prepare_v2(connection, countUnpinnedSQL, -1, &statementPointer, nil) == SQLITE_OK {
                if sqlite3_step(statementPointer) == SQLITE_ROW {
                    unpinnedCount = Int(sqlite3_column_int(statementPointer, 0))
                }
                sqlite3_finalize(statementPointer)
            }
            
            if unpinnedCount > maxCount {
                let deleteCount = unpinnedCount - maxCount
                let deleteOldSQL = """
                DELETE FROM clipboard_items WHERE id IN (
                    SELECT id FROM clipboard_items WHERE is_pinned = 0 ORDER BY updated_at ASC LIMIT ?
                );
                """
                if sqlite3_prepare_v2(connection, deleteOldSQL, -1, &statementPointer, nil) == SQLITE_OK {
                    sqlite3_bind_int(statementPointer, 1, Int32(deleteCount))
                    _ = sqlite3_step(statementPointer)
                    sqlite3_finalize(statementPointer)
                }
            }
        }
    }
    
    // MARK: - 结果集解析辅助方法
    
    /// 从 SQLite Statement 游标中解析 ClipboardItem 实体
    private func parseItemFromStatement(_ statementPointer: OpaquePointer?) -> ClipboardItem? {
        guard let statementPointer = statementPointer else { return nil }
        
        guard let idCString = sqlite3_column_text(statementPointer, 0),
              let id = UUID(uuidString: String(cString: idCString)),
              let typeCString = sqlite3_column_text(statementPointer, 1),
              let type = ClipboardContentType(rawValue: String(cString: typeCString)),
              let contentCString = sqlite3_column_text(statementPointer, 2) else {
            return nil
        }
        
        let contentText = String(cString: contentCString)
        
        var htmlContent: String?
        if let htmlCString = sqlite3_column_text(statementPointer, 3) {
            htmlContent = String(cString: htmlCString)
        }
        
        var imagePath: String?
        if let imageCString = sqlite3_column_text(statementPointer, 4) {
            imagePath = String(cString: imageCString)
        }
        
        var filePaths: [String]?
        if let filesCString = sqlite3_column_text(statementPointer, 5) {
            let filesJSONString = String(cString: filesCString)
            if let filesData = filesJSONString.data(using: .utf8) {
                filePaths = try? JSONDecoder().decode([String].self, from: filesData)
            }
        }
        
        var sourceAppName: String?
        if let applicationCString = sqlite3_column_text(statementPointer, 6) {
            sourceAppName = String(cString: applicationCString)
        }
        
        var sourceAppBundleId: String?
        if let bundleCString = sqlite3_column_text(statementPointer, 7) {
            sourceAppBundleId = String(cString: bundleCString)
        }
        
        let charCount = Int(sqlite3_column_int(statementPointer, 8))
        let wordCount = Int(sqlite3_column_int(statementPointer, 9))
        let lineCount = Int(sqlite3_column_int(statementPointer, 10))
        let isPinned = sqlite3_column_int(statementPointer, 11) == 1
        let isFavorite = sqlite3_column_int(statementPointer, 12) == 1
        let copiedCount = Int(sqlite3_column_int(statementPointer, 13))
        let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(statementPointer, 14))
        let updatedAt = Date(timeIntervalSince1970: sqlite3_column_double(statementPointer, 15))
        
        return ClipboardItem(
            id: id,
            type: type,
            contentText: contentText,
            htmlContent: htmlContent,
            imagePath: imagePath,
            filePaths: filePaths,
            sourceAppName: sourceAppName,
            sourceAppBundleId: sourceAppBundleId,
            charCount: charCount,
            wordCount: wordCount,
            lineCount: lineCount,
            isPinned: isPinned,
            isFavorite: isFavorite,
            copiedCount: copiedCount,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
