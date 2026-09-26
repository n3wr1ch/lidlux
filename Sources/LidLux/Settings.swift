import Combine
import Foundation
import os

final class Settings: ObservableObject {
    enum ResponseSpeed: String, CaseIterable, Identifiable {
        case slow, normal, fast
        var id: String { rawValue }
        var title: String {
            switch self { case .slow: return "느림"; case .normal: return "보통"; case .fast: return "빠름" }
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

    private let defaults: UserDefaults
    private let logger = Logger(subsystem: "com.ntoktok.lidlux", category: "settings")
    /// UI and controller run on the main thread. The controller reads changes on its next sample.
    var onChange: ((String) -> Void)?
    var onExternalChange: ((String) -> Void)?
    @Published private var externalEnabledValue: Bool
    @Published private var externalBiasValue: Double
    @Published private var externalOffsetValue: Double
    @Published private var externalMinimumValue: Double
    @Published private var enabledValue: Bool
    @Published private var offsetValue: Float
    @Published private var biasValue: Double
    @Published private var minimumValue: Double
    @Published private var speedValue: ResponseSpeed

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        Self.migrateLegacySettings(into: defaults)
        externalEnabledValue = defaults.object(forKey: "externalEnabled") as? Bool ?? true
        externalBiasValue = Self.read(defaults, "externalBias", fallback: 0, range: -0.3...0.3)
        externalOffsetValue = Self.read(defaults, "externalOffset", fallback: 0, range: -1...1)
        externalMinimumValue = Self.read(defaults, "externalMinimum", fallback: 0, range: 0...1)
        enabledValue = defaults.object(forKey: "enabled") as? Bool ?? true
        offsetValue = Float(Self.read(defaults, "offset", fallback: 0, range: -1...1))
        biasValue = Self.read(defaults, "brightnessBias", fallback: 0, range: -0.3...0.3)
        minimumValue = Self.read(defaults, "minimumBrightness", fallback: 0.03, range: 0...0.3)
        speedValue = ResponseSpeed(rawValue: defaults.string(forKey: "responseSpeed") ?? "") ?? .normal
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
    var offset: Float {
        get { offsetValue }
        set {
            let value = Float(Self.bounded(Double(newValue), fallback: 0, range: -1...1))
            guard value != offsetValue else { return }
            offsetValue = value
            save(value, key: "offset")
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
    var externalOffset: Double {
        get { externalOffsetValue }
        set {
            let value = Self.bounded(newValue, fallback: 0, range: -1...1)
            guard value != externalOffsetValue else { return }
            externalOffsetValue = value
            save(value, key: "externalOffset")
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
        max(Float(minimumBrightness), min(1, BrightnessController.baseBrightness(forLogLux: x) + Float(brightnessBias) + offset))
    }

    func restoreDefaults() {
        externalBias = 0
        externalOffset = 0
        externalMinimum = 0
        externalEnabled = true
        brightnessBias = 0
        minimumBrightness = 0.03
        responseSpeed = .normal
        offset = 0
        isEnabled = true
        logger.notice("Restored default brightness settings")
    }
}
