//
//  DisplayAtoms.swift
//  AlphaEqt
//
//  Display containers that implement TeX Appendix G positioning rules
//  via the OpenType MATH table. Positions and dimensions are computed
//  during init using TeX's algorithm so the typesetter does not need
//  to recalculate afterwards.
//
//  Fraction positioning:
//    - Start with numeratorShiftUp / denominatorShiftDown from MATH table
//    - Check clearance to the bar, expand shifts to meet gap-minimums
//    - Bar drawn at axisHeight; numerator/denominator aligned above/below
//

import Foundation
import CoreGraphics
import CoreText

// MARK: - MTSupSubDisplay

public class MTSupSubDisplay: MTDisplay {
    public var base: MTDisplay?
    public var superscript: MTDisplay?
    public var subscriptDisplay: MTDisplay?

    public init(base: MTDisplay?, superscript: MTDisplay?, subscript sub: MTDisplay?, scriptSpace: CGFloat = 0) {
        self.base = base
        self.superscript = superscript
        self.subscriptDisplay = sub
        super.init()

        var a = base?.ascent ?? 0, d = base?.descent ?? 0
        var w = (base?.position.x ?? 0) + (base?.width ?? 0)
        if let s = superscript {
            a = max(a, s.position.y + s.ascent)
            w = max(w, s.position.x + s.width)
        }
        if let s = sub {
            d = max(d, -(s.position.y - s.descent))
            w = max(w, s.position.x + s.width)
        }
        // Add scriptSpace so the typesetter places the next element
        // at the correct distance, matching TeX's spaceAfterScript.
        self.ascent = a; self.descent = d; self.width = w + scriptSpace
    }

    override public func draw(_ ctx: CGContext) {
        super.draw(ctx)
        ctx.saveGState()
        if let b = base {
            ctx.saveGState()
            ctx.translateBy(x: b.position.x, y: b.position.y)
            b.draw(ctx)
            ctx.restoreGState()
        }
        if let s = superscript {
            ctx.saveGState(); ctx.translateBy(x: s.position.x, y: s.position.y)
            s.draw(ctx); ctx.restoreGState()
        }
        if let s = subscriptDisplay {
            ctx.saveGState(); ctx.translateBy(x: s.position.x, y: s.position.y)
            s.draw(ctx); ctx.restoreGState()
        }
        ctx.restoreGState()
    }

    override public var textColor: MTColor? {
        set { base?.textColor = newValue; superscript?.textColor = newValue; subscriptDisplay?.textColor = newValue }
        get { return base?.textColor }
    }

    override public func dumpDisplayTree(indent: String = "") {
        super.dumpDisplayTree(indent: indent)
        base?.dumpDisplayTree(indent: indent + "  B> ")
        superscript?.dumpDisplayTree(indent: indent + "  ^> ")
        subscriptDisplay?.dumpDisplayTree(indent: indent + "  _> ")
    }
}

// MARK: - MTFractionDisplay

/// Renders a fraction using TeX Appendix G rules.
///
/// Coordinate system (matching SwiftMath):
///   `position.y` is the mathematical baseline (y=0 axis).
///   The fraction bar is drawn at `position.y + linePosition`.
///   `numeratorUp` is the distance from the baseline to the numerator's baseline.
///   `denominatorDown` is the distance from the baseline to the denominator's baseline.
///
/// TeX positioning algorithm (from the typesetter's `makeFraction`):
///   1. Start with `numeratorShiftUp` / `denominatorShiftDown` from the MATH table.
///   2. Compute the actual clearance between the numerator's bottom and the bar top:
///      `distanceFromNumeratorToBar = (numeratorUp - num.descent) - (linePosition + ruleThickness/2)`
///   3. If clearance < `numeratorGapMin`, increase `numeratorUp` to meet the minimum.
///   4. Same for denominator: `distanceFromDenominatorToBar = (linePosition - ruleThickness/2) - (den.ascent - denominatorDown)`
///   5. If clearance < `denominatorGapMin`, increase `denominatorDown` to meet the minimum.
///   6. `ascent = num.ascent + numeratorUp`
///   7. `descent = den.descent + denominatorDown`
///   8. `width = max(num.width, den.width)`
public class MTFractionDisplay: MTDisplay {
    public var numerator: MTDisplay?
    public var denominator: MTDisplay?

