import CoreGraphics
import Foundation

struct StrokePoint {
    var location: CGPoint
    var force: CGFloat
    var azimuth: CGFloat
    var altitude: CGFloat
}

struct Stroke {
    var points: [StrokePoint] = []
}
