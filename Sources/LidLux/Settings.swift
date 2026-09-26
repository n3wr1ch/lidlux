import Combine
import Foundation
import os

final class Settings: ObservableObject {
    enum ResponseSpeed: String, CaseIterable, Identifiable {
        case slow, normal, fast
        var id: String { rawValue }
        var title: String {
            switch self { case .slow: return L10n.slow; case .normal: return L10n.normal; case .fast: return L10n.fast }
        }
        var brighteningAlpha: Double {
            switch self { case .slow: return 0.18; case .normal: return 0.35; case .fast: return 0.6 }
        }
        var darkeningAlpha: Double {
            switch self { case .slow: return 0.06; case .normal: return 0.12; case .fast: return 0.24 }
        }
        var animationStep: Float {
            switch self { case .slow: return 0.04; case .normal: return 0.08; case .fast: return 0.16 }
        }
    }

    @Published private var brightnessKeysValue: Bool
    var onBrightnessKeysChange: (() -> Void)?

    var brightnessKeysControlExternal: Bool {
        get { brightnessKeysValue }
        set {
            guard brightnessKeysValue != newValue else { return }
            brightnessKeysValue = newValue
            defaults.set(newValue, forKey: "brightnessKeysControlExternal")
            onBrightnessKeysChange?()
        }
    }