    /// Distance from the baseline to the numerator's baseline.
    public var numeratorUp: CGFloat = 0 { didSet { updateNumeratorPosition() } }
    /// Distance from the baseline to the denominator's baseline (positive value goes downward).
    public var denominatorDown: CGFloat = 0 { didSet { updateDenominatorPosition() } }

    /// The distance from the baseline to the fraction bar's center.
    public var linePosition: CGFloat = 0
    /// Thickness of the fraction bar (0 for rule-less fractions like \binom).
    public var lineThickness: CGFloat = 0

    /// Initialize with TeX MATH table parameters.
    public init(numerator: MTDisplay?,
                denominator: MTDisplay?,
                ruleThickness: CGFloat,
                axisHeight: CGFloat,
                numeratorShiftUp: CGFloat,
                denominatorShiftDown: CGFloat,
                numeratorGapMin: CGFloat,
                denominatorGapMin: CGFloat) {
        self.numerator = numerator
        self.denominator = denominator
        self.lineThickness = ruleThickness
        self.linePosition = axisHeight
        super.init()

        guard let num = numerator, let den = denominator else { return }

        var numUp = numeratorShiftUp
        var denDown = denominatorShiftDown
        let barY = axisHeight
        let halfRule = ruleThickness / 2

        let distanceFromNumToBar = (numUp - num.descent) - (barY + halfRule)
        if distanceFromNumToBar < numeratorGapMin {
            numUp += numeratorGapMin - distanceFromNumToBar
        }

        let distanceFromDenToBar = (barY - halfRule) - (den.ascent - denDown)
        if distanceFromDenToBar < denominatorGapMin {
            denDown += denominatorGapMin - distanceFromDenToBar
        }

        self.numeratorUp = numUp
        self.denominatorDown = denDown
        let maxWidth = max(num.width, den.width)
        self.width = maxWidth
        self.ascent = num.ascent + numUp
        self.descent = den.descent + denDown
        updateNumeratorPosition()
        updateDenominatorPosition()
    }

    private func updateNumeratorPosition() {
        guard let num = numerator else { return }
        num.position = CGPoint(x: (width - num.width) / 2, y: numeratorUp)
    }

    private func updateDenominatorPosition() {
        guard let den = denominator else { return }
        den.position = CGPoint(x: (width - den.width) / 2, y: -denominatorDown)
    }

    override public func draw(_ ctx: CGContext) {
        super.draw(ctx)
        ctx.saveGState()
        if let n = numerator {
            ctx.saveGState(); ctx.translateBy(x: n.position.x, y: n.position.y)
            n.draw(ctx); ctx.restoreGState()
        }
        if let d = denominator {
            ctx.saveGState(); ctx.translateBy(x: d.position.x, y: d.position.y)
            d.draw(ctx); ctx.restoreGState()
        }
        if lineThickness > 0 {
            textColor?.setStroke()
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 0, y: linePosition))
            path.addLine(to: CGPoint(x: width, y: linePosition))
            ctx.setLineWidth(lineThickness)
            ctx.addPath(path)
            ctx.strokePath()
        }
        ctx.restoreGState()
    }

    override public var textColor: MTColor? {
        set { numerator?.textColor = newValue; denominator?.textColor = newValue }
        get { return numerator?.textColor }
    }

    override public func dumpDisplayTree(indent: String = "") {
        super.dumpDisplayTree(indent: indent)
        print("\(indent)  numeratorUp=\(Int(numeratorUp)) denominatorDown=\(Int(denominatorDown)) linePosition=\(Int(linePosition))")
        numerator?.dumpDisplayTree(indent: indent + "  N> ")
        denominator?.dumpDisplayTree(indent: indent + "  D> ")
    }
}

// MARK: - MTRadicalDisplay

/// Renders a radical (square root / nth root) using TeX Appendix G rules.
///
/// When the √ glyph is shorter than the required radicand height,
/// a diagonal connector line (slope ~5.67 from font metrics) extends
/// from the glyph body up to the horizontal rule bar, avoiding the
/// ugly vertical extender assembly.
///
/// Coordinate system:
///   `position` is the baseline origin of the radical.
///   The radical glyph is placed at `local (radicalShift, 0)`.
///   The radicand sits at `local (radicalShift + glyphWidth, 0)`.
///   The rule bar connects from glyph right edge across the radicand width.
///
/// Dimensions:
///   - Width: glyphWidth + extenderDeltaX (if slope‑extended) + radicand.width
///   - Ascent: tops at ruleThickness + clearance + radicand.ascent + extraAscender
public class MTRadicalDisplay: MTDisplay {
    public var radicand: MTDisplay?
    public var degree: MTDisplay?

