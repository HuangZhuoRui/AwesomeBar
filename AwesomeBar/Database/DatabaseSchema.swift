import Foundation

/// SQLite 数据库表结构定义与 SQL 语句常量集合
public enum DatabaseSchema {
    /// 创建剪贴板数据表 SQL
    public static let createClipboardTableSQL: String = """
    CREATE TABLE IF NOT EXISTS clipboard_items (
        id TEXT PRIMARY KEY,
        type TEXT NOT NULL,
        content_text TEXT NOT NULL,
        html_content TEXT,
        image_path TEXT,
        file_paths TEXT,
        source_app_name TEXT,
        source_app_bundle_id TEXT,
        char_count INTEGER DEFAULT 0,
        word_count INTEGER DEFAULT 0,
        line_count INTEGER DEFAULT 0,
        is_pinned INTEGER DEFAULT 0,
        is_favorite INTEGER DEFAULT 0,
        copied_count INTEGER DEFAULT 1,
        created_at REAL NOT NULL,
        updated_at REAL NOT NULL
    );
    """
    
    /// 创建更新时间降序索引 SQL
    public static let createUpdatedAtIdxSQL: String = """
    CREATE INDEX IF NOT EXISTS idx_clipboard_updated_at ON clipboard_items(updated_at DESC);
    """
    
    /// 创建类型索引 SQL
    public static let createTypeIdxSQL: String = """
    CREATE INDEX IF NOT EXISTS idx_clipboard_type ON clipboard_items(type);
    """
    
    /// 创建置顶索引 SQL
    public static let createPinnedIdxSQL: String = """
    CREATE INDEX IF NOT EXISTS idx_clipboard_is_pinned ON clipboard_items(is_pinned);
    """
    
    /// 所有初始化 DDL 语句序列
    public static let allTableCreationStatements: [String] = [
        createClipboardTableSQL,
        createUpdatedAtIdxSQL,
        createTypeIdxSQL,
        createPinnedIdxSQL
    ]
}
