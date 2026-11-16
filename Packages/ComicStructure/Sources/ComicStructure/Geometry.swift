import Foundation

public struct Point: Hashable, Codable, Sendable {
    public var x: Double
    public var y: Double
    public init(_ x: Double, _ y: Double) { self.x = x; self.y = y }
}

/// Axis-aligned rectangle in normalized coordinates.
public struct Rect: Hashable, Codable, Sendable {
    public var minX: Double, minY: Double, maxX: Double, maxY: Double
    public init(minX: Double, minY: Double, maxX: Double, maxY: Double) {
        self.minX = minX; self.minY = minY; self.maxX = maxX; self.maxY = maxY
    }
    public static let unit = Rect(minX: 0, minY: 0, maxX: 1, maxY: 1)
    var width: Double { maxX - minX }
    var height: Double { maxY - minY }
    var midX: Double { (minX + maxX) / 2 }

    /// Maps a point in this rect's local unit square into the outer space.
    func fromLocal(_ p: Point) -> Point { Point(minX + p.x * width, minY + p.y * height) }
    /// Maps a point in the outer space into this rect's local unit square.
    func toLocal(_ p: Point) -> Point { Point((p.x - minX) / width, (p.y - minY) / height) }
    /// A sub-rect given in this rect's local unit square, in outer coordinates.
    func sub(_ r: Rect) -> Rect {
        let a = fromLocal(Point(r.minX, r.minY)), b = fromLocal(Point(r.maxX, r.maxY))
        return Rect(minX: a.x, minY: a.y, maxX: b.x, maxY: b.y)
    }
}

/// A convex polygon in normalized coordinates (0...1 on both axes).
public struct Polygon: Hashable, Codable, Sendable {
    public var points: [Point]
    public init(_ points: [Point]) { self.points = points }
    public static func rect(_ r: Rect) -> Polygon {
        Polygon([Point(r.minX, r.minY), Point(r.maxX, r.minY), Point(r.maxX, r.maxY), Point(r.minX, r.maxY)])
    }

    var bounds: Rect {
        Rect(minX: points.map(\.x).min() ?? 0, minY: points.map(\.y).min() ?? 0,
             maxX: points.map(\.x).max() ?? 0, maxY: points.map(\.y).max() ?? 0)
    }

    /// Signed area (shoelace); positive when counter-clockwise in a y-up frame.
    var signedArea: Double {
        guard points.count >= 3 else { return 0 }
        var a = 0.0
        for i in points.indices {
            let p = points[i], q = points[(i + 1) % points.count]
            a += p.x * q.y - q.x * p.y
        }
        return a / 2
    }

    var area: Double { abs(signedArea) }

    var centroid: Point {
        Point(points.map(\.x).reduce(0, +) / Double(points.count), points.map(\.y).reduce(0, +) / Double(points.count))
    }

    /// ≥3 points, non-degenerate, convex, inside the unit square.
    var isWellFormed: Bool {
        guard points.count >= 3, area > 1e-9 else { return false }
        guard points.allSatisfy({ (-1e-9...1 + 1e-9).contains($0.x) && (-1e-9...1 + 1e-9).contains($0.y) }) else { return false }
        var sign = 0.0
        for i in points.indices {
            let c = cross(points[i], points[(i + 1) % points.count], points[(i + 2) % points.count])
            if abs(c) < 1e-12 { continue }
            if sign == 0 { sign = c } else if (c > 0) != (sign > 0) { return false }
        }
        return true
    }

    /// True if `p` is inside the polygon or within `tolerance` of its boundary.
    func contains(_ p: Point, tolerance: Double = 0) -> Bool {
        let orientation: Double = signedArea >= 0 ? 1 : -1
        var inside = true
        for i in points.indices where cross(points[i], points[(i + 1) % points.count], p) * orientation < 0 {
            inside = false
            break
        }
        if inside { return true }
        return points.indices.contains { distance(p, segment: points[$0], points[($0 + 1) % points.count]) <= tolerance }
    }

