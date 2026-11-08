import AppKit
import GameController
import QuartzCore

/// DualSense 입력을 120Hz로 읽어 설정(PadConfig)에 따라 마우스/스크롤/키 입력으로 바꾼다.
///
/// 고정 동작
///   왼쪽 스틱   → 마우스 이동
///   오른쪽 스틱 → 스크롤
///   Options(≡)  → 기능 켜기/끄기
///   L2          → 누른 채 다른 버튼 = "L2 누른 채" 동작, 짧게 눌렀다 떼기 = L2 동작
/// 나머지 버튼은 설정 창에서 바꿀 수 있다.
final class PadEngine {
    let cursorMinSpeed: Double = 60   // px/s, 스틱을 살짝 기울였을 때
    let moveDeadzone: Double = 0.12
    let scrollDeadzone: Double = 0.15
    let l2TapMaxDuration: CFTimeInterval = 0.6   // 이보다 짧게 누르고 떼면 L2 동작 실행
    let appSwitcherTimeout: CFTimeInterval = 0.8 // 마지막 앱 전환 입력 뒤 이 시간이 지나면 전환 확정

    private(set) var config = PadConfig.defaults

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

    private var menuWasPressed = false
    private var triggerOn: [PadButton: Bool] = [:]

    /// 지금 눌려 있는 버튼과, 누를 때 정해진 동작 (L2를 먼저 떼도 같은 동작으로 끝내기 위해)
    private struct Held { var action: PadAction; var nextRepeat: CFTimeInterval? }
    private var held: [PadButton: Held] = [:]

    private var leftDown = false
    private var rightDown = false