    /// The radical glyph (the √ sign).
    private var _radicalGlyph: MTDisplay?
    /// Extra shift applied when degree is present (kernBefore + degree.width + kernAfter).
    private var _radicalShift: CGFloat = 0

    /// Diagonal line start point (relative to glyph origin), used when
    /// the glyph is extended via slope instead of extender assembly.
    private var _extenderPosition: CGPoint = .zero
    /// Horizontal offset from glyph right edge to the rule bar start.
    /// This is where the diagonal lands and the horizontal bar begins.
    private var _barStartX: CGFloat = 0
    /// Whether the glyph was slope‑extended (diagonal connector needed).
    private var _hasExtender: Bool = false

    /// Kern between radical and degree; cached so repositioning tracks parent.
    private var _degreeKernBefore: CGFloat = 0
    /// Vertical raise of degree above baseline; cached for repositioning.
    private var _degreeRaise: CGFloat = 0

    public var topKern: CGFloat = 0
    public var lineThickness: CGFloat = 0

    public init(radicand: MTDisplay?, glyph: MTDisplay, position: CGPoint, range: NSRange) {
        self.radicand = radicand
        self._radicalGlyph = glyph
        super.init()
        self.range = range
        self.position = position
        updateRadicandPosition()
    }

    /// Marks the glyph as slope‑extended and configures the diagonal connector.
    /// - Parameter start: The start point of the diagonal (relative to glyph origin).
    /// - Parameter barStartX: Horizontal distance from glyph right edge to where
    ///   the horizontal rule bar begins (the landing point of the diagonal).
    public func setExtender(start: CGPoint, barStartX: CGFloat) {
        _hasExtender = true
        _extenderPosition = start
        _barStartX = barStartX
    }

    /// Configures an optional degree (nth-root index) with MATH table metrics.
    public func setDegree(_ degree: MTDisplay?, fontMetrics: MTFontMathTable) {
        guard let degree = degree else { return }
        var kernBefore = fontMetrics.radicalKernBeforeDegree
        let kernAfter = fontMetrics.radicalKernAfterDegree
        let raise = fontMetrics.radicalDegreeBottomRaisePercent * (self.ascent - self.descent)

        self.degree = degree
        _radicalShift = kernBefore + degree.width + kernAfter
        if _radicalShift < 0 {
            kernBefore -= _radicalShift
            _radicalShift = 0
        }

        _degreeKernBefore = kernBefore
        _degreeRaise = raise
        updateDegreePosition()

        self.width = _radicalShift + (_radicalGlyph?.width ?? 0) + (radicand?.width ?? 0)
        updateRadicandPosition()
    }

    private func updateDegreePosition() {
        guard let degree = self.degree, _radicalGlyph != nil else { return }
        degree.position = CGPoint(x: _degreeKernBefore, y: _degreeRaise)
    }

    private func updateRadicandPosition() {
        guard let glyph = _radicalGlyph else { return }
        radicand?.position = CGPoint(
            x: _radicalShift + glyph.width,
            y: 0
        )
    }

    override public var position: CGPoint {
        get { super.position }
        set {
            super.position = newValue
        }
    }

