import AppKit
import Combine
import os

/// Main-thread state machine. Only ExternalDisplays performs DDC I/O.
final class ExternalBrightnessController: ObservableObject {
    struct Status: Identifiable {
        let id: UInt64
        let name: String
        let current: Int?
        let maximum: Int?
        let unavailable: Bool
        var title: String {
            guard !unavailable, let current, let maximum else { return L10n.brightnessUnavailable(name) }
            return L10n.monitorBrightness(name, Int((Double(current) / Double(maximum) * 100).rounded()))
        }
    }
    private final class Monitor {
        let display: ExternalDisplays.Display
        var current: Int?
        var maximum: Int?
        var lastSet: Int?
        var lastWrite: TimeInterval = -.infinity
        var nextRead: TimeInterval = 0
        var learningAfter: TimeInterval = .infinity
        var manualUntil: TimeInterval = 0
        var readFailures = 0
        var writeFailures = 0
        var busy = false
        var skipped: Bool { readFailures >= 3 || writeFailures >= 3 }
        init(_ display: ExternalDisplays.Display) { self.display = display }
    }

    @Published private(set) var displays: [Status] = []
    @Published private(set) var conflictWarnings: [String] = []
    var onUpdate: (() -> Void)?
    private let settings: Settings
    private let ddc = ExternalDisplays()
    private let logger = Logger(subsystem: "com.ntoktok.lidlux", category: "external-controller")
    private var monitors: [Monitor] = []
    private var timer: Timer?
    private var token = 0
    private var systemSleeping = false
    private var screensSleeping = false
    private var sleeping: Bool { systemSleeping || screensSleeping }
    private var logLux: Double?
    private var sampleTime: TimeInterval = -.infinity
    private var nextConflictCheck: TimeInterval = 0
    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    init(settings: Settings) { self.settings = settings }

    func start() {
        guard timer == nil else { return }
        checkConflicts()
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        resync(reason: "start")
    }

    func accept(logLux: Double) {
        self.logLux = logLux
        sampleTime = now
    }

    func settingsChanged(_ key: String) {
        if key == "externalEnabled" { resync(reason: "external enabled changed") }
        onUpdate?()
    }

    func resetOffset() {
        settings.externalLearnedPoints = LearnedCurve()
        for monitor in monitors { monitor.manualUntil = 0 }
        logger.notice("Reset external learned adjustment")
    }

    func setSleeping(_ value: Bool, system: Bool) {
        if system { systemSleeping = value } else { screensSleeping = value }
        // A system wake is followed by a screen wake; keep I/O paused until both arrive.
        resync(reason: value ? "sleep" : "wake")
    }

    func resync(reason: String) {
        token = ddc.invalidate()
        logLux = nil
        sampleTime = -.infinity
        monitors = []
        publish()
        logger.notice("External resync: \(reason, privacy: .public)")
        guard !sleeping else { return }
        let generation = token
        ddc.enumerate(token: generation) { [weak self] found in
            guard let self, self.token == generation, !self.sleeping else { return }
            self.monitors = Self.named(found).map(Monitor.init)
            self.logger.notice("Discovered \(found.count) external monitor services")
            self.publish()
            self.tick()
        }
    }

    /// DDC 서비스 노드에는 제품명이 없는 경우가 많다. 외부 화면이 한 대면 macOS 화면 이름을 쓰고,
    /// 여러 대면 어느 서비스가 어느 화면인지 확실하지 않으므로 번호로 구분한다.
    private static func named(_ found: [ExternalDisplays.Display]) -> [ExternalDisplays.Display] {
        let externalScreens = NSScreen.screens.filter {
            guard let id = $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { return false }
            return CGDisplayIsBuiltin(id) == 0
        }
        return found.enumerated().map { index, display in
            guard !display.hasProductName else { return display }
            if found.count == 1, externalScreens.count == 1 {
                return ExternalDisplays.Display(id: display.id, name: externalScreens[0].localizedName)
            }
            return ExternalDisplays.Display(id: display.id, name: found.count > 1 ? L10n.externalMonitorNumber(index + 1) : L10n.externalMonitor)
        }
    }

    private func tick() {
        if now >= nextConflictCheck {
            checkConflicts()
            nextConflictCheck = now + 10
        }
        guard !sleeping else { return }
        for monitor in monitors where !monitor.busy && !monitor.skipped {
            // Reserve a quiet interval for polling, even during a long brightness ramp.
            if now >= monitor.nextRead {
                if now - monitor.lastWrite >= 3 { read(monitor) }
                continue
            }
            guard settings.externalEnabled, let logLux, now - sampleTime <= 2,
                  now >= monitor.manualUntil, now >= monitor.learningAfter,
                  now - monitor.lastWrite >= 1,
                  let maximum = monitor.maximum, let previous = monitor.lastSet else { continue }
            let level = settings.externalAppliedBrightness(forLogLux: logLux)
            let target = Int((level * Double(maximum)).rounded())
            guard abs(target - previous) >= 3 else { continue }
            write(monitor, value: previous + max(-8, min(8, target - previous)))
        }
    }

