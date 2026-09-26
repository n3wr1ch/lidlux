import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var controller: BrightnessController!

    private let statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let offsetLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let enabledItem = NSMenuItem(title: "자동 밝기 조절", action: #selector(toggleEnabled), keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "로그인 시 실행", action: #selector(toggleLogin), keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let sensor = AmbientLightSensor(), let display = BuiltinDisplay() else {
            let alert = NSAlert()
            alert.messageText = "조도 센서 또는 내장 디스플레이를 찾을 수 없습니다."
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        controller = BrightnessController(sensor: sensor, display: display)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        buildMenu()
        controller.onUpdate = { [weak self] in self?.refresh() }

        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            center.addObserver(self, selector: #selector(resync), name: name, object: nil)
        }
        NotificationCenter.default.addObserver(
            self, selector: #selector(resync),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)

        if controller.isEnabled { controller.start() }
        refresh()
    }

    private func buildMenu() {
        let menu = NSMenu()
        menu.delegate = self
        statusLine.isEnabled = false
        offsetLine.isEnabled = false
        menu.addItem(statusLine)
        menu.addItem(offsetLine)
        menu.addItem(.separator())
        enabledItem.target = self
        menu.addItem(enabledItem)
        let reset = NSMenuItem(title: "보정값 초기화", action: #selector(resetOffset), keyEquivalent: "")
        reset.target = self
        menu.addItem(reset)
        menu.addItem(.separator())
        loginItem.target = self
        menu.addItem(loginItem)
        menu.addItem(NSMenuItem(title: "종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    private func refresh() {
        let on = controller.isEnabled
        statusItem.button?.image = NSImage(
            systemSymbolName: on ? "sun.max.fill" : "sun.max",
            accessibilityDescription: "AutoBright")
        statusItem.button?.appearsDisabled = !on

        let lux = controller.lastLux.map { String(format: "%.0f lux", $0) } ?? "– lux"
        let level = controller.currentBrightness.map { String(format: "%.0f%%", $0 * 100) } ?? "내장 디스플레이 꺼짐"
        statusLine.title = "조도 \(lux) · 밝기 \(level)"
        offsetLine.title = String(format: "선호 보정 %+.0f%%  (밝기 키로 조절하면 학습)", controller.offset * 100)
        enabledItem.state = on ? .on : .off
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    func menuWillOpen(_ menu: NSMenu) { refresh() }

    @objc private func toggleEnabled() {
        controller.isEnabled.toggle()
        refresh()
    }

    @objc private func resetOffset() {
        controller.resetOffset()
    }

    @objc private func resync() {
        controller.resync()
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
        }
        refresh()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
