import Foundation
import Testing
@testable import LidLux

@Suite(.serialized) struct LearnedCurveTests {
    private let base: (Double) -> Double = { $0 * 0.2 }

    @Test func testEmptySingleInterpolationAndEndpoints() {
        var curve = LearnedCurve()
        #expect(curve.offset(at: 2, base: base) == 0)
        curve.learn(x: 1, offset: 0.1, base: base, bias: 0)
        #expect(curve.offset(at: -10, base: base) == 0.1)
        #expect(curve.offset(at: 10, base: base) == 0.1)
        curve.learn(x: 3, offset: 0.3, base: base, bias: 0)
        #expect(abs(curve.offset(at: 2, base: base) - (0.2)) < 1e-12)
        #expect(abs(curve.offset(at: 1, base: base) - (0.1)) < 1e-12)
        #expect(curve.offset(at: -10, base: base) == 0.1)
        #expect(curve.offset(at: 10, base: base) == 0.3)
    }

    @Test func testReplacementIncludesBothSidesAndBoundary() {
        var curve = LearnedCurve()
        curve.learn(x: 0, offset: 0, base: base, bias: 0)
        curve.learn(x: 0.7, offset: 0, base: base, bias: 0)
        curve.learn(x: 2, offset: 0, base: base, bias: 0)
        curve.learn(x: 0.35, offset: 0.1, base: base, bias: 0)
        #expect(curve.points.map(\.x) == [0.35, 2])
        #expect(abs(curve.offset(at: 0.35, base: base) - (0.1)) < 1e-12)
    }

    @Test func testOldestEvictionAndReplacementRefreshAgeAfterRoundTrip() throws {
        var curve = LearnedCurve()
        for x in [3.0, 0, 1, 2, 4, 5, 6, 7] {
            curve.learn(x: x, offset: 0, base: base, bias: 0)
        }
        curve = try JSONDecoder().decode(LearnedCurve.self, from: JSONEncoder().encode(curve))
        curve.learn(x: 8, offset: 0, base: base, bias: 0)
        #expect(curve.points.map(\.x) == [0, 1, 2, 4, 5, 6, 7, 8]) // oldest, not farthest
        curve.learn(x: 0, offset: 0.1, base: base, bias: 0)
        curve.learn(x: 9, offset: 0, base: base, bias: 0)
        #expect(curve.points.map(\.x) == [0, 2, 4, 5, 6, 7, 8, 9])
    }

    @Test func testMonotonicPointAdjustmentBothDirectionsWithBias() {
        var curve = LearnedCurve()
        let bias = 0.1
        for x in [0.0, 1, 2, 3, 4] { curve.learn(x: x, offset: 0, base: base, bias: bias) }
        curve.learn(x: 2, offset: -0.4, base: base, bias: bias)
        #expect(abs(base(1) + bias + curve.offset(at: 1, base: base) - (0.1)) < 1e-12)
        curve.learn(x: 2, offset: 0.5, base: base, bias: bias)
        #expect(abs(base(3) + bias + curve.offset(at: 3, base: base) - (1)) < 1e-12)
        let levels = curve.points.map { base($0.x) + bias + $0.offset }
        for (a, b) in zip(levels, levels.dropFirst()) { #expect(a <= b + 1e-12) }
        // For a linear base, monotonicity also holds throughout interpolated intervals.
        var previous = -Double.infinity
        for step in 0...500 {
            let x = Double(step) / 100
            let level = base(x) + bias + curve.offset(at: x, base: base)
            #expect(level + 1e-12 >= previous)
            previous = level
        }
    }

    @Test func realCurveStaysMonotonicBetweenOrderedPoints() {
        var curve = LearnedCurve()
        let base = LearnedCurve.defaultBase
        // 어두운 방은 밝게, 100 lux 는 같은 밝기로: 이전 구현은 사이 구간에서 밝기가 내려갔다.
        curve.learn(x: 0, offset: 0, base: base, bias: 0)
        curve.learn(x: 2, offset: base(0) - base(2), base: base, bias: 0)
        var previous = -Double.infinity
        for step in 0...400 {
            let x = Double(step) / 100
            let level = base(x) + curve.offset(at: x)
            #expect(level + 1e-12 >= previous)
            previous = level
        }
    }

    @Test func testAppliedCurvesAreIndependentAndNotifyCorrectController() {
        withDefaults { defaults in
            let settings = Settings(defaults: defaults)
            var changes: [String] = []
            var externalChanges: [String] = []
            settings.onChange = { changes.append($0) }
            settings.onExternalChange = { externalChanges.append($0) }
            settings.learnedPoints.learn(x: 1, offset: -0.1, base: base, bias: 0)
            settings.externalLearnedPoints.learn(x: 1, offset: 0.2, base: base, bias: 0)
            #expect(changes == ["learnedPoints", "externalLearnedPoints"])
            #expect(externalChanges == ["externalLearnedPoints"])
            #expect(abs(settings.appliedBrightness(forLogLux: 1) - (0.18)) < 1e-6)
            #expect(abs(settings.externalAppliedBrightness(forLogLux: 1) - (0.48)) < 1e-6)
            settings.learnedPoints = LearnedCurve()
            #expect(Settings(defaults: defaults).learnedPoints.points.isEmpty)
            #expect(settings.externalLearnedPoints.points.count == 1)
        }
    }

    private func withDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
        let name = "LidLuxTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(true, forKey: "migratedLegacySettings")
        try body(defaults)
    }

    @Test func testMigrationPersistenceAndReset() throws {
        try withDefaults { defaults in
            defaults.set(-0.2, forKey: "offset")
            defaults.set(0.15, forKey: "externalOffset")
            let settings = Settings(defaults: defaults)
            #expect(settings.learnedPoints.points.map(\.x) == [2])
            #expect(settings.externalLearnedPoints.points.map(\.x) == [2])
            for x in [0.0, 2, 4] {
                #expect(settings.learnedPoints.offset(at: x) == -0.2)
                #expect(settings.externalLearnedPoints.offset(at: x) == 0.15)
            }
            #expect(defaults.double(forKey: "offset") == 0)
            #expect(defaults.double(forKey: "externalOffset") == 0)
            let data = try #require(defaults.data(forKey: "learnedPoints"))
            #expect(try JSONDecoder().decode(LearnedCurve.self, from: data) == settings.learnedPoints)
            #expect(Settings(defaults: defaults).learnedPoints == settings.learnedPoints)
            settings.restoreDefaults()
            #expect(Settings(defaults: defaults).learnedPoints.points.isEmpty)
            #expect(Settings(defaults: defaults).externalLearnedPoints.points.isEmpty)
        }
    }

    @Test func testExistingPointsTakePrecedenceAndFreshDefaultsStayEmpty() {
        withDefaults { defaults in
            let settings = Settings(defaults: defaults)
            #expect(settings.learnedPoints.points.isEmpty)
            settings.learnedPoints.learn(x: 1, offset: 0.1, base: base, bias: 0)
            settings.externalLearnedPoints.learn(x: 3, offset: -0.1, base: base, bias: 0)
            defaults.set(0.7, forKey: "offset")
            defaults.set(-0.7, forKey: "externalOffset")
            let reloaded = Settings(defaults: defaults)
            #expect(reloaded.learnedPoints == settings.learnedPoints)
            #expect(reloaded.externalLearnedPoints == settings.externalLearnedPoints)
            #expect(defaults.double(forKey: "offset") == 0)
            #expect(defaults.double(forKey: "externalOffset") == 0)
        }
    }
}
