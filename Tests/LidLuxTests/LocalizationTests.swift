import Foundation
import Testing
@testable import LidLux

@Suite(.serialized)
struct LocalizationTests {
    @Test func languageSelectionUsesOnlyFirstPreference() {
        #expect(L10n.language(for: ["ko-KR", "en-US"]) == .korean)
        #expect(L10n.language(for: ["ko"]) == .korean)
        #expect(L10n.language(for: ["en-US", "ko-KR"]) == .english)
        #expect(L10n.language(for: ["ja-JP"]) == .english)
        #expect(L10n.language(for: []) == .english)
    }

    private var strings: [String] {
        [
            L10n.settingsTitle,
            L10n.settings,
            L10n.launchAtLogin,
            L10n.quit,
            L10n.automaticBrightness,
            L10n.adjustExternal,
            L10n.brightnessKeys,
            L10n.openAccessibility,
            L10n.keysOff,
            L10n.permissionRequired,
            L10n.keysActive,
            L10n.keysRetrying,
            L10n.hardwareUnavailable,
            L10n.resetAdjustments,
            L10n.resetExternalAdjustments,
            L10n.restoreDefaults,
            L10n.noExternalMonitors,
            L10n.noDetectedExternalMonitors,
            L10n.builtinDisplayOff,
            L10n.displayOff,
            L10n.noMeasurement,
            L10n.slow,
            L10n.normal,
            L10n.fast,
            L10n.brightnessBias,
            L10n.darker,
            L10n.brighter,
            L10n.minimumBrightness,
            L10n.responseSpeed,
            L10n.currentLux,
            L10n.currentBrightness,
            L10n.externalMonitor,
            L10n.externalBrightnessBias,
            L10n.curveLegend,
            L10n.ddcHelp,
            L10n.restoreHelp,
            L10n.luxAxis,
            L10n.curveAccessibility
        ]
    }

    @Test func bothLanguagesHaveDistinctNonemptyStrings() {
        let previous = L10n.overrideLanguage
        defer { L10n.overrideLanguage = previous }
        L10n.overrideLanguage = .english
        let english = strings
        L10n.overrideLanguage = .korean
        let korean = strings
        #expect(english.count == korean.count)
        for (en, ko) in zip(english, korean) {
            #expect(!en.isEmpty)
            #expect(!ko.isEmpty)
            #expect(en != ko)
        }
    }

    @Test func overrideCanSwitchAndRestoreSystemLanguage() {
        let previous = L10n.overrideLanguage
        defer { L10n.overrideLanguage = previous }
        L10n.overrideLanguage = .english
        #expect(L10n.settings == "Settings…")
        #expect(Settings.ResponseSpeed.slow.title == "Slow")
        L10n.overrideLanguage = .korean
        #expect(L10n.settings == "설정…")
        #expect(Settings.ResponseSpeed.slow.title == "느림")
        L10n.overrideLanguage = nil
        #expect(L10n.language == L10n.language(for: Locale.preferredLanguages))
    }

    @Test func formattedStringsPreserveValuesInBothLanguages() {
        let previous = L10n.overrideLanguage
        defer { L10n.overrideLanguage = previous }
        for language in [L10n.Language.english, .korean] {
            L10n.overrideLanguage = language
            let status = L10n.luxAndBrightness("123 lux", "67%")
            #expect(status.contains("123 lux"))
            #expect(status.contains("67%"))
            let adjustment = L10n.adjustment("-12%", points: 8)
            #expect(adjustment.contains("-12%"))
            #expect(adjustment.contains("8"))
            #expect(L10n.externalMonitorNumber(3).contains("3"))
            #expect(L10n.brightnessUnavailable("Studio").contains("Studio"))
            #expect(L10n.monitorBrightness("Studio", 67) == "Studio 67%")
            #expect(L10n.conflictWarning("Lunar").contains("Lunar"))
            #expect(L10n.externalBrightnessAccessibility(67).contains("67"))
            #expect(L10n.brightnessBiasValue(12).contains("+12%"))
            #expect(L10n.lux(123) == "123 lux")
            #expect(L10n.percent(67) == "67%")
            #expect(L10n.signedPercent(-12) == "-12%")
            #expect(L10n.number(1000) == "1000")
        }
    }

    @Test func productNamePresenceDoesNotDependOnDisplayText() {
        let named = ExternalDisplays.Display(id: 1, name: "외부 모니터")
        let unnamed = ExternalDisplays.Display(id: 2, name: "", hasProductName: false)
        #expect(named.hasProductName)
        #expect(!unnamed.hasProductName)
    }
}
