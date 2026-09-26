import Foundation

/// Sorted log-lux samples. Age is independent of position and survives JSON round trips.
struct LearnedCurve: Codable, Equatable {
    struct Point: Codable, Equatable {
        let x: Double
        var offset: Double
        var order: Int
    }

    private(set) var points: [Point] = []

    static let defaultBase: (Double) -> Double = { Double(BrightnessController.baseBrightness(forLogLux: $0)) }

    /// 학습 지점 사이에서는 보정값이 아니라 **밝기**를 직선으로 잇는다. learn() 이 지점 밝기의 순서를
    /// 보장하므로 지점 사이 구간도 조도가 오를 때 밝기가 내려가지 않는다. 양 끝 밖은 가장 가까운 지점의 보정값을 유지한다.
    func offset(at x: Double, base: (Double) -> Double = LearnedCurve.defaultBase) -> Double {
        guard let first = points.first, let last = points.last else { return 0 }
        if x <= first.x { return first.offset }
        for (a, b) in zip(points, points.dropFirst()) where x <= b.x {
            let levelA = base(a.x) + a.offset
            let levelB = base(b.x) + b.offset
            let t = b.x > a.x ? (x - a.x) / (b.x - a.x) : 1
            return levelA + (levelB - levelA) * t - base(x)
        }
        return last.offset
    }

    mutating func learn(x: Double, offset: Double, base: (Double) -> Double, bias: Double) {
        guard x.isFinite, offset.isFinite, bias.isFinite else { return }
        let brightness = base(x) + bias + offset
        guard brightness.isFinite else { return }
        points.removeAll { abs($0.x - x) <= 0.35 }
        // Compact ages before inserting, avoiding an ever-growing counter.
        let ages = points.map(\.order).sorted()
        for index in points.indices { points[index].order = ages.firstIndex(of: points[index].order)! }
        points.append(Point(x: x, offset: offset, order: points.count))
        if points.count > 8, let oldest = points.indices.min(by: { points[$0].order < points[$1].order }) {
            points.remove(at: oldest)
        }
        for index in points.indices {
            let point = points[index]
            let level = base(point.x) + bias + point.offset
            if (point.x < x && level > brightness) || (point.x > x && level < brightness) {
                points[index].offset = brightness - base(point.x) - bias
            }
        }
        points.sort { $0.x < $1.x }
    }
}
