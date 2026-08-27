import Foundation
import CryptoKit

/// 文本数据格式转换与结构化排版工具集
public enum TextFormatter {
    /// 转为全大写字符串
    /// - Parameter text: 原始文本
    /// - Returns: 大写文本
    public static func toUpperCase(_ text: String) -> String {
        return text.uppercased()
    }
    
    /// 转为全小写字符串
    /// - Parameter text: 原始文本
    /// - Returns: 小写文本
    public static func toLowerCase(_ text: String) -> String {
        return text.lowercased()
    }
    
    /// 转为每个单词首字母大写
    /// - Parameter text: 原始文本
    /// - Returns: 首字母大写文本
    public static func toTitleCase(_ text: String) -> String {
        return text.capitalized
    }
    
    /// 对 JSON 格式字符串进行多行结构化缩进美化排版
    /// - Parameter text: 待排版的 JSON 字符串
    /// - Returns: 美化后的 JSON 字符串（若解析失败则返回 nil）
    public static func prettifyJSON(_ text: String) -> String? {
        guard let jsonData = text.data(using: .utf8),
              let jsonObject = try? JSONSerialization.jsonObject(with: jsonData, options: []),
              let prettyPrintedData = try? JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted]),
              let formattedString = String(data: prettyPrintedData, encoding: .utf8) else {
            return nil
        }
        return formattedString
    }
    
    /// 将多行 JSON 压缩为紧凑单行格式
    /// - Parameter text: 原始 JSON 文本
    /// - Returns: 单行压缩 JSON 字符串（若解析失败则返回 nil）
    public static func minifyJSON(_ text: String) -> String? {
        guard let jsonData = text.data(using: .utf8),
              let jsonObject = try? JSONSerialization.jsonObject(with: jsonData, options: []),
              let minifiedData = try? JSONSerialization.data(withJSONObject: jsonObject, options: []),
              let resultString = String(data: minifiedData, encoding: .utf8) else {
            return nil
        }
        return resultString
    }
    
    /// 对字符串执行标准 URL 百分号编码
    /// - Parameter text: 原始文本
    /// - Returns: 编码后文本
    public static func urlEncode(_ text: String) -> String? {
        return text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
    }
    
    /// 对已编码的 URL 字符串进行解码还原
    /// - Parameter text: 编码文本
    /// - Returns: 解码后文本
    public static func urlDecode(_ text: String) -> String? {
        return text.removingPercentEncoding
    }
    
    /// 对字符串执行 Base64 编码
    /// - Parameter text: 原始文本
    /// - Returns: Base64 编码字符串
    public static func base64Encode(_ text: String) -> String? {
        guard let utf8Data = text.data(using: .utf8) else { return nil }
        return utf8Data.base64EncodedString()
    }
    
    /// 对 Base64 字符串执行还原解码
    /// - Parameter text: Base64 编码文本
    /// - Returns: 解码后的纯文本（若数据损坏则返回 nil）
    public static func base64Decode(_ text: String) -> String? {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let base64Data = Data(base64Encoded: cleanText),
              let decodedString = String(data: base64Data, encoding: .utf8) else {
            return nil
        }
        return decodedString
    }
    
    /// 压缩并去除文本中多余的连续空白字符
    /// - Parameter text: 原始文本
    /// - Returns: 压缩后的单行文本
    public static func compressWhitespaces(_ text: String) -> String {
        let segments = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        return segments.joined(separator: " ")
    }
    
    /// 移除文本中的所有换行符并拼接为单行
    /// - Parameter text: 原始文本
    /// - Returns: 去除换行后的文本
    public static func removeLineBreaks(_ text: String) -> String {
        return text.components(separatedBy: .newlines).joined(separator: " ")
    }
    
    /// 计算文本的 MD5 摘要哈希值
    /// - Parameter text: 原始文本
    /// - Returns: 32位十六进制 MD5 字符串
    public static func computeMD5Hash(_ text: String) -> String {
        guard let data = text.data(using: .utf8) else { return "" }
        let digest = Insecure.MD5.hash(data: data)
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }
    
    /// 计算文本的 SHA256 摘要哈希值
    /// - Parameter text: 原始文本
    /// - Returns: 64位十六进制 SHA256 字符串
    public static func computeSHA256Hash(_ text: String) -> String {
        guard let data = text.data(using: .utf8) else { return "" }
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }
}
