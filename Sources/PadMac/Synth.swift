import AppKit
import CoreGraphics

/// 마우스/키보드/스크롤 이벤트를 만들어 시스템에 보낸다.
/// (손쉬운 사용 권한이 없으면 macOS가 이벤트를 조용히 버린다)
enum Synth {
    static let source = CGEventSource(stateID: .hidSystemState)

    static func cursor() -> CGPoint {
        CGEvent(source: nil)?.location ?? .zero
    }

    static func post(_ event: CGEvent?) {
        event?.post(tap: .cghidEventTap)
    }

    // MARK: - Mouse

    static func move(to point: CGPoint, delta: CGPoint, type: CGEventType, button: CGMouseButton) {
        let e = CGEvent(mouseEventSource: source, mouseType: type,
                        mouseCursorPosition: point, mouseButton: button)
        e?.setIntegerValueField(.mouseEventDeltaX, value: Int64(delta.x))
        e?.setIntegerValueField(.mouseEventDeltaY, value: Int64(delta.y))
        post(e)
    }

    static func button(_ button: CGMouseButton, down: Bool, at point: CGPoint, clickCount: Int) {
        let type: CGEventType
        switch (button, down) {
        case (.right, true): type = .rightMouseDown
        case (.right, false): type = .rightMouseUp
        case (_, true): type = .leftMouseDown
        case (_, false): type = .leftMouseUp
        }
        let e = CGEvent(mouseEventSource: source, mouseType: type,
                        mouseCursorPosition: point, mouseButton: button)
        e?.setIntegerValueField(.mouseEventClickState, value: Int64(clickCount))
        post(e)
    }

    static func scroll(dx: Int32, dy: Int32) {
        let e = CGEvent(scrollWheelEvent2Source: source, units: .pixel,
                        wheelCount: 2, wheel1: dy, wheel2: dx, wheel3: 0)
        post(e)
    }

    // MARK: - 키 조합

    /// 실제 키보드처럼: 수식키 누름 → 키 누름 ... 키 뗌 → 수식키 뗌
    static func keyDown(_ c: KeyCombo) {
        var flags: CGEventFlags = []
        for m in modifiers(c) where m.on {
            flags.insert(m.flag)
            postKey(m.code, down: true, flags: flags)
        }
        postKey(c.keyCode, down: true, flags: keyFlags(c))
    }

    static func keyRepeat(_ c: KeyCombo) {
        let e = CGEvent(keyboardEventSource: source, virtualKey: c.keyCode, keyDown: true)
        e?.flags = keyFlags(c)
        e?.setIntegerValueField(.keyboardEventAutorepeat, value: 1)
        post(e)
    }

    static func keyUp(_ c: KeyCombo) {
        postKey(c.keyCode, down: false, flags: keyFlags(c))
        var flags = modifierFlags(c)
        for m in modifiers(c).reversed() where m.on {
            flags.remove(m.flag)
            postKey(m.code, down: false, flags: flags)
        }
    }

    private static func postKey(_ code: CGKeyCode, down: Bool, flags: CGEventFlags) {
        let e = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down)
        e?.flags = flags
        post(e)
    }

    private static func modifiers(_ c: KeyCombo) -> [(on: Bool, code: CGKeyCode, flag: CGEventFlags)] {
        [(c.control, 59, .maskControl), (c.option, 58, .maskAlternate),
         (c.shift, 56, .maskShift), (c.command, 55, .maskCommand)]
    }

    private static func modifierFlags(_ c: KeyCombo) -> CGEventFlags {
        var f: CGEventFlags = []
        for m in modifiers(c) where m.on { f.insert(m.flag) }
        return f
    }

    /// 실제 키보드의 화살표·F키 등은 Fn(·숫자패드) 플래그가 붙어서 온다.
    /// 시스템 단축키(⌃← Space 이동 등)가 이 플래그까지 맞아야 동작한다.
    private static let fnKeys: Set<CGKeyCode> = [
        115, 116, 117, 119, 121, 122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111,
        123, 124, 125, 126,
    ]

    private static func keyFlags(_ c: KeyCombo) -> CGEventFlags {
        var f = modifierFlags(c)
        if fnKeys.contains(c.keyCode) { f.insert(.maskSecondaryFn) }
        if (123...126).contains(c.keyCode) { f.insert(.maskNumericPad) }
        return f
    }

    // MARK: - 앱 전환 (⌘Tab)

    /// ⌘ 키만 누르거나 뗀다. 앱 전환기를 열어 두는 동안 ⌘를 잡고 있기 위해 쓴다.
    static func holdCommand(_ down: Bool) {
        postKey(55, down: down, flags: down ? .maskCommand : [])
    }

    /// ⌘가 눌린 상태에서 Tab 한 번
    static func commandTabStep() {
        postKey(48, down: true, flags: .maskCommand)
        postKey(48, down: false, flags: .maskCommand)
    }

    // MARK: - Mission Control

    static func missionControl() {
        let url = URL(fileURLWithPath: "/System/Applications/Mission Control.app")
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    // MARK: - 화면 경계

    /// 새 위치가 어느 화면에도 없으면, 이전 위치가 속한 화면 안으로 자른다.
    static func clampToDisplays(_ p: CGPoint, from old: CGPoint) -> CGPoint {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)
        let rects = ids.map { CGDisplayBounds($0) }

        if rects.contains(where: { $0.contains(p) }) { return p }
        guard let base = rects.first(where: { $0.contains(old) }) ?? rects.first else { return p }
        return CGPoint(x: min(max(p.x, base.minX), base.maxX - 1),
                       y: min(max(p.y, base.minY), base.maxY - 1))
    }
}
