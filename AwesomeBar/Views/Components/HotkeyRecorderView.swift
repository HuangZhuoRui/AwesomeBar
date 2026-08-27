import SwiftUI
import AppKit

/// 自定义快捷键录制与预设快速切换组件
public struct HotkeyRecorderView: View {
    /// 绑定的快捷键实体
    @Binding public var binding: HotkeyBinding
    /// 预设常用推荐列表
    public var presets: [HotkeyBinding]
    
    @State private var isRecording: Bool = false
    @State private var eventMonitor: Any?
    @Environment(\.colorScheme) private var colorScheme
    
    public init(
        binding: Binding<HotkeyBinding>,
        presets: [HotkeyBinding] = [
            .singleOption,
            .doubleOption,
            .optionSpace,
            .optionV,
            .optionB,
            .cmdShiftV,
            .cmdShiftB,
            .none
        ]
    ) {
        self._binding = binding
        self.presets = presets
    }
    
    public var body: some View {
        HStack(spacing: 8) {
            // 1. 快捷键录制主按钮
            Button(action: {
                if isRecording {
                    stopRecording()
                } else {
                    startRecording()
                }
            }) {
                HStack(spacing: 6) {
                    if isRecording {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 7, height: 7)
                        Text("请在键盘上按下快捷键...")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundColor(.primary)
                    } else {
                        Image(systemName: iconForBinding)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Text(binding.displayTitle)
                            .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                            .foregroundColor(.primary)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isRecording
                              ? Color.red.opacity(colorScheme == .dark ? 0.2 : 0.08)
                              : (colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05)))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(isRecording ? Color.red.opacity(0.6) : Color.primary.opacity(0.1), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .help(isRecording ? "按 Esc 取消录制" : "点击即可直接按下键盘录制自定义快捷键")
            
            // 2. 常用预设快捷切换下拉菜单
            Menu {
                Section(header: Text("常用快捷键预设")) {
                    ForEach(presets, id: \.self) { preset in
                        Button(action: {
                            binding = preset
                        }) {
                            HStack {
                                Text(preset.displayTitle)
                                if binding == preset {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
                
                Divider()
                
                Button("自定义录制快捷键") {
                    startRecording()
                }
            } label: {
                Image(systemName: "chevron.down.circle")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 18)
            .help("选择常用预设快捷键")
        }
    }
    
    // MARK: - 辅助计算图标
    
    private var iconForBinding: String {
        switch binding.kind {
        case .singleOption, .doubleOption:
            return "option"
        case .keyCombination:
            return "command"
        case .none:
            return "slash.circle"
        }
    }
    
    // MARK: - 录制事件监听
    
    private func startRecording() {
        stopRecording()
        isRecording = true
        
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            // Esc 取消录制
            if event.type == .keyDown && event.keyCode == 53 {
                self.stopRecording()
                return nil
            }
            
            // 解析录制的按键组合
            if event.type == .keyDown {
                if let recorded = HotkeyBinding.fromEvent(event) {
                    self.binding = recorded
                    self.stopRecording()
                    SoundManager.shared.playCopySound()
                    return nil
                }
            }
            
            return event
        }
    }
    
    private func stopRecording() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        isRecording = false
    }
}
