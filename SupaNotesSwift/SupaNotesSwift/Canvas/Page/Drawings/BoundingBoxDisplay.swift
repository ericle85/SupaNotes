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

func makeLineUnderlineLayer() -> CAShapeLayer {
    let layer = CAShapeLayer()
    layer.fillColor = nil
    layer.strokeColor = UIColor.systemRed.cgColor
    layer.lineWidth = 2
    return layer
}

func showLineUnderlines(_ rects: [CGRect], on layer: CAShapeLayer) {
    let path = UIBezierPath()
    for rect in rects {
        let y = rect.maxY + 2
        path.move(to: CGPoint(x: rect.minX, y: y))
        path.addLine(to: CGPoint(x: rect.maxX, y: y))
    }
    layer.path = path.cgPath
    layer.isHidden = rects.isEmpty
}