    override public func draw(_ ctx: CGContext) {
        super.draw(ctx)

        // Draw radicand at its local position.
        if let rad = radicand {
            ctx.saveGState()
            ctx.translateBy(x: rad.position.x, y: rad.position.y)
            rad.draw(ctx)
            ctx.restoreGState()
        }
        // Draw degree at its local position.
        if let deg = degree {
            ctx.saveGState()
            ctx.translateBy(x: deg.position.x, y: deg.position.y)
            deg.draw(ctx)
            ctx.restoreGState()
        }

        ctx.saveGState()
        textColor?.setStroke()
        textColor?.setFill()

        // Translate to glyph position and draw it.
        ctx.translateBy(x: _radicalShift, y: 0)
        ctx.textPosition = .zero
        _radicalGlyph?.draw(ctx)

        // Draw the rule bar (and diagonal connector if slope‑extended).
        if lineThickness > 0, let glyph = _radicalGlyph, let rad = radicand {
            let barY = self.ascent - topKern - lineThickness / 2
            let path = CGMutablePath()

            if _hasExtender {
                // Diagonal from extenderPosition (relative to glyph origin)
                // up to (_barStartX, barY) — the landing point of the diagonal.
                path.move(to: CGPoint(x: _extenderPosition.x, y: _extenderPosition.y))
                path.addLine(to: CGPoint(x: _barStartX, y: barY))
                // Horizontal bar from the landing point across radicand.
                path.move(to: CGPoint(x: _barStartX, y: barY))
                path.addLine(to: CGPoint(x: _barStartX + rad.width, y: barY))
            } else {
                path.move(to: CGPoint(x: glyph.width, y: barY))
                path.addLine(to: CGPoint(x: glyph.width + rad.width, y: barY))
            }

            ctx.setLineWidth(lineThickness)
            ctx.setLineCap(.round)
            ctx.addPath(path)
            ctx.strokePath()
        }

        ctx.restoreGState()
    }

    override public var textColor: MTColor? {
        set {
            super.textColor = newValue
            radicand?.textColor = newValue
            degree?.textColor = newValue
            _radicalGlyph?.textColor = newValue
        }
        get { super.textColor }
    }

    override public func dumpDisplayTree(indent: String = "") {
        super.dumpDisplayTree(indent: indent)
        print("\(indent)  radicalShift=\(Int(_radicalShift)) topKern=\(Int(topKern)) lineThickness=\(Int(lineThickness)) hasExtender=\(_hasExtender)")
        radicand?.dumpDisplayTree(indent: indent + "  R> ")
        degree?.dumpDisplayTree(indent: indent + "  D> ")
    }
}

// MARK: - MTGlyphConstructionDisplay

/// Stacked glyph display built from extendable assembly parts.
/// Used for stretchy radicals and delimiters when no single pre‑built
/// variant is tall enough.
public class MTGlyphConstructionDisplay: MTDisplay {
    public var glyphs: [CGGlyph] = []
    public var positions: [CGPoint] = []
    public var font: MTFont?
    public var shiftDown: CGFloat = 0

    public override init() { super.init() }

    public init(glyphs: [CGGlyph], offsets: [CGFloat], font: MTFont?) {
        self.font = font
        self.glyphs = glyphs
        self.positions = offsets.map { CGPoint(x: 0, y: $0) }
        super.init()
    }

    override public func draw(_ ctx: CGContext) {
        super.draw(ctx)
        ctx.saveGState()

        ctx.translateBy(x: 0, y: -shiftDown)
        ctx.textPosition = .zero

        textColor?.setFill()
        if let ctFont = font?.ctFont, !glyphs.isEmpty {
            let count = min(glyphs.count, positions.count)
            CTFontDrawGlyphs(ctFont, glyphs, positions, count, ctx)
        }

        ctx.restoreGState()
    }

    override public var ascent: CGFloat {
        get { super.ascent - shiftDown }
        set { super.ascent = newValue }
    }
    override public var descent: CGFloat {
        get { super.descent + shiftDown }
        set { super.descent = newValue }
    }
}

// MARK: - MTGlyphDisplay

/// Standalone glyph display for drawing a single glyph.
/// `shiftDown` centers the glyph on the math axis: `0.5*(ascent-descent) - axisHeight`.
/// `rawAscent`/`rawDescent` hold the glyph's true bounding box.
/// The public `ascent`/`descent` are adjusted when `shiftDown` is set
/// so parents see visual (axis-centered) bounds.
public class MTGlyphDisplay: MTDisplay {
    public var glyph: CGGlyph
    public weak var font: MTFont?
    public var shiftDown: CGFloat = 0 {
        didSet { applyShiftDown() }
    }

