import Foundation

/// Code-only localization: the app is distributed without a resource bundle.
enum L10n {
    enum Language { case english, korean }

    /// Tests that override the language must run serially and restore this value.
    static var overrideLanguage: Language?

    static func language(for preferredLanguages: [String]) -> Language {
        preferredLanguages.first?.hasPrefix("ko") == true ? .korean : .english
    }

    static var language: Language {
        overrideLanguage ?? language(for: Locale.preferredLanguages)
    }

    private static func tr(_ english: String, _ korean: String) -> String {
        language == .korean ? korean : english
    }

    static var settingsTitle: String { tr("LidLux Settings", "LidLux 설정") }
    static var settings: String { tr("Settings…", "설정…") }
    static var launchAtLogin: String { tr("Launch at Login", "로그인 시 실행") }
    static var quit: String { tr("Quit LidLux", "종료") }
    static var automaticBrightness: String { tr("Automatically adjust brightness", "자동 밝기 조절") }
    static var adjustExternal: String { tr("Also adjust external monitors", "외부 모니터도 조절") }
    static var brightnessKeys: String { tr("Use brightness keys for external monitors", "밝기 키로 외부 모니터 조절") }
    static var openAccessibility: String { tr("Open Accessibility Settings…", "손쉬운 사용 설정 열기…") }
    static var keysOff: String { tr("External monitor brightness keys are off", "밝기 키 외부 조절 꺼짐") }
    static var permissionRequired: String { tr("Accessibility permission required", "손쉬운 사용 권한 필요") }
    static var keysActive: String { tr("External monitor brightness keys are active", "밝기 키 외부 조절 사용 중") }
    static var keysRetrying: String { tr("Unable to monitor brightness keys · Retrying", "밝기 키 감시 시작 실패 · 재시도 중") }
    static var hardwareUnavailable: String { tr("The ambient light sensor or built-in display could not be found.", "조도 센서 또는 내장 디스플레이를 찾을 수 없습니다.") }
    static var resetAdjustments: String { tr("Reset Learned Adjustments", "보정값 초기화") }
    static var resetExternalAdjustments: String { tr("Reset External Learned Adjustments", "외부 보정값 초기화") }
    static var restoreDefaults: String { tr("Restore Defaults", "기본값으로 되돌리기") }
    static var noExternalMonitors: String { tr("No external monitors detected", "외부 모니터 감지 없음") }
    static var noDetectedExternalMonitors: String { tr("No external monitors detected", "감지된 외부 모니터 없음") }
    static var builtinDisplayOff: String { tr("Built-in display is off", "내장 디스플레이 꺼짐") }
    static var displayOff: String { tr("Display is off", "디스플레이 꺼짐") }
    static var noMeasurement: String { tr("No reading", "측정 없음") }
    static var slow: String { tr("Slow", "느림") }
    static var normal: String { tr("Normal", "보통") }
    static var fast: String { tr("Fast", "빠름") }
    static var brightnessBias: String { tr("Brightness preference", "밝기 성향") }
    static var darker: String { tr("Darker", "어둡게") }
    static var brighter: String { tr("Brighter", "밝게") }
    static var minimumBrightness: String { tr("Minimum brightness", "최소 밝기") }
    static var responseSpeed: String { tr("Response speed", "반응 속도") }
    static var currentLux: String { tr("Ambient light", "현재 조도") }
    static var currentBrightness: String { tr("Current brightness", "현재 밝기") }
    static var externalMonitor: String { tr("External Monitor", "외부 모니터") }
    static var externalBrightnessBias: String { tr("External monitor brightness preference", "외부 모니터 밝기 성향") }
    static var curveLegend: String { tr("Solid line: adjusted curve · Gray dashed line: default curve (overlap when equal)\nLarge dot: target brightness at the current light level · Small orange circles: learned points\nScreen brightness changes smoothly at the selected response speed.", "실선: 적용 곡선 · 회색 점선: 기본 곡선 (같으면 겹침)\n큰 점: 현재 조도의 목표 밝기 · 주황색 작은 원: 학습 지점\n실제 화면 밝기는 반응 속도에 따라 부드럽게 이동합니다.") }
    static var ddcHelp: String { tr("Enable DDC/CI in your monitor’s on-screen menu. Learned adjustments are shared across external monitors. Brightness reflects the last read or write.", "모니터 OSD에서 DDC/CI를 켜세요. 보정값은 외부 모니터들이 공유합니다. 밝기는 마지막 읽기 또는 쓰기 기준입니다.") }
    static var restoreHelp: String { tr("Restoring defaults turns on automatic adjustment and resets learned adjustments and brightness settings.", "기본값 복원 시 자동 조절을 켜고 보정값과 밝기 설정을 초기화합니다.") }
    static var luxAxis: String { tr("Ambient light (lux, logarithmic scale)", "조도 (lux, 로그 스케일)") }
    static var curveAccessibility: String { tr("Brightness curve preview. Horizontal axis: ambient light on a logarithmic scale. Vertical axis: brightness from 0 to 100 percent.", "밝기 곡선 미리보기. 가로축 조도, 로그 스케일. 세로축 밝기 0에서 100퍼센트.") }

    static let appName = "LidLux"
    static var unknownLux: String { "– lux" }
    static func lux(_ value: Double) -> String { String(format: "%.0f lux", value) }
    static func percent(_ value: Double) -> String { String(format: "%.0f%%", value) }
    static func signedPercent(_ value: Double) -> String { String(format: "%+.0f%%", value) }
    static func number(_ value: Int) -> String { String(value) }

    static func luxAndBrightness(_ lux: String, _ level: String) -> String {
        tr("Ambient light \(lux) · Brightness \(level)", "조도 \(lux) · 밝기 \(level)")
    }
    static func adjustment(_ value: String, points: Int) -> String {
        tr("Adjustment at current light level: \(value) · Learned points: \(points)",
           "현재 조도에서의 보정 \(value) · 학습 지점 \(points)개")
    }
    static func externalMonitorNumber(_ number: Int) -> String {
        tr("External Monitor \(number)", "외부 모니터 \(number)")
    }
    static func brightnessUnavailable(_ name: String) -> String {
        tr("\(name) · Brightness unavailable", "\(name) · 밝기 읽기 불가")
    }
    static func monitorBrightness(_ name: String, _ percent: Int) -> String {
        "\(name) \(percent)%"
    }
    static func conflictWarning(_ name: String) -> String {
        tr("\(name) is running — brightness controls may conflict", "\(name) 실행 중 — 밝기 제어가 충돌할 수 있습니다")
    }
    static func externalBrightnessAccessibility(_ percent: Int) -> String {
        tr("External monitor brightness \(percent) percent", "외부 모니터 밝기 \(percent)퍼센트")
    }
    static func brightnessBiasValue(_ value: Double) -> String {
        "\(brightnessBias)  \(signedPercent(value))"
    }
}
