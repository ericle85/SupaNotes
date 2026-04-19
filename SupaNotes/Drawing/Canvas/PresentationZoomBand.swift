import CoreGraphics

enum PresentationZoomBand: CGFloat, CaseIterable {
    case baseline = 1.0
    case detail = 2.0
    case deep = 4.0

    var scale: CGFloat { rawValue }

    static func preferredBand(for effectiveZoom: CGFloat) -> PresentationZoomBand {
        switch effectiveZoom {
        case ..<1.75:
            .baseline
        case ..<3.5:
            .detail
        default:
            .deep
        }
    }
}
