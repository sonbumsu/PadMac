import AppKit
import SwiftUI

/// 버튼별 동작을 고르는 설정 창
struct SettingsView: View {
    @ObservedObject var store: ConfigStore
    @StateObject private var recorder = KeyRecorder()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScrollView {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                    GridRow {
                        Text("버튼").bold()
                        Text("기본").bold()
                        Text("L2 누른 채").bold()
                    }
                    Divider().gridCellUnsizedAxes(.horizontal)
                    ForEach(PadButton.allCases) { b in
                        GridRow {
                            Text(b.label)
                            actionMenu(b, layer: false)
                            if b.hasLayer {
                                actionMenu(b, layer: true)
                            } else {
                                Text("레이어 버튼").foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
                .padding(.trailing, 12)
            }

            Divider()

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                GridRow {
                    Text("마우스 속도")
                    Slider(value: $store.config.cursorSpeed, in: 400...3200)
                }
                GridRow {
                    Text("스크롤 속도")
                    Slider(value: $store.config.scrollSpeed, in: 600...6000)
                }
                GridRow {
                    Text("")
                    Toggle("스크롤 방향 반전", isOn: $store.config.invertScroll)
                }
            }

            Text("""
                 왼쪽 스틱(마우스), 오른쪽 스틱(스크롤), Options(켜기/끄기)는 고정입니다.
                 L2는 짧게 눌렀다 떼면 "기본" 동작, 누른 채 다른 버튼을 누르면 그 버튼의 "L2 누른 채" 동작이 실행됩니다.
                 ⌘Space·⌘Tab처럼 macOS가 먼저 가져가는 단축키는 직접 입력이 안 되니 목록에서 고르세요.
                 """)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("기본값으로 되돌리기") { store.config = .defaults }
                Spacer()
                Button("설정 파일 보기") {
                    NSWorkspace.shared.activateFileViewerSelecting([store.fileURL])
                }
            }
        }
        .padding(20)
        .frame(width: 620, height: 720)
        .onDisappear { recorder.stop() }
    }

    private func actionMenu(_ b: PadButton, layer: Bool) -> some View {
        let target = KeyRecorder.Target(button: b, layer: layer)
        let title = recorder.target == target
            ? "키 조합을 누르세요… (Esc 취소)"
            : store.action(b, layer: layer).display

        return Menu(title) {
            ForEach(Array(PadAction.presetGroups.enumerated()), id: \.offset) { i, group in
                if i > 0 { Divider() }
                ForEach(group) { preset in
                    Button(preset.name) {
                        recorder.stop()
                        store.set(b, layer: layer, preset.action)
                    }
                }
            }
            Divider()
            Button("단축키 직접 입력…") {
                recorder.start(target) { combo in
                    store.set(b, layer: layer, .key(combo: combo))
                }
            }
        }
        .frame(width: 220)
    }
}

/// 설정 창에서 누른 키 조합을 한 번 녹화한다.
final class KeyRecorder: ObservableObject {
    struct Target: Equatable {
        let button: PadButton
        let layer: Bool
    }

    @Published private(set) var target: Target?
    private var monitor: Any?

    func start(_ target: Target, onRecord: @escaping (KeyCombo) -> Void) {
        stop()
        self.target = target
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let mods = event.modifierFlags.intersection([.command, .shift, .option, .control])
            if event.keyCode == 53 && mods.isEmpty { // Esc 단독 = 취소
                self.stop()
                return nil
            }
            onRecord(KeyCombo(keyCode: event.keyCode,
                              command: mods.contains(.command),
                              shift: mods.contains(.shift),
                              option: mods.contains(.option),
                              control: mods.contains(.control)))
            self.stop()
            return nil // 녹화한 키는 앱에 전달하지 않음
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        target = nil
    }
}
