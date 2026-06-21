import CoreGraphics
import UIKit

struct StrokePoint {
    var location: CGPoint
    var force: CGFloat
    var azimuth: CGFloat
    var altitude: CGFloat
}

struct Stroke {
    var points: [StrokePoint] = []
    var color: UIColor = .label
    var width: CGFloat = 3
}
