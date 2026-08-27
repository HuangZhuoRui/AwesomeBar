import Foundation
import AppKit

/// 操作音频与触觉反馈播放管理器
public final class SoundManager {
    /// 全局共享单例
    public static let shared = SoundManager()
    
    /// 私有初始化方法
    private init() {}
    
    /// 播放复制成功提示音（清脆 Pop 音效）
    public func playCopySound() {
        guard AppSettings.shared.playSoundEffects else { return }
        NSSound(named: "Pop")?.play()
    }
    
    /// 播放粘贴完成提示音（轻盈 Tink 音效）
    public func playPasteSound() {
        guard AppSettings.shared.playSoundEffects else { return }
        NSSound(named: "Tink")?.play()
    }
    
    /// 播放删除条目提示音（低沉 Basso 音效）
    public func playDeleteSound() {
        guard AppSettings.shared.playSoundEffects else { return }
        NSSound(named: "Basso")?.play()
    }
    
    /// 播放置顶与取消置顶提示音（柔和 Purr 音效）
    public func playPinSound() {
        guard AppSettings.shared.playSoundEffects else { return }
        NSSound(named: "Purr")?.play()
    }
}
