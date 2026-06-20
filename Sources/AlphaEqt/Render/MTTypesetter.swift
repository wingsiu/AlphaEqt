//
//  MTTypesetter.swift
//  AlphaEqt
//
//  Typesetter following TeX Appendix G rules via OpenType MATH table.
//

import Foundation
import CoreGraphics
import CoreText

// MARK: - Parallel Render (Sendable-safe for Swift 6)

private final class ConcurrentBox<T>: @unchecked Sendable {
    var value: T!
    init() {}
}

/// Runs two independent rendering closures concurrently.
private func concurrentRender(
    _ a: @escaping @Sendable () -> MTDisplay?,
    _ b: @escaping @Sendable () -> MTDisplay?
) -> (MTDisplay?, MTDisplay?) {
    let r0 = ConcurrentBox<MTDisplay?>()
    let r1 = ConcurrentBox<MTDisplay?>()
    let group = DispatchGroup()
    group.enter()
    DispatchQueue.global().async { r0.value = a(); group.leave() }
    group.enter()
    DispatchQueue.global().async { r1.value = b(); group.leave() }
    group.wait()
    return (r0.value, r1.value)
}

// MARK: - Math Italic

fileprivate func mathItalicize(_ text: String) -> String {
    var result = ""
    for ch in text {
        guard let scalar = ch.unicodeScalars.first?.value else {
            result.append(ch)
            continue
        }
        if ch >= "a", ch <= "z" {
            let offset = scalar - 0x61
            result.append(Character(UnicodeScalar(0x1D44E + offset)!))
        } else if ch >= "A", ch <= "Z" {
            let offset = scalar - 0x41
            result.append(Character(UnicodeScalar(0x1D434 + offset)!))
        } else if scalar >= 0x03B1, scalar <= 0x03C9 {
            // Greek lowercase α–ω → math italic (U+1D6FC–U+1D714)
            // Variant forms (ϕ, ϑ, etc.) use pre-styled codepoints from
            // the symbol table and are NOT in this range, so they pass
            // through unchanged.
            let offset = scalar - 0x03B1
            result.append(Character(UnicodeScalar(0x1D6FC + offset)!))
        } else {
            result.append(ch)
        }
    }
    return result
}

// MARK: - MTMathListDisplay

public class MTMathListDisplay: MTDisplay {
    public var subDisplays: [MTDisplay] = []
    public var mathList: [ASTNode]?

    /// The minimum `position.x` among all direct sub‑displays (may be < 0).
    /// Used by MathView to pad the left margin so no content is clipped.
    public internal(set) var minChildX: CGFloat = 0

    public init(withDisplays displays: [MTDisplay], range: NSRange) {
        self.subDisplays = displays
        super.init()
        self.range = range
        recalculateDimensions()
    }

    private func recalculateDimensions() {
        var ascent: CGFloat = 0, descent: CGFloat = 0
        var minX: CGFloat = 0, maxX: CGFloat = 0
        for d in subDisplays {
            ascent = max(ascent, d.position.y + d.ascent)
            descent = max(descent, -(d.position.y - d.descent))
            if d.position.x < minX { minX = d.position.x }
            let right = d.position.x + d.width
            if right > maxX { maxX = right }
        }
        self.ascent = ascent; self.descent = descent
        // True content width includes any left-side overshoot (negative minX).
        self.width = maxX - minX
        self.minChildX = minX
    }

    public override func draw(_ context: CGContext) {
        super.draw(context)
        for d in subDisplays {
            context.saveGState()
            context.translateBy(x: d.position.x, y: d.position.y)
            d.draw(context)
            context.restoreGState()
        }
    }

    public override func dumpDisplayTree(indent: String = "") {
        super.dumpDisplayTree(indent: indent)
        for d in subDisplays {
            d.dumpDisplayTree(indent: indent + "  ")
        }
    }

    override public var textColor: MTColor? {
        set { for d in subDisplays { d.textColor = newValue } }
        get { return subDisplays.first?.textColor }
    }
}

// MARK: - Typesetter

public class Typesetter: @unchecked Sendable {

    nonisolated(unsafe) public static var useParallel = true

    let font: MTFont
    let style: MTLineStyle
    let textColor: CGColor?

    public init(font: MTFont, style: MTLineStyle = .display, textColor: CGColor? = nil) {
        self.font = font; self.style = style; self.textColor = textColor
    }

    func scriptStyle() -> MTLineStyle {
        switch style {
        case .display, .text: return .script
        case .script, .scriptOfScript: return .scriptOfScript
        }
    }

