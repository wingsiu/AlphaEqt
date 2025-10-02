//
//  MTCTLineDisplay.swift
//  AlphaEqt
//
//  Created by Alpha Ng on 2/10/2025.
//
import Foundation
import QuartzCore
import CoreText

// MARK: - MTCTLineDisplay

/// A rendering of a single CTLine as an MTDisplay
public class MTCTLineDisplay : MTDisplay {
    
    /// The CTLine being displayed
    public var line:CTLine!
    /// The attributed string used to generate the CTLineRef. Note setting this does not reset the dimensions of
    /// the display. So set only when
    //var attributedString:NSAttributedString? {
    public var attributedString:NSAttributedString? { //By Alpha
        didSet {
            line = CTLineCreateWithAttributedString(attributedString!)
        }
    }
    
    /// An array of MTMathAtoms that this CTLine displays. Used for indexing back into the MTMathList
    public fileprivate(set) var atoms : [ASTNode]? = nil
    
    init(attrString: NSAttributedString?, position: CGPoint, range: NSRange, font: MTFont?, atoms: [ASTNode]?) {
        super.init()
        self.position = position
        self.attributedString = attrString
        self.line = attrString != nil ? CTLineCreateWithAttributedString(attrString!) : nil
        self.range = range
        self.atoms = atoms

        // Set width
        if let line = self.line {
            self.width = CTLineGetTypographicBounds(line, nil, nil, nil)

            // Use glyph path bounds for ascent/descent
            let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
            self.ascent = max(0, bounds.maxY)
            self.descent = max(0, -bounds.minY)
            // If you want to use bounds.maxX as width:
            // self.width = bounds.maxX
        } else {
            self.width = 0
            self.ascent = 0
            self.descent = 0
        }

        // If you need to compute dimensions using font for some fallback:
        // if self.width == 0, let font = font {
        //     self.computeDimensions(font)
        // }
    }
    
    override var textColor: MTColor? {
        set {
            super.textColor = newValue
            let attrStr = attributedString!.mutableCopy() as! NSMutableAttributedString
            let foregroundColor = NSAttributedString.Key(kCTForegroundColorAttributeName as String)
            attrStr.addAttribute(foregroundColor, value:self.textColor!.cgColor, range:NSMakeRange(0, attrStr.length))
            self.attributedString = attrStr
        }
        get { super.textColor }
    }

    func computeDimensions(_ font:MTFont?) {
        let runs = CTLineGetGlyphRuns(line) as NSArray
        for obj in runs {
            let run = obj as! CTRun?
            let numGlyphs = CTRunGetGlyphCount(run!)
            var glyphs = [CGGlyph]()
            glyphs.reserveCapacity(numGlyphs)
            CTRunGetGlyphs(run!, CFRangeMake(0, numGlyphs), &glyphs);
            let bounds = CTFontGetBoundingRectsForGlyphs(font!.ctFont, .horizontal, glyphs, nil, numGlyphs);
            let ascent = max(0, CGRectGetMaxY(bounds) - 0);
            // Descent is how much the line goes below the origin. However if the line is all above the origin, then descent can't be negative.
            let descent = max(0, 0 - CGRectGetMinY(bounds));
            if (ascent > self.ascent) {
                self.ascent = ascent;
            }
            if (descent > self.descent) {
                self.descent = descent;
            }
        }
    }
    
    override public func draw(_ context: CGContext) {
        super.draw(context)
        context.saveGState()
        
        context.textPosition = self.position
        CTLineDraw(line, context)
        
        context.restoreGState()
    }
}
