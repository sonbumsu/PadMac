import Foundation
import CoreGraphics

// MARK: - 패드 버튼

/// 설정할 수 있는 버튼. (스틱 이동과 Options 버튼은 고정)
enum PadButton: String, Codable, CaseIterable, Identifiable, CodingKeyRepresentable {
    case l1, r1, l2, r2, l3, r3
    case cross, circle, square, triangle
    case dpadUp, dpadDown, dpadLeft, dpadRight
    case create, ps, touchpad

    var id: String { rawValue }

    var label: String {
        switch self {
        case .l1: return "L1"
        case .r1: return "R1"
        case .l2: return "L2 (짧게)"
        case .r2: return "R2"
        case .l3: return "L3 (왼쪽 스틱 누르기)"
        case .r3: return "R3 (오른쪽 스틱 누르기)"
        case .cross: return "✕"
        case .circle: return "○"
        case .square: return "□"
        case .triangle: return "△"
        case .dpadUp: return "방향키 ↑"
        case .dpadDown: return "방향키 ↓"
        case .dpadLeft: return "방향키 ←"
        case .dpadRight: return "방향키 →"
        case .create: return "Create"
        case .ps: return "PS"
        case .touchpad: return "터치패드 클릭"
        }
    }

    /// L2는 레이어 버튼 자체라서 "L2 누른 채" 동작이 없다.
    var hasLayer: Bool { self != .l2 }
}

// MARK: - 키 조합

struct KeyCombo: Codable, Hashable {
    var keyCode: CGKeyCode
    var command = false
    var shift = false
    var option = false
    var control = false

    /// ⌘/⌃/⌥ 가 없는 키만 누르고 있을 때 반복한다. (⌘T 를 꾹 눌러 탭이 잔뜩 열리는 것 방지)
    var repeats: Bool { !command && !control && !option }

    var display: String {
        var s = ""
        if control { s += "⌃" }
        if option { s += "⌥" }
        if shift { s += "⇧" }
        if command { s += "⌘" }
        return s + KeyNames.name(keyCode)
    }
}

// MARK: - 동작

enum PadAction: Codable, Hashable {
    case none
    case leftClick
    case rightClick
    case missionControl
    case appSwitcher
    case key(combo: KeyCombo)

    var display: String {
        if let preset = PadAction.presetGroups.joined().first(where: { $0.action == self }) {
            return preset.name
        }
        if case .key(let c) = self { return c.display }
        return "없음"
    }

    struct Preset: Identifiable {
        let name: String
        let action: PadAction
        var id: String { name }
    }

    private static func k(_ code: CGKeyCode, cmd: Bool = false, shift: Bool = false,
                          ctrl: Bool = false) -> PadAction {
        .key(combo: KeyCombo(keyCode: code, command: cmd, shift: shift, control: ctrl))
    }

    /// 설정 창 목록에 보이는 동작들 (그룹마다 구분선)
    static let presetGroups: [[Preset]] = [
        [
            Preset(name: "없음", action: .none),
        ],
        [
            Preset(name: "좌클릭", action: .leftClick),
            Preset(name: "우클릭", action: .rightClick),
        ],
        [
            Preset(name: "왼쪽 Space (⌃←)", action: k(123, ctrl: true)),
            Preset(name: "오른쪽 Space (⌃→)", action: k(124, ctrl: true)),
            Preset(name: "Mission Control", action: .missionControl),
            Preset(name: "앱 전환 (⌘Tab)", action: .appSwitcher),
            Preset(name: "Spotlight (⌘Space)", action: k(49, cmd: true)),
        ],
        [
            Preset(name: "Return", action: k(36)),
            Preset(name: "Esc", action: k(53)),
            Preset(name: "Tab", action: k(48)),
            Preset(name: "Space", action: k(49)),
            Preset(name: "Delete", action: k(51)),
            Preset(name: "↑", action: k(126)),
            Preset(name: "↓", action: k(125)),
            Preset(name: "←", action: k(123)),
            Preset(name: "→", action: k(124)),
        ],
        [
            Preset(name: "복사 (⌘C)", action: k(8, cmd: true)),
            Preset(name: "붙여넣기 (⌘V)", action: k(9, cmd: true)),
            Preset(name: "잘라내기 (⌘X)", action: k(7, cmd: true)),
            Preset(name: "실행 취소 (⌘Z)", action: k(6, cmd: true)),
            Preset(name: "다시 실행 (⌘⇧Z)", action: k(6, cmd: true, shift: true)),
            Preset(name: "모두 선택 (⌘A)", action: k(0, cmd: true)),
            Preset(name: "저장 (⌘S)", action: k(1, cmd: true)),
            Preset(name: "찾기 (⌘F)", action: k(3, cmd: true)),
        ],
        [
            Preset(name: "뒤로 (⌘[)", action: k(33, cmd: true)),
            Preset(name: "앞으로 (⌘])", action: k(30, cmd: true)),
            Preset(name: "새 탭 (⌘T)", action: k(17, cmd: true)),
            Preset(name: "탭/창 닫기 (⌘W)", action: k(13, cmd: true)),
            Preset(name: "다음 탭 (⌃Tab)", action: k(48, ctrl: true)),
            Preset(name: "이전 탭 (⌃⇧Tab)", action: k(48, shift: true, ctrl: true)),
            Preset(name: "확대 (⌘+)", action: k(24, cmd: true)),
            Preset(name: "축소 (⌘-)", action: k(27, cmd: true)),
            Preset(name: "앱 종료 (⌘Q)", action: k(12, cmd: true)),
        ],
    ]
}