    public func createDisplay(_ nodes: [ASTNode]) -> MTDisplay? {
        var displays: [MTDisplay] = []
        var xOffset: CGFloat = 0
        var lastType: ASTNodeType?
        var currentStyle = style
        var currentFont = font

        for node in nodes {
            if node.type == .sizing, let styleStr = node.text {
                let newStyle = Typesetter.styleFromSizing(styleStr)
                currentStyle = newStyle
                currentFont = font.copy(withSize: Typesetter.getStyleSize(newStyle, baseFont: font))
                if let children = node.childNodes, !children.isEmpty {
                    let subTS = Typesetter(font: currentFont, style: currentStyle, textColor: textColor)
                    guard let display = subTS.createDisplay(children) else { continue }
                    if let last = lastType {
                        xOffset += getInterElementSpace(last, right: .inner)
                    }
                    display.position.x = xOffset
                    xOffset += display.width
                    displays.append(display)
                    lastType = node.type
                }
                continue
            }
            let tsWithStyle = Typesetter(font: currentFont, style: currentStyle, textColor: textColor)
            guard let display = tsWithStyle.renderNode(node) else { continue }
            if let last = lastType {
                let rightAtomType: AtomType
                if node.type == .supsub, let first = node.childNodes?.first {
                    rightAtomType = first.atomType
                } else {
                    rightAtomType = node.atomType
                }
                xOffset += tsWithStyle.getInterElementSpace(last, right: rightAtomType)
            }
            display.position.x = xOffset
            xOffset += display.width
            displays.append(display)
            lastType = node.type
        }
        guard !displays.isEmpty else { return nil }
        let list = MTMathListDisplay(withDisplays: displays, range: NSRange(location: 0, length: nodes.count))
        list.mathList = nodes
        return list
    }

    static func getStyleSize(_ style: MTLineStyle, baseFont: MTFont) -> CGFloat {
        let original = baseFont.size
        switch style {
        case .display, .text: return original
        case .script:         return max(original * baseFont.mathTable.scriptScaleDown, 6)
        case .scriptOfScript: return max(original * baseFont.mathTable.scriptScriptScaleDown, 6)
        }
    }

    static func styleFromSizing(_ text: String) -> MTLineStyle {
        switch text.lowercased().trimmingCharacters(in: .whitespaces) {
        case "displaystyle":       return .display
        case "textstyle":          return .text
        case "scriptstyle":        return .script
        case "scriptscriptstyle":  return .scriptOfScript
        default:                   return .display
        }
    }

    func renderNode(_ node: ASTNode) -> MTDisplay? {
        switch node.type {
        case .supsub: return renderSupSub(node)
        case .frac:   return renderFraction(node)
        case .sizing: return renderSizing(node)
        case .op:     return renderLargeOp(node)
        case .sqrt:   return renderRadical(node, hasDegree: false)
        case .root:   return renderRadical(node, hasDegree: true)
        case .spacing:   return renderSpacing(node)
        case .leftright: return renderLeftRight(node)
        case .array:     return renderArray(node)
        default:         return renderTextNode(node)
        }
    }

    private func renderSizing(_ node: ASTNode) -> MTDisplay? {
        if let children = node.childNodes, !children.isEmpty {
            let newStyle = Typesetter.styleFromSizing(node.text ?? "displaystyle")
            let newFont = font.copy(withSize: Typesetter.getStyleSize(newStyle, baseFont: font))
            let subTS = Typesetter(font: newFont, style: newStyle, textColor: textColor)
            return subTS.createDisplay(children)
        }
        return nil
    }

    // MARK: - Text rendering

    private func renderTextNode(_ node: ASTNode) -> MTDisplay? {
        if let children = node.childNodes, !children.isEmpty {
            return createDisplay(children)
        }
        let text = collectText(node)
        guard !text.isEmpty else { return nil }
        let displayText: String
        switch node.type {
        case .mathord, .unicode:
            displayText = mathItalicize(text)
        case .text, .textord:
            displayText = text
        case .bin, .rel:
            displayText = text.replacingOccurrences(of: "-", with: "\u{2212}")
        default:
            displayText = text
        }
        let ctDisplay = MTCTLineDisplay(
            attrString: makeAttributedString(displayText, font: font.ctFont),
            position: .zero, range: node.indexRange, font: font, atoms: [node]
        )
        node.display = ctDisplay
        return ctDisplay
    }

    private func makeAttributedString(_ text: String, font ctFont: CTFont) -> NSAttributedString {
        var attrs: [NSAttributedString.Key: Any] = [.font: ctFont]
        if let fg = textColor {
            attrs[NSAttributedString.Key(kCTForegroundColorAttributeName as String)] = fg
        }
        return NSAttributedString(string: text, attributes: attrs)
    }

    private func collectText(_ node: ASTNode) -> String {
        if let t = node.text, !t.isEmpty, t != "^", t != "_" { return t }
        return ""
    }

    // MARK: - Superscript / Subscript

