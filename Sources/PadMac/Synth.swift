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

    // MARK: - ⌘ 단축키

    enum Key: CGKeyCode {
        case c = 8, v = 9, z = 6, w = 13, t = 17
        case minus = 27, equal = 24, leftBracket = 33, rightBracket = 30
        case returnKey = 36, escape = 53, tab = 48, space = 49
    }

    /// 수식키 없이 키 하나를 누르고 뗀다. (Return, Esc 등)
    static func tap(_ key: Key) {
        let down = CGEvent(keyboardEventSource: source, virtualKey: key.rawValue, keyDown: true)
        down?.flags = []
        let up = CGEvent(keyboardEventSource: source, virtualKey: key.rawValue, keyDown: false)
        up?.flags = []
        post(down)
        post(up)
    }

    // MARK: - 앱 전환 (⌘Tab)

    /// ⌘ 키만 누르거나 뗀다. 앱 전환기를 열어 두는 동안 ⌘를 잡고 있기 위해 쓴다.
    static func holdCommand(_ down: Bool) {
        let e = CGEvent(keyboardEventSource: source, virtualKey: 55, keyDown: down)
        e?.flags = down ? .maskCommand : []
        post(e)
    }

    /// ⌘가 눌린 상태에서 Tab 한 번
    static func commandTabStep() {
        let down = CGEvent(keyboardEventSource: source, virtualKey: Key.tab.rawValue, keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: source, virtualKey: Key.tab.rawValue, keyDown: false)
        up?.flags = .maskCommand
        post(down)
        post(up)
    }

    // MARK: - Mission Control

    static func missionControl() {
        let url = URL(fileURLWithPath: "/System/Applications/Mission Control.app")
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    /// ⌘(+⇧) + key 를 누르고 뗀다. (예: ⌘C 복사, ⌘⇧Z 다시 실행)
    static func command(_ key: Key, shift: Bool = false) {
        let cmd: CGKeyCode = 55
        let shiftKey: CGKeyCode = 56
        let flags: CGEventFlags = shift ? [.maskCommand, .maskShift] : .maskCommand

        var events: [CGEvent?] = []
        let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: cmd, keyDown: true)
        cmdDown?.flags = .maskCommand
        events.append(cmdDown)
        if shift {
            let shiftDown = CGEvent(keyboardEventSource: source, virtualKey: shiftKey, keyDown: true)
            shiftDown?.flags = flags
            events.append(shiftDown)
        }
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: key.rawValue, keyDown: true)
        keyDown?.flags = flags
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: key.rawValue, keyDown: false)
        keyUp?.flags = flags
        events += [keyDown, keyUp]
        if shift {
            let shiftUp = CGEvent(keyboardEventSource: source, virtualKey: shiftKey, keyDown: false)
            shiftUp?.flags = .maskCommand
            events.append(shiftUp)
        }
        let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: cmd, keyDown: false)
        cmdUp?.flags = []
        events.append(cmdUp)

        events.forEach(post)
    }

    // MARK: - 화살표 키

    enum Arrow: CGKeyCode {
        case left = 123, right = 124, down = 125, up = 126
    }

    /// 실제 키보드 화살표처럼 누름/뗌/자동 반복 이벤트를 보낸다.
    static func arrow(_ arrow: Arrow, down: Bool, isRepeat: Bool = false) {
        let e = CGEvent(keyboardEventSource: source, virtualKey: arrow.rawValue, keyDown: down)
        // 실제 화살표 키 이벤트에는 Fn·숫자패드 플래그가 붙어 있다.
        e?.flags = [.maskSecondaryFn, .maskNumericPad]
        if isRepeat { e?.setIntegerValueField(.keyboardEventAutorepeat, value: 1) }
        post(e)
    }

    // MARK: - Space 전환 (3손가락 좌/우 스와이프와 같은 동작)

    /// macOS 기본 단축키 "왼쪽/오른쪽 Space로 이동" = ⌃← / ⌃→
    static func switchSpace(left: Bool) {
        let ctrl: CGKeyCode = 59
        let arrow: CGKeyCode = left ? 123 : 124
        // 시스템 단축키는 화살표 키에 Fn 플래그가 붙은 상태로 등록되어 있다.
        let flags: CGEventFlags = [.maskControl, .maskSecondaryFn]

        let ctrlDown = CGEvent(keyboardEventSource: source, virtualKey: ctrl, keyDown: true)
        ctrlDown?.flags = .maskControl
        let arrowDown = CGEvent(keyboardEventSource: source, virtualKey: arrow, keyDown: true)
        arrowDown?.flags = flags
        let arrowUp = CGEvent(keyboardEventSource: source, virtualKey: arrow, keyDown: false)
        arrowUp?.flags = flags
        let ctrlUp = CGEvent(keyboardEventSource: source, virtualKey: ctrl, keyDown: false)
        ctrlUp?.flags = []

        [ctrlDown, arrowDown, arrowUp, ctrlUp].forEach(post)
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
