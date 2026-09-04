import SwiftUI

/// 「列表正在滚动」环境标记
///
/// 用途：macOS 上滚动列表时鼠标其实并未移动，是内容在鼠标下方掠过，
/// 这会让每一行依次被误判为「悬停」。若行视图在悬停态与静置态之间切换的是不同的视图结构
/// （例如整组操作按钮 ↔ 单个角标），SwiftUI 就会在滚动过程中反复重建视图树并重新布局，
/// 观感上就是卡片「原地闪烁」而不是平滑滚动。
///
/// 因此在滚动期间把该标记置为 true，各行据此忽略悬停事件；滚动停止后自然恢复。
/// 这样既消除闪烁，又完全不改变原有的悬停视觉设计。
private struct IsScrollingEnvironmentKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    /// 所在列表当前是否正在滚动
    public var isScrolling: Bool {
        get { self[IsScrollingEnvironmentKey.self] }
        set { self[IsScrollingEnvironmentKey.self] = newValue }
    }
}

/// 传递滚动内容纵向偏移量的 Preference Key
public struct ScrollOffsetPreferenceKey: PreferenceKey {
    public static let defaultValue: CGFloat = 0

    public static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