    private func renderSupSub(_ node: ASTNode) -> MTDisplay? {
        guard let children = node.childNodes, children.count >= 1 else { return nil }
        guard let base = renderNode(children[0]) else { return nil }
        if children.count < 2 { return base }

        let hasSup = children[1].type != .mathord || !(children[1].text ?? "").isEmpty
        let hasSub = children.count > 2
            && (children[2].type != .mathord || !(children[2].text ?? "").isEmpty)
        if !hasSup && !hasSub { return base }

        let baseNode = children[0]
        let isLargeOp = baseNode.type == .op
        let isLimitsOp: Bool
        if isLargeOp, let nucleusText = baseNode.text {
            let limitsOps: Set<String> = ["\u{2211}", "\u{220F}", "\u{2210}",
                "\u{22C2}", "\u{22C3}", "\u{22C1}", "\u{22C0}",
                "\u{2A00}", "\u{2A01}", "\u{2A02}", "\u{2A06}", "\u{2A04}"]
            isLimitsOp = limitsOps.contains(String(nucleusText.prefix(1)))
                || nucleusText.unicodeScalars.count > 1
        } else {
            isLimitsOp = false
        }
        let limitsAboveBelow = isLimitsOp && style == .display

        let scale = font.mathTable.scriptScaleDown
        let scriptFontSz = max(font.size * scale, 6)
        let scriptFont = font.copy(withSize: scriptFontSz)
        let mt = font.mathTable

        let supDisplay: MTDisplay?
        let subDisplay: MTDisplay?
        if hasSup {
            if children[1].childNodes == nil {
                let text = mathItalicize(children[1].text ?? "")
                supDisplay = makeCTLine(text, scriptFont.ctFont,
                                        children[1].indexRange, scriptFont)
            } else {
                let subTS = Typesetter(font: scriptFont, style: scriptStyle(),
                                       textColor: textColor)
                supDisplay = subTS.renderNode(children[1])
            }
        } else {
            supDisplay = nil
        }

        if hasSub {
            if children[2].childNodes == nil {
                let text = mathItalicize(children[2].text ?? "")
                subDisplay = makeCTLine(text, scriptFont.ctFont,
                                        children[2].indexRange, scriptFont)
            } else {
                let subTS = Typesetter(font: scriptFont, style: scriptStyle(),
                                       textColor: textColor)
                subDisplay = subTS.renderNode(children[2])
            }
        } else {
            subDisplay = nil
        }

        if limitsAboveBelow {
            var delta: CGFloat = 0
            if let nucleusText = baseNode.text, nucleusText.unicodeScalars.count == 1,
               let ch = nucleusText.unicodeScalars.first {
                let unicharPtr = UnsafeMutablePointer<UniChar>.allocate(capacity: 1)
                defer { unicharPtr.deallocate() }
                unicharPtr[0] = UniChar(ch.value)
                var glyph: CGGlyph = 0
                if CTFontGetGlyphsForCharacters(font.ctFont, unicharPtr, &glyph, 1) {
                    delta = mt.getItalicCorrection(glyph)
                }
            }

            let opsDisplay = MTLargeOpLimitsDisplay(
                nucleus: base,
                upperLimit: supDisplay,
                lowerLimit: subDisplay,
                limitShift: delta / 2,
                extraPadding: 0
            )
            if supDisplay != nil {
                let upperGap = max(mt.upperLimitGapMin,
                                   mt.upperLimitBaselineRiseMin - (supDisplay?.descent ?? 0))
                opsDisplay.upperLimitGap = upperGap
            }
            if subDisplay != nil {
                let lowerGap = max(mt.lowerLimitGapMin,
                                   mt.lowerLimitBaselineDropMin - (subDisplay?.ascent ?? 0))
                opsDisplay.lowerLimitGap = lowerGap
            }
            return opsDisplay
        }

        let subXDelta: CGFloat
        if isLargeOp, !isLimitsOp, let gd = base as? MTGlyphDisplay {
            subXDelta = gd.leftMargin
        } else {
            subXDelta = 0
        }
        let scriptHOffset = mt.scriptSpace

        var supShift: CGFloat = 0
        var subShift: CGFloat = 0

        if !(base is MTCTLineDisplay) {
            supShift = base.ascent - mt.superscriptBaselineDropMax
            subShift = base.descent + mt.subscriptBaselineDropMin
        }

        if let sub = subDisplay, supDisplay == nil {
            subShift = max(subShift, mt.subscriptShiftDown)
            subShift = max(subShift, sub.ascent - mt.subscriptTopMax)
            sub.position = CGPoint(x: base.width + scriptHOffset - subXDelta, y: -subShift)
            return MTSupSubDisplay(base: base, superscript: nil, subscript: sub,
                                   scriptSpace: mt.scriptSpace)
        }

        guard let sup = supDisplay else { return base }
        supShift = max(supShift, mt.superscriptShiftUp)
        supShift = max(supShift, sup.descent + mt.superscriptBottomMin)

        if let sub = subDisplay {
            subShift = max(subShift, mt.subscriptShiftDown)
            let gap = (supShift - sup.descent) + (subShift - sub.ascent)
            if gap < mt.subSuperscriptGapMin {
                subShift += mt.subSuperscriptGapMin - gap
                let bottomDelta = mt.superscriptBottomMaxWithSubscript - (supShift - sup.descent)
                if bottomDelta > 0 {
                    supShift += bottomDelta
                    subShift -= bottomDelta
                }
            }
            sup.position = CGPoint(x: base.width + scriptHOffset, y: supShift)
            sub.position = CGPoint(x: base.width + scriptHOffset - subXDelta, y: -subShift)
            return MTSupSubDisplay(base: base, superscript: sup, subscript: sub,
                                   scriptSpace: mt.scriptSpace)
        } else {
            sup.position = CGPoint(x: base.width + scriptHOffset, y: supShift)
            return MTSupSubDisplay(base: base, superscript: sup, subscript: nil,
                                   scriptSpace: mt.scriptSpace)
        }
    }

    private func makeCTLine(_ text: String, _ ctFont: CTFont,
                             _ range: NSRange, _ f: MTFont) -> MTCTLineDisplay {
        MTCTLineDisplay(attrString: makeAttributedString(text, font: ctFont),
                        position: .zero, range: range, font: f, atoms: [])
    }

    // MARK: - Fraction

