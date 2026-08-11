import CoreGraphics
import Metal

final class CatmullRomGPU {
  private let device: MTLDevice
  private let commandQueue: MTLCommandQueue
  private let computePipeline: MTLComputePipelineState

  init?(device: MTLDevice, library: MTLLibrary? = nil) {
    self.device = device

    guard let queue = device.makeCommandQueue(),
      let lib = library ?? device.makeDefaultLibrary(),
      let computeFunc = lib.makeFunction(name: "catmullRomCompute")
    else { return nil }

    self.commandQueue = queue

    guard let state = try? device.makeComputePipelineState(function: computeFunc)
    else { return nil }
    self.computePipeline = state
  }

  func smooth(points: [CGPoint], subdivisions: UInt32 = 8) -> [CGPoint] {
    if points.count < 2 {
      return points
    }

    let floatPoints = points.map { SIMD2<Float>(Float($0.x), Float($0.y)) }

    guard
      let pointBuffer = device.makeBuffer(
        bytes: floatPoints,
        length: floatPoints.count * MemoryLayout<SIMD2<Float>>.stride,
        options: .storageModeShared
      )
    else { return points }

    let outputCount = (points.count - 1) * Int(subdivisions)

    guard
      let outputBuffer = device.makeBuffer(
        length: outputCount * MemoryLayout<SIMD2<Float>>.stride,
        options: .storageModeShared
      )
    else { return points }

    var pointCount = UInt32(points.count)
    var subs = subdivisions

    guard let commandBuffer = commandQueue.makeCommandBuffer(),
      let encoder = commandBuffer.makeComputeCommandEncoder()
    else { return points }

    encoder.setComputePipelineState(computePipeline)
    encoder.setBuffer(pointBuffer, offset: 0, index: 0)
    encoder.setBuffer(outputBuffer, offset: 0, index: 1)
    encoder.setBytes(&pointCount, length: 4, index: 2)
    encoder.setBytes(&subs, length: 4, index: 3)

    let threadGroupWidth = min(
      computePipeline.maxTotalThreadsPerThreadgroup,
      outputCount
    )
    encoder.dispatchThreads(
      MTLSize(width: outputCount, height: 1, depth: 1),
      threadsPerThreadgroup: MTLSize(width: threadGroupWidth, height: 1, depth: 1)
    )
    encoder.endEncoding()

    commandBuffer.commit()
    commandBuffer.waitUntilCompleted()

    let outputPointer = outputBuffer.contents().bindMemory(
      to: SIMD2<Float>.self,
      capacity: outputCount
    )

    var result = [CGPoint]()
    result.reserveCapacity(outputCount + 1)
    result.append(points[0])
    for i in 0..<outputCount {
      let p = outputPointer[i]
      result.append(CGPoint(x: CGFloat(p.x), y: CGFloat(p.y)))
    }

    return result
  }
}
