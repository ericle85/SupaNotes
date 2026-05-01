import UIKit

// Lightweight placeholder for a single page in the vertical stack. Holds an
// optional low-res bitmap (the page's "snapshot" view) and provides a paper-
// colored background for empty/uninitialized pages. The live DrawingCanvasView
// is reparented onto whichever slot the user is currently focused on; the
// remaining slots show their bitmap (or just paper) until visited.
final class PageSlotView: UIView {

    // Bitmap snapshot for this page. Set to nil when the live canvas is
    // mounted on this slot — the canvas covers the imageView anyway, but
    // hiding it avoids a brief flash if the canvas is moved away.
    var bitmap: UIImage? {
        get { imageView.image }
        set {
            imageView.image = newValue
            imageView.isHidden = (newValue == nil)
        }
    }

    // The page index this slot represents. Set by the coordinator at rebuild.
    var pageIndex: Int = 0

    // Paper-colored background view + low-res snapshot layer.
    private let imageView = UIImageView()

    init(frame: CGRect, template: PageTemplate) {
        super.init(frame: frame)
        // Paper-style fill so empty slots still look like a page.
        backgroundColor = template.backgroundColor
        // Page shadow lives on the slot so bitmap and live canvas slots look identical.
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = Float(Design.Shadow.page.opacity)
        layer.shadowOffset = CGSize(width: Design.Shadow.page.x, height: Design.Shadow.page.y)
        layer.shadowRadius = Design.Shadow.page.radius
        // Snapshot fills the slot exactly. Hidden until a bitmap is set.
        imageView.contentMode = .scaleToFill
        imageView.frame = bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        imageView.isHidden = true
        addSubview(imageView)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
