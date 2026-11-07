import AppKit
import GameController
import QuartzCore

/// DualSense 입력을 120Hz로 읽어 마우스/스크롤/키 입력으로 바꾼다.
///
/// 기본 매핑
///   왼쪽 스틱   → 마우스 이동
///   오른쪽 스틱 → 스크롤
///   L1 / R1     → 우클릭 / 좌클릭 (누르고 있으면 드래그)
///   L2 / R2     → 왼쪽 / 오른쪽 Space로 이동 (L2는 짧게 눌렀다 뗄 때)
///   L3 / R3     → 축소 / 확대 (⌘- / ⌘+)
///   ✕ / ○       → Return / Esc
///   □ / △       → 탭 닫기 / 새 탭 (⌘W / ⌘T)
///   방향키      → 화살표 키 (누르고 있으면 반복)
///   Create      → Spotlight (⌘Space)
///   PS          → Mission Control
///   터치패드 클릭 → 앱 전환 (⌘Tab, 연타하면 다음 앱으로)
///   Options(≡)  → 기능 켜기/끄기
///
/// L2를 누른 채로 (편집 레이어)
///   ✕ / ○       → 복사 / 붙여넣기 (⌘C / ⌘V)
///   □ / △       → 실행 취소 / 다시 실행 (⌘Z / ⌘⇧Z)
///   ← / →       → 뒤로 / 앞으로 (⌘[ / ⌘])
final class PadEngine {
    // MARK: 튜닝 값
    var cursorMinSpeed: Double = 60      // px/s, 스틱을 살짝 기울였을 때
    var cursorMaxSpeed: Double = 1600    // px/s, 끝까지 기울였을 때
    var scrollMaxSpeed: Double = 2400    // px/s
    let moveDeadzone: Double = 0.12
    let scrollDeadzone: Double = 0.15
    let l2TapMaxDuration: CFTimeInterval = 0.6   // 이보다 짧게 누르고 떼면 Space 이동
    let appSwitcherTimeout: CFTimeInterval = 0.8 // 터치패드를 마지막으로 누른 뒤 이 시간이 지나면 앱 전환 확정

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
    private var menuWasPressed = false
    private var pressedButtons: [String: Bool] = [:]
    private var arrowNextRepeat: [Synth.Arrow: CFTimeInterval] = [:] // 눌려 있는 화살표 → 다음 반복 시각

    // L2: 짧게 = Space 이동, 누른 채 = 편집 레이어
    private var l2Held = false
    private var l2PressedAt: CFTimeInterval = 0
    private var l2UsedAsModifier = false
    private var r2Held = false

    // 터치패드 앱 전환: ⌘를 잡고 있는 동안 연타하면 다음 앱으로
    private var appSwitcherDeadline: CFTimeInterval?

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
        handleButtons(pad, now: now)
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

    // MARK: - 버튼

    private func handleButtons(_ pad: GCExtendedGamepad, now: CFTimeInterval) {
        // R1 = 좌클릭, L1 = 우클릭
        let r1 = pad.rightShoulder.isPressed
        if r1 != leftDown { leftDown = r1; click(.left, down: r1) }

        let l1 = pad.leftShoulder.isPressed
        if l1 != rightDown { rightDown = l1; click(.right, down: l1) }

        // 트리거는 아날로그라 히스테리시스로 판정
        // L2: 누른 채 다른 버튼을 쓰면 편집 레이어, 짧게 누르고 떼기만 하면 왼쪽 Space
        let l2 = pad.leftTrigger.value
        if !l2Held && l2 > 0.6 {
            l2Held = true
            l2PressedAt = now
            l2UsedAsModifier = false
        } else if l2Held && l2 < 0.3 {
            l2Held = false
            if !l2UsedAsModifier && now - l2PressedAt < l2TapMaxDuration {
                Synth.switchSpace(left: true)
            }
        }

        let r2 = pad.rightTrigger.value
        if !r2Held && r2 > 0.6 { r2Held = true; Synth.switchSpace(left: false) }
        else if r2Held && r2 < 0.3 { r2Held = false }

        // L3/R3 = 축소/확대
        onPress("L3", pad.leftThumbstickButton?.isPressed) { Synth.command(.minus) }
        onPress("R3", pad.rightThumbstickButton?.isPressed) { Synth.command(.equal) }

        // 도형 버튼: L2를 누르고 있으면 편집 레이어
        onPress("cross", pad.buttonA.isPressed) {
            layered(base: { Synth.tap(.returnKey) }, edit: { Synth.command(.c) })
        }
        onPress("circle", pad.buttonB.isPressed) {
            layered(base: { Synth.tap(.escape) }, edit: { Synth.command(.v) })
        }
        onPress("square", pad.buttonX.isPressed) {
            layered(base: { Synth.command(.w) }, edit: { Synth.command(.z) })
        }
        onPress("triangle", pad.buttonY.isPressed) {
            layered(base: { Synth.command(.t) }, edit: { Synth.command(.z, shift: true) })
        }

        // 시스템 버튼
        onPress("create", pad.buttonOptions?.isPressed) { Synth.command(.space) }
        onPress("ps", pad.buttonHome?.isPressed) { Synth.missionControl() }
        let touchpad = (pad as? GCDualSenseGamepad)?.touchpadButton.isPressed
        onPress("touchpad", touchpad) { stepAppSwitcher(now: now) }
        if let deadline = appSwitcherDeadline, now >= deadline {
            Synth.holdCommand(false) // ⌘를 떼면 선택한 앱으로 전환
            appSwitcherDeadline = nil
        }

        // 방향키: 화살표 키. L2를 누르고 있으면 ←/→ = 뒤로/앞으로
        handleArrow(.up, pad.dpad.up.isPressed, now)
        handleArrow(.down, pad.dpad.down.isPressed, now)
        let dLeft = pad.dpad.left.isPressed
        let dRight = pad.dpad.right.isPressed
        if l2Held {
            handleArrow(.left, false, now)
            handleArrow(.right, false, now)
            onPress("dpadLeft", dLeft) { l2UsedAsModifier = true; Synth.command(.leftBracket) }
            onPress("dpadRight", dRight) { l2UsedAsModifier = true; Synth.command(.rightBracket) }
        } else {
            pressedButtons["dpadLeft"] = dLeft
            pressedButtons["dpadRight"] = dRight
            handleArrow(.left, dLeft, now)
            handleArrow(.right, dRight, now)
        }
    }

    /// L2를 누르고 있으면 edit, 아니면 base 를 실행한다.
    private func layered(base: () -> Void, edit: () -> Void) {
        if l2Held {
            l2UsedAsModifier = true
            edit()
        } else {
            base()
        }
    }

    /// 처음 누르면 ⌘를 잡고 Tab, 시간 안에 다시 누르면 Tab 한 번 더.
    /// 마지막으로 누르고 appSwitcherTimeout 이 지나면 ⌘를 떼서 전환을 확정한다.
    private func stepAppSwitcher(now: CFTimeInterval) {
        if appSwitcherDeadline == nil { Synth.holdCommand(true) }
        Synth.commandTabStep()
        appSwitcherDeadline = now + appSwitcherTimeout
    }

    /// 버튼이 눌리는 순간에만 한 번 실행한다.
    private func onPress(_ id: String, _ pressed: Bool?, _ action: () -> Void) {
        let now = pressed ?? false
        if now && !(pressedButtons[id] ?? false) { action() }
        pressedButtons[id] = now
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
        if appSwitcherDeadline != nil {
            Synth.holdCommand(false)
            appSwitcherDeadline = nil
        }
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
