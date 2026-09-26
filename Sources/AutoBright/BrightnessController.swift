import CoreGraphics
import Foundation
import os

/// 조도 센서 값을 읽어 내장 디스플레이 밝기를 부드럽게 조절한다.
/// 사용자가 밝기 키로 직접 바꾸면 그 차이를 오프셋으로 학습해 이후에도 반영한다.
final class BrightnessController {
    private var sensor: AmbientLightSensor?
    private let logger = Logger(subsystem: "com.ntoktok.autobright", category: "controller")
    private var sensorFailures = 0
    private var displayWasAvailable = false
    private var isSleeping = false
    private var learningAfter: TimeInterval = 0
    private let display: BuiltinDisplay
    private let defaults = UserDefaults.standard

    private var sampleTimer: Timer?
    private var animationTimer: Timer?

    /// log10(lux + 1) 의 지수이동평균
    private var smoothedLogLux: Double?
    /// 현재 향하고 있는 목표 밝기
    private var goal: Float?
    /// 이 앱이 마지막으로 설정한 밝기 (외부 변경 감지용)
    private var lastSet: Float?
    /// 사용자가 조절 중이면 이 시각까지 자동 조절을 멈춘다
    private var manualUntil = Date.distantPast
    /// 사용자가 자리를 비운 사이 시스템이 밝기를 바꿨으면(유휴 디밍 등) 다시 활동할 때까지 멈춘다
    private var suspendedUntilActivity = false

    private(set) var lastLux: Double?
    var onUpdate: (() -> Void)?

    // MARK: 설정 (UserDefaults)

    var isEnabled: Bool {
        get { defaults.object(forKey: "enabled") as? Bool ?? true }
        set {
            defaults.set(newValue, forKey: "enabled")
            newValue ? start() : stop()
        }
    }

    /// 사용자 선호 보정값 (-1 ~ 1)
    private(set) var offset: Float {
        get { defaults.float(forKey: "offset") }
        set { defaults.set(max(-1, min(1, newValue)), forKey: "offset") }
    }

    var currentBrightness: Float? { display.brightness }

    init(sensor: AmbientLightSensor, display: BuiltinDisplay) {
        self.sensor = sensor
        self.display = display
    }

    // MARK: 곡선

    /// log10(lux+1) → 밝기. 어두운 방에서는 낮게, 햇빛 아래에서는 최대로.
    private static let curve: [(x: Double, y: Double)] = [
        (0.0, 0.08),  // 0 lux (완전히 어두움)
        (1.0, 0.28),  // ~9 lux (어두운 방)
        (2.0, 0.52),  // ~100 lux (일반 실내 조명)
        (3.0, 0.82),  // ~1,000 lux (밝은 사무실/창가)
        (3.7, 1.00),  // ~5,000 lux (야외)
    ]

    static func baseBrightness(forLogLux x: Double) -> Float {
        let points = curve
        if x <= points[0].x { return Float(points[0].y) }
        for (a, b) in zip(points, points.dropFirst()) where x <= b.x {
            let t = (x - a.x) / (b.x - a.x)
            return Float(a.y + (b.y - a.y) * t)
        }
        return Float(points[points.count - 1].y)
    }

    private static let minimumBrightness: Float = 0.03

    // MARK: 동작

