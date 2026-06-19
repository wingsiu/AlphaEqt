//
//  MTCTLineDisplay.swift
//  AlphaEqt
//

import Foundation
import QuartzCore
import CoreText

public class MTCTLineDisplay: MTDisplay {

    public var line: CTLine!
    public var attributedString: NSAttributedString? {
        didSet {
            if let str = attributedString { line = CTLineCreateWithAttributedString(str) }
            else { line = nil }
        }
    }

    public fileprivate(set) var atoms: [ASTNode]? = nil

    public init(attrString: NSAttributedString?, position: CGPoint, range: NSRange, font: MTFont?, atoms: [ASTNode]?) {
        super.init()
        self.position = position
        self.attributedString = attrString
        if let str = attrString { self.line = CTLineCreateWithAttributedString(str) }
        self.range = range
        self.atoms = atoms
        if let line = self.line {
            self.width = CTLineGetTypographicBounds(line, nil, nil, nil)
            let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
            self.ascent = max(0, bounds.maxY)
            self.descent = max(0, -bounds.minY)
        } else {
            self.width = 0; self.ascent = 0; self.descent = 0
        }
    }

    override public var textColor: MTColor? {
        set {
            super.textColor = newValue
            guard let color = newValue else { return }
            guard let mutable = attributedString?.mutableCopy() as? NSMutableAttributedString else { return }
            // Convert dynamic cgColor to concrete deviceRGB.
            // CTLineDraw requires a concrete CGColor — dynamic proxy cgColor renders black.
            let key = NSAttributedString.Key(kCTForegroundColorAttributeName as String)
            let resolved = color.cgColor.converted(to: CGColorSpaceCreateDeviceRGB(),
                                                    intent: .defaultIntent, options: nil)
            ?? color.cgColor
            mutable.addAttribute(key, value: resolved, range: NSRange(location: 0, length: mutable.length))
            self.attributedString = mutable
        }
        get { super.textColor }
    }

    override public func draw(_ context: CGContext) {
        super.draw(context)
        guard let line = line else { return }
        context.saveGState()
        context.textPosition = .zero
        CTLineDraw(line, context)
        context.restoreGState()
    }
}