    private let defaults: UserDefaults
    private let logger = Logger(subsystem: "com.ntoktok.lidlux", category: "settings")
    /// UI and controller run on the main thread. The controller reads changes on its next sample.
    var onChange: ((String) -> Void)?
    var onExternalChange: ((String) -> Void)?
    @Published private var externalEnabledValue: Bool
    @Published private var externalBiasValue: Double
    @Published private var externalLearnedValue: LearnedCurve
    @Published private var externalMinimumValue: Double
    @Published private var enabledValue: Bool
    @Published private var learnedValue: LearnedCurve
    @Published private var biasValue: Double
    @Published private var minimumValue: Double
    @Published private var speedValue: ResponseSpeed

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        brightnessKeysValue = defaults.object(forKey: "brightnessKeysControlExternal") as? Bool ?? true
        Self.migrateLegacySettings(into: defaults)
        externalEnabledValue = defaults.object(forKey: "externalEnabled") as? Bool ?? true
        externalBiasValue = Self.read(defaults, "externalBias", fallback: 0, range: -0.3...0.3)
        externalLearnedValue = Self.loadCurve(defaults, key: "externalLearnedPoints", legacyKey: "externalOffset")
        externalMinimumValue = Self.read(defaults, "externalMinimum", fallback: 0, range: 0...1)
        enabledValue = defaults.object(forKey: "enabled") as? Bool ?? true
        learnedValue = Self.loadCurve(defaults, key: "learnedPoints", legacyKey: "offset")
        biasValue = Self.read(defaults, "brightnessBias", fallback: 0, range: -0.3...0.3)
        minimumValue = Self.read(defaults, "minimumBrightness", fallback: 0.03, range: 0...0.3)
        speedValue = ResponseSpeed(rawValue: defaults.string(forKey: "responseSpeed") ?? "") ?? .normal
    }

    private static func loadCurve(_ defaults: UserDefaults, key: String, legacyKey: String) -> LearnedCurve {
        var curve = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(LearnedCurve.self, from: $0) } ?? LearnedCurve()
        let legacy = read(defaults, legacyKey, fallback: 0, range: -1...1)
        if curve.points.isEmpty && legacy != 0 {
            curve.learn(x: 2, offset: legacy, base: { _ in 0 }, bias: 0)
        }
        if let data = try? JSONEncoder().encode(curve) { defaults.set(data, forKey: key) }
        defaults.set(0, forKey: legacyKey)
        return curve
    }

    /// 이전 이름(AutoBright, com.ntoktok.autobright) 시절의 설정을 한 번만 옮겨온다.
    private static func migrateLegacySettings(into defaults: UserDefaults) {
        let marker = "migratedLegacySettings"
        guard !defaults.bool(forKey: marker) else { return }
        defaults.set(true, forKey: marker)
        guard let legacy = UserDefaults(suiteName: "com.ntoktok.autobright")?.persistentDomain(forName: "com.ntoktok.autobright") else { return }
        for key in ["enabled", "offset", "brightnessBias", "minimumBrightness", "responseSpeed"]
        where defaults.object(forKey: key) == nil {
            if let value = legacy[key] { defaults.set(value, forKey: key) }
        }
    }

    private static func read(_ defaults: UserDefaults, _ key: String, fallback: Double, range: ClosedRange<Double>) -> Double {
        let value = (defaults.object(forKey: key) as? NSNumber)?.doubleValue ?? fallback
        return bounded(value, fallback: fallback, range: range)
    }

    private static func bounded(_ value: Double, fallback: Double, range: ClosedRange<Double>) -> Double {
        value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : fallback
    }

    private func save(_ value: Any, key: String) {
        defaults.set(value, forKey: key)
        logger.notice("Setting changed: \(key, privacy: .public)")
        onChange?(key)
        if key.hasPrefix("external") { onExternalChange?(key) }
    }

    var isEnabled: Bool {
        get { enabledValue }
        set { guard newValue != enabledValue else { return }; enabledValue = newValue; save(newValue, key: "enabled") }
    }
    var learnedPoints: LearnedCurve {
        get { learnedValue }
        set {
            guard newValue != learnedValue, let data = try? JSONEncoder().encode(newValue) else { return }
            learnedValue = newValue
            save(data, key: "learnedPoints")
        }
    }
    var brightnessBias: Double {
        get { biasValue }
        set {
            let value = Self.bounded(newValue, fallback: 0, range: -0.3...0.3)
            guard value != biasValue else { return }
            biasValue = value
            save(value, key: "brightnessBias")
        }
    }
    var minimumBrightness: Double {
        get { minimumValue }
        set {
            let value = Self.bounded(newValue, fallback: 0.03, range: 0...0.3)
            guard value != minimumValue else { return }
            minimumValue = value
            save(value, key: "minimumBrightness")
        }
    }
    var responseSpeed: ResponseSpeed {
        get { speedValue }
        set { guard newValue != speedValue else { return }; speedValue = newValue; save(newValue.rawValue, key: "responseSpeed") }
    }

    var externalEnabled: Bool {
        get { externalEnabledValue }
        set { guard newValue != externalEnabledValue else { return }; externalEnabledValue = newValue; save(newValue, key: "externalEnabled") }
    }
    var externalBias: Double {
        get { externalBiasValue }
        set {
            let value = Self.bounded(newValue, fallback: 0, range: -0.3...0.3)
            guard value != externalBiasValue else { return }
            externalBiasValue = value
            save(value, key: "externalBias")
        }
    }
    var externalLearnedPoints: LearnedCurve {
        get { externalLearnedValue }
        set {
            guard newValue != externalLearnedValue, let data = try? JSONEncoder().encode(newValue) else { return }
            externalLearnedValue = newValue
            save(data, key: "externalLearnedPoints")
        }
    }
    var externalMinimum: Double {
        get { externalMinimumValue }
        set {
            let value = Self.bounded(newValue, fallback: 0, range: 0...1)
            guard value != externalMinimumValue else { return }
            externalMinimumValue = value
            save(value, key: "externalMinimum")
        }
    }

    func appliedBrightness(forLogLux x: Double) -> Float {
        max(Float(minimumBrightness), min(1, BrightnessController.baseBrightness(forLogLux: x) + Float(brightnessBias) + Float(learnedPoints.offset(at: x))))
    }

    func externalAppliedBrightness(forLogLux x: Double) -> Double {
        max(externalMinimum, min(1, Double(BrightnessController.baseBrightness(forLogLux: x))
            + externalBias + externalLearnedPoints.offset(at: x)))
    }

    func adjustmentDescription(at x: Double?, external: Bool = false) -> String {
        let curve = external ? externalLearnedPoints : learnedPoints
        let value = x.map { L10n.signedPercent(curve.offset(at: $0) * 100) } ?? L10n.noMeasurement
        return L10n.adjustment(value, points: curve.points.count)
    }

    func restoreDefaults() {
        brightnessKeysControlExternal = true
        externalBias = 0
        externalLearnedPoints = LearnedCurve()
        externalMinimum = 0
        externalEnabled = true
        brightnessBias = 0
        minimumBrightness = 0.03
        responseSpeed = .normal
        learnedPoints = LearnedCurve()
        isEnabled = true
        logger.notice("Restored default brightness settings")
    }
}