    private func renderFraction(_ node: ASTNode) -> MTDisplay? {
        guard let children = node.childNodes, children.count >= 2 else { return nil }
        let numNode = children[0]
        let denNode = children[1]

        let innerFont: MTFont
        switch style {
        case .display:
            innerFont = font
        case .text:
            let scale = MTConfig.shared.fractionScriptScaleDown ?? font.mathTable.scriptScaleDown
            innerFont = font.copy(withSize: max(font.size * scale, MTConfig.shared.minimumFontSize))
        case .script:
            let scale = MTConfig.shared.fractionScriptScriptScaleDown ?? font.mathTable.scriptScriptScaleDown
            innerFont = font.copy(withSize: max(font.size * scale, MTConfig.shared.minimumFontSize))
        case .scriptOfScript:
            innerFont = font
        }
        let subTS = Typesetter(font: innerFont, style: .text, textColor: textColor)

        let trivial = (numNode.text?.count ?? 0) + (denNode.text?.count ?? 0) <= 2
        let (num, den): (MTDisplay?, MTDisplay?)
        if Self.useParallel && !trivial {
            (num, den) = concurrentRender(
                { subTS.renderNode(numNode) },
                { subTS.renderNode(denNode) }
            )
        } else {
            num = subTS.renderNode(numNode)
            den = subTS.renderNode(denNode)
        }
        guard let num, let den else { return nil }

        let mt = font.mathTable
        let isDisplay = style == .display
        let isDisplayOrText = style == .display || style == .text
        let numShiftUp = isDisplay ? mt.fractionNumeratorDisplayStyleShiftUp : mt.fractionNumeratorShiftUp
        let denShiftDown = isDisplay ? mt.fractionDenominatorDisplayStyleShiftDown : mt.fractionDenominatorShiftDown
        let numGapMin = isDisplayOrText ? mt.fractionNumeratorDisplayStyleGapMin : mt.fractionNumeratorGapMin
        let denGapMin = isDisplayOrText ? mt.fractionDenominatorDisplayStyleGapMin : mt.fractionDenominatorGapMin

        return MTFractionDisplay(
            numerator: num, denominator: den,
            ruleThickness: mt.fractionRuleThickness,
            axisHeight: mt.axisHeight,
            numeratorShiftUp: numShiftUp,
            denominatorShiftDown: denShiftDown,
            numeratorGapMin: numGapMin,
            denominatorGapMin: denGapMin
        )
    }

    // MARK: - Large Operators

    private func renderLargeOp(_ node: ASTNode) -> MTDisplay? {
        let nucleus = node.text ?? ""
        if nucleus.unicodeScalars.count == 1 {
            return renderSingleCharOp(nucleus, node: node)
        }
        return renderTextNode(node)
    }

    private func renderSingleCharOp(_ nucleus: String, node: ASTNode) -> MTDisplay? {
        let mt = font.mathTable
        guard let ch = nucleus.unicodeScalars.first else { return renderTextNode(node) }

        let unicharPtr = UnsafeMutablePointer<UniChar>.allocate(capacity: 1)
        defer { unicharPtr.deallocate() }
        unicharPtr[0] = UniChar(ch.value)
        var outGlyph: CGGlyph = 0
        guard CTFontGetGlyphsForCharacters(font.ctFont, unicharPtr, &outGlyph, 1) else {
            return renderTextNode(node)
        }

        var glyph = outGlyph
        if style == .display {
            glyph = mt.getLargerGlyph(glyph)
        }

        let bbox = CTFontGetBoundingRectsForGlyphs(font.ctFont, .horizontal, &glyph, nil, 1)
        let rawAscent = max(0, bbox.maxY)
        let rawDescent = max(0, -bbox.minY)
        let advance = CTFontGetAdvancesForGlyphs(font.ctFont, .horizontal, &glyph, nil, 1)
        let shiftDown = 0.5 * (rawAscent - rawDescent) - mt.axisHeight

        let italicCorrection = mt.getItalicCorrection(glyph)

        let gd = MTGlyphDisplay(glyph: glyph, range: node.indexRange, font: font)
        gd.rawAscent = rawAscent
        gd.rawDescent = rawDescent
        gd.width = advance
        gd.glyphAdvance = advance
        gd.italicCorrection = italicCorrection
        gd.leftMargin = italicCorrection
        gd.shiftDown = shiftDown
        gd.position = .zero

        return gd
    }


    // MARK: - Radicals

    /// Constant slope for the diagonal connector on extended radicals (∼5.67).
    private static let radicalSlope: CGFloat = 3075.0 / 542.0

    private func radicalVerticalGap() -> CGFloat {
        let mt = font.mathTable
        if style == .display {
            return mt.radicalDisplayStyleVerticalGap
        }
        return mt.radicalVerticalGap
    }

