import QuartzCore
import UIKit

final class NoFadeTiledLayer: CATiledLayer {
    override static func fadeDuration() -> CFTimeInterval {
        return 0
    }
}
