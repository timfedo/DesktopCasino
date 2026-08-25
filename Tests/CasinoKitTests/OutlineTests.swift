import SwiftUI
import Testing

@testable import CasinoKit

/// `RoundedRectOutline.sample` is eight branches of arc-length maths that nothing else checks,
/// and the win marquee is drawn entirely from it.
@Suite("Rounded rect outline")
struct OutlineTests {
    private let outline = RoundedRectOutline(size: CGSize(width: 216, height: 82), radius: 12)

    @Test("Length is the straights plus one full circle of corners")
    func length() {
        let expected = 2 * (216 - 24) + 2 * (82 - 24) + 2 * Double.pi * 12
        #expect(abs(outline.length - expected) < 0.0001)
    }

    @Test("Normals are unit vectors all the way round")
    func normalsAreUnit() {
        for step in 0..<720 {
            let sample = outline.sample(at: outline.length * Double(step) / 720)
            let magnitude = (sample.normal.dx * sample.normal.dx
                + sample.normal.dy * sample.normal.dy).squareRoot()
            #expect(abs(magnitude - 1) < 0.0001)
        }
    }

    @Test("The outline is closed: sampling at 0 and at length agree")
    func closed() {
        let start = outline.sample(at: 0)
        let end = outline.sample(at: outline.length)
        #expect(abs(start.point.x - end.point.x) < 0.0001)
        #expect(abs(start.point.y - end.point.y) < 0.0001)
    }

    @Test("Sampling wraps, so negative and over-length distances stay on the outline")
    func wraps() {
        let reference = outline.sample(at: 30)
        for offset in [-2, -1, 1, 2] {
            let wrapped = outline.sample(at: 30 + outline.length * Double(offset))
            #expect(abs(wrapped.point.x - reference.point.x) < 0.001)
            #expect(abs(wrapped.point.y - reference.point.y) < 0.001)
        }
    }

    @Test("Consecutive samples advance by the step, with no jump at a corner seam")
    func continuous() {
        let step = outline.length / 2000
        var previous = outline.sample(at: 0).point
        for index in 1...2000 {
            let point = outline.sample(at: step * Double(index)).point
            let travelled = ((point.x - previous.x) * (point.x - previous.x)
                + (point.y - previous.y) * (point.y - previous.y)).squareRoot()
            // A discontinuity would show up as a hop far larger than the sampling step.
            #expect(travelled < step * 1.5)
            previous = point
        }
    }

    @Test("Every point sits on the outline, at the corner radius from its arc centre")
    func pointsLieOnOutline() {
        for step in 0..<720 {
            let sample = outline.sample(at: outline.length * Double(step) / 720)
            let (x, y) = (sample.point.x, sample.point.y)
            let onStraight = abs(x) < 0.001 || abs(x - 216) < 0.001
                || abs(y) < 0.001 || abs(y - 82) < 0.001
            if !onStraight {
                // Otherwise it must be exactly `radius` from the nearest corner's centre.
                let cx = x < 108 ? 12.0 : 216 - 12
                let cy = y < 41 ? 12.0 : 82 - 12
                let distance = ((x - cx) * (x - cx) + (y - cy) * (y - cy)).squareRoot()
                #expect(abs(distance - 12) < 0.001)
            }
        }
    }

    @Test("arcProgress is nil on the straights and spans 0...1 on each corner")
    func arcProgress() {
        var cornerSamples = 0
        for step in 0..<2000 {
            let sample = outline.sample(at: outline.length * Double(step) / 2000)
            if let progress = sample.arcProgress {
                #expect(progress >= 0 && progress <= 1)
                cornerSamples += 1
            }
        }
        #expect(cornerSamples > 0)
        // Four quarter arcs are 2*pi*r of the perimeter; allow a sampling tolerance.
        let expectedFraction = (2 * Double.pi * 12) / outline.length
        let actualFraction = Double(cornerSamples) / 2000
        #expect(abs(actualFraction - expectedFraction) < 0.02)
    }
}