    private func findGlyph(_ glyph: CGGlyph, withHeight height: CGFloat,
                           glyphAscent: inout CGFloat,
                           glyphDescent: inout CGFloat,
                           glyphWidth: inout CGFloat) -> CGGlyph {
        let mt = font.mathTable
        let variants = mt.getVerticalVariantsForGlyph(glyph)
        let numVariants = variants.count
        guard numVariants > 0 else {
            glyphAscent = 0; glyphDescent = 0; glyphWidth = 0
            return glyph
        }

        var varGlyphs = [CGGlyph]()
        varGlyphs.reserveCapacity(numVariants)
        for v in variants {
            varGlyphs.append(CGGlyph(truncating: v ?? NSNumber(value: 0)))
        }

        var bboxes = [CGRect](repeating: .zero, count: numVariants)
        var advances = [CGSize](repeating: .zero, count: numVariants)
        CTFontGetBoundingRectsForGlyphs(font.ctFont, .horizontal,
                                        &varGlyphs, &bboxes, numVariants)
        CTFontGetAdvancesForGlyphs(font.ctFont, .horizontal,
                                   &varGlyphs, &advances, numVariants)

        for i in 0..<numVariants {
            let bounds = bboxes[i]
            let a = max(0, bounds.maxY)
            let d = max(0, -bounds.minY)
            let w = advances[i].width
            if a + d >= height {
                glyphAscent = a; glyphDescent = d; glyphWidth = w
                return varGlyphs[i]
            }
        }
        let lastBounds = bboxes[numVariants - 1]
        glyphAscent = max(0, lastBounds.maxY)
        glyphDescent = max(0, -lastBounds.minY)
        glyphWidth = advances[numVariants - 1].width
        return varGlyphs[numVariants - 1]
    }

    private func getRadicalGlyph(withHeight radicalHeight: CGFloat) -> MTGlyphDisplay? {
        let sqrtChar = "\u{221A}"
        let unicharPtr = UnsafeMutablePointer<UniChar>.allocate(capacity: 1)
        defer { unicharPtr.deallocate() }
        let utf16 = sqrtChar.utf16
        var i = utf16.startIndex
        unicharPtr[0] = utf16[i]
        utf16.formIndex(after: &i)
        var radicalGlyph: CGGlyph = 0
        let numChars = (i == utf16.startIndex) ? 1 : (utf16.distance(from: utf16.startIndex, to: i))
        guard CTFontGetGlyphsForCharacters(font.ctFont, unicharPtr, &radicalGlyph, numChars) else {
            return nil
        }

        var glyphAscent: CGFloat = 0, glyphDescent: CGFloat = 0, glyphWidth: CGFloat = 0
        let glyph = findGlyph(radicalGlyph, withHeight: radicalHeight,
                              glyphAscent: &glyphAscent,
                              glyphDescent: &glyphDescent,
                              glyphWidth: &glyphWidth)

        let gd = MTGlyphDisplay(glyph: glyph, range: NSRange(location: NSNotFound, length: 0), font: font)
        gd.rawAscent = glyphAscent
        gd.rawDescent = glyphDescent
        gd.width = glyphWidth
        gd.position = .zero
        return gd
    }

    /// Renders `\sqrt{radicand}` or `\sqrt[degree]{radicand}`.
    ///
    /// Two construction paths:
    ///
    /// **Extender** (when the largest glyph variant is too short):
    ///   - The √ glyph sits anchored to the bottom of the radicand.
    ///   - A diagonal connector of constant slope (≈5.67) runs from the
    ///     glyph's visual top‑right corner up to the horizontal rule bar.
    ///   - Neither the glyph's virtual ascent nor the bar position move;
    ///     the diagonal bridges the gap.
    ///
    /// **Non‑extender** (glyph variant is tall enough):
    ///   - The glyph is shifted so its visual top aligns with the bar,
    ///     ensuring the bar connects to the glyph's right edge.
    ///   - `adjustedRadicalAscent` accounts for excess glyph height for
    ///     visual centering.
    private func renderRadical(_ node: ASTNode, hasDegree: Bool) -> MTDisplay? {
        let mt = font.mathTable
        guard let children = node.childNodes, !children.isEmpty else { return nil }

        let degreeNode: ASTNode?
        let radicandNode: ASTNode
        if hasDegree {
            degreeNode = children[0]
            radicandNode = children.count >= 2 ? children[1] : children[0]
        } else {
            degreeNode = nil
            radicandNode = children[0]
        }

        let subTS = Typesetter(font: font, style: style, textColor: textColor)
        guard let radicand = subTS.renderNode(radicandNode) else { return nil }

        var clearance = radicalVerticalGap()
        let ruleThickness = mt.radicalRuleThickness
        let radicalHeight = radicand.ascent + radicand.descent + clearance + ruleThickness

        guard let glyph = getRadicalGlyph(withHeight: radicalHeight) else { return nil }

        let glyphTotalHeight = glyph.rawAscent + glyph.rawDescent
        let needsExtender = glyphTotalHeight < radicalHeight

        // Excess glyph height distributed to clearance for visual centering.
        let excess = glyphTotalHeight - (radicand.ascent + radicand.descent + clearance + ruleThickness)
        if excess > 0 {
            clearance += excess / 2
        }
        let adjustedRadicalAscent = ruleThickness + clearance + radicand.ascent

        if needsExtender {
            // ---- Extender path ----
            // The √ glyph is anchored so its visual bottom aligns with the
            // radicand's bottom (or its own bottom, whichever is lower).
            // This ensures the glyph doesn't float above the radicand when
            // the radicand has significant descent (e.g. a fraction).
            // A diagonal connector of constant slope bridges the gap from
            // the glyph's visual top-right corner up to the horizontal bar.
            let origGlyphWidth = glyph.width
            let origGlyphAscent = glyph.rawAscent

            // Anchor bottom to radicand's descent.
            glyph.shiftDown = max(0, radicand.descent - glyph.rawDescent)

            // barY in MTRadicalDisplay draw space.
            let barY = adjustedRadicalAscent - ruleThickness / 2

            // Visual top of the glyph after bottom-anchoring.
            let visualTop = origGlyphAscent - glyph.shiftDown

            // Gap from visual top to bar center.
            let deltaY = barY - visualTop

            if deltaY > 0 {
                let deltaX = deltaY / Self.radicalSlope

                glyph.rawAscent = origGlyphAscent + deltaY
                glyph.width = origGlyphWidth + deltaX

                // Diagonal from visual top-right of original glyph body to bar start.
                let extStartX = origGlyphWidth
                let extStartY = visualTop
                let barStartX = glyph.width

                let radical = MTRadicalDisplay(
                    radicand: radicand, glyph: glyph,
                    position: .zero, range: node.indexRange
                )
                radical.ascent = adjustedRadicalAscent + mt.radicalExtraAscender
                radical.topKern = mt.radicalExtraAscender
                radical.lineThickness = ruleThickness
                radical.descent = max(glyph.rawAscent + glyph.rawDescent - adjustedRadicalAscent,
                                       radicand.descent)
                radical.width = glyph.width + radicand.width
                radical.setExtender(start: CGPoint(x: extStartX, y: extStartY),
                                    barStartX: barStartX)

                if hasDegree, let degNode = degreeNode {
                    let degTS = Typesetter(font: font.copy(withSize: font.size * mt.scriptScaleDown),
                                            style: .script, textColor: textColor)
                    if let degree = degTS.renderNode(degNode) {
                        radical.setDegree(degree, fontMetrics: mt)
                    }
                }
                return radical
            }

            // deltaY <= 0: glyph top is already at or above the bar.
            // This shouldn't happen when needsExtender is true, but handle
            // gracefully by falling through to the non-extender path.
            glyph.rawAscent = origGlyphAscent
            glyph.width = origGlyphWidth
        }

        // ---- Non‑extender path ----
        // Align the glyph's visual top to the bar so the bar connects
        // to the glyph's right edge at the correct y-position.
        glyph.shiftDown = glyph.rawAscent - adjustedRadicalAscent

        let radical = MTRadicalDisplay(
            radicand: radicand, glyph: glyph,
            position: .zero, range: node.indexRange
        )
        radical.ascent = adjustedRadicalAscent + mt.radicalExtraAscender
        radical.topKern = mt.radicalExtraAscender
        radical.lineThickness = ruleThickness
        let glyphExtentBelowBar = (glyph.rawAscent + glyph.rawDescent) - adjustedRadicalAscent
        radical.descent = max(glyphExtentBelowBar, radicand.descent)
        radical.width = glyph.width + radicand.width

        if hasDegree, let degNode = degreeNode {
            let degTS = Typesetter(font: font.copy(withSize: font.size * mt.scriptScaleDown),
                                    style: .script, textColor: textColor)
            if let degree = degTS.renderNode(degNode) {
                radical.setDegree(degree, fontMetrics: mt)
            }
        }
        return radical
    }

