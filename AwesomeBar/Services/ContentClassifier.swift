import Foundation

/// 剪贴板内容类型智能分类与模式识别器
public enum ContentClassifier {
    /// 十六进制 HEX 颜色正则表达式模式
    private static let hexColorPattern = "^#([0-9a-fA-F]{3}|[0-9a-fA-F]{4}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$"
    
    /// 常见编程语言语法关键字集合，用于代码片段识别
    private static let programmingKeywords: [String] = [
        "func ", "class ", "import ", "struct ", "enum ", "let ", "var ", "const ",
        "function", "def ", "return ", "if (", "for (", "while (", "switch (",
        "public ", "private ", "protected ", "interface ", "package ", "namespace ",
        "SELECT ", "INSERT INTO", "UPDATE ", "DELETE FROM", "<html>", "</div>", "/>",
        "console.log", "print(", "System.out", "#include", "std::", "async ", "await "
    ]
    
    /// 对输入的纯文本字符串进行内容特征分析与分类
    /// - Parameter text: 待分类的文本
    /// - Returns: 识别出的内容分类（颜色/链接/代码/纯文本）
    public static func classifyText(_ text: String) -> ClipboardContentType {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 1. 颜色色值识别（支持 #RGB, #RGBA, #RRGGBB, #RRGGBBAA 以及 rgb()/rgba()/hsl()）
        if trimmedText.range(of: hexColorPattern, options: .regularExpression) != nil {
            return .color
        }
        let lowercasedText = trimmedText.lowercased()
        if lowercasedText.hasPrefix("rgb(") || lowercasedText.hasPrefix("rgba(") || lowercasedText.hasPrefix("hsl(") {
            return .color
        }
        
        // 2. 网络 URL 链接识别
        if lowercasedText.hasPrefix("http://") || lowercasedText.hasPrefix("https://") || lowercasedText.hasPrefix("ftp://") {
            if let validUrl = URL(string: trimmedText), validUrl.host != nil {
                return .url
            }
        }
        
        // 3. 代码片段模式识别
        var matchedKeywordCount = 0
        for keyword in programmingKeywords {
            if text.contains(keyword) {
                matchedKeywordCount += 1
            }
        }
        
        if matchedKeywordCount >= 2 || (matchedKeywordCount >= 1 && (text.contains("{") || text.contains("}") || text.contains("=>") || text.contains("->"))) {
            return .code
        }
        
        // 4. 默认分类为通用纯文本
        return .text
    }
}
