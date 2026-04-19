import UIKit
import PencilKit

/// PKCanvasView subclass that removes the "Insert Space Above" menu item
/// from the lasso selection context menu via swizzling PKTiledView's
/// UIEditMenuInteraction delegate method.
class SupaCanvasView: PKCanvasView {
    var presentationScale: CGFloat = 1.0

    private static var hasSwizzled = false

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        Self.swizzleEditMenuIfNeeded(in: self)
    }

    private static func swizzleEditMenuIfNeeded(in view: UIView) {
        guard !hasSwizzled else { return }

        // Find the PKTiledView that holds the UIEditMenuInteraction
        guard let tiledView = findSubview(named: "PKTiledView", in: view) else { return }

        // Find the UIEditMenuInteraction on it
        guard let editMenuInteraction = tiledView.interactions.first(where: { $0 is UIEditMenuInteraction }) as? UIEditMenuInteraction else { return }

        // The delegate is the PKTiledView itself — swizzle its class's delegate method
        guard let delegate = editMenuInteraction.delegate else { return }
        let delegateClass: AnyClass = type(of: delegate)

        let selector = #selector(UIEditMenuInteractionDelegate.editMenuInteraction(_:menuFor:suggestedActions:))

        guard let original = class_getInstanceMethod(delegateClass, selector) else { return }

        let block: @convention(block) (AnyObject, UIEditMenuInteraction, UIEditMenuConfiguration, [UIMenuElement]) -> UIMenu? = { obj, interaction, config, suggestedActions in
            // Call original implementation
            typealias OriginalIMP = @convention(c) (AnyObject, Selector, UIEditMenuInteraction, UIEditMenuConfiguration, [UIMenuElement]) -> UIMenu?
            let originalIMP = unsafeBitCast(swizzledOriginalIMP, to: OriginalIMP.self)
            let menu = originalIMP(obj, selector, interaction, config, suggestedActions)

            guard let menu = menu else { return nil }

            // Filter out "Insert Space Above" from children
            let filtered = menu.children.filter { element in
                if let action = element as? UIAction {
                    return !action.title.contains("Insert Space")
                }
                if let submenu = element as? UIMenu {
                    return !submenu.title.contains("Insert Space")
                }
                return true
            }

            return menu.replacingChildren(filtered)
        }

        let newIMP = imp_implementationWithBlock(block)
        swizzledOriginalIMP = method_setImplementation(original, newIMP)
        hasSwizzled = true
    }

    private static var swizzledOriginalIMP: IMP!

    private static func findSubview(named className: String, in view: UIView) -> UIView? {
        let viewClassName = String(describing: type(of: view))
        if viewClassName == className { return view }
        for sub in view.subviews {
            if let found = findSubview(named: className, in: sub) { return found }
        }
        return nil
    }
}
