//
//  Printer.swift
//  MaLiang
//
//  Created by Harley-xk on 2019/4/25.
//

import Foundation
import Metal

/// Printer is a special brush witch can print images to canvas
open class Printer: Brush {
    /// make shader vertex function from the library made by makeShaderLibrary()
    /// overrides to provide your own vertex function
    override public func makeShaderVertexFunction(from library: MTLLibrary) -> MTLFunction? {
        return library.makeFunction(name: "vertex_printer_func")
    }

    /// make shader fragment function from the library made by makeShaderLibrary()
    /// overrides to provide your own fragment function
    override public func makeShaderFragmentFunction(from library: MTLLibrary) -> MTLFunction? {
        return library.makeFunction(name: "fragment_render_target")
    }

    /// Blending options for this brush, overrides to implement your own blending options
    override public func setupBlendOptions(for attachment: MTLRenderPipelineColorAttachmentDescriptor) {
        attachment.isBlendingEnabled = true

        attachment.rgbBlendOperation = .add
        attachment.alphaBlendOperation = .add

        attachment.sourceRGBBlendFactor = .sourceAlpha
        attachment.sourceAlphaBlendFactor = .one

        attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
        attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
    }

    func render(chartlet: Chartlet, on renderTarget: RenderTarget? = nil) {
        guard let target = renderTarget ?? target?.screenTarget else {
            return
        }

        // make sure reusable command buffer is ready
        target.prepareForDraw()

        // get commandEncoder form resuable command buffer
        let commandEncoder = target.makeCommandEncoder()

        commandEncoder?.setRenderPipelineState(pipelineState)

        if let vertex_buffer = chartlet.vertex_buffer, let texture = self.target?.findTexture(by: chartlet.textureID)?.texture {
            commandEncoder?.setVertexBuffer(vertex_buffer, offset: 0, index: 0)
            commandEncoder?.setVertexBuffer(target.uniform_buffer, offset: 0, index: 1)
            commandEncoder?.setVertexBuffer(target.transform_buffer, offset: 0, index: 2)
            commandEncoder?.setFragmentTexture(texture, index: 0)
            commandEncoder?.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }

        commandEncoder?.endEncoding()
    }
}
