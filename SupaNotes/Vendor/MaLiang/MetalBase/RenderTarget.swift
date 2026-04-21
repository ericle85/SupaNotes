//
//  RenderTarget.swift
//  MaLiang
//
//  Created by Harley-xk on 2019/4/15.
//

import Foundation
import Metal
import simd
import UIKit

/// a target for any thing that can be render on
open class RenderTarget {
    /// texture to render on
    public private(set) var texture: MTLTexture?

    /// the scale level of view, all things scales
    open var scale: CGFloat = 1 {
        didSet {
            updateTransformBuffer()
        }
    }

    /// the zoom level of render target, only scale render target
    open var zoom: CGFloat = 1

    /// the offset of render target with zoomed size
    open var contentOffset: CGPoint = .zero {
        didSet {
            updateTransformBuffer()
        }
    }

    /// create with texture and device
    public init(size: CGSize, pixelFormat: MTLPixelFormat, device: MTLDevice?) {
        drawableSize = size
        self.pixelFormat = pixelFormat
        self.device = device
        texture = makeEmptyTexture()
        commandQueue = device?.makeCommandQueue()

        renderPassDescriptor = MTLRenderPassDescriptor()
        let attachment = renderPassDescriptor?.colorAttachments[0]
        attachment?.texture = texture
        attachment?.loadAction = .load
        attachment?.storeAction = .store

        updateBuffer(with: size)
    }

    /// clear the contents of texture
    open func clear() {
        texture = makeEmptyTexture()
        renderPassDescriptor?.colorAttachments[0].texture = texture
        commitCommands()
    }

    var pixelFormat: MTLPixelFormat = .bgra8Unorm
    var drawableSize: CGSize
    var uniform_buffer: MTLBuffer!
    var transform_buffer: MTLBuffer!
    var renderPassDescriptor: MTLRenderPassDescriptor?
    var commandBuffer: MTLCommandBuffer?
    var commandQueue: MTLCommandQueue?
    var device: MTLDevice?

    func updateBuffer(with size: CGSize) {
        drawableSize = size
        let metrix = Matrix.identity
        let zoomUniform = 2 * Float(zoom / scale)
        metrix.scaling(x: zoomUniform / Float(size.width), y: -zoomUniform / Float(size.height), z: 1)
        metrix.translation(x: -1, y: 1, z: 0)
        uniform_buffer = device?.makeBuffer(bytes: metrix.m, length: MemoryLayout<Float>.size * 16, options: [])

        updateTransformBuffer()
    }

    func updateTransformBuffer() {
        let scaleFactor = UIScreen.main.nativeScale
        var transform = ScrollingTransform(offset: contentOffset * scaleFactor, scale: scale)
        transform_buffer = device?.makeBuffer(bytes: &transform, length: MemoryLayout<ScrollingTransform>.stride, options: [])
    }

    func prepareForDraw() {
        if commandBuffer == nil {
            commandBuffer = commandQueue?.makeCommandBuffer()
        }
    }

    func makeCommandEncoder() -> MTLRenderCommandEncoder? {
        guard let commandBuffer = commandBuffer, let rpd = renderPassDescriptor else {
            return nil
        }
        return commandBuffer.makeRenderCommandEncoder(descriptor: rpd)
    }

    func commitCommands() {
        commandBuffer?.commit()
        commandBuffer = nil
    }

    /// make empty testure
    func makeEmptyTexture() -> MTLTexture? {
        guard drawableSize.width * drawableSize.height > 0 else {
            return nil
        }
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: pixelFormat,
                                                                         width: Int(drawableSize.width),
                                                                         height: Int(drawableSize.height),
                                                                         mipmapped: false)
        textureDescriptor.usage = [.renderTarget, .shaderRead]
        let texture = device?.makeTexture(descriptor: textureDescriptor)
        texture?.clear()
        return texture
    }
}
