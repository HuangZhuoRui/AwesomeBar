import SwiftUI
import AppKit

// MARK: - NSColor 十六进制色值扩展
extension NSColor {
    /// 通过十六进制 HEX 颜色字符串初始化 NSColor
    /// - Parameter hex: 十六进制字符串（支持 "#RGB", "#RGBA", "#RRGGBB", "#RRGGBBAA" 或不带 "#"）
    public convenience init?(hex: String) {
        var sanitizedHex = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if sanitizedHex.hasPrefix("#") {
            sanitizedHex.remove(at: sanitizedHex.startIndex)
        }
        
        var rgbValue: UInt64 = 0
        guard Scanner(string: sanitizedHex).scanHexInt64(&rgbValue) else { return nil }
        
        if sanitizedHex.count == 6 {
            let red = CGFloat((rgbValue & 0xFF0000) >> 16) / 255.0
            let green = CGFloat((rgbValue & 0x00FF00) >> 8) / 255.0
            let blue = CGFloat(rgbValue & 0x0000FF) / 255.0
            self.init(red: red, green: green, blue: blue, alpha: 1.0)
        } else if sanitizedHex.count == 8 {
            let red = CGFloat((rgbValue & 0xFF000000) >> 24) / 255.0
            let green = CGFloat((rgbValue & 0x00FF0000) >> 16) / 255.0
            let blue = CGFloat((rgbValue & 0x0000FF00) >> 8) / 255.0
            let alpha = CGFloat(rgbValue & 0x000000FF) / 255.0
            self.init(red: red, green: green, blue: blue, alpha: alpha)
        } else {
            return nil
        }
    }
}

// MARK: - SwiftUI Color 十六进制色值扩展
extension Color {
    /// 通过十六进制 HEX 颜色字符串初始化 SwiftUI Color
    /// - Parameter hex: 十六进制字符串（支持 "#RGB", "#RGBA", "#RRGGBB", "#RRGGBBAA"）
    public init?(hex: String) {
        var sanitizedHex = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if sanitizedHex.hasPrefix("#") {
            sanitizedHex.remove(at: sanitizedHex.startIndex)
        }
        
        var rgbValue: UInt64 = 0
        guard Scanner(string: sanitizedHex).scanHexInt64(&rgbValue) else { return nil }
        
        if sanitizedHex.count == 6 {
            let red = Double((rgbValue & 0xFF0000) >> 16) / 255.0
            let green = Double((rgbValue & 0x00FF00) >> 8) / 255.0
            let blue = Double(rgbValue & 0x0000FF) / 255.0
            self.init(red: red, green: green, blue: blue)
        } else if sanitizedHex.count == 8 {
            let red = Double((rgbValue & 0xFF000000) >> 24) / 255.0
            let green = Double((rgbValue & 0x00FF0000) >> 16) / 255.0
            let blue = Double((rgbValue & 0x0000FF00) >> 8) / 255.0
            let alpha = Double(rgbValue & 0x000000FF) / 255.0
            self.init(red: red, green: green, blue: blue, opacity: alpha)
        } else {
            return nil
        }
    }
}
