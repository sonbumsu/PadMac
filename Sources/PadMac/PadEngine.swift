import AppKit
import GameController
import QuartzCore

/// DualSense 입력을 120Hz로 읽어 마우스/스크롤/Space 전환으로 바꾼다.
///
/// 매핑
///   왼쪽 스틱   → 마우스 이동
///   오른쪽 스틱 → 스크롤
///   L1 / R1     → 우클릭 / 좌클릭 (누르고 있으면 드래그)
///   L2 / R2     → 왼쪽 / 오른쪽 Space로 이동
///   L3 / R3     → 뒤로 / 앞으로 (⌘[ / ⌘])
///   ✕ / ○       → 복사 / 붙여넣기 (⌘C / ⌘V)
///   □ / △       → 실행 취소 / 다시 실행 (⌘Z / ⌘⇧Z)
///   방향키      → 화살표 키 (누르고 있으면 반복)
///   Options(≡)  → 기능 켜기/끄기
final class PadEngine {
    // MARK: 튜닝 값
    var cursorMinSpeed: Double = 60      // px/s, 스틱을 살짝 기울였을 때
    var cursorMaxSpeed: Double = 1600    // px/s, 끝까지 기울였을 때
    var scrollMaxSpeed: Double = 2400    // px/s
    let moveDeadzone: Double = 0.12
    let scrollDeadzone: Double = 0.15

    var invertScroll = false

    var enabled = true {
        didSet {
            guard oldValue != enabled else { return }
            if !enabled { releaseAll() }
            updateLight()
            onChange?()
        }
    }

    var onChange: (() -> Void)?
    private(set) var controller: GCController?

    private var timer: Timer?
    private var lastTick = CACurrentMediaTime()
    private var moveRemainder = CGPoint.zero
    private var scrollRemainder = CGPoint.zero

    private var leftDown = false
    private var rightDown = false
    private var l2Held = false
    private var r2Held = false
    private var menuWasPressed = false
    private var pressedButtons: [String: Bool] = [:]
    private var arrowNextRepeat: [Synth.Arrow: CFTimeInterval] = [:] // 눌려 있는 화살표 → 다음 반복 시각

    private struct Click { var button: CGMouseButton; var time: CFTimeInterval; var pos: CGPoint; var count: Int }
    private var lastClick: Click?

    // MARK: - Lifecycle

