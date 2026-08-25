import SwiftUI

/// Arc-length parameterisation of a rounded rectangle: four straight runs joined by four quarter
/// arcs, walked clockwise from the start of the top edge.
///
/// Solved analytically rather than by sampling `Path.trimmedPath`, which costs a path allocation
/// per sample and would run several hundred times a frame.
public struct RoundedRectOutline {
    public let size: CGSize
    public let radius: CGFloat

    public init(size: CGSize, radius: CGFloat) {
        self.size = size
        self.radius = radius
    }

    private var straightX: CGFloat { max(size.width - 2 * radius, 0) }
    private var straightY: CGFloat { max(size.height - 2 * radius, 0) }
    private var quarter: CGFloat { .pi * radius / 2 }

    public var length: CGFloat { 2 * (straightX + straightY) + 4 * quarter }

    public struct Sample {
        public let point: CGPoint
        public let normal: CGVector
        /// How far through a corner arc this point is, 0...1. `nil` on the straight runs.
        public let arcProgress: CGFloat?
    }

    /// The point `distance` along the outline, its outward unit normal, and its position within
    /// a corner arc if it is on one.
    public func sample(at distance: CGFloat) -> Sample {
        var s = distance.truncatingRemainder(dividingBy: length)
        if s < 0 { s += length }
        let (w, h, r) = (size.width, size.height, radius)

        if s < straightX { return straight(CGPoint(x: r + s, y: 0), CGVector(dx: 0, dy: -1)) }
        s -= straightX
        if s < quarter { return arc(centre: CGPoint(x: w - r, y: r), from: -.pi / 2, along: s) }
        s -= quarter
        if s < straightY { return straight(CGPoint(x: w, y: r + s), CGVector(dx: 1, dy: 0)) }
        s -= straightY
        if s < quarter { return arc(centre: CGPoint(x: w - r, y: h - r), from: 0, along: s) }
        s -= quarter
        if s < straightX { return straight(CGPoint(x: w - r - s, y: h), CGVector(dx: 0, dy: 1)) }
        s -= straightX
        if s < quarter { return arc(centre: CGPoint(x: r, y: h - r), from: .pi / 2, along: s) }
        s -= quarter
        if s < straightY { return straight(CGPoint(x: 0, y: h - r - s), CGVector(dx: -1, dy: 0)) }
        s -= straightY
        return arc(centre: CGPoint(x: r, y: r), from: .pi, along: s)
    }

    private func straight(_ point: CGPoint, _ normal: CGVector) -> Sample {
        Sample(point: point, normal: normal, arcProgress: nil)
    }

    private func arc(centre: CGPoint, from start: CGFloat, along travelled: CGFloat) -> Sample {
        let angle = start + (radius > 0 ? travelled / radius : 0)
        let normal = CGVector(dx: cos(angle), dy: sin(angle))
        return Sample(
            point: CGPoint(x: centre.x + radius * normal.dx, y: centre.y + radius * normal.dy),
            normal: normal,
            arcProgress: quarter > 0 ? travelled / quarter : 0
        )
    }
}

public extension CGPoint {
    func offset(by normal: CGVector, times amount: CGFloat) -> CGPoint {
        CGPoint(x: x + normal.dx * amount, y: y + normal.dy * amount)
    }
}
