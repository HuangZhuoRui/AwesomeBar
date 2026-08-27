import SwiftUI
import AppKit

/// 剪贴板条目深入检查与全功能文本格式转换弹窗组件
public struct DetailPreviewSheet: View {
    /// 目标条目
    public let item: ClipboardItem
    /// 关闭弹窗回调
    public var onClose: () -> Void
    /// 执行粘贴回调（自动粘贴并收起浮动窗口）
    public var onPasteAndClose: (ClipboardItem) -> Void
    
    /// 当前可编辑与转换的文本内容
    @State private var workingTextContent: String
    /// 临时提示气泡文本
    @State private var toastPromptMessage: String?
    @Environment(\.colorScheme) private var colorScheme
    
    public init(item: ClipboardItem, onClose: @escaping () -> Void, onPasteAndClose: @escaping (ClipboardItem) -> Void) {
        self.item = item
        self.onClose = onClose
        self.onPasteAndClose = onPasteAndClose
        self._workingTextContent = State(initialValue: item.contentText)
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // 1. 顶部标题栏与类型标识
            headerBarView
            
            Divider()
            
            // 2. 中间内容预览与工具箱滚动区
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    contentPreviewArea
                    statisticsBadgesArea
                    
                    if item.type == .text || item.type == .richText || item.type == .code || item.type == .url {
                        textTransformationToolsArea
                    }
                }
                .padding(20)
            }
            
            Divider()
            
            // 3. 底部操作按钮栏
            footerActionBarView
        }
        .frame(width: 560, height: 470)
        .background(
            LiquidGlassBackground(cornerRadius: 18)
        )
    }
    
    // MARK: - 区域子视图
    
    private var headerBarView: some View {
        HStack(spacing: 12) {
            Image(systemName: item.type.iconName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.accentColor)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(item.type.displayName)
                    .font(.system(size: 15, weight: .bold))
                
                Text("创建于 \(item.fullTimeDisplay) • \(item.sourceAppName ?? "未知应用")")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("关闭详情 (Esc)")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color.primary.opacity(0.03))
    }
    
    @ViewBuilder
    private var contentPreviewArea: some View {
        if item.type == .image,
           let imageFileName = item.imagePath,
           let loadedImage = ImageStorageManager.shared.loadImage(filename: imageFileName) {
            Image(nsImage: loadedImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxHeight: 200)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
                .frame(maxWidth: .infinity, alignment: .center)
        } else if item.type == .color, let hexString = item.colorHex {
            HStack(spacing: 16) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(hex: hexString) ?? .gray)
                    .frame(width: 50, height: 50)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.3), lineWidth: 1))
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(hexString)
                        .font(.system(size: 17, weight: .bold, design: .monospaced))
                    Text("可点击下方工具快速转换色值与文本")
                        .font(.system(size: 11.5))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 4)
        } else {
            TextEditor(text: $workingTextContent)
                .font(.system(size: 13, design: item.type == .code ? .monospaced : .default))
                .frame(minHeight: 130, maxHeight: 190)
                .padding(6)
                .background(Color.primary.opacity(0.03))
                .cornerRadius(8)
        }
    }
    
    private var statisticsBadgesArea: some View {
        HStack(spacing: 10) {
            statBadge(title: "字符数", value: "\(workingTextContent.count)")
            statBadge(title: "单词数", value: "\(ClipboardItem(type: item.type, contentText: workingTextContent).wordCount)")
            statBadge(title: "行数", value: "\(workingTextContent.components(separatedBy: .newlines).count)")
            statBadge(title: "使用频次", value: "\(item.copiedCount) 次")
        }
    }
    
    private var textTransformationToolsArea: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("文本快速转换与排版工具箱")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                toolButton("转大写", icon: "textformat.size.larger") {
                    workingTextContent = TextFormatter.toUpperCase(workingTextContent)
                    displayToast(message: "已转为大写")
                }
                toolButton("转小写", icon: "textformat.size.smaller") {
                    workingTextContent = TextFormatter.toLowerCase(workingTextContent)
                    displayToast(message: "已转为小写")
                }
                toolButton("首字母大写", icon: "textformat") {
                    workingTextContent = TextFormatter.toTitleCase(workingTextContent)
                    displayToast(message: "已转为首字母大写")
                }
                toolButton("去除多余空白", icon: "arrow.left.and.right") {
                    workingTextContent = TextFormatter.compressWhitespaces(workingTextContent)
                    displayToast(message: "已压缩多余空白")
                }
                toolButton("JSON 美化", icon: "curlybraces") {
                    if let prettified = TextFormatter.prettifyJSON(workingTextContent) {
                        workingTextContent = prettified
                        displayToast(message: "JSON 已排版美化")
                    } else {
                        displayToast(message: "非标准 JSON 格式")
                    }
                }
                toolButton("JSON 压缩", icon: "chevron.compact.right") {
                    if let minified = TextFormatter.minifyJSON(workingTextContent) {
                        workingTextContent = minified
                        displayToast(message: "JSON 已压缩为单行")
                    } else {
                        displayToast(message: "非标准 JSON 格式")
                    }
                }
                toolButton("URL 编码", icon: "link.badge.plus") {
                    if let encoded = TextFormatter.urlEncode(workingTextContent) {
                        workingTextContent = encoded
                        displayToast(message: "已完成 URL 编码")
                    }
                }
                toolButton("URL 解码", icon: "link") {
                    if let decoded = TextFormatter.urlDecode(workingTextContent) {
                        workingTextContent = decoded
                        displayToast(message: "已完成 URL 解码")
                    }
                }
                toolButton("Base64 编码", icon: "lock.fill") {
                    if let encoded = TextFormatter.base64Encode(workingTextContent) {
                        workingTextContent = encoded
                        displayToast(message: "已完成 Base64 编码")
                    }
                }
                toolButton("Base64 解码", icon: "lock.open.fill") {
                    if let decoded = TextFormatter.base64Decode(workingTextContent) {
                        workingTextContent = decoded
                        displayToast(message: "已完成 Base64 解码")
                    } else {
                        displayToast(message: "Base64 解码失败")
                    }
                }
                toolButton("MD5 哈希", icon: "number") {
                    let hash = TextFormatter.computeMD5Hash(workingTextContent)
                    workingTextContent = hash
                    displayToast(message: "已计算 MD5 哈希")
                }
                toolButton("SHA256 哈希", icon: "shield.checkerboard") {
                    let hash = TextFormatter.computeSHA256Hash(workingTextContent)
                    workingTextContent = hash
                    displayToast(message: "已计算 SHA256 哈希")
                }
            }
        }
    }
    
    private var footerActionBarView: some View {
        HStack {
            if let toastText = toastPromptMessage {
                Text(toastText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.accentColor)
                    .transition(.opacity)
            }
            
            Spacer()
            
            Button("仅复制内容 (保持打开)") {
                var updatedItem = item
                updatedItem.contentText = workingTextContent
                PasteSimulator.shared.copyToClipboard(item: updatedItem)
                displayToast(message: "已复制到剪贴板")
            }
            .buttonStyle(.bordered)
            .help("仅写入系统剪贴板，不粘贴、不收起窗口")
            
            Button("粘贴并收起 (↵)") {
                var updatedItem = item
                updatedItem.contentText = workingTextContent
                onPasteAndClose(updatedItem)
            }
            .buttonStyle(.borderedProminent)
            .help("写回系统剪贴板，并自动粘贴至活动窗口并收起")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.primary.opacity(0.03))
    }
    
    private func statBadge(title: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 13, weight: .bold))
            Text(title)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.04))
        .cornerRadius(6)
    }
    
    private func toolButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(title)
                    .font(.system(size: 10.5, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .background(Color.primary.opacity(0.05))
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
    
    private func displayToast(message: String) {
        withAnimation {
            self.toastPromptMessage = message
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                if self.toastPromptMessage == message {
                    self.toastPromptMessage = nil
                }
            }
        }
    }
}