    // MARK: - Spacing commands

    /// Renders explicit spacing commands (\quad, \qquad, \,, \;, \!).
    /// Returns an invisible kern display with the appropriate width.
    private func renderSpacing(_ node: ASTNode) -> MTDisplay? {
        let spaceType = node.text ?? ""
        let width: CGFloat
        switch spaceType {
        case "quad":    width = font.size                   // 1 em
        case "qquad":   width = font.size * 2               // 2 em
        case "thin":    width = 3 * font.mathTable.muUnit   // 3 mu
        case "thick":   width = 5 * font.mathTable.muUnit   // 5 mu
        case "negative":width = -3 * font.mathTable.muUnit  // -3 mu (\!)
        default:        width = 0
        }
        let d = MTDisplay()
        d.width = width
        d.ascent = 0
        d.descent = 0
        d.range = node.indexRange
        return d
    }

    // MARK: - Left/Right Delimiters

    /// Renders `\left<delim> ... \right<delim>` with stretchy delimiters.
    ///
    /// Computes required delimiter height from inner content, selects the
    /// largest pre-built variant glyph, or falls back to glyph assembly
    /// (stacked parts) for very tall expressions.
    private func renderLeftRight(_ node: ASTNode) -> MTDisplay? {
        guard let children = node.childNodes, children.count >= 1 else { return nil }
        guard let innerGroup = children.first else { return nil }

        // Parse delimiter chars from node.text "leftDelim\0rightDelim"
        let parts = (node.text ?? ".\0.").split(separator: "\0")
        let leftDelim = parts.count > 0 ? String(parts[0]) : "."
        let rightDelim = parts.count > 1 ? String(parts[1]) : "."

        // Render inner content
        let subTS = Typesetter(font: font, style: style, textColor: textColor)
        guard let innerDisplay = subTS.createDisplay(innerGroup.childNodes ?? []) else { return nil }

        let mt = font.mathTable
        let axis = mt.axisHeight

        // Calculate required delimiter height (SwiftMath algorithm)
        let delta = max(innerDisplay.ascent - axis, innerDisplay.descent + axis)
        let d1 = (delta / 500) * 901  // 90% coverage
        let d2 = 2 * delta - 5         // 5pt shortfall
        let glyphHeight = max(d1, d2)

        let delimiterPadding = mt.muUnit * 2
        var elements: [MTDisplay] = []

        // Left delimiter
        if leftDelim != "." {
            let leftGD = makeDelimiterGlyph(leftDelim, height: glyphHeight)
            leftGD?.position = .zero
            if let lg = leftGD {
                elements.append(lg)
            }
        }

        // Inner content
        innerDisplay.position = CGPoint(
            x: (leftDelim != "." ? (elements.first?.width ?? 0) + delimiterPadding : 0),
            y: 0
        )
        elements.append(innerDisplay)

        // Right delimiter
        if rightDelim != "." {
            let rightX = (elements.last?.position.x ?? 0) + (elements.last?.width ?? 0) + delimiterPadding
            let rightGD = makeDelimiterGlyph(rightDelim, height: glyphHeight)
            rightGD?.position = CGPoint(x: rightX, y: 0)
            if let rg = rightGD {
                elements.append(rg)
            }
        }

        let list = MTMathListDisplay(withDisplays: elements, range: node.indexRange)
        return list
    }

