import SwiftUI
import AppKit

/// 剪贴板条目根据其数据类型的特化预览视图（颜色块、图片缩略图、代码高亮卡、文本、链接、文件）
public struct ContentPreviewView: View {
    /// 目标条目
    public let item: ClipboardItem
    /// 颜色快速复制成功的临时状态
    @State private var isColorCopySuccessShowing: Bool = false
    
    public init(item: ClipboardItem) {
        self.item = item
    }
    
    public var body: some View {
        switch item.type {
        case .color:
            // 颜色色值特化预览
            HStack(spacing: 8) {
                if let hexString = item.colorHex {
                    Button(action: {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(hexString, forType: .string)
                        SoundManager.shared.playCopySound()
                        withAnimation {
                            isColorCopySuccessShowing = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                            withAnimation {
                                isColorCopySuccessShowing = false
                            }
                        }
                    }) {
                        HStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color(hex: hexString) ?? .gray)
                                .frame(width: 24, height: 24)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .stroke(Color.white.opacity(0.4), lineWidth: 1)
                                )
                            
                            Text(isColorCopySuccessShowing ? "已复制色值" : item.contentText)
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .foregroundColor(isColorCopySuccessShowing ? .green : .primary)
                        }
                    }
                    .buttonStyle(.plain)
                    .help("点击仅复制该 HEX 颜色代码")
                }
            }
            
        case .image:
            // 图片缩略图特化预览
            HStack(spacing: 8) {
                let imageFile = item.imagePath ?? item.filePaths?.first
                if let path = imageFile,
                   let loadedImage = ImageStorageManager.shared.loadImage(filename: path) {
                    Image(nsImage: loadedImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 44, height: 32)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Color.white.opacity(0.3), lineWidth: 1)
                        )
                } else {
                    Image(systemName: "photo.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.purple)
                        .frame(width: 32, height: 32)
                        .background(Color.purple.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                
                Text(item.previewTitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
            }
            
        case .url:
            // 网络 URL 链接特化预览
            HStack(spacing: 6) {
                Text(item.previewTitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.blue)
                    .lineLimit(1)
                
                Button(action: {
                    if let targetUrl = URL(string: item.contentText) {
                        NSWorkspace.shared.open(targetUrl)
                    }
                }) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("在默认浏览器中打开此网页链接")
            }
            
        case .file:
            // 文件及文件夹路径特化预览（包含图片文件缩略图）
            HStack(spacing: 8) {
                let imageExtensions = ["jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "tiff", "tif", "bmp", "svg", "ico"]
                let firstPath = item.filePaths?.first ?? ""
                let pathExtension = (firstPath as NSString).pathExtension.lowercased()
                
                if imageExtensions.contains(pathExtension),
                   let loadedImage = ImageStorageManager.shared.loadImage(filename: firstPath) {
                    Image(nsImage: loadedImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 44, height: 32)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Color.white.opacity(0.3), lineWidth: 1)
                        )
                }
                
                Text(item.previewTitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                if !firstPath.isEmpty {
                    Button(action: {
                        let fileUrl = URL(fileURLWithPath: firstPath)
                        NSWorkspace.shared.activateFileViewerSelecting([fileUrl])
                    }) {
                        Image(systemName: "folder.badge.gearshape")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("在访达 Finder 中定位该文件")
                }
            }
            
        case .code:
            // 代码片段等宽字体特化预览
            VStack(alignment: .leading, spacing: 2) {
                Text(item.previewTitle)
                    .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                if !item.previewSnippet.isEmpty {
                    Text(item.previewSnippet)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            
        case .text, .richText:
            // 纯文本、富文本标准预览
            VStack(alignment: .leading, spacing: 2) {
                Text(item.previewTitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                if !item.previewSnippet.isEmpty {
                    Text(item.previewSnippet)
                        .font(.system(size: 11.5))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
}
