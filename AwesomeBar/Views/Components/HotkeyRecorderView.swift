import SwiftUI
import AppKit

/// 自定义快捷键录制与预设快速切换组件（支持多按键序列完整捕获：从第一个按键按下持续追踪，直到最后一个按键全部松开才确认录制）
public struct HotkeyRecorderView: View {
    /// 绑定的快捷键实体
    @Binding public var binding: HotkeyBinding
    /// 预设常用推荐列表
    public var presets: [HotkeyBinding]
    
    /// 是否正处于录制模式
    @State private var isRecording: Bool = false
    /// 本地键盘事件监听器
    @State private var eventMonitor: Any?
    /// 当前物理按下的按键 KeyCode 集合（用于精准判定何时全部松开）
    @State private var pressedKeyCodes: Set<UInt16> = []
    /// 本次录制累积捕获的全部修饰键
    @State private var accumulatedModifiers: NSEvent.ModifierFlags = []
    /// 本次录制累积捕获的普通字符按键 KeyCode
    @State private var accumulatedKeyCode: UInt16? = nil
    /// 本次录制累积捕获的单修饰键 KeyCode (如左 Option 58, 右 Option 61)
    @State private var accumulatedModifierKeyCode: UInt16? = nil
    /// 是否已有按键被按下（标记录制活跃期）
    @State private var isChordActive: Bool = false
    /// 实时按键预览文本
    @State private var previewText: String = ""
    
    @Environment(\.colorScheme) private var colorScheme
    
    public init(
        binding: Binding<HotkeyBinding>,
        presets: [HotkeyBinding] = [
            .singleOption,
            .doubleOption,
            .singleRightOption,
            .doubleRightOption,
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
                        
                        Text(previewText.isEmpty ? "请按下组合键..." : previewText)
                            .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
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
                              ? Color.red.opacity(colorScheme == .dark ? 0.22 : 0.09)
                              : (colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05)))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(isRecording ? Color.red.opacity(0.65) : Color.primary.opacity(0.1), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .help(isRecording ? "按 Esc 取消录制，松开所有按键即可确认保存" : "点击即可直接按下键盘录制自定义快捷键（支持多按键组合，松开所有按键后生效）")
            
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
        case .singleOption, .doubleOption, .singleRightOption, .doubleRightOption:
            return "option"
        case .singleControl, .doubleControl:
            return "control"
        case .keyCombination:
            return "command"
        case .none:
            return "slash.circle"
        }
    }
    
    // MARK: - 多按键完整生命周期录制引擎
    
    private func startRecording() {
        stopRecording()
        
        isRecording = true
        pressedKeyCodes.removeAll()
        accumulatedModifiers = []
        accumulatedKeyCode = nil
        accumulatedModifierKeyCode = nil
        isChordActive = false
        previewText = ""
        
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { event in
            // Esc 取消录制（仅在未开始输入有效按键时生效）
            if event.type == .keyDown && event.keyCode == 53 && !isChordActive {
                self.stopRecording()
                return nil
            }
            
            switch event.type {
            case .keyDown:
                let keyCode = event.keyCode
                let isModifierKey = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63].contains(keyCode)
                
                if !isModifierKey {
                    self.isChordActive = true
                    self.pressedKeyCodes.insert(keyCode)
                    self.accumulatedKeyCode = keyCode
                    
                    let currentMods = event.modifierFlags.intersection([.command, .option, .shift, .control])
                    self.accumulatedModifiers.formUnion(currentMods)
                    
                    self.updatePreview()
                    return nil
                }
                
            case .keyUp:
                let keyCode = event.keyCode
                self.pressedKeyCodes.remove(keyCode)
                
                // 核心规则：当第一个按键已按下，且最后一个按键松开（当前按键集合完全清空）时，确认并完成录制！
                if self.isChordActive && self.pressedKeyCodes.isEmpty {
                    self.finishRecording()
                    return nil
                }
                
            case .flagsChanged:
                let keyCode = event.keyCode
                let cleanFlags = event.modifierFlags.intersection([.command, .option, .shift, .control])
                
                // 根据具体物理键码精确判断该修饰键是按下还是松开
                let isKeyDown: Bool
                switch keyCode {
                case 55, 54: // Command
                    isKeyDown = cleanFlags.contains(.command)
                case 58, 61: // Option
                    isKeyDown = cleanFlags.contains(.option)
                case 56, 60: // Shift
                    isKeyDown = cleanFlags.contains(.shift)
                case 59, 62: // Control
                    isKeyDown = cleanFlags.contains(.control)
                default:
                    isKeyDown = !cleanFlags.isEmpty
                }
                
                if isKeyDown {
                    // 修饰键按下：加入当前物理按键集合并累积修饰键标记
                    self.isChordActive = true
                    self.pressedKeyCodes.insert(keyCode)
                    self.accumulatedModifierKeyCode = keyCode
                    self.accumulatedModifiers.formUnion(cleanFlags)
                    self.updatePreview()
                } else {
                    // 修饰键松开：从当前物理按键集合移除
                    self.pressedKeyCodes.remove(keyCode)
                    
                    // 核心规则：当最后一个修饰键也松开时，确认并完成录制！
                    if self.isChordActive && self.pressedKeyCodes.isEmpty {
                        self.finishRecording()
                        return nil
                    }
                }
                
            default:
                break
            }
            
            return nil
        }
    }
    
    /// 刷新录制过程中的动态预览文本
    private func updatePreview() {
        self.previewText = HotkeyBinding.previewString(
            modifiers: accumulatedModifiers,
            keyCode: accumulatedKeyCode,
            modifierKeyCode: accumulatedModifierKeyCode
        )
    }
    
    /// 最终完成并保存录制的快捷键
    private func finishRecording() {
        if let newBinding = HotkeyBinding.makeBinding(
            modifiers: accumulatedModifiers,
            keyCode: accumulatedKeyCode,
            modifierKeyCode: accumulatedModifierKeyCode
        ) {
            self.binding = newBinding
            SoundManager.shared.playCopySound()
        }
        
        stopRecording()
    }
    
    /// 停止录制并清理监听器与临时状态
    private func stopRecording() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        isRecording = false
        isChordActive = false
        pressedKeyCodes.removeAll()
        accumulatedModifiers = []
        accumulatedKeyCode = nil
        accumulatedModifierKeyCode = nil
        previewText = ""
    }
}