    /// Builds a single stretchy delimiter glyph using variants or assembly.
    /// When the largest pre‑built variant is too short, falls back to glyph
    /// assembly (stacked parts: bottom + extender + top).
    private func makeDelimiterGlyph(_ delim: String, height: CGFloat) -> MTDisplay? {
        let mt = font.mathTable
        let axis = mt.axisHeight

        // Get the base glyph for the delimiter character
        guard let ch = delim.unicodeScalars.first else { return nil }
        let unicharPtr = UnsafeMutablePointer<UniChar>.allocate(capacity: 1)
        defer { unicharPtr.deallocate() }
        unicharPtr[0] = UniChar(ch.value)
        var baseGlyph: CGGlyph = 0
        guard CTFontGetGlyphsForCharacters(font.ctFont, unicharPtr, &baseGlyph, 1) else {
            return nil
        }

        // Find the largest variant
        var glyphAscent: CGFloat = 0, glyphDescent: CGFloat = 0, glyphWidth: CGFloat = 0
        let glyph = findGlyph(baseGlyph, withHeight: height,
                              glyphAscent: &glyphAscent,
                              glyphDescent: &glyphDescent,
                              glyphWidth: &glyphWidth)

        // If the largest variant isn't tall enough, try assembly
        if glyphAscent + glyphDescent < height {
            let parts = mt.getVerticalGlyphAssembly(forGlyph: baseGlyph)
            if !parts.isEmpty {
                return buildAssemblyDisplay(parts: parts, targetHeight: height, axis: axis)
            }
        }

        let gd = MTGlyphDisplay(glyph: glyph, range: NSRange(location: NSNotFound, length: 0),
                                font: font)
        gd.rawAscent = glyphAscent
        gd.rawDescent = glyphDescent
        gd.width = glyphWidth
        gd.shiftDown = 0.5 * (glyphAscent - glyphDescent) - axis
        gd.position = .zero
        return gd
    }

    /// Builds a stacked glyph from assembly parts (bottom, extender, top).
    /// The extender is repeated until the total height meets `targetHeight`.
    private func buildAssemblyDisplay(parts: [MTFontMathTable.GlyphPart],
                                       targetHeight: CGFloat, axis: CGFloat) -> MTDisplay? {
        guard parts.count >= 3 else { return nil }

        // Parts: [0]=bottom, [1]=extender, [2]=top
        let bottom = parts[0]
        let extender = parts[1]
        let top = parts[2]

        let bottomAdv = bottom.fullAdvance
        let extAdv = extender.fullAdvance
        let topAdv = top.fullAdvance

        let nonExtHeight = bottomAdv + topAdv
        let extHeight = max(0, targetHeight - nonExtHeight)
        let extCount = max(1, Int(ceil(extHeight / extAdv)))

        var glyphs: [CGGlyph] = []
        var offsets: [CGFloat] = []
        var yOffset: CGFloat = 0

        // Bottom
        glyphs.append(CGGlyph(bottom.glyph))
        offsets.append(yOffset)
        yOffset += bottomAdv

        // Extenders (repeated)
        for _ in 0..<extCount {
            glyphs.append(CGGlyph(extender.glyph))
            offsets.append(yOffset)
            yOffset += extAdv
        }

        // Top
        glyphs.append(CGGlyph(top.glyph))
        offsets.append(yOffset)
        yOffset += topAdv

        let totalHeight = yOffset
        // Centre the assembly on the math axis so it covers content evenly
        // from top and bottom. TeX rule: the delimiter is axis-centered
        // and extends sufficiently above and below the content.
        let gd = MTGlyphConstructionDisplay(glyphs: glyphs, offsets: offsets, font: font)
        // Raw ascent: entire stack extends upward from glyph origin
        gd.ascent = totalHeight
        gd.descent = 0
        // Shift down so the visual center aligns with the math axis
        gd.shiftDown = (totalHeight / 2) - axis

        // Get actual glyph advance width from the extender piece
        var extGlyph = CGGlyph(extender.glyph)
        let extWidth = CTFontGetAdvancesForGlyphs(font.ctFont, .horizontal, &extGlyph, nil, 1)
        gd.width = extWidth
        gd.position = .zero
        return gd
    }

    // MARK: - Arrays / Matrices

