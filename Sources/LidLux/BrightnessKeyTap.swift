import AppKit
import ApplicationServices
import Combine
import os

/// The tap and its state live on the main run loop; DDC work is dispatched after returning.
final class BrightnessKeyTap: ObservableObject {
    @Published private(set) var permissionGranted = false
    @Published private(set) var isActive = false
    var onUpdate: (() -> Void)?
    private let settings: Settings
    private let external: ExternalBrightnessController
    private let logger = Logger(subsystem: "com.ntoktok.lidlux", category: "keys")
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var permissionTimer: Timer?
    private var captured = Set<Int>()
    private let hud = BrightnessHUD()
    private var lastTrust: Bool?
    private var reportedFailure = false

    var status: String {
        if !settings.brightnessKeysControlExternal { return L10n.keysOff }
        if !permissionGranted { return L10n.permissionRequired }
        return isActive ? L10n.keysActive : L10n.keysRetrying
    }

    init(settings: Settings, external: ExternalBrightnessController) {
        self.settings = settings
        self.external = external
        settings.onBrightnessKeysChange = { [weak self] in self?.settingChanged() }

    }

    func start() {
        guard permissionTimer == nil else { return }
        // 실행할 때마다 권한 창을 띄우지 않도록 자동 안내는 처음 한 번만 한다.
        let promptedKey = "didPromptAccessibility"
        if settings.brightnessKeysControlExternal, !UserDefaults.standard.bool(forKey: promptedKey) {
            UserDefaults.standard.set(true, forKey: promptedKey)
            settingChanged()
        } else {
            reconcile()
        }
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.reconcile() }
        permissionTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stop() {
        permissionTimer?.invalidate()
        permissionTimer = nil
        removeTap()
    }

    private func settingChanged() {
        if settings.brightnessKeysControlExternal, !AXIsProcessTrusted() {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
        reconcile()
    }

    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    private func reconcile() {
        let trusted = AXIsProcessTrusted()
        if lastTrust != trusted {
            lastTrust = trusted
            permissionGranted = trusted
            logger.notice("Accessibility permission: \(trusted)")
        }
        defer { onUpdate?() }
        guard trusted else { removeTap(); return }
        guard settings.brightnessKeysControlExternal else {
            // Finish swallowing the release of a press captured before the toggle changed.
            if captured.isEmpty { removeTap() }
            return
        }
        guard tap == nil else { return }
        let mask: CGEventMask = 1 << 14 // NX_SYSDEFINED
        guard let newTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let owner = Unmanaged<BrightnessKeyTap>.fromOpaque(context).takeUnretainedValue()
                return owner.handle(type: type, event: event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            if !reportedFailure { logger.notice("Brightness event tap creation failed") }
            reportedFailure = true
            return
        }
        guard let newSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0) else {
            CFMachPortInvalidate(newTap)
            logger.notice("Brightness event tap run loop source creation failed")
            return
        }
        tap = newTap
        source = newSource
        CFRunLoopAddSource(CFRunLoopGetMain(), newSource, .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)
        isActive = true
        reportedFailure = false
        logger.notice("Brightness event tap created")
    }

    private func removeTap() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
        captured.removeAll()
        isActive = false
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
                logger.notice("Brightness event tap re-enabled")
            }
            return Unmanaged.passUnretained(event)
        }
        guard type.rawValue == 14, let key = NSEvent(cgEvent: event),
              key.type == .systemDefined, key.subtype.rawValue == 8 else { return Unmanaged.passUnretained(event) }
        let code = (key.data1 & 0xFFFF0000) >> 16
        guard code == 2 || code == 3 else { return Unmanaged.passUnretained(event) }
        let flags = key.data1 & 0xFFFF
        let down = ((flags & 0xFF00) >> 8) == 0x0A
        let repeating = flags & 0x1 != 0
        if !down {
            return captured.remove(code) != nil ? nil : Unmanaged.passUnretained(event)
        }
        if !repeating { captured.remove(code) }
        // DDC 로 조절할 수 있는 외부 모니터가 없으면 키를 삼키지 않고 시스템에 넘긴다.
        guard settings.brightnessKeysControlExternal, !external.displays.isEmpty,
              let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }),
              let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              CGDisplayIsBuiltin(id) == 0 else { return Unmanaged.passUnretained(event) }
        captured.insert(code)
        let fine = key.modifierFlags.contains([.option, .shift])
        let step = (code == 2 ? 1.0 : -1.0) / (fine ? 64.0 : 16.0)
        DispatchQueue.main.async { [weak self] in
            guard let self, self.settings.brightnessKeysControlExternal else { return }
            self.external.onUserAdjustment = { [weak self] level in
                self?.hud.show(level: level, on: screen)
            }
            self.external.userAdjust(targetName: screen.localizedName, step: step)
        }
        return nil
    }
}
