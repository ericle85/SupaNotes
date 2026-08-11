import Metal
import UIKit
import simd

final class MetalStrokeRenderer {
  let device: MTLDevice
  private let commandQueue: MTLCommandQueue
  private let computePipeline: MTLComputePipelineState
  private let renderPipeline: MTLRenderPipelineState

  init?(device: MTLDevice) {
    self.device = device

    guard let queue = device.makeCommandQueue(),
      let library = device.makeDefaultLibrary(),
      let computeFunc = library.makeFunction(name: "catmullRomCompute"),
      let vertexFunc = library.makeFunction(name: "stampVertex"),
      let fragmentFunc = library.makeFunction(name: "stampFragment")
    else { return nil }

    self.commandQueue = queue

    guard let computeState = try? device.makeComputePipelineState(function: computeFunc)
    else { return nil }
    self.computePipeline = computeState

    let desc = MTLRenderPipelineDescriptor()
    desc.vertexFunction = vertexFunc
    desc.fragmentFunction = fragmentFunc
    desc.colorAttachments[0].pixelFormat = .bgra8Unorm
    desc.colorAttachments[0].isBlendingEnabled = true
    desc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
    desc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
    desc.colorAttachments[0].sourceAlphaBlendFactor = .one
    desc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

    guard let renderState = try? device.makeRenderPipelineState(descriptor: desc)
    else { return nil }
    self.renderPipeline = renderState
  }

  func render(
    points: [CGPoint],
    color: UIColor,
    width: CGFloat,
    to drawable: CAMetalDrawable,
    viewportSize: CGSize
  ) {
    guard let commandBuffer = commandQueue.makeCommandBuffer()
    else { return }

    if points.count < 2 {
      renderDot(
        point: points[0],
        color: color,
        width: width,
        drawable: drawable,
        viewportSize: viewportSize,
        commandBuffer: commandBuffer
      )
      return
    }

    let floatPoints = points.map {
      SIMD2<Float>(Float($0.x), Float($0.y))
    }

    guard
      let pointBuffer = device.makeBuffer(
        bytes: floatPoints,
        length: floatPoints.count * MemoryLayout<SIMD2<Float>>.stride,
        options: .storageModeShared
      )
    else { return }

    let subdivisions: UInt32 = 16
    let outputCount = (points.count - 1) * Int(subdivisions)

    guard
      let outputBuffer = device.makeBuffer(
        length: outputCount * MemoryLayout<SIMD2<Float>>.stride,
        options: .storageModeShared
      )
    else { return }

    var pointCount = UInt32(points.count)
    var subs = subdivisions

    guard let computeEncoder = commandBuffer.makeComputeCommandEncoder()
    else { return }
    computeEncoder.setComputePipelineState(computePipeline)
    computeEncoder.setBuffer(pointBuffer, offset: 0, index: 0)
    computeEncoder.setBuffer(outputBuffer, offset: 0, index: 1)
    computeEncoder.setBytes(&pointCount, length: 4, index: 2)
    computeEncoder.setBytes(&subs, length: 4, index: 3)

    let threadGroupWidth = min(
      computePipeline.maxTotalThreadsPerThreadgroup,
      outputCount
    )
    computeEncoder.dispatchThreads(
      MTLSize(width: outputCount, height: 1, depth: 1),
      threadsPerThreadgroup: MTLSize(width: threadGroupWidth, height: 1, depth: 1)
    )
    computeEncoder.endEncoding()

    encodeStamps(
      buffer: outputBuffer,
      instanceCount: outputCount,
      color: color,
      width: width,
      drawable: drawable,
      viewportSize: viewportSize,
      commandBuffer: commandBuffer
    )

    commandBuffer.present(drawable)
    commandBuffer.commit()
  }

  private func renderDot(
    point: CGPoint,
    color: UIColor,
    width: CGFloat,
    drawable: CAMetalDrawable,
    viewportSize: CGSize,
    commandBuffer: MTLCommandBuffer
  ) {
    var floatPoint = SIMD2<Float>(Float(point.x), Float(point.y))

    guard
      let buffer = device.makeBuffer(
        bytes: &floatPoint,
        length: MemoryLayout<SIMD2<Float>>.stride,
        options: .storageModeShared
      )
    else { return }

    encodeStamps(
      buffer: buffer,
      instanceCount: 1,
      color: color,
      width: width,
      drawable: drawable,
      viewportSize: viewportSize,
      commandBuffer: commandBuffer
    )

    commandBuffer.present(drawable)
    commandBuffer.commit()
  }

  func clear(drawable: CAMetalDrawable) {
    guard let commandBuffer = commandQueue.makeCommandBuffer()
    else { return }

    let desc = MTLRenderPassDescriptor()
    desc.colorAttachments[0].texture = drawable.texture
    desc.colorAttachments[0].loadAction = .clear
    desc.colorAttachments[0].clearColor = MTLClearColor(
      red: 0, green: 0, blue: 0, alpha: 0
    )
    desc.colorAttachments[0].storeAction = .store

    guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: desc)
    else { return }
    encoder.endEncoding()

    commandBuffer.present(drawable)
    commandBuffer.commit()
  }

  private func encodeStamps(
    buffer: MTLBuffer,
    instanceCount: Int,
    color: UIColor,
    width: CGFloat,
    drawable: CAMetalDrawable,
    viewportSize: CGSize,
    commandBuffer: MTLCommandBuffer
  ) {
    let renderDesc = MTLRenderPassDescriptor()
    renderDesc.colorAttachments[0].texture = drawable.texture
    renderDesc.colorAttachments[0].loadAction = .clear
    renderDesc.colorAttachments[0].clearColor = MTLClearColor(
      red: 0, green: 0, blue: 0, alpha: 0
    )
    renderDesc.colorAttachments[0].storeAction = .store

    guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderDesc)
    else { return }
    encoder.setRenderPipelineState(renderPipeline)
    encoder.setVertexBuffer(buffer, offset: 0, index: 0)

    var viewport = SIMD2<Float>(Float(viewportSize.width), Float(viewportSize.height))
    encoder.setVertexBytes(&viewport, length: MemoryLayout<SIMD2<Float>>.stride, index: 1)

    var radius = Float(width / 2)
    encoder.setVertexBytes(&radius, length: 4, index: 2)

    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var alpha: CGFloat = 0
    color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
    var rgba = SIMD4<Float>(Float(red), Float(green), Float(blue), Float(alpha))
    encoder.setFragmentBytes(&rgba, length: 16, index: 0)

    encoder.drawPrimitives(
      type: .triangleStrip,
      vertexStart: 0,
      vertexCount: 4,
      instanceCount: instanceCount
    )
    encoder.endEncoding()
  }
}
