//
//  GlowingBrush.swift
//  Chrysan
//
//  Created by Harley-xk on 2019/5/5.
//

import CoreGraphics
import Foundation
import Metal
import UIKit

public final class GlowingBrush: Brush {
    /// size proportion of the core line, must be set between 0 ~ 1, defaults to 0.5
    public var coreProportion: CGFloat = 0.25

    /// color of core lines, defaults to white
    public var coreColor: UIColor = .white {
        didSet {
            subBrush.color = coreColor
        }
    }

    // MARK: - Overrides

    // make properties of subbrush synch with it's parent

    override public var pointSize: CGFloat {
        didSet {
            subBrush.pointSize = pointSize * coreProportion
        }
    }

    override public var pointStep: CGFloat {
        didSet {
            subBrush.pointStep = 1
        }
    }

    override public var forceSensitive: CGFloat {
        didSet {
            subBrush.forceSensitive = forceSensitive
        }
    }

    override public var scaleWithCanvas: Bool {
        didSet {
            subBrush.scaleWithCanvas = scaleWithCanvas
        }
    }

    override public var forceOnTap: CGFloat {
        didSet {
            subBrush.forceOnTap = forceOnTap
        }
    }

    /// sub brush to render core white line
    private var subBrush: Brush!

    private var pendingCoreLines: [MLLine] = []

    /// designed initializer, will be called by target when reigster called
    /// identifier is not necessary if you won't save the content of your canvas to file
    public required init(name: String?, textureID: String?, target: Canvas) {
        super.init(name: name, textureID: textureID, target: target)
        subBrush = Brush(name: self.name + ".sub", textureID: nil, target: target)
        subBrush.color = coreColor
        subBrush.opacity = 10
    }

    /// get a line with specified begin and end location
    override public func makeLine(from: CGPoint, to: CGPoint, force: CGFloat? = nil, uniqueColor _: Bool = false) -> [MLLine] {
        let shadowLines = super.makeLine(from: from, to: to, force: force)
        let delta = (pointSize * (1 - coreProportion)) / 2
        var coreLines: [MLLine] = []

        while let first = pendingCoreLines.first?.begin, first.distance(to: from) >= delta {
            coreLines.append(pendingCoreLines.removeFirst())
        }
        let lines = subBrush.makeLine(from: from, to: to, force: force, uniqueColor: true)
        pendingCoreLines.append(contentsOf: lines)
        return shadowLines + coreLines
    }

    override public func finishLineStrip(at _: Pan) -> [MLLine] {
        let lines = pendingCoreLines
        pendingCoreLines.removeAll()
        return lines
    }
}
