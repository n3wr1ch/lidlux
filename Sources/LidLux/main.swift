import AppKit
import ServiceManagement
import os

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let logger = Logger(subsystem: "com.ntoktok.lidlux", category: "app")
    private var statusItem: NSStatusItem?
    private var controller: BrightnessController?
    private var externalController: ExternalBrightnessController?
    private var externalStatusItems: [NSMenuItem] = []
    private let externalEnabledItem = NSMenuItem(title: "외부 모니터도 조절", action: #selector(toggleExternalEnabled), keyEquivalent: "")
    private var brightnessKeys: BrightnessKeyTap?
    private let brightnessKeysItem = NSMenuItem(title: "밝기 키로 외부 모니터 조절", action: #selector(toggleBrightnessKeys), keyEquivalent: "")
    private let brightnessKeysStatus = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let accessibilityItem = NSMenuItem(title: "손쉬운 사용 설정 열기…", action: #selector(openAccessibility), keyEquivalent: "")
    private var settingsWindow: SettingsWindow?
    private var biasMenuView: BiasMenuView?

    private let statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let offsetLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let enabledItem = NSMenuItem(title: "자동 밝기 조절", action: #selector(toggleEnabled), keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "로그인 시 실행", action: #selector(toggleLogin), keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.notice("LidLux launching")
        guard let sensor = AmbientLightSensor(), let display = BuiltinDisplay() else {
            logger.error("Unable to initialize ambient light sensor or display API")
            let alert = NSAlert()
            alert.messageText = "조도 센서 또는 내장 디스플레이를 찾을 수 없습니다."
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        let controller = BrightnessController(sensor: sensor, display: display)
        self.controller = controller
        let external = ExternalBrightnessController(settings: controller.settings)
        externalController = external
        let keys = BrightnessKeyTap(settings: controller.settings, external: external)
        brightnessKeys = keys
        keys.onUpdate = { [weak self] in self?.refresh() }
        controller.onSample = { [weak external] in external?.accept(logLux: $0) }
        controller.settings.onExternalChange = { [weak external] in external?.settingsChanged($0) }
        external.onUpdate = { [weak self] in self?.refresh() }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        buildMenu()
        controller.onUpdate = { [weak self] in self?.refresh() }

        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification, NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification] {
            center.addObserver(self, selector: #selector(resync(_:)), name: name, object: nil)
        }
        NotificationCenter.default.addObserver(
            self, selector: #selector(resync(_:)),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)

        external.start()
        keys.start()
        if controller.isEnabled || controller.settings.externalEnabled { controller.start() }
        refresh()
    }

    private func buildMenu() {
        let menu = NSMenu()
        menu.delegate = self
        statusLine.isEnabled = false
        offsetLine.isEnabled = false
        menu.addItem(statusLine)
        menu.addItem(offsetLine)
        if let controller {
            let view = BiasMenuView(settings: controller.settings)
            biasMenuView = view
            let item = NSMenuItem()
            item.view = view
            menu.addItem(item)
        }
        menu.addItem(.separator())
        enabledItem.target = self
        menu.addItem(enabledItem)
        externalEnabledItem.target = self
        menu.addItem(externalEnabledItem)
        brightnessKeysItem.target = self
        menu.addItem(brightnessKeysItem)
        brightnessKeysStatus.isEnabled = false
        menu.addItem(brightnessKeysStatus)
        accessibilityItem.target = self
        menu.addItem(accessibilityItem)
        let reset = NSMenuItem(title: "보정값 초기화", action: #selector(resetOffset), keyEquivalent: "")
        reset.target = self
        menu.addItem(reset)
        menu.addItem(.separator())
        let settingsItem = NSMenuItem(title: "설정…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.keyEquivalentModifierMask = .command
        settingsItem.target = self
        menu.addItem(settingsItem)
        loginItem.target = self
        menu.addItem(loginItem)
        menu.addItem(NSMenuItem(title: "종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    private func refresh() {
        guard let controller, let statusItem else { return }
        biasMenuView?.refresh()
        brightnessKeysItem.state = controller.settings.brightnessKeysControlExternal ? .on : .off
        brightnessKeysStatus.title = brightnessKeys?.status ?? ""
        accessibilityItem.isHidden = brightnessKeys?.permissionGranted == true
        externalEnabledItem.state = controller.settings.externalEnabled ? .on : .off
        if let menu = statusItem.menu, let externalController {
            let titles = (externalController.displays.isEmpty ? ["외부 모니터 감지 없음"] : externalController.displays.map(\.title)) + externalController.conflictWarnings
            if externalStatusItems.map(\.title) != titles {
                for item in externalStatusItems { menu.removeItem(item) }
                externalStatusItems = titles.map { title in
                    let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                    item.isEnabled = false
                    return item
                }
                let index = menu.index(of: externalEnabledItem) + 1
                for (offset, item) in externalStatusItems.enumerated() { menu.insertItem(item, at: index + offset) }
            }
        }
        let on = controller.isEnabled || controller.settings.externalEnabled
        statusItem.button?.image = NSImage(
            systemSymbolName: on ? "sun.max.fill" : "sun.max",
            accessibilityDescription: "LidLux")
        statusItem.button?.appearsDisabled = !on

        let lux = controller.lastLux.map { String(format: "%.0f lux", $0) } ?? "– lux"
        let level = controller.currentBrightness.map { String(format: "%.0f%%", $0 * 100) } ?? "내장 디스플레이 꺼짐"
        statusLine.title = "조도 \(lux) · 밝기 \(level)"
        offsetLine.title = String(format: "선호 보정 %+.0f%%  (밝기 키로 조절하면 학습)", controller.offset * 100)
        enabledItem.state = controller.isEnabled ? .on : .off
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    func menuWillOpen(_ menu: NSMenu) { refresh() }

    @objc private func openSettings() {
        guard let controller, let externalController, let brightnessKeys else { return }
        if settingsWindow == nil { settingsWindow = SettingsWindow(controller: controller, external: externalController, keys: brightnessKeys) }
        settingsWindow?.present()
    }

    func applicationWillTerminate(_ notification: Notification) { brightnessKeys?.stop() }

    @objc private func toggleBrightnessKeys() {
        controller?.settings.brightnessKeysControlExternal.toggle()
        refresh()
    }

    @objc private func openAccessibility() { brightnessKeys?.openAccessibilitySettings() }

    @objc private func toggleEnabled() {
        guard let controller else { return }
        controller.isEnabled.toggle()
        refresh()
    }

    @objc private func toggleExternalEnabled() {
        controller?.settings.externalEnabled.toggle()
        refresh()
    }

    @objc private func resetOffset() {
        controller?.resetOffset()
    }

    @objc private func resync(_ notification: Notification) {
        let reason = notification.name.rawValue
        switch notification.name {
        case NSWorkspace.willSleepNotification:
            externalController?.setSleeping(true, system: true)
        case NSWorkspace.screensDidSleepNotification:
            externalController?.setSleeping(true, system: false)
        case NSWorkspace.didWakeNotification:
            externalController?.setSleeping(false, system: true)
        case NSWorkspace.screensDidWakeNotification:
            externalController?.setSleeping(false, system: false)
        default:
            externalController?.resync(reason: reason)
        }
        switch notification.name {
        case NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification:
            controller?.setSleeping(true, reason: reason)
        case NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification,
             NSWorkspace.sessionDidBecomeActiveNotification:
            controller?.setSleeping(false, reason: reason)
        default:
            controller?.resync(reason: reason)
        }
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