    /// Renders an array/matrix node using TeX `\vcenter` semantics:
    ///   - Each row's cells are baseline-aligned and centered horizontally in columns
    ///   - Rows are stacked top-to-bottom with `rowGap` between content edges
    ///   - The entire array is axis-centered so its vertical midpoint sits on the math axis
    ///
    /// This matches the behaviour of KaTeX, iOSMath, and TeX's `\vcenter` for matrices.
    private func renderArray(_ node: ASTNode) -> MTDisplay? {
        guard let rows = node.childNodes, !rows.isEmpty else { return nil }

        let mt = font.mathTable
        let mu = mt.muUnit
        let colGap = mu * 18   // inter‑column space (2 × 9mu per TeX)
        let rowGap = mu * 3    // \jot equivalent = 3mu ≈ 1.67pt at 10pt

        // Determine column count
        var numCols = 0
        for row in rows { numCols = max(numCols, row.childNodes?.count ?? 0) }
        guard numCols > 0 else { return nil }

        // Render every cell, track per‑column widths and per‑row extents
        var allCells = [[MTDisplay?]]()
        var colW = [CGFloat](repeating: 0, count: numCols)
        var rowAscent = [CGFloat](repeating: 0, count: rows.count)
        var rowDescent = [CGFloat](repeating: 0, count: rows.count)

        for (ri, row) in rows.enumerated() {
            let cols = row.childNodes ?? []
            var rowCells = [MTDisplay?]()
            for ci in 0..<numCols {
                guard ci < cols.count else { rowCells.append(nil); continue }
                let col = cols[ci]
                let sub = Typesetter(font: font, style: style, textColor: textColor)
                let d: MTDisplay?
                if col.type == .ordgroup, let ch = col.childNodes { d = sub.createDisplay(ch) }
                else { d = sub.renderNode(col) }
                if let cd = d {
                    colW[ci] = max(colW[ci], cd.width)
                    rowAscent[ri] = max(rowAscent[ri], cd.ascent)
                    rowDescent[ri] = max(rowDescent[ri], cd.descent)
                }
                rowCells.append(d)
            }
            allCells.append(rowCells)
        }

        // Build rows: cells baseline-aligned (position.y = 0 in row space)
        var rowDisplays = [MTDisplay]()
        for cells in allCells {
            var rowElements = [MTDisplay]()
            var x: CGFloat = 0
            for ci in 0..<numCols {
                guard let cell = cells[ci] else { x += colW[ci] + colGap; continue }
                cell.position = CGPoint(x: x + (colW[ci] - cell.width) / 2, y: 0)
                rowElements.append(cell)
                x += colW[ci] + colGap
            }
            let w = max(0, x - colGap)
            let row = MTMathListDisplay(withDisplays: rowElements,
                                         range: NSRange(location: NSNotFound, length: 0))
            row.width = w
            row.position = .zero
            rowDisplays.append(row)
        }

        // ---- Vertical stacking (TeX \vcenter semantics) ----
        //
        // Each row's `position.y` is its baseline. Cells within the row sit
        // at y=0, so the row's ascent = max cell ascent and descent = max
        // cell descent.
        //
        // We stack rows top-to-bottom so that:
        //   row[0].content.top = 0        (highest y = top reference)
        //   row[i].content.top = row[i-1].content.bottom - rowGap
        //
        // After positioning we compute the content's vertical midpoint and
        // shift everything so that midpoint sits on the math axis.

        var currentTop: CGFloat = 0  // y-coordinate of the next row's content top

        for (ri, row) in rowDisplays.enumerated() {
            // Row baseline = contentTop - ascent
            // (because content top = position.y + ascent → position.y = contentTop - ascent)
            row.position = CGPoint(x: 0, y: currentTop - rowAscent[ri])

            // Update currentTop to the bottom of this row's content
            // (bottom of content = position.y - descent), plus the gap to next row
            currentTop = row.position.y - rowDescent[ri] - rowGap
        }

        // Content spans from y=0 (top of first row) to `currentTop + rowGap`
        // (the bottom of the last row — we subtracted the gap after the last
        //  row, so add it back to get the actual bottom).
        let contentBottom = currentTop + rowGap
        let contentMid = (0 + contentBottom) / 2

        // Shift so the content v-center sits on the math axis
        let axis = mt.axisHeight
        let shift = axis - contentMid
        for row in rowDisplays {
            row.position = CGPoint(x: row.position.x, y: row.position.y + shift)
        }

        // Build the outer container; MTMathListDisplay will compute the
        // correct ascent/descent from row positions.
        let maxW = rowDisplays.map { $0.width }.max() ?? 0
        let outer = MTMathListDisplay(withDisplays: rowDisplays, range: node.indexRange)
        outer.width = maxW
        return outer
    }

    // MARK: - Inter-element spacing

    private func getInterElementSpace(_ left: ASTNodeType, right: AtomType) -> CGFloat {
        let spaceType = Spaces.shared.getInterElementSpaceType(
            ASTNode(fromType: left).atomType, right: right)
        guard spaceType != .invalid else { return 0 }
        let mu = font.mathTable.muUnit
        switch spaceType {
        case .none: return 0
        case .thin: return 3 * mu
        case .nsThin: return style.isNotScript ? 3 * mu : 0
        case .nsMedium: return style.isNotScript ? 4 * mu : 0
        case .nsThick: return style.isNotScript ? 5 * mu : 0
        case .invalid: return 0
        }
    }
}

extension ASTNode {
    internal convenience init(fromType type: ASTNodeType) { self.init(type: type) }
}