    private var l2Held = false
    private var l2PressedAt: CFTimeInterval = 0
    private var l2UsedAsModifier = false

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
        RunLoop.main.add(t, forMode: .common) // 메뉴/설정 창이 열려 있어도 계속 동작
        timer = t
    }

    /// 설정이 바뀌면 눌려 있던 것을 모두 떼고 새 설정을 쓴다.
    func apply(_ newConfig: PadConfig) {
        releaseAll()
        config = newConfig
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
        handleButtons(readStates(pad), now: now)
        handleScroll(pad, dt: dt)
    }

    // MARK: - 왼쪽 스틱 → 마우스

    private func handleMove(_ pad: GCExtendedGamepad, dt: Double) {
        let x = Double(pad.leftThumbstick.xAxis.value)
        let y = Double(pad.leftThumbstick.yAxis.value)
        let mag = hypot(x, y)
        guard mag > moveDeadzone else { moveRemainder = .zero; return }

        let n = min((mag - moveDeadzone) / (1 - moveDeadzone), 1)
        let maxSpeed = max(config.cursorSpeed, cursorMinSpeed)
        let speed = cursorMinSpeed + (maxSpeed - cursorMinSpeed) * n * n

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

    private func readStates(_ pad: GCExtendedGamepad) -> [PadButton: Bool] {
        [
            .l1: pad.leftShoulder.isPressed,
            .r1: pad.rightShoulder.isPressed,
            .l2: trigger(.l2, pad.leftTrigger.value),
            .r2: trigger(.r2, pad.rightTrigger.value),
            .l3: pad.leftThumbstickButton?.isPressed ?? false,
            .r3: pad.rightThumbstickButton?.isPressed ?? false,
            .cross: pad.buttonA.isPressed,
            .circle: pad.buttonB.isPressed,
            .square: pad.buttonX.isPressed,
            .triangle: pad.buttonY.isPressed,
            .dpadUp: pad.dpad.up.isPressed,
            .dpadDown: pad.dpad.down.isPressed,
            .dpadLeft: pad.dpad.left.isPressed,
            .dpadRight: pad.dpad.right.isPressed,
            .create: pad.buttonOptions?.isPressed ?? false,
            .ps: pad.buttonHome?.isPressed ?? false,
            .touchpad: (pad as? GCDualSenseGamepad)?.touchpadButton.isPressed ?? false,
        ]
    }

    /// 트리거는 아날로그라 히스테리시스로 눌림을 판정 (0.6 이상 눌림, 0.3 미만 뗌)
    private func trigger(_ b: PadButton, _ value: Float) -> Bool {
        let wasOn = triggerOn[b] ?? false
        let on = wasOn ? value > 0.3 : value > 0.6
        triggerOn[b] = on
        return on
    }

    private func handleButtons(_ states: [PadButton: Bool], now: CFTimeInterval) {
        // L2: 레이어 버튼. 다른 버튼과 같이 안 쓰고 짧게 떼면 L2 자체 동작
        let l2 = states[.l2] ?? false
        if l2 && !l2Held {
            l2Held = true
            l2PressedAt = now
            l2UsedAsModifier = false
        } else if !l2 && l2Held {
            l2Held = false
            if !l2UsedAsModifier && now - l2PressedAt < l2TapMaxDuration {
                let action = config.binding(.l2).base
                _ = begin(action, now: now)
                end(action)
            }
        }

        for b in PadButton.allCases where b != .l2 {
            let pressed = states[b] ?? false
            if pressed, var h = held[b] {
                // 계속 누르는 중: 키 반복
                if let next = h.nextRepeat, now >= next, case .key(let c) = h.action {
                    Synth.keyRepeat(c)
                    h.nextRepeat = now + NSEvent.keyRepeatInterval
                    held[b] = h
                }
            } else if pressed {
                let binding = config.binding(b)
                let action = l2Held ? binding.layer : binding.base
                if l2Held { l2UsedAsModifier = true }
                held[b] = Held(action: action, nextRepeat: begin(action, now: now))
            } else if let h = held[b] {
                end(h.action)
                held[b] = nil
            }
        }

        if let deadline = appSwitcherDeadline, now >= deadline {
            Synth.holdCommand(false) // ⌘를 떼면 선택한 앱으로 전환
            appSwitcherDeadline = nil
        }
    }

    /// 동작 시작. 키 반복이 필요하면 첫 반복 시각을 돌려준다.
    private func begin(_ action: PadAction, now: CFTimeInterval) -> CFTimeInterval? {
        switch action {
        case .none:
            break
        case .leftClick:
            if !leftDown { leftDown = true; click(.left, down: true) }
        case .rightClick:
            if !rightDown { rightDown = true; click(.right, down: true) }
        case .missionControl:
            Synth.missionControl()
        case .appSwitcher:
            stepAppSwitcher(now: now)
        case .key(let c):
            Synth.keyDown(c)
            return c.repeats ? now + NSEvent.keyRepeatDelay : nil
        }
        return nil
    }

    private func end(_ action: PadAction) {
        switch action {
        case .leftClick:
            if leftDown { leftDown = false; click(.left, down: false) }
        case .rightClick:
            if rightDown { rightDown = false; click(.right, down: false) }
        case .key(let c):
            Synth.keyUp(c)
        case .none, .missionControl, .appSwitcher:
            break
        }
    }

    /// 처음 누르면 ⌘를 잡고 Tab, 시간 안에 다시 누르면 Tab 한 번 더.
    /// 마지막으로 누르고 appSwitcherTimeout 이 지나면 ⌘를 떼서 전환을 확정한다.
    private func stepAppSwitcher(now: CFTimeInterval) {
        if appSwitcherDeadline == nil { Synth.holdCommand(true) }
        Synth.commandTabStep()
        appSwitcherDeadline = now + appSwitcherTimeout
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
        let speed = config.scrollSpeed * n * n
        let sign: Double = config.invertScroll ? -1 : 1

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
        for h in held.values { end(h.action) }
        held.removeAll()
        if leftDown { leftDown = false; click(.left, down: false) }
        if rightDown { rightDown = false; click(.right, down: false) }
        triggerOn.removeAll()
        l2Held = false
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
