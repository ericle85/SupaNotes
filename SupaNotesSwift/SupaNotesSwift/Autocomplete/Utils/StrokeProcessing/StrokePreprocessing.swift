import Foundation

let RESAMPLE_STEP: Float = 0.02
let MAX_SEQ_LEN = 2048
let FEATURE_DIM = 6

struct StrokePoint {
    let x: Float
    let y: Float
    let t: Float
}

func resampleStroke(_ stroke: [StrokePoint], step: Float = RESAMPLE_STEP) -> [StrokePoint] {
    guard stroke.count >= 2 else {
        return stroke
    }

    var cumLen = [Float](repeating: 0, count: stroke.count)
    for i in 1 ..< stroke.count {
        let dx = stroke[i].x - stroke[i - 1].x
        let dy = stroke[i].y - stroke[i - 1].y
        cumLen[i] = cumLen[i - 1] + sqrt(dx * dx + dy * dy)
    }
    let totalLen = cumLen.last!

    if totalLen < 1e-8 {
        return [stroke[0]]
    }

    let nPoints = max(2, Int(ceil(totalLen / step)) + 1)
    var result = [StrokePoint]()
    result.reserveCapacity(nPoints)

    let xs = stroke.map { $0.x }
    let ys = stroke.map { $0.y }
    let ts = stroke.map { $0.t }

    for i in 0 ..< nPoints {
        let targetLen = totalLen * Float(i) / Float(nPoints - 1)
        let interpX = linearInterp(cumLen, xs, at: targetLen)
        let interpY = linearInterp(cumLen, ys, at: targetLen)
        let interpT = linearInterp(cumLen, ts, at: targetLen)
        result.append(StrokePoint(x: interpX, y: interpY, t: interpT))
    }

    return result
}

private func linearInterp(_ keys: [Float], _ values: [Float], at target: Float) -> Float {
    if target <= keys[0] {
        return values[0]
    }
    if target >= keys[keys.count - 1] {
        return values[values.count - 1]
    }

    var lo = 0
    var hi = keys.count - 1
    while lo < hi - 1 {
        let mid = (lo + hi) / 2
        if keys[mid] <= target {
            lo = mid
        } else {
            hi = mid
        }
    }

    let frac = (target - keys[lo]) / max(keys[hi] - keys[lo], 1e-10)
    return values[lo] + frac * (values[hi] - values[lo])
}