    /// The part of the polygon on the left of the directed line a→b (cross ≥ 0). Sutherland–Hodgman, one plane.
    func clipped(keepingLeftOf a: Point, _ b: Point) -> Polygon {
        var out: [Point] = []
        for i in points.indices {
            let p = points[i], q = points[(i + 1) % points.count]
            let cp = cross(a, b, p), cq = cross(a, b, q)
            if cp >= 0 { out.append(p) }
            if (cp >= 0) != (cq >= 0) {
                let t = cp / (cp - cq)
                out.append(Point(p.x + t * (q.x - p.x), p.y + t * (q.y - p.y)))
            }
        }
        return Polygon(out).deduplicated
    }

    func clipped(to r: Rect) -> Polygon {
        self.clipped(keepingLeftOf: Point(r.minX, r.maxY), Point(r.minX, r.minY))
            .clipped(keepingLeftOf: Point(r.minX, r.minY), Point(r.maxX, r.minY))
            .clipped(keepingLeftOf: Point(r.maxX, r.minY), Point(r.maxX, r.maxY))
            .clipped(keepingLeftOf: Point(r.maxX, r.maxY), Point(r.minX, r.maxY))
    }

    func map(_ f: (Point) -> Point) -> Polygon { Polygon(points.map(f)) }

    private var deduplicated: Polygon {
        var out: [Point] = []
        for p in points where out.last.map({ distance($0, p) > 1e-12 }) ?? true { out.append(p) }
        if out.count > 1, let f = out.first, let l = out.last, distance(f, l) <= 1e-12 { out.removeLast() }
        return Polygon(out)
    }

    /// Convex hull (Andrew's monotone chain).
    static func hull(_ pts: [Point]) -> Polygon {
        let s = Set(pts).sorted { ($0.x, $0.y) < ($1.x, $1.y) }
        guard s.count >= 3 else { return Polygon(s) }
        func chain(_ seq: [Point]) -> [Point] {
            var h: [Point] = []
            for p in seq {
                while h.count >= 2 && cross(h[h.count - 2], h[h.count - 1], p) <= 0 { h.removeLast() }
                h.append(p)
            }
            return h
        }
        let lower = chain(s), upper = chain(s.reversed())
        return Polygon(Array(lower.dropLast() + upper.dropLast()))
    }
}

/// z of (b − a) × (c − a).
func cross(_ a: Point, _ b: Point, _ c: Point) -> Double {
    (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
}

func distance(_ a: Point, _ b: Point) -> Double { hypot(a.x - b.x, a.y - b.y) }

func distance(_ p: Point, segment a: Point, _ b: Point) -> Double {
    let dx = b.x - a.x, dy = b.y - a.y
    let len2 = dx * dx + dy * dy
    guard len2 > 0 else { return distance(p, a) }
    let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2))
    return distance(p, Point(a.x + t * dx, a.y + t * dy))
}

/// The virtual canvas a Panel's shape lives in. A one-Page Panel uses its Page's normalized coordinates.
/// A two-Page Panel's canvas places both Pages side by side as a spread, in reading direction:
/// right-to-left puts the first Page on the right, left-to-right on the left, vertical scroll on top.
// ponytail: both Pages get half the canvas regardless of pixel size; weight by width if spreads of unequal Pages matter.
enum Canvas {
    /// Region of the canvas occupied by the Page at `slot` (0 or 1) of a two-Page Panel.
    static func region(slot: Int, direction: ReadingDirection) -> Rect {
        switch (direction, slot) {
        case (.rightToLeft, 0), (.leftToRight, 1): return Rect(minX: 0.5, minY: 0, maxX: 1, maxY: 1)
        case (.rightToLeft, _), (.leftToRight, _): return Rect(minX: 0, minY: 0, maxX: 0.5, maxY: 1)
        case (.verticalScroll, 0): return Rect(minX: 0, minY: 0, maxX: 1, maxY: 0.5)
        case (.verticalScroll, _): return Rect(minX: 0, minY: 0.5, maxX: 1, maxY: 1)
        }
    }
}