// MARK: - 설정

struct ButtonBinding: Codable, Hashable {
    var base: PadAction
    var layer: PadAction // L2를 누른 채
}

struct PadConfig: Codable, Equatable {
    var bindings: [PadButton: ButtonBinding]
    var cursorSpeed: Double
    var scrollSpeed: Double
    var invertScroll: Bool

    init(bindings: [PadButton: ButtonBinding] = PadConfig.defaultBindings,
         cursorSpeed: Double = 1600, scrollSpeed: Double = 2400, invertScroll: Bool = false) {
        self.bindings = bindings
        self.cursorSpeed = cursorSpeed
        self.scrollSpeed = scrollSpeed
        self.invertScroll = invertScroll
    }

    // 파일에 빠진 항목이 있어도 기본값으로 채워서 읽는다.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = PadConfig()
        bindings = try c.decodeIfPresent([PadButton: ButtonBinding].self, forKey: .bindings) ?? d.bindings
        cursorSpeed = try c.decodeIfPresent(Double.self, forKey: .cursorSpeed) ?? d.cursorSpeed
        scrollSpeed = try c.decodeIfPresent(Double.self, forKey: .scrollSpeed) ?? d.scrollSpeed
        invertScroll = try c.decodeIfPresent(Bool.self, forKey: .invertScroll) ?? d.invertScroll
    }

    func binding(_ b: PadButton) -> ButtonBinding {
        bindings[b] ?? PadConfig.defaultBindings[b] ?? ButtonBinding(base: .none, layer: .none)
    }

    static let defaults = PadConfig()

    static let defaultBindings: [PadButton: ButtonBinding] = {
        func key(_ code: CGKeyCode, cmd: Bool = false, shift: Bool = false, ctrl: Bool = false) -> PadAction {
            .key(combo: KeyCombo(keyCode: code, command: cmd, shift: shift, control: ctrl))
        }
        return [
            .l1: ButtonBinding(base: .rightClick, layer: .none),
            .r1: ButtonBinding(base: .leftClick, layer: .none),
            .l2: ButtonBinding(base: key(123, ctrl: true), layer: .none),
            .r2: ButtonBinding(base: key(124, ctrl: true), layer: .none),
            .l3: ButtonBinding(base: key(27, cmd: true), layer: .none),
            .r3: ButtonBinding(base: key(24, cmd: true), layer: .none),
            .cross: ButtonBinding(base: key(36), layer: key(8, cmd: true)),
            .circle: ButtonBinding(base: key(53), layer: key(9, cmd: true)),
            .square: ButtonBinding(base: key(13, cmd: true), layer: key(6, cmd: true)),
            .triangle: ButtonBinding(base: key(17, cmd: true), layer: key(6, cmd: true, shift: true)),
            .dpadUp: ButtonBinding(base: key(126), layer: key(126)),
            .dpadDown: ButtonBinding(base: key(125), layer: key(125)),
            .dpadLeft: ButtonBinding(base: key(123), layer: key(33, cmd: true)),
            .dpadRight: ButtonBinding(base: key(124), layer: key(30, cmd: true)),
            .create: ButtonBinding(base: key(49, cmd: true), layer: .none),
            .ps: ButtonBinding(base: .missionControl, layer: .none),
            .touchpad: ButtonBinding(base: .appSwitcher, layer: .none),
        ]
    }()
}

// MARK: - 저장소

/// ~/Library/Application Support/PadMac/config.json 에 저장하고, 바뀌면 바로 알린다.
final class ConfigStore: ObservableObject {
    @Published var config: PadConfig {
        didSet {
            guard config != oldValue else { return }
            save()
            onChange?(config)
        }
    }

    var onChange: ((PadConfig) -> Void)?
    let fileURL: URL

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PadMac", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("config.json")

        if let data = try? Data(contentsOf: fileURL),
           let loaded = try? JSONDecoder().decode(PadConfig.self, from: data) {
            config = loaded
        } else {
            config = .defaults
            save()
        }
    }

    func action(_ b: PadButton, layer: Bool) -> PadAction {
        let binding = config.binding(b)
        return layer ? binding.layer : binding.base
    }

    func set(_ b: PadButton, layer: Bool, _ action: PadAction) {
        var binding = config.binding(b)
        if layer { binding.layer = action } else { binding.base = action }
        config.bindings[b] = binding
    }

    private func save() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(config) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}

// MARK: - 키 이름 (US 배열 기준 키 코드)

enum KeyNames {
    static func name(_ code: CGKeyCode) -> String {
        table[code] ?? "키 \(code)"
    }

    private static let table: [CGKeyCode: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7",
        27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P",
        36: "Return", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",",
        44: "/", 45: "N", 46: "M", 47: ".", 48: "Tab", 49: "Space", 50: "`", 51: "Delete",
        53: "Esc", 115: "Home", 116: "Page Up", 117: "⌦", 119: "End", 121: "Page Down",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]
}
