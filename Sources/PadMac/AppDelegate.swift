import AppKit
import ApplicationServices
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let engine = PadEngine()
    private let store = ConfigStore()
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        engine.apply(store.config)
        store.onChange = { [weak self] config in self?.engine.apply(config) }
        engine.onChange = { [weak self] in self?.updateIcon() }
        engine.start()
        updateIcon()

        // 처음 실행 시 손쉬운 사용 권한 요청 창 표시
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    /// 메뉴바 아이콘: 로고 실루엣 (꺼져 있거나 패드가 없으면 흐리게)
    private lazy var menuBarImage: NSImage? = {
        guard let url = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "png"),
              let img = NSImage(contentsOf: url) else {
            return NSImage(systemSymbolName: "gamecontroller.fill", accessibilityDescription: "PadMac")
        }
        let height: CGFloat = 16
        img.size = NSSize(width: (img.size.width / img.size.height * height).rounded(), height: height)
        img.isTemplate = true // 다크/라이트 모드에 맞게 자동으로 색이 바뀜
        return img
    }()

    private func updateIcon() {
        statusItem.button?.image = menuBarImage
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
        invert.state = store.config.invertScroll ? .on : .off
        menu.addItem(invert)

        menu.addItem(.separator())

        let settings = NSMenuItem(title: "버튼 설정…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "PadMac 종료", action: #selector(NSApplication.terminate(_:)),
                              keyEquivalent: "q")
        menu.addItem(quit)
    }

    @objc private func toggleEnabled() { engine.enabled.toggle() }
    @objc private func toggleInvert() { store.config.invertScroll.toggle() }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(store: store)))
            window.title = "PadMac 버튼 설정"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true) // 메뉴바 앱이라 직접 앞으로 가져와야 키 입력을 받는다
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func openAccessibility() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
