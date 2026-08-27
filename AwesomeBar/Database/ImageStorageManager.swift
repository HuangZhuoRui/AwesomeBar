import Foundation
import AppKit

/// 剪贴板图片原图与缩略图本地文件存储与内存高速缓存管理器
public final class ImageStorageManager {
    /// 全局共享单例
    public static let shared = ImageStorageManager()
    
    /// 文件系统管理器
    private let fileManager = FileManager.default
    /// 图片存储主目录 URL（存放在 ~/Library/Application Support/AwesomeBar/Images）
    private let imagesDirectory: URL
    /// 内存图片高速缓存（支持 ProMotion 120Hz 极速即时加载，避免滑动时频繁产生磁盘 I/O）
    private let inMemoryImageCache = NSCache<NSString, NSImage>()
    
    /// 私有初始化方法，确保目录已创建
    private init() {
        let applicationSupportUrl = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.imagesDirectory = applicationSupportUrl.appendingPathComponent("AwesomeBar/Images", isDirectory: true)
        
        try? fileManager.createDirectory(at: imagesDirectory, withIntermediateDirectories: true, attributes: nil)
        
        // 配置缓存上限（最多缓存 200 张缩略图，占用不超过 64MB 内存）
        inMemoryImageCache.countLimit = 200
        inMemoryImageCache.totalCostLimit = 64 * 1024 * 1024
    }
    
    /// 获取本地存储图片的完整绝对物理路径
    public func getImageFullPath(filename: String) -> String {
        if filename.hasPrefix("/") {
            return filename
        }
        return imagesDirectory.appendingPathComponent(filename).path
    }
    
    /// 保存 NSImage 图片对象至本地磁盘并写入内存缓存
    /// - Parameter image: 待保存的 NSImage
    /// - Returns: 生成的文件名（例如：`3B2E9D...png`）
    public func saveImage(image: NSImage) -> String? {
        guard let tiffData = image.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            return nil
        }
        
        let uniqueFileName = "\(UUID().uuidString).png"
        let destinationUrl = imagesDirectory.appendingPathComponent(uniqueFileName)
        
        do {
            try pngData.write(to: destinationUrl)
            inMemoryImageCache.setObject(image, forKey: uniqueFileName as NSString)
            return uniqueFileName
        } catch {
            print("保存图片到磁盘失败: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// 保存原始二进制图片数据
    /// - Parameter data: PNG 或 JPEG 二进制数据
    /// - Returns: 生成的文件名
    public func saveImageData(_ data: Data) -> String? {
        guard let image = NSImage(data: data) else { return nil }
        let uniqueFileName = "\(UUID().uuidString).png"
        let destinationUrl = imagesDirectory.appendingPathComponent(uniqueFileName)
        
        do {
            try data.write(to: destinationUrl)
            inMemoryImageCache.setObject(image, forKey: uniqueFileName as NSString)
            return uniqueFileName
        } catch {
            print("保存图片二进制数据失败: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// 根据文件名或绝对路径加载图片（优先内存高速缓存命中，0 磁盘 I/O 开销）
    /// - Parameter filename: 图片文件名或绝对路径
    /// - Returns: 对应的 NSImage 对象
    public func loadImage(filename: String) -> NSImage? {
        let cacheKey = filename as NSString
        if let cachedImage = inMemoryImageCache.object(forKey: cacheKey) {
            return cachedImage
        }
        
        let targetUrl: URL
        if filename.hasPrefix("/") {
            targetUrl = URL(fileURLWithPath: filename)
        } else {
            targetUrl = imagesDirectory.appendingPathComponent(filename)
        }
        
        if let diskImage = NSImage(contentsOf: targetUrl) {
            inMemoryImageCache.setObject(diskImage, forKey: cacheKey)
            return diskImage
        }
        return nil
    }
    
    /// 获取图片的本地文件完整 URL
    /// - Parameter filename: 图片文件名
    /// - Returns: 文件完整 URL
    public func imageURL(for filename: String) -> URL {
        return imagesDirectory.appendingPathComponent(filename)
    }
    
    /// 删除指定名称的图片文件及缓存
    /// - Parameter filename: 目标文件名
    public func deleteImage(filename: String) {
        inMemoryImageCache.removeObject(forKey: filename as NSString)
        let targetUrl = imagesDirectory.appendingPathComponent(filename)
        try? fileManager.removeItem(at: targetUrl)
    }
    
    /// 清除所有缓存的图片文件与内存缓存
    public func clearAllImages() {
        inMemoryImageCache.removeAllObjects()
        if let fileList = try? fileManager.contentsOfDirectory(at: imagesDirectory, includingPropertiesForKeys: nil) {
            for fileUrl in fileList {
                try? fileManager.removeItem(at: fileUrl)
            }
        }
    }
}