    func start() {
        // 앱이 앞에 없어도(메뉴바 앱은 항상 그렇다) 패드 입력을 받는다.
        GCController.shouldMonitorBackgroundEvents = true

        let nc = NotificationCenter.default
        nc.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] _ in
            self?.refreshController()
        }
        nc.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] _ in
            self?.refreshController()
        }
        GCController.startWirelessControllerDiscovery {}
        refreshController()

        let t = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common) // 메뉴가 열려 있어도 계속 동작
        timer = t
    }

    private func refreshController() {
        let pads = GCController.controllers().filter { $0.extendedGamepad != nil }
        controller = pads.first(where: { $0.physicalInputProfile is GCDualSenseGamepad }) ?? pads.first
        if controller == nil { releaseAll() }
        updateLight()
        onChange?()
    }

    // MARK: - Loop

    private func tick() {
        let now = CACurrentMediaTime()
        let dt = min(now - lastTick, 0.05)
        lastTick = now

        guard let pad = controller?.extendedGamepad else { return }

        // Options 버튼: 켜기/끄기 (꺼져 있어도 이 버튼은 항상 읽는다)
        let menu = pad.buttonMenu.isPressed
        if menu && !menuWasPressed {
            enabled.toggle()
            NSSound(named: enabled ? "Tink" : "Pop")?.play()
        }
        menuWasPressed = menu

        guard enabled else { return }

        handleMove(pad, dt: dt)
        handleButtons(pad)
        handleScroll(pad, dt: dt)
    }

    // MARK: - 왼쪽 스틱 → 마우스

    private func handleMove(_ pad: GCExtendedGamepad, dt: Double) {
        let x = Double(pad.leftThumbstick.xAxis.value)
        let y = Double(pad.leftThumbstick.yAxis.value)
        let mag = hypot(x, y)
        guard mag > moveDeadzone else { moveRemainder = .zero; return }

        let n = min((mag - moveDeadzone) / (1 - moveDeadzone), 1)
        let speed = cursorMinSpeed + (cursorMaxSpeed - cursorMinSpeed) * n * n

        moveRemainder.x += x / mag * speed * dt
        moveRemainder.y += -y / mag * speed * dt // 화면 좌표는 아래가 +y
        let dx = moveRemainder.x.rounded(.towardZero)
        let dy = moveRemainder.y.rounded(.towardZero)
        guard dx != 0 || dy != 0 else { return }
        moveRemainder.x -= dx
        moveRemainder.y -= dy

        let old = Synth.cursor()
        let new = Synth.clampToDisplays(CGPoint(x: old.x + dx, y: old.y + dy), from: old)

        let type: CGEventType
        let button: CGMouseButton
        if leftDown { type = .leftMouseDragged; button = .left }
        else if rightDown { type = .rightMouseDragged; button = .right }
        else { type = .mouseMoved; button = .left }

        Synth.move(to: new, delta: CGPoint(x: dx, y: dy), type: type, button: button)
    }

    // MARK: - L1/R1 클릭, L2/R2 Space 전환

    private func handleButtons(_ pad: GCExtendedGamepad) {
        // R1 = 좌클릭, L1 = 우클릭
        let r1 = pad.rightShoulder.isPressed
        if r1 != leftDown { leftDown = r1; click(.left, down: r1) }

        let l1 = pad.leftShoulder.isPressed
        if l1 != rightDown { rightDown = l1; click(.right, down: l1) }

        // 트리거는 아날로그라 히스테리시스로 한 번 누를 때 한 번만 실행
        let l2 = pad.leftTrigger.value
        if !l2Held && l2 > 0.6 { l2Held = true; Synth.switchSpace(left: true) }
        else if l2Held && l2 < 0.3 { l2Held = false }

        let r2 = pad.rightTrigger.value
        if !r2Held && r2 > 0.6 { r2Held = true; Synth.switchSpace(left: false) }
        else if r2Held && r2 < 0.3 { r2Held = false }

        // L3/R3 = 뒤로/앞으로 (⌘[ / ⌘]), ✕/○ = 복사/붙여넣기 (⌘C / ⌘V)
        onPress("L3", pad.leftThumbstickButton?.isPressed) { Synth.command(.leftBracket) }
        onPress("R3", pad.rightThumbstickButton?.isPressed) { Synth.command(.rightBracket) }
        onPress("cross", pad.buttonA.isPressed) { Synth.command(.c) }
        onPress("circle", pad.buttonB.isPressed) { Synth.command(.v) }
        // □ = 실행 취소 (⌘Z)
        onPress("square", pad.buttonX.isPressed) { Synth.command(.z) }
        // △ = 다시 실행 (⌘⇧Z)
        onPress("triangle", pad.buttonY.isPressed) { Synth.command(.z, shift: true) }

        // 방향키 = 맥 화살표 키 (누르고 있으면 키보드처럼 반복)
        let now = CACurrentMediaTime()
        handleArrow(.up, pad.dpad.up.isPressed, now)
        handleArrow(.down, pad.dpad.down.isPressed, now)
        handleArrow(.left, pad.dpad.left.isPressed, now)
        handleArrow(.right, pad.dpad.right.isPressed, now)
    }

    /// 누름 → keyDown, 계속 누름 → 시스템 키 반복 설정대로 반복, 뗌 → keyUp
    private func handleArrow(_ arrow: Synth.Arrow, _ pressed: Bool, _ now: CFTimeInterval) {
        if pressed {
            if let next = arrowNextRepeat[arrow] {
                if now >= next {
                    Synth.arrow(arrow, down: true, isRepeat: true)
                    arrowNextRepeat[arrow] = now + NSEvent.keyRepeatInterval
                }
            } else {
                Synth.arrow(arrow, down: true)
                arrowNextRepeat[arrow] = now + NSEvent.keyRepeatDelay
            }
        } else if arrowNextRepeat[arrow] != nil {
            Synth.arrow(arrow, down: false)
            arrowNextRepeat[arrow] = nil
        }
    }

    /// 버튼이 눌리는 순간에만 한 번 실행한다.
    private func onPress(_ id: String, _ pressed: Bool?, _ action: () -> Void) {
        let now = pressed ?? false
        if now && !(pressedButtons[id] ?? false) { action() }
        pressedButtons[id] = now
    }

    private func click(_ button: CGMouseButton, down: Bool) {
        let pos = Synth.cursor()
        var count = 1
        if down {
            let now = CACurrentMediaTime()
            if let lc = lastClick, lc.button == button,
               now - lc.time < NSEvent.doubleClickInterval,
               hypot(lc.pos.x - pos.x, lc.pos.y - pos.y) < 5 {
                count = lc.count + 1 // 더블/트리플 클릭
            }
            lastClick = Click(button: button, time: now, pos: pos, count: count)
        } else {
            count = lastClick?.count ?? 1
        }
        Synth.button(button, down: down, at: pos, clickCount: count)
    }

    // MARK: - 오른쪽 스틱 → 스크롤

    private func handleScroll(_ pad: GCExtendedGamepad, dt: Double) {
        let x = Double(pad.rightThumbstick.xAxis.value)
        let y = Double(pad.rightThumbstick.yAxis.value)
        let mag = hypot(x, y)
        guard mag > scrollDeadzone else { scrollRemainder = .zero; return }

        let n = min((mag - scrollDeadzone) / (1 - scrollDeadzone), 1)
        let speed = scrollMaxSpeed * n * n
        let sign: Double = invertScroll ? -1 : 1

        // 스틱 위 → 페이지 위쪽 내용 보기, 스틱 오른쪽 → 오른쪽 내용 보기
        scrollRemainder.y += y / mag * speed * dt * sign
        scrollRemainder.x += -x / mag * speed * dt * sign
        let sx = scrollRemainder.x.rounded(.towardZero)
        let sy = scrollRemainder.y.rounded(.towardZero)
        guard sx != 0 || sy != 0 else { return }
        scrollRemainder.x -= sx
        scrollRemainder.y -= sy

        Synth.scroll(dx: Int32(sx), dy: Int32(sy))
    }

    // MARK: - Helpers

    private func releaseAll() {
        let pos = Synth.cursor()
        if leftDown { Synth.button(.left, down: false, at: pos, clickCount: 1) }
        if rightDown { Synth.button(.right, down: false, at: pos, clickCount: 1) }
        leftDown = false
        rightDown = false
        l2Held = false
        r2Held = false
        pressedButtons.removeAll()
        for arrow in arrowNextRepeat.keys { Synth.arrow(arrow, down: false) }
        arrowNextRepeat.removeAll()
        moveRemainder = .zero
        scrollRemainder = .zero
    }

    /// 라이트바 색으로 상태 표시: 켜짐 = 파랑, 꺼짐 = 주황
    private func updateLight() {
        guard let light = controller?.light else { return }
        light.color = enabled ? GCColor(red: 0.0, green: 0.35, blue: 1.0)
                              : GCColor(red: 1.0, green: 0.35, blue: 0.0)
    }
}