    func start() {
        guard sampleTimer == nil else { return }
        resync(reason: "start")
        logger.info("Automatic brightness started")
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.sample() }
        RunLoop.main.add(timer, forMode: .common)
        sampleTimer = timer
        sample()
    }

    func stop() {
        sampleTimer?.invalidate()
        sampleTimer = nil
        stopAnimation()
        onUpdate?()
    }

    /// 잠자기 해제, 디스플레이 구성 변경 등 이후 상태를 새로 잡는다.
    func resync(reason: String = "requested") {
        stopAnimation()
        lastSet = nil
        goal = nil
        suspendedUntilActivity = false
        manualUntil = .distantPast
        smoothedLogLux = nil
        learningAfter = ProcessInfo.processInfo.systemUptime + 3
        logger.info("Resync: \(reason, privacy: .public)")
    }

    func setSleeping(_ sleeping: Bool, reason: String) {
        isSleeping = sleeping
        resync(reason: reason)
    }

    func resetOffset() {
        offset = 0
        manualUntil = .distantPast
        if isEnabled { sample() }
    }

    private var secondsSinceUserActivity: Double {
        guard let eventType = CGEventType(rawValue: UInt32.max) else { return .infinity }
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: eventType)
    }

    private func sample() {
        defer { onUpdate?() }

        guard !isSleeping else { return }
        guard let actual = display.brightness else {
            if displayWasAvailable {
                resync(reason: "built-in display unavailable")
            }
            displayWasAvailable = false
            return
        }
        if !displayWasAvailable {
            resync(reason: "built-in display available")
            displayWasAvailable = true
        }

        guard let lux = sensor?.lux() else {
            if sensorFailures == 0 { resync(reason: "sensor read unavailable") }
            lastLux = nil
            sensorFailures += 1
            if sensorFailures >= 5 {
                sensorFailures = 0
                sensor = AmbientLightSensor()
                logger.notice("Recreated ambient light sensor; available: \(self.sensor != nil)")
                resync(reason: "consecutive sensor read failures")
            }
            return
        }
        if sensorFailures > 0 { resync(reason: "sensor readings recovered") }
        sensorFailures = 0
        lastLux = lux

        let logLux = log10(max(lux, 0) + 1)
        let smoothed: Double
        if let s = smoothedLogLux {
            // 밝아질 때는 빠르게, 어두워질 때는 천천히 따라간다
            let alpha = logLux > s ? 0.35 : 0.12
            smoothed = s + (logLux - s) * alpha
        } else {
            smoothed = logLux
        }
        smoothedLogLux = smoothed
        let base = Self.baseBrightness(forLogLux: smoothed)

        // 화면 복귀 직후 OS가 적용하는 밝기는 학습하지 않고 기준만 갱신한다.
        if ProcessInfo.processInfo.systemUptime < learningAfter {
            stopAnimation()
            lastSet = actual
            goal = actual
            return
        }

        let idle = secondsSinceUserActivity

        if suspendedUntilActivity {
            guard idle < 2 else { return }
            resync(reason: "user activity resumed")
            lastSet = actual
            goal = actual
            return
        }

        // 우리가 설정하지 않은 밝기 변화 감지
        if let lastSet, abs(actual - lastSet) > 0.015 {
            stopAnimation()
            self.lastSet = actual
            goal = actual
            if idle < 5 {
                // 사용자가 밝기 키로 직접 조절함 → 선호도로 학습
                offset = actual - base
                manualUntil = Date().addingTimeInterval(4)
                logger.info("Learned user adjustment: brightness=\(actual), offset=\(self.offset)")
            } else {
                // 자리를 비운 사이 시스템이 바꿈(유휴 디밍 등) → 사용자가 돌아올 때까지 건드리지 않음
                suspendedUntilActivity = true
                logger.info("Suspended after system brightness change while idle")
            }
            return
        }

        if Date() < manualUntil { return }

        let target = max(Self.minimumBrightness, min(1, base + offset))
        let reference = goal ?? actual
        // 작은 변화는 무시해서 밝기가 계속 꿈틀거리지 않게 한다
        guard abs(target - reference) >= 0.025 || (lastSet == nil && abs(target - actual) >= 0.005) else {
            if lastSet == nil { lastSet = actual }
            return
        }
        goal = target
        if lastSet == nil { lastSet = actual }
        startAnimation()
    }

    private func startAnimation() {
        guard animationTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.animationStep() }
        RunLoop.main.add(timer, forMode: .common)
        animationTimer = timer
    }

    private func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
    }

    private func animationStep() {
        guard let goal, let current = lastSet else { return stopAnimation() }
        let diff = goal - current
        if abs(diff) < 0.002 {
            apply(goal)
            return stopAnimation()
        }
        // 차이에 비례해 감속하면서 이동 (최소 속도 보장)
        let step = max(abs(diff) * 0.08, 0.002)
        apply(current + (diff > 0 ? min(step, diff) : max(-step, diff)))
    }

    private func apply(_ value: Float) {
        if display.setBrightness(value) {
            lastSet = value
        } else {
            resync(reason: "brightness write failed")
            displayWasAvailable = false
        }
    }
}
