import AppKit
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let engine = PadEngine()
    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        engine.onChange = { [weak self] in self?.updateIcon() }
        engine.start()
        updateIcon()

        // 처음 실행 시 손쉬운 사용 권한 요청 창 표시
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    private func updateIcon() {
        let name = engine.enabled ? "gamecontroller.fill" : "gamecontroller"
        let img = NSImage(systemSymbolName: name, accessibilityDescription: "PadMac")
        img?.isTemplate = true
        statusItem.button?.image = img
        statusItem.button?.appearsDisabled = !engine.enabled || engine.controller == nil
    }

    // 메뉴를 열 때마다 최신 상태로 다시 그린다.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let name = engine.controller?.vendorName ?? "연결된 컨트롤러 없음"
        menu.addItem(withTitle: "🎮 \(name)", action: nil, keyEquivalent: "")

        if !AXIsProcessTrusted() {
            let item = NSMenuItem(title: "⚠️ 손쉬운 사용 권한 필요 — 열기…",
                                  action: #selector(openAccessibility), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let toggle = NSMenuItem(title: "패드로 조작하기 (Options 버튼)",
                                action: #selector(toggleEnabled), keyEquivalent: "")
        toggle.target = self
        toggle.state = engine.enabled ? .on : .off
        menu.addItem(toggle)

        let invert = NSMenuItem(title: "스크롤 방향 반전",
                                action: #selector(toggleInvert), keyEquivalent: "")
        invert.target = self
        invert.state = engine.invertScroll ? .on : .off
        menu.addItem(invert)

        menu.addItem(.separator())
        menu.addItem(withTitle: "왼쪽 스틱: 마우스 · 오른쪽 스틱: 스크롤", action: nil, keyEquivalent: "")
        menu.addItem(withTitle: "L1/R1: 우/좌 클릭 · L2/R2: Space 이동", action: nil, keyEquivalent: "")
        menu.addItem(withTitle: "L3/R3: 뒤로/앞으로 · ✕/○: 복사/붙여넣기", action: nil, keyEquivalent: "")
        menu.addItem(withTitle: "□/△: 실행 취소/다시 실행 · 방향키: 화살표", action: nil, keyEquivalent: "")
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "PadMac 종료", action: #selector(NSApplication.terminate(_:)),
                              keyEquivalent: "q")
        menu.addItem(quit)
    }

    @objc private func toggleEnabled() { engine.enabled.toggle() }
    @objc private func toggleInvert() { engine.invertScroll.toggle() }

    @objc private func openAccessibility() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
