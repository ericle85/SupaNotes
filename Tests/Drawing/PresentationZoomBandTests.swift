import Testing
import CoreGraphics
@testable import SupaNotes

struct PresentationZoomBandTests {
    @Test("Baseline requires higher zoom before switching to detail")
    func baselineSwitchesUpOnlyAfterUpperThreshold() {
        #expect(
            PresentationZoomBand.preferredBand(
                for: CGFloat(1.74),
                currentBand: .baseline
            ) == .baseline
        )
        #expect(
            PresentationZoomBand.preferredBand(
                for: CGFloat(1.75),
                currentBand: .baseline
            ) == .detail
        )
    }

    @Test("Detail stays detail in the hysteresis window")
    func detailDoesNotImmediatelyFallBackNearBoundary() {
        #expect(
            PresentationZoomBand.preferredBand(
                for: CGFloat(1.5),
                currentBand: .detail
            ) == .detail
        )
        #expect(
            PresentationZoomBand.preferredBand(
                for: CGFloat(1.26),
                currentBand: .detail
            ) == .detail
        )
    }

    @Test("Detail falls back to baseline only below lower threshold")
    func detailSwitchesDownOnlyAfterLowerThreshold() {
        #expect(
            PresentationZoomBand.preferredBand(
                for: CGFloat(1.25),
                currentBand: .detail
            ) == .baseline
        )
        #expect(
            PresentationZoomBand.preferredBand(
                for: CGFloat(1.24),
                currentBand: .detail
            ) == .baseline
        )
    }
}