    /// Glyph bounding box without axis-centering.
    public var rawAscent: CGFloat = 0 { didSet { applyShiftDown() } }
    public var rawDescent: CGFloat = 0 { didSet { applyShiftDown() } }
    /// Space between bbox.minX and the visual glyph body start (left-bearing).
    public var leftMargin: CGFloat = 0
    /// Raw glyph advance width (from CTFontGetAdvancesForGlyphs).
    /// `displayBounds().width` is set to this value.
    public var glyphAdvance: CGFloat = 0
    /// Italic correction from the MATH table.
    /// Used for subscript x‑offset (subXDelta) in renderSupSub.
    public var italicCorrection: CGFloat = 0

    public init(glyph: CGGlyph, range: NSRange, font: MTFont?) {
        self.glyph = glyph
        self.font = font
        super.init()
        self.range = range
    }

    private func applyShiftDown() {
        // Adjust the stored ascent/descent so parents see the visual bounds.
        super.ascent = rawAscent - shiftDown
        super.descent = rawDescent + shiftDown
    }

    override public func draw(_ ctx: CGContext) {
        super.draw(ctx)
        ctx.saveGState()

        ctx.translateBy(x: 0, y: -shiftDown)
        ctx.textPosition = CGPoint.zero
        if let ctFont = font?.ctFont {
            // Set fill color before drawing glyph, otherwise CTFontDrawGlyphs
            // uses the context's default (black), which breaks dark mode.
            textColor?.setFill()
            var glyphs = [glyph]
            var points = [CGPoint(x: 0, y: 0)]
            CTFontDrawGlyphs(ctFont, &glyphs, &points, 1, ctx)
        }
        ctx.restoreGState()
    }

    override public func dumpDisplayTree(indent: String = "") {
        var extra = ""
        if shiftDown != 0 { extra += " shiftDown=\(Int(shiftDown))" }
        if leftMargin != 0 { extra += " leftMargin=\(Int(leftMargin))" }
        print("\(indent)\(type(of: self))"
              + " pos=(\(Int(position.x)),\(Int(position.y)))"
              + " ascent=\(Int(ascent)) descent=\(Int(descent))"
              + " width=\(Int(width))\(extra)")
    }
}

// MARK: - MTRuleDisplay

/// Draws a filled horizontal rule (rectangle) with configurable thickness.
/// Used for overbar accents (`\bar{abc}`) when the font lacks stretchy glyph variants.
/// Positioned such that the rule's center is at y=0; the caller sets `position.y`
/// to place it correctly above the accentee.
/// Renders a filled horizontal rule (rectangle) with configurable thickness.
/// y=0 is the **bottom** edge of the rule (ascent = thickness, descent = 0),
/// matching glyph display semantics so the rule can be positioned using
/// the same `accentBaseHeight` formula as accent glyphs.
public class MTRuleDisplay: MTDisplay {
    public var ruleThickness: CGFloat

    public init(width: CGFloat, thickness: CGFloat) {
        self.ruleThickness = thickness
        super.init()
        self.width = width
        self.ascent = thickness
        self.descent = 0
    }

    override public func draw(_ ctx: CGContext) {
        super.draw(ctx)
        ctx.saveGState()
        textColor?.setFill()
        let rect = CGRect(x: 0, y: 0,
                          width: width, height: ruleThickness)
        ctx.fill(rect)
        ctx.restoreGState()
    }
}

// MARK: - MTAccentDisplay

/// Renders an accent glyph (e.g., ^, ~, ˙) above a base accentee.
/// Matches iOSMath `MTAccentDisplay` behavior.
///
/// Positioning (TeX Appendix G, Rule 12 + OpenType MATH table):
///   1. The accent is placed at (skew, accentee.ascent - accentBaseHeight).
///   2. `skew` = accenteeAdjustment - accentAdjustment, aligning the
///      attachment points of accent and accentee per font metrics.
///   3. Wrapping the accentee in a display ensures it contributes to
///      the full ascent/descent of the compound display.
public class MTAccentDisplay: MTDisplay {
    public var accent: MTDisplay?
    public var accentee: MTDisplay?

    public init(accent: MTDisplay?, accentee: MTDisplay?, range: NSRange) {
        self.accent = accent
        self.accentee = accentee
        super.init()
        self.range = range

        if let acc = accent, let aee = accentee {
            // Width is determined by the accentee
            self.width = aee.width
            // Descent matches the accentee
            self.descent = aee.descent
            // Ascent must encompass both the accent (which may sit above the accentee)
            // and the accentee itself.
            self.ascent = max(aee.ascent, max(0, acc.position.y + acc.ascent))
        }
    }

