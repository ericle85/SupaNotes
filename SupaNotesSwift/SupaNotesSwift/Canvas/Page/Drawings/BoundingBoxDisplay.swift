import UIKit

func makeBoundingBoxLayer() -> CAShapeLayer {
    let layer = CAShapeLayer()
    layer.fillColor = nil
    layer.strokeColor = UIColor.systemBlue.cgColor
    layer.lineWidth = 2
    layer.lineDashPattern = [6, 4]
    layer.isHidden = true
    return layer
}

func showBoundingBox(_ rect: CGRect, on layer: CAShapeLayer) {
    layer.path = UIBezierPath(
        roundedRect: rect.insetBy(dx: -4, dy: -4), cornerRadius: 4
    ).cgPath
    layer.isHidden = false
}