    private func read(_ monitor: Monitor) {
        monitor.busy = true
        let generation = token
        ddc.read(id: monitor.display.id, token: generation) { [weak self] result in
            guard let self, self.token == generation, !self.sleeping else { return }
            monitor.busy = false
            monitor.nextRead = self.now + 10
            guard let result else {
                monitor.readFailures += 1
                self.logger.notice("External read failed: \(monitor.display.name, privacy: .public), consecutive=\(monitor.readFailures), skipped=\(monitor.skipped)")
                self.publish()
                return
            }
            monitor.readFailures = 0
            let previous = monitor.lastSet
            let previousMaximum = monitor.maximum
            monitor.current = result.current
            monitor.maximum = result.maximum
            if previous == nil || previousMaximum != result.maximum {
                monitor.lastSet = result.current
                monitor.learningAfter = self.now + 5
                self.logger.notice("External baseline: \(monitor.display.name, privacy: .public), brightness=\(result.current)/\(result.maximum)")
            } else if let previous, abs(result.current - previous) >= 3 {
                monitor.lastSet = result.current
                if self.settings.externalEnabled, self.now >= monitor.learningAfter,
                   let logLux = self.logLux, self.now - self.sampleTime <= 2 {
                    let base = Double(BrightnessController.baseBrightness(forLogLux: logLux))
                    self.settings.externalLearnedPoints.learn(
                        x: logLux, offset: Double(result.current) / Double(result.maximum) - base - self.settings.externalBias,
                        base: { Double(BrightnessController.baseBrightness(forLogLux: $0)) }, bias: self.settings.externalBias)
                    monitor.manualUntil = self.now + 5
                    self.logger.notice("Learned external adjustment: \(monitor.display.name, privacy: .public), offset=\(self.settings.externalLearnedPoints.offset(at: logLux))")
                }
            }
            self.publish()
        }
    }

    private func write(_ monitor: Monitor, value: Int) {
        monitor.busy = true
        let generation = token
        ddc.write(id: monitor.display.id, value: value, token: generation) { [weak self] success in
            guard let self, self.token == generation, !self.sleeping else { return }
            monitor.busy = false
            monitor.lastWrite = self.now
            if success {
                monitor.lastSet = value
                monitor.current = value
                monitor.writeFailures = 0
            } else {
                monitor.writeFailures += 1
                monitor.nextRead = self.now
                self.logger.notice("External write failed: \(monitor.display.name, privacy: .public), skipped=\(monitor.skipped)")
            }
            self.publish()
        }
    }

    private func publish() {
        displays = monitors.map {
            Status(id: $0.display.id, name: $0.display.name, current: $0.current,
                   maximum: $0.maximum, unavailable: $0.skipped || $0.readFailures > 0)
        }
        onUpdate?()
    }

    private func checkConflicts() {
        var names = Set<String>()
        for app in NSWorkspace.shared.runningApplications {
            if app.bundleIdentifier == "fyi.lunar.Lunar" || app.localizedName == "Lunar" { names.insert("Lunar") }
            if app.bundleIdentifier == "me.guillaumeb.MonitorControl" || app.localizedName == "MonitorControl" { names.insert("MonitorControl") }
        }
        let warnings = names.sorted().map { L10n.conflictWarning($0) }
        guard warnings != conflictWarnings else { return }
        conflictWarnings = warnings
        logger.notice("External brightness conflicts: \(warnings.isEmpty ? "none" : warnings.joined(separator: "; "), privacy: .public)")
        onUpdate?()
    }

    /// User writes deliberately leave lastSet/lastWrite untouched: read() owns learning.
    var onUserAdjustment: ((Double) -> Void)?
    private var userInputs: [(monitor: Monitor, step: Double, generation: Int, completion: ((Double) -> Void)?)] = []
    private var userInputTimer: Timer?
    private var userWriteInFlight = false

    func userAdjust(targetName: String?, step: Double) {
        guard !sleeping, step.isFinite else { return }
        let matching = monitors.filter { $0.display.name == targetName }
        let targets = monitors.count == 1 || matching.isEmpty ? monitors : matching
        for monitor in targets {
            monitor.manualUntil = now + 6
            monitor.nextRead = now + 3.5
            userInputs.append((monitor, step, token, onUserAdjustment))
        }
        drainUserInputs()
    }

    private func drainUserInputs() {
        guard !userWriteInFlight else { return }
        userInputTimer?.invalidate()
        userInputTimer = nil
        while let input = userInputs.first {
            guard input.generation == token, !sleeping else {
                userInputs.removeFirst()
                continue
            }
            let monitor = input.monitor
            // Existing automatic I/O must finish before calculating from its result.
            if monitor.busy {
                let timer = Timer(timeInterval: 0.02, repeats: false) { [weak self] _ in self?.drainUserInputs() }
                userInputTimer = timer
                RunLoop.main.add(timer, forMode: .common)
                return
            }
            userInputs.removeFirst()
            guard let current = monitor.current ?? monitor.lastSet,
                  let maximum = monitor.maximum, maximum > 0 else { continue }
            let value = Int(max(0, min(Double(maximum), Double(current) + input.step * Double(maximum))).rounded())
            monitor.manualUntil = now + 6
            monitor.nextRead = now + 3.5
            monitor.busy = true
            userWriteInFlight = true
            ddc.write(id: monitor.display.id, value: value, token: input.generation) { [weak self] success in
                guard let self else { return }
                self.userWriteInFlight = false
                if self.token == input.generation, !self.sleeping {
                    monitor.busy = false
                    // Also protect a slow or queued write from an immediate automatic overwrite.
                    monitor.manualUntil = self.now + 6
                    monitor.nextRead = self.now + 3.5
                    if success {
                        monitor.current = value
                        monitor.writeFailures = 0
                        self.publish()
                        input.completion?(Double(value) / Double(maximum))
                    }
                }
                self.drainUserInputs()
            }
            return
        }
    }

}