    override public func draw(_ ctx: CGContext) {
        super.draw(ctx)
        ctx.saveGState()
        if let aee = accentee {
            ctx.saveGState()
            ctx.translateBy(x: aee.position.x, y: aee.position.y)
            aee.draw(ctx)
            ctx.restoreGState()
        }
        if let acc = accent {
            ctx.saveGState()
            ctx.translateBy(x: acc.position.x, y: acc.position.y)
            acc.draw(ctx)
            ctx.restoreGState()
        }
        ctx.restoreGState()
    }

    override public var textColor: MTColor? {
        set { accent?.textColor = newValue; accentee?.textColor = newValue }
        get { accent?.textColor }
    }

    override public func dumpDisplayTree(indent: String = "") {
        super.dumpDisplayTree(indent: indent)
        accent?.dumpDisplayTree(indent: indent + "  A> ")
        accentee?.dumpDisplayTree(indent: indent + "  aee> ")
    }
}

// MARK: - MTColorboxDisplay

/// Renders a background‑colored box with optional border around inner content.
/// Used for `\colorbox{color}{content}` and `\fcolorbox{border}{fill}{content}`.
public class MTColorboxDisplay: MTDisplay {
    public var inner: MTDisplay?
    public var fillColor: MTColor
    public var borderColor: MTColor
    public var padding: CGFloat

    public init(inner: MTDisplay?, fillColor: MTColor, borderColor: MTColor, padding: CGFloat) {
        self.inner = inner
        self.fillColor = fillColor
        self.borderColor = borderColor
        self.padding = padding
        super.init()
        guard let inner = inner else { return }
        // Width = inner width + padding on both sides
        self.width = inner.width + 2 * padding
        // Ascent/descent extend by padding above/below inner content
        self.ascent = inner.ascent + padding
        self.descent = inner.descent + padding
        // Inner is positioned at (padding, 0) — baseline aligned
        inner.position = CGPoint(x: padding, y: 0)
    }

    override public func draw(_ ctx: CGContext) {
        super.draw(ctx)

        // Fill background
        ctx.saveGState()
        ctx.setFillColor(fillColor.cgColor)
        let bgRect = CGRect(x: 0, y: -descent, width: width, height: ascent + descent)
        ctx.fill(bgRect)

        // Draw border
        ctx.setStrokeColor(borderColor.cgColor)
        ctx.setLineWidth(1)
        ctx.stroke(bgRect)
        ctx.restoreGState()

        // Draw inner content
        if let inner = inner {
            ctx.saveGState()
            ctx.translateBy(x: inner.position.x, y: inner.position.y)
            inner.draw(ctx)
            ctx.restoreGState()
        }
    }

    override public var textColor: MTColor? {
        set { inner?.textColor = newValue }
        get { inner?.textColor }
    }

    override public func dumpDisplayTree(indent: String = "") {
        super.dumpDisplayTree(indent: indent)
        print("\(indent)  fill=\(fillColor) border=\(borderColor) padding=\(Int(padding))")
        inner?.dumpDisplayTree(indent: indent + "  > ")
    }
}

// MARK: - MTLargeOpLimitsDisplay

/// Renders a large operator (e.g., ∑, ∫, ∏) with limits above/below
/// in display style. Matches iOSMath `MTLargeOpLimitsDisplay` behavior.
///
/// Positioning:
///   - Nucleus centered horizontally at `self.position`
///   - Upper limit: `self.position.y + nuc.ascent + upperLimitGap + upper.descent`
///   - Lower limit: `self.position.y - nuc.descent - lowerLimitGap - lower.ascent`
///
/// Reported dimensions include full extent of limits:
///   - `ascent = nuc.ascent + extraPadding + upper.ascent + upperGap + upper.descent`
///   - `descent = nuc.descent + extraPadding + lowerGap + lower.ascent + lower.descent`
public class MTLargeOpLimitsDisplay: MTDisplay {
    private var _nucleus: MTDisplay?
    public var upperLimit: MTDisplay?
    public var lowerLimit: MTDisplay?
    private var _limitShift: CGFloat = 0
    private var _extraPadding: CGFloat = 0
    private var _upperLimitGap: CGFloat = 0
    private var _lowerLimitGap: CGFloat = 0

    public var upperLimitGap: CGFloat {
        get { _upperLimitGap }
        set { _upperLimitGap = newValue; repositionAll() }
    }
    public var lowerLimitGap: CGFloat {
        get { _lowerLimitGap }
        set { _lowerLimitGap = newValue; repositionAll() }
    }

    public var nucleus: MTDisplay? { _nucleus }

    public init(nucleus: MTDisplay?, upperLimit: MTDisplay?,
                lowerLimit: MTDisplay?, limitShift: CGFloat, extraPadding: CGFloat) {
        _nucleus = nucleus
        self.upperLimit = upperLimit
        self.lowerLimit = lowerLimit
        _limitShift = limitShift
        _extraPadding = extraPadding
        super.init()

        var maxWidth = nucleus?.width ?? 0
        if let u = upperLimit { maxWidth = max(maxWidth, u.width) }
        if let l = lowerLimit { maxWidth = max(maxWidth, l.width) }
        self.width = maxWidth
        repositionAll()
    }

    override public var position: CGPoint {
        get { super.position }
        set {
            super.position = newValue
            repositionAll()
        }
    }

    // MARK: - Position updates

    private func repositionAll() {
        updateNucleusPosition()
        updateUpperLimitPosition()
        updateLowerLimitPosition()
        recomputeBounds()
    }

    private func recomputeBounds() {
        guard let nuc = _nucleus else { return }
        if let upper = upperLimit {
            super.ascent = nuc.ascent + _extraPadding + upper.ascent + upperLimitGap + upper.descent
        } else {
            super.ascent = nuc.ascent
        }
        if let lower = lowerLimit {
            super.descent = nuc.descent + _extraPadding + lowerLimitGap + lower.ascent + lower.descent
        } else {
            super.descent = nuc.descent
        }
    }

    private func updateUpperLimitPosition() {
        guard let upper = upperLimit, let nuc = _nucleus else { return }
        upper.position = CGPoint(
            x: _limitShift + (width - upper.width) / 2,
            y: nuc.ascent + upperLimitGap + upper.descent
        )
    }

    private func updateLowerLimitPosition() {
        guard let lower = lowerLimit, let nuc = _nucleus else { return }
        lower.position = CGPoint(
            x: -_limitShift + (width - lower.width) / 2,
            y: -(nuc.descent + lowerLimitGap + lower.ascent)
        )
    }

    private func updateNucleusPosition() {
        guard let nuc = _nucleus else { return }
        nuc.position = CGPoint(x: (width - nuc.width) / 2, y: 0)
    }

    // MARK: - Draw

    override public func draw(_ ctx: CGContext) {
        super.draw(ctx)
        // Draw each child at its relative position. Children's draw()
        // methods expect to be called at the context origin, so we
        // translate to their position first.
        ctx.saveGState()
        if let nuc = _nucleus {
            ctx.saveGState()
            ctx.translateBy(x: nuc.position.x, y: nuc.position.y)
            nuc.draw(ctx)
            ctx.restoreGState()
        }
        if let upper = upperLimit {
            ctx.saveGState()
            ctx.translateBy(x: upper.position.x, y: upper.position.y)
            upper.draw(ctx)
            ctx.restoreGState()
        }
        if let lower = lowerLimit {
            ctx.saveGState()
            ctx.translateBy(x: lower.position.x, y: lower.position.y)
            lower.draw(ctx)
            ctx.restoreGState()
        }
        ctx.restoreGState()
    }

    override public var textColor: MTColor? {
        set {
            _nucleus?.textColor = newValue
            upperLimit?.textColor = newValue
            lowerLimit?.textColor = newValue
        }
        get { _nucleus?.textColor }
    }

    override public func dumpDisplayTree(indent: String = "") {
        super.dumpDisplayTree(indent: indent)
        print("\(indent)  upperGap=\(Int(upperLimitGap)) lowerGap=\(Int(lowerLimitGap)) limitShift=\(Int(_limitShift))")
        if let nuc = _nucleus { nuc.dumpDisplayTree(indent: indent + "  N> ") }
        if let ul = upperLimit { ul.dumpDisplayTree(indent: indent + "  ^> ") }
        if let ll = lowerLimit { ll.dumpDisplayTree(indent: indent + "  _> ") }
    }
}
