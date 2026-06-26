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
    /// Active font style from a wrapping `\mathbb{}`, `\mathbf{}`, etc.
    let fontStyle: MTFontStyle
    /// Whether this style is cramped (TeX Appendix G prime styles).
    /// Affects superscript shift — cramped superscripts use `superscriptShiftUpCramped`.
    let cramped: Bool
    /// Font scaled for the current style (SwiftMath's styleFont).
    /// Uses the base font size for .display/.text, and scaled for .script/.scriptOfScript.
    private lazy var _styleFont: MTFont? = nil
    var styleFont: MTFont {
        if _styleFont == nil {
            _styleFont = font.copy(withSize: Self.getStyleSize(style, baseFont: font))
        }
        return _styleFont!
    }

    public init(font: MTFont, style: MTLineStyle = .display, cramped: Bool = false,
                textColor: CGColor? = nil, fontStyle: MTFontStyle = .defaultStyle) {
        self.font = font; self.style = style; self.cramped = cramped
        self.textColor = textColor; self.fontStyle = fontStyle
    }

    func scriptStyle() -> MTLineStyle {
        switch style {
        case .display, .text: return .script
        case .script, .scriptOfScript: return .scriptOfScript
        }
    }

    /// Per TeX: subscript is always cramped.
    func subscriptCramped() -> Bool { true }

    /// Per TeX: superscript is cramped only if parent style is cramped.
    func superscriptCramped() -> Bool { cramped }

    /// The shift-up value for superscripts — uses cramped variant when cramped.
    func superscriptShiftUp() -> CGFloat {
        let supSubFontSize = Self.getStyleSize(style, baseFont: font)
        let mt = font.copy(withSize: supSubFontSize).mathTable
        return cramped ? mt.superscriptShiftUpCramped : mt.superscriptShiftUp
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
                    let subTS = Typesetter(font: currentFont, style: currentStyle,
                                           cramped: self.cramped, textColor: textColor,
                                           fontStyle: fontStyle)
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
            let tsWithStyle = Typesetter(font: currentFont, style: currentStyle,
                                         cramped: self.cramped, textColor: textColor,
                                         fontStyle: fontStyle)
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
        case .accent:    return renderAccent(node)
        case .horizBrace: return renderHorizBrace(node)
        case .stack:     return renderStack(node)
        case .xarrow:    return renderXArrow(node)
        case .overline:  return renderOverline(node)
        case .underline: return renderUnderline(node)
        case .color:     return renderColor(node)
        case .colorbox:  return renderColorbox(node)
        case .styling:   return renderStyling(node)
        default:         return renderTextNode(node)
        }
    }

    private func renderSizing(_ node: ASTNode) -> MTDisplay? {
        if let children = node.childNodes, !children.isEmpty {
            let newStyle = Typesetter.styleFromSizing(node.text ?? "displaystyle")
            let newFont = font.copy(withSize: Typesetter.getStyleSize(newStyle, baseFont: font))
            let subTS = Typesetter(font: newFont, style: newStyle, cramped: self.cramped,
                                   textColor: textColor, fontStyle: fontStyle)
            return subTS.createDisplay(children)
        }
        return nil
    }

    private func renderStyling(_ node: ASTNode) -> MTDisplay? {
        guard let children = node.childNodes, !children.isEmpty else { return nil }
        let style = node.fontStyle
        let subTS = Typesetter(font: font, style: self.style, cramped: cramped,
                               textColor: textColor, fontStyle: style)
        return subTS.createDisplay(children)
    }

    // MARK: - Text rendering

    private func renderTextNode(_ node: ASTNode) -> MTDisplay? {
        if let children = node.childNodes, !children.isEmpty {
            return createDisplay(children)
        }
        let text = collectText(node)
        guard !text.isEmpty else { return nil }
        let displayText: String
        let isTextMode: Bool
        switch node.type {
        case .mathord, .unicode:
            displayText = applyMathFontStyle(text, style: fontStyle)
            isTextMode = false
        case .text, .textord:
            displayText = text
            isTextMode = true
        case .bin, .rel:
            displayText = text.replacingOccurrences(of: "-", with: "\u{2212}")
            isTextMode = false
        default:
            displayText = text
            isTextMode = false
        }
        let scaledFont = styleFont
        let ctFont: CTFont
        if isTextMode {
            ctFont = uprightSystemFont(size: scaledFont.size)
        } else if fontStyle == .blackboard {
            ctFont = KaTeXFont.amsRegular(size: scaledFont.size)
        } else {
            ctFont = scaledFont.ctFont
        }
        let ctDisplay = MTCTLineDisplay(
            attrString: makeAttributedString(displayText, font: ctFont),
            position: .zero, range: node.indexRange, font: scaledFont, atoms: [node]
        )
        node.display = ctDisplay
        return ctDisplay
    }

    /// Returns an upright (non-italic) system font at the given size,
    /// used for `\text{}` content which should render in roman style.
    private func uprightSystemFont(size: CGFloat) -> CTFont {
        // Times New Roman is an upright serif font matching LaTeX \text{} behavior.
        // CTFontCreateWithName falls back to system font if not found on the platform.
        CTFontCreateWithName("Times New Roman" as CFString, size, nil)
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
            if limitsOps.contains(String(nucleusText.prefix(1))) {
                isLimitsOp = true
            } else if nucleusText.unicodeScalars.count > 1 {
                // Multi-char operators: only "lim", "limsup", "liminf", "max", "min",
                // "sup", "inf", "det", "gcd", "Pr" get limits. All others (sin, cos,
                // tan, log, ln, etc.) are no-limits per standard LaTeX.
                let wordLimitsOps: Set<String> = [
                    "lim", "lim sup", "lim inf", "max", "min",
                    "sup", "inf", "det", "gcd", "Pr"
                ]
                isLimitsOp = wordLimitsOps.contains(nucleusText)
            } else {
                isLimitsOp = false
            }
        } else {
            isLimitsOp = false
        }
        let limitsAboveBelow = isLimitsOp && style == .display

        let supSubFontSize = Self.getStyleSize(style, baseFont: font)
        let mt = font.copy(withSize: supSubFontSize).mathTable

        // TeX Appendix G, Rule 18: subscript shift depends on style.
        // OpenType MATH table provides only one SubscriptShiftDown (single value),
        // but TeX distinguishes: σ16=0.15em (display) vs σ17=0.247em (non-display).
        // Use TeX em-based parameters like MathJax does, producing more compact
        // subscript placement for display-style operators (∑, ∫, etc.).
        let texSub1: CGFloat = 0.15     // display-style subscript shift
        let texSub2: CGFloat = 0.247    // non-display subscript shift
        let texSubShift = (style == .display ? texSub1 : texSub2) * supSubFontSize

        let supDisplay: MTDisplay?
        let subDisplay: MTDisplay?
        // Font for plain text scripts: always scale from the top-level
        // base font, not from the already-scaled effective font.
        let scriptFontSize = Self.getStyleSize(scriptStyle(), baseFont: font)
        let scriptFontForText = font.copy(withSize: scriptFontSize)

        if hasSup {
            if children[1].childNodes == nil {
                let text = applyMathFontStyle(children[1].text ?? "", style: fontStyle)
                supDisplay = makeCTLine(text, ctFontForMathText(size: scriptFontSize),
                                        children[1].indexRange, scriptFontForText)
            } else {
                let subTS = Typesetter(font: font, style: scriptStyle(),
                                       cramped: superscriptCramped(), textColor: textColor,
                                       fontStyle: fontStyle)
                supDisplay = subTS.renderNode(children[1])
            }
        } else {
            supDisplay = nil
        }

        if hasSub {
            if children[2].childNodes == nil {
                let text = applyMathFontStyle(children[2].text ?? "", style: fontStyle)
                subDisplay = makeCTLine(text, ctFontForMathText(size: scriptFontSize),
                                        children[2].indexRange, scriptFontForText)
            } else {
                let subTS = Typesetter(font: font, style: scriptStyle(),
                                       cramped: true, textColor: textColor, fontStyle: fontStyle)
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

        if baseNode.type == .horizBrace, let brace = base as? MTAccentDisplay, let accent = brace.accent {
            let isOver = baseNode.text == "overbrace"
            let fs = font.size
            let labelGap = TeXStackMetrics.horizBraceLabelGap(fs)
            if let sup = supDisplay, isOver {
                let padTop = TeXStackMetrics.horizBraceLabelPadTop(fs)
                let braceTop = accent.position.y + accent.ascent
                sup.position = CGPoint(x: (brace.width - sup.width) / 2,
                                       y: braceTop + labelGap + sup.descent)
                brace.ascent = padTop + sup.position.y + sup.ascent
                return MTSupSubDisplay(base: brace, superscript: sup, subscript: nil, scriptSpace: 0)
            }
            if let sub = subDisplay, !isOver {
                let padBottom = TeXStackMetrics.horizBraceLabelPadTop(fs)
                let braceBottom = accent.position.y - accent.descent
                sub.position = CGPoint(x: (brace.width - sub.width) / 2,
                                       y: braceBottom - labelGap - sub.ascent)
                brace.descent = padBottom + max(brace.descent, -(sub.position.y - sub.descent))
                return MTSupSubDisplay(base: brace, superscript: nil, subscript: sub, scriptSpace: 0)
            }
            return brace
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
            // For glyph bases, subscript starts at the glyph's visual descent
            // (which includes axis-centering shiftDown). The texSubShift
            // and subscriptTopMax constraints applied later ensure clearance.
            // subscriptBaselineDropMin is omitted for glyph bases to avoid
            // excessive gap between the operator body and its subscript.
            let baseDescent: CGFloat
            if let gd = base as? MTGlyphDisplay {
                baseDescent = gd.descent
            } else {
                baseDescent = base.descent + mt.subscriptBaselineDropMin
            }
            subShift = baseDescent
        }

        if let sub = subDisplay, supDisplay == nil {
            subShift = max(subShift, texSubShift)
            subShift = max(subShift, sub.ascent - mt.subscriptTopMax)
            sub.position = CGPoint(x: base.width + scriptHOffset - subXDelta, y: -subShift)
            return MTSupSubDisplay(base: base, superscript: nil, subscript: sub,
                                   scriptSpace: mt.scriptSpace)
        }

        guard let sup = supDisplay else { return base }
        // Use cramped-aware shift from the style-scaled math table.
        supShift = max(supShift, cramped ? mt.superscriptShiftUpCramped : mt.superscriptShiftUp)
        supShift = max(supShift, sup.descent + mt.superscriptBottomMin)

        if let sub = subDisplay {
            subShift = max(subShift, texSubShift)
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

    private func ctFontForMathText(size: CGFloat) -> CTFont {
        if fontStyle == .blackboard {
            return KaTeXFont.amsRegular(size: size)
        }
        return font.copy(withSize: size).ctFont
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

        // TeX Appendix G, Rule 15e: fraction inner style = style.inc()
        // (display→text, text→script, script→scriptscript, scriptscript→scriptscript)
        let innerStyle: MTLineStyle
        switch style {
        case .display: innerStyle = .text
        case .text:    innerStyle = .script
        case .script:  innerStyle = .scriptOfScript
        case .scriptOfScript: innerStyle = .scriptOfScript
        }
        
        // TeX Rule 15e: numerator is cramped only if parent is cramped;
        // denominator is always cramped.
        let numTS = Typesetter(font: font, style: innerStyle, cramped: self.cramped,
                               textColor: textColor, fontStyle: fontStyle)
        let denTS = Typesetter(font: font, style: innerStyle, cramped: true,
                               textColor: textColor, fontStyle: fontStyle)

        let trivial = (numNode.text?.count ?? 0) + (denNode.text?.count ?? 0) <= 2
        let (num, den): (MTDisplay?, MTDisplay?)
        if Self.useParallel && !trivial {
            (num, den) = concurrentRender(
                { numTS.renderNode(numNode) },
                { denTS.renderNode(denNode) }
            )
        } else {
            num = numTS.renderNode(numNode)
            den = denTS.renderNode(denNode)
        }
        guard let num, let den else { return nil }

        // Per TeX: shift/gap values depend on the fraction's own style level.
        let fracFontSize = Self.getStyleSize(style, baseFont: font)
        let mt = font.copy(withSize: fracFontSize).mathTable
        let fracKind = node.text ?? ""
        let isBinom = ["binom", "dbinom", "tbinom"].contains(fracKind)
        let isDisplay = style == .display
        let ruleThickness = isBinom ? 0 : mt.fractionRuleThickness

        // TeX Appendix G: use em-based shift parameters (like MathJax).
        // These are the classic TeX font parameters, not OpenType MATH table values.
        // They scale linearly with fontSize and produce compact fractions.
        let texNum1: CGFloat = 0.676; let texNum2: CGFloat = 0.394
        let texDenom1: CGFloat = 0.686; let texDenom2: CGFloat = 0.345
        let numShiftUp = (isDisplay ? texNum1 : texNum2) * fracFontSize
        let denShiftDown = (isDisplay ? texDenom1 : texDenom2) * fracFontSize
        // Keep gap min, axis, and rule from MATH table (font-specific)
        let numGapMin = isDisplay ? mt.fractionNumeratorDisplayStyleGapMin : mt.fractionNumeratorGapMin
        let denGapMin = isDisplay ? mt.fractionDenominatorDisplayStyleGapMin : mt.fractionDenominatorGapMin

        // Bar overhang: extends rule beyond content (matches original computation)
        let barOverhang = fracFontSize * 0.1
        // Container padding: \nulldelimiterspace (0.12em)
        let fractionPadding = fracFontSize * 0.12
        let styleLabel = isDisplay ? "D" : (style == .text ? "T" : (style == .script ? "S" : "SS"))
        print("[FRAC \(styleLabel)] fontSize=\(fracFontSize) numAscent=\(num.ascent) numDescent=\(num.descent) denAscent=\(den.ascent) denDescent=\(den.descent)")
        print("[FRAC \(styleLabel)] shiftUp=\(numShiftUp) shiftDown=\(denShiftDown) gapMinNum=\(numGapMin) gapMinDen=\(denGapMin) axis=\(mt.axisHeight) rule=\(mt.fractionRuleThickness)")
        let binomDisplay: Bool = {
            switch fracKind {
            case "dbinom": return true
            case "tbinom": return false
            case "binom": return style == .display
            default: return false
            }
        }()
        let fracDisp = MTFractionDisplay(
            numerator: num, denominator: den,
            ruleThickness: ruleThickness,
            axisHeight: mt.axisHeight,
            numeratorShiftUp: numShiftUp,
            denominatorShiftDown: denShiftDown,
            numeratorGapMin: numGapMin,
            denominatorGapMin: denGapMin,
            barOverhang: barOverhang,
            fractionPadding: fractionPadding,
            binomDisplayStyle: isBinom ? binomDisplay : nil,
            binomFontSize: isBinom ? fracFontSize : nil
        )
        if isBinom {
            return wrapBinomWithDelimiters(fracDisp)
        }
        return fracDisp
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

    /// Finds a vertical glyph variant that satisfies the required height.
    /// Uses the provided math table and measurement font so everything matches
    /// the current style scale.
    private func findGlyph(_ glyph: CGGlyph, withHeight height: CGFloat,
                           using mt: MTFontMathTable,
                           measurementFont: MTFont,
                           glyphAscent: inout CGFloat,
                           glyphDescent: inout CGFloat,
                           glyphWidth: inout CGFloat) -> CGGlyph {
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
        CTFontGetBoundingRectsForGlyphs(measurementFont.ctFont, .horizontal,
                                        &varGlyphs, &bboxes, numVariants)
        CTFontGetAdvancesForGlyphs(measurementFont.ctFont, .horizontal,
                                   &varGlyphs, &advances, numVariants)

        var bestIdx: Int?
        var bestTotal = CGFloat.infinity
        for i in 0..<numVariants {
            let bounds = bboxes[i]
            let a = max(0, bounds.maxY)
            let d = max(0, -bounds.minY)
            let total = a + d
            if total >= height {
                if total < bestTotal {
                    bestTotal = total
                    bestIdx = i
                }
            }
        }
        if let idx = bestIdx {
            let bounds = bboxes[idx]
            glyphAscent = max(0, bounds.maxY)
            glyphDescent = max(0, -bounds.minY)
            glyphWidth = advances[idx].width
            return varGlyphs[idx]
        }
        let lastBounds = bboxes[numVariants - 1]
        glyphAscent = max(0, lastBounds.maxY)
        glyphDescent = max(0, -lastBounds.minY)
        glyphWidth = advances[numVariants - 1].width
        return varGlyphs[numVariants - 1]
    }

    /// Returns the best radical glyph for the given height, using the provided
    /// scaled math table and font so the glyph matches the style level.
    private func getRadicalGlyph(withHeight radicalHeight: CGFloat,
                                  mt: MTFontMathTable,
                                  radicalFont: MTFont) -> MTGlyphDisplay? {
        let sqrtChar = "\u{221A}"
        let unicharPtr = UnsafeMutablePointer<UniChar>.allocate(capacity: 1)
        defer { unicharPtr.deallocate() }
        let utf16 = sqrtChar.utf16
        var i = utf16.startIndex
        unicharPtr[0] = utf16[i]
        utf16.formIndex(after: &i)
        var radicalGlyph: CGGlyph = 0
        let numChars = (i == utf16.startIndex) ? 1 : (utf16.distance(from: utf16.startIndex, to: i))
        guard CTFontGetGlyphsForCharacters(radicalFont.ctFont, unicharPtr, &radicalGlyph, numChars) else {
            return nil
        }

        var glyphAscent: CGFloat = 0, glyphDescent: CGFloat = 0, glyphWidth: CGFloat = 0
        let glyph = findGlyph(radicalGlyph, withHeight: radicalHeight,
                              using: mt,
                              measurementFont: radicalFont,
                              glyphAscent: &glyphAscent,
                              glyphDescent: &glyphDescent,
                              glyphWidth: &glyphWidth)

        let gd = MTGlyphDisplay(glyph: glyph, range: NSRange(location: NSNotFound, length: 0), font: radicalFont)
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
        // Scale math table to the current style's font size so clearance,
        // rule thickness, and other metrics are proportional.
        let radicalFontSize = Self.getStyleSize(style, baseFont: font)
        let mt = font.copy(withSize: radicalFontSize).mathTable
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

        // Per TeX Rule 11: the radicand is always typeset in cramped style.
        let subTS = Typesetter(font: font, style: style, cramped: true,
                               textColor: textColor, fontStyle: fontStyle)
        guard let radicand = subTS.renderNode(radicandNode) else { return nil }

        var clearance: CGFloat
        if style == .display {
            clearance = mt.radicalDisplayStyleVerticalGap
        } else {
            clearance = mt.radicalVerticalGap
        }
        let ruleThickness = mt.radicalRuleThickness
        // Per TeX Rule 11: radical must be tall enough to cover
        // the entire radicand (ascent + descent) plus clearance and rule.
        let radicalHeight = radicand.ascent + radicand.descent + clearance + ruleThickness

        let radicalFont = font.copy(withSize: radicalFontSize)
        guard let glyph = getRadicalGlyph(withHeight: radicalHeight,
                                           mt: mt, radicalFont: radicalFont) else { return nil }
        print("[RADICAL] selected glyph=\(glyph.glyph) rawAscent=\(glyph.rawAscent) rawDescent=\(glyph.rawDescent) width=\(glyph.width)")
        print("[RADICAL] radicalHeight=\(radicalHeight) radicand(a=\(radicand.ascent) d=\(radicand.descent)) clearance=\(clearance) ruleThickness=\(ruleThickness)")
        // Dump the path of the selected glyph at design units
        if let path = CTFontCreatePathForGlyph(radicalFont.ctFont, glyph.glyph, nil) {
            var lastRisingDy: CGFloat = 0, lastRisingDx: CGFloat = 0
            var px: CGFloat?=nil, py: CGFloat?=nil
            path.applyWithBlock { e in
                let el = e.pointee
                func add(x: CGFloat, y: CGFloat) {
                    if let x0 = px, let y0 = py {
                        let dx = x-x0, dy = y-y0
                        if dy > 0 { lastRisingDy=dy; lastRisingDx=dx }
                    }
                    px=x; py=y
                }
                switch el.type {
                case .moveToPoint: px=el.points[0].x; py=el.points[0].y
                case .addLineToPoint: add(x:el.points[0].x, y:el.points[0].y)
                case .addCurveToPoint: add(x:el.points[2].x, y:el.points[2].y)
                default: break
                }
            }
            if lastRisingDx > 0 {
                print("[RADICAL] last rising edge: dy=\(lastRisingDy) dx=\(lastRisingDx) slope=\(lastRisingDy/lastRisingDx)")
                print("[RADICAL] → radicalSlope = \(lastRisingDy)/\(lastRisingDx) = \(lastRisingDy/lastRisingDx)")
            }
        }

        // Shift glyph to cover radicand's descent first.
        glyph.shiftDown = max(0, radicand.descent - glyph.rawDescent)

        // Compare glyph's visual top (after descent shift) against bar-needed height.
        let glyphTopAfterShift = glyph.rawAscent - glyph.shiftDown
        let barNeeded = radicand.ascent + clearance + ruleThickness
        let needsExtender = glyphTopAfterShift < barNeeded

        // If glyph top exceeds bar height, distribute excess to clearance.
        let excess = glyphTopAfterShift - barNeeded
        if excess > 0 {
            clearance += excess / 2
        }
        let adjustedRadicalAscent = max(barNeeded, ruleThickness + clearance + radicand.ascent)

        if needsExtender {
            // ---- Extender path ----
            // Replace the radical glyph with XITS construction glyph.
            // STIX2 radical variants have a flat horizontal top that breaks the
            // extender diagonal connector geometry. XITS variants have the
            // classic check-mark body shape. Use the XITS glyph for both the
            // visible √ symbol and the extender geometry math.
            let xitsConstructionFont = MathFont.xitsFont.mtfont(size: radicalFontSize)
            let xitsMT = xitsConstructionFont.mathTable
            if let constGlyph = getRadicalGlyph(withHeight: radicalHeight,
                                                 mt: xitsMT, radicalFont: xitsConstructionFont) {
                glyph.glyph = constGlyph.glyph
                glyph.rawAscent = constGlyph.rawAscent
                glyph.rawDescent = constGlyph.rawDescent
                glyph.width = constGlyph.width
                glyph.font = xitsConstructionFont
            }

            // Anchor XITS construction body to radicand's descent.
            glyph.shiftDown = max(0, radicand.descent - glyph.rawDescent)

            let origGlyphWidth = glyph.width
            let origGlyphAscent = glyph.rawAscent

            // barY in MTRadicalDisplay draw space.
            let barY = adjustedRadicalAscent - ruleThickness / 2

            // Visual top of the construction glyph after bottom-anchoring.
            let visualTop = origGlyphAscent - glyph.shiftDown

            // Gap from visual top to bar center.
            let deltaY = barY - visualTop

            if deltaY > 0 {
                let slope = Self.radicalSlope
                let deltaX = deltaY / slope

                glyph.rawAscent = origGlyphAscent + deltaY
                glyph.width = origGlyphWidth + deltaX

                // Diagonal from visual top-right of construction glyph body to bar start.
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
                    // TeX Rule 11: degree is in scriptscript style, not cramped.
                    let degTS = Typesetter(font: font, style: .scriptOfScript,
                                           textColor: textColor, fontStyle: fontStyle)
                    if let degree = degTS.renderNode(degNode) {
                        radical.setDegree(degree, fontMetrics: mt)
                    }
                }
                return radical
            }

            // deltaY <= 0: construction glyph is tall enough — skip extender.
            // Fall through to the non-extender path with original glyph geometry.
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
            // TeX Rule 11: degree is in scriptscript style, not cramped.
            let degTS = Typesetter(font: font, style: .scriptOfScript,
                                   textColor: textColor, fontStyle: fontStyle)
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
        guard let segmentNodes = node.childNodes, !segmentNodes.isEmpty else { return nil }

        let metaParts = (node.text ?? ".\0.").split(separator: "\0", omittingEmptySubsequences: false).map(String.init)
        let leftDelim = metaParts.count > 0 ? metaParts[0] : "."
        let rightDelim = metaParts.count > 1 ? metaParts[1] : "."
        let middleDelims = metaParts.count > 2 ? Array(metaParts.dropFirst(2)) : []

        let mt = font.mathTable
        let delimiterPadding: CGFloat = 0
        let subTS = Typesetter(font: font, style: style, cramped: self.cramped,
                               textColor: textColor, fontStyle: fontStyle)

        var segments: [MTDisplay] = []
        for segNode in segmentNodes {
            if let inner = subTS.createDisplay(segNode.childNodes ?? []) {
                segments.append(inner)
            }
        }
        guard !segments.isEmpty else { return nil }

        let maxH = segments.map { $0.ascent + $0.descent }.max() ?? mt.axisHeight * 2
        let delta = max(maxH * 0.5 - mt.axisHeight, mt.axisHeight)
        let glyphHeight = max((delta / 500) * 901, 2 * delta - 5)

        func makeDelimiter(_ delim: String) -> MTDisplay? {
            guard delim != "." else { return nil }
            guard let gd = makeDelimiterGlyph(delim, height: glyphHeight) else { return nil }
            gd.position = .zero
            return gd
        }

        var elements: [MTDisplay] = []
        var x: CGFloat = 0

        if let lg = makeDelimiter(leftDelim) {
            lg.position.x = x
            elements.append(lg)
            x += lg.width + delimiterPadding
        }

        for (idx, inner) in segments.enumerated() {
            inner.position = CGPoint(x: x, y: 0)
            elements.append(inner)
            x += inner.width + delimiterPadding
            if idx < middleDelims.count, let md = makeDelimiter(middleDelims[idx]) {
                md.position.x = x
                elements.append(md)
                x += md.width + delimiterPadding
            }
        }

        if let rg = makeDelimiter(rightDelim) {
            rg.position.x = x
            elements.append(rg)
        }

        return MTMathListDisplay(withDisplays: elements, range: node.indexRange)
    }

    /// `\binom` delimiters: MathJax-sized `\biggl`/`\biggr` (fixed 2.143em cap).
    private func wrapBinomWithDelimiters(_ inner: MTDisplay) -> MTDisplay {
        let delimH = TeXStackMetrics.binomDelimCap(font.size)
        var elements: [MTDisplay] = []
        var x: CGFloat = 0
        guard let lg = makeDelimiterGlyph("(", height: delimH, tightFit: true) else {
            return wrapWithDelimiters(inner, left: "(", right: ")", minHeight: delimH)
        }
        lg.position = .zero
        elements.append(lg)
        x = lg.width
        let innerCenter = (inner.ascent - inner.descent) / 2
        let delimCenter = (lg.ascent - lg.descent) / 2
        let yAlign = delimCenter - innerCenter
        inner.position = CGPoint(x: x, y: yAlign)
        elements.append(inner)
        x += inner.width
        if let rg = makeDelimiterGlyph(")", height: delimH, tightFit: true) {
            rg.position = CGPoint(x: x, y: 0)
            elements.append(rg)
        }
        return MTMathListDisplay(withDisplays: elements, range: inner.range)
    }

    private func wrapWithDelimiters(_ inner: MTDisplay, left: String, right: String,
                                    minHeight: CGFloat? = nil) -> MTDisplay {
        let mt = font.mathTable
        let h = inner.ascent + inner.descent
        let glyphHeight = max(h, minHeight ?? mt.axisHeight * 2)
        var elements: [MTDisplay] = []
        var x: CGFloat = 0
        if let lg = makeDelimiterGlyph(left, height: glyphHeight) {
            lg.position = .zero
            elements.append(lg)
            x = lg.width
        }
        inner.position = CGPoint(x: x, y: 0)
        elements.append(inner)
        x += inner.width
        if let rg = makeDelimiterGlyph(right, height: glyphHeight) {
            rg.position = CGPoint(x: x, y: 0)
            elements.append(rg)
        }
        return MTMathListDisplay(withDisplays: elements, range: inner.range)
    }

    /// Builds a single stretchy delimiter glyph using variants or assembly.
    /// When the largest pre‑built variant is too short, falls back to glyph
    /// assembly (stacked parts: bottom + extender + top).
    private func makeDelimiterGlyph(_ delim: String, height: CGFloat, tightFit: Bool = false) -> MTDisplay? {
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

        let parts = mt.getVerticalGlyphAssembly(forGlyph: baseGlyph)
        var glyphAscent: CGFloat = 0, glyphDescent: CGFloat = 0, glyphWidth: CGFloat = 0
        // Binom tight-fit: prefer the text-style variant tier, allowing slight protrusion
        // instead of jumping to a taller assembly (MathJax `\biggl` stays compact).
        let variantTarget = tightFit ? height * 0.92 : height
        let glyph = findGlyph(baseGlyph, withHeight: variantTarget,
                              using: mt,
                              measurementFont: font,
                              glyphAscent: &glyphAscent,
                              glyphDescent: &glyphDescent,
                              glyphWidth: &glyphWidth)
        let variantH = glyphAscent + glyphDescent

        if tightFit {
            var best: MTDisplay?
            var bestH = CGFloat.infinity
            if variantH >= height * 0.96 {
                let gd = MTGlyphDisplay(glyph: glyph, range: NSRange(location: NSNotFound, length: 0), font: font)
                gd.rawAscent = glyphAscent
                gd.rawDescent = glyphDescent
                gd.width = glyphWidth
                gd.shiftDown = 0.5 * (glyphAscent - glyphDescent) - axis
                gd.position = .zero
                best = gd
                bestH = variantH
            }
            if !parts.isEmpty, let asm = buildAssemblyDisplay(parts: parts, targetHeight: height, axis: axis) {
                let asmH = asm.ascent + asm.descent
                if asmH >= height, asmH < bestH {
                    best = asm
                    bestH = asmH
                }
            }
            if let best { return best }
        } else if variantH < height, !parts.isEmpty,
                  let asm = buildAssemblyDisplay(parts: parts, targetHeight: height, axis: axis) {
            return asm
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
        let gap = max(0, targetHeight - nonExtHeight)
        let extCount: Int
        if extAdv > 0.001 {
            var count = Int(floor(gap / extAdv))
            if nonExtHeight + CGFloat(count) * extAdv < targetHeight { count += 1 }
            extCount = count
        } else {
            extCount = 0
        }

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
    ///   - Each row enforces `\@arstrut` minimum height/depth (0.7/0.3 × baselineskip)
    ///   - Rows are stacked using `\normalbaselines` (`\baselineskip` / `\lineskip`)
    ///   - The entire array is axis-centered so its vertical midpoint sits on the math axis
    private func renderArray(_ node: ASTNode) -> MTDisplay? {
        guard let rows = node.childNodes, !rows.isEmpty else { return nil }

        let mt = font.mathTable
        let mu = mt.muUnit
        let colGap = mu * 18   // inter‑column space (2 × 9mu per TeX)
        // TeX matrix cells use \textstyle by default.
        // A fraction inside a textstyle cell then cascades to scriptstyle
        // for numerator/denominator (via renderFraction's Rule 15e).
        let cellStyle: MTLineStyle = .text
        let cellFont = font
        // TeX matrix row spacing: \normalbaselines at 10pt = \baselineskip=12pt,
        // \lineskip=1pt, \lineskiplimit=0pt (per PROGRESS.md)
        let baselineSkip = font.size * 1.2
        let lineSkip = font.size * 0.1
        let lineSkipLimit: CGFloat = 0

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
                // Matrix cells render in \textstyle (not \displaystyle)
                // Use cramped style for matrix cells
                let sub = Typesetter(font: cellFont, style: cellStyle, cramped: true,
                                     textColor: textColor, fontStyle: fontStyle)
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

        // TeX \@arstrutbox (lttab.dtx): every array row gets minimum height 0.7×baselineskip
        // and depth 0.3×baselineskip so short cells still occupy a full text line.
        let arstrutHeight = baselineSkip * 0.7
        let arstrutDepth = baselineSkip * 0.3
        for ri in 0..<rows.count {
            rowAscent[ri] = max(rowAscent[ri], arstrutHeight)
            rowDescent[ri] = max(rowDescent[ri], arstrutDepth)
        }

        // Build rows: cells baseline-aligned (position.y = 0 in row space)
        var rowDisplays = [MTDisplay]()
        for (ri, cells) in allCells.enumerated() {
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
            row.ascent = rowAscent[ri]
            row.descent = rowDescent[ri]
            rowDisplays.append(row)
        }

        // ---- Vertical stacking (TeX \halign rule) ----
        // TeX §22: \normalbaselines at 10pt = \baselineskip=12pt, \lineskip=1pt
        // For row i > 0:
        //   natural = baselineskip - descent[i-1] - ascent[i]
        //   If natural >= lineskiplimit → space by baselineskip (uniform)
        //   Else → space by lineskip (content-bottom to content-top)

        rowDisplays[0].position = CGPoint(x: 0, y: 0)
        var prevBaseline: CGFloat = 0

        for ri in 1..<rowDisplays.count {
            let prevDepth = rowDescent[ri-1]
            let curHeight = rowAscent[ri]
            let naturalGap = baselineSkip - prevDepth - curHeight
            if naturalGap >= lineSkipLimit {
                prevBaseline -= baselineSkip
            } else {
                let prevBottom = prevBaseline - prevDepth
                prevBaseline = prevBottom - lineSkip - curHeight
            }
            rowDisplays[ri].position = CGPoint(x: 0, y: prevBaseline)
        }

        // Content spans from y=0 (first baseline + ascent) to last baseline - last descent
        let contentTop = rowAscent[0]
        let lastPos = rowDisplays.last!.position.y
        let contentBottom = lastPos - rowDescent[rowDescent.count - 1]
        let contentMid = (contentTop + contentBottom) / 2

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

    // MARK: - Color

    private func renderColor(_ node: ASTNode) -> MTDisplay? {
        guard let children = node.childNodes, !children.isEmpty else { return nil }
        guard let colorName = node.text, !colorName.isEmpty else { return createDisplay(children) }
        let color = parseColor(colorName)
        let subTS = Typesetter(font: font, style: style, cramped: self.cramped,
                               textColor: color?.cgColor ?? textColor, fontStyle: fontStyle)
        guard let inner = subTS.createDisplay(children) else { return nil }
        if let c = color { inner.textColor = c }
        return inner
    }

    private func renderColorbox(_ node: ASTNode) -> MTDisplay? {
        guard let children = node.childNodes, !children.isEmpty else { return nil }
        let colorStr = node.text ?? ""
        let parts = colorStr.split(separator: "\0", maxSplits: 1)
        let fillColorName = parts.count > 0 ? String(parts[0]) : ""
        let borderColorName = parts.count > 1 ? String(parts[1]) : ""
        let fillColor = fillColorName.isEmpty ? MTColor.black : (parseColor(fillColorName) ?? MTColor.black)
        let borderColor = borderColorName.isEmpty ? MTColor.black : (parseColor(borderColorName) ?? MTColor.black)
        let subTS = Typesetter(font: font, style: style, cramped: self.cramped,
                               textColor: textColor, fontStyle: fontStyle)
        guard let inner = subTS.createDisplay(children) else { return nil }
        let box = MTColorboxDisplay(inner: inner, fillColor: fillColor, borderColor: borderColor, padding: 0)
        box.range = node.indexRange
        return box
    }

    // MARK: - Accents

    private func isSingleCharAccentee(_ node: ASTNode) -> Bool {
        guard let children = node.childNodes, children.count == 1 else { return false }
        let inner = children[0]
        guard inner.childNodes == nil else { return false }
        guard let text = inner.text, text.unicodeScalars.count == 1 else { return false }
        if inner.type == .supsub { return false }
        return true
    }

    /// TeX Appendix G, Rule 12: accent horizontal position.
    /// For a single‑character accentee, the accent is placed at
    ///   h = Atop(nucleus) − Atop(accent)
    /// where the nucleus is the math‑italicized glyph actually drawn.
    /// Atop is the TopAccentAttachment value from the MATH table.
    /// For multi‑character accentees, the accent is centered.
    private func getSkew(accentNode: ASTNode, accentee: MTDisplay, accentGlyph: CGGlyph) -> CGFloat {
        let mt = font.mathTable
        let accentAdjustment = mt.getTopAccentAdjustment(accentGlyph)
        if !isSingleCharAccentee(accentNode) {
            // Multi‑char: center the accent over the accentee
            return (accentee.width - accentee.width) / 2  // will be overridden by caller to (aw-accentBase.width)/2
        }

        // Single‑char: extract the actual rendered (math‑italic) glyph
        // and get its TopAccentAttachment value (Atop in TeX notation).
        var accenteeAdjustment: CGFloat = accentee.width / 2

        // Walk display tree to find the leaf glyph — the accentee may be
        // wrapped in MTMathListDisplay, MTAccentDisplay, etc.
        let leafGlyph = findLeafGlyph(in: accentee)
        if let leaf = leafGlyph {
            accenteeAdjustment = mt.getTopAccentAdjustment(leaf)
        }

        // TeX Rule 12: accent x‑position = Atop(nucleus) − Atop(accent)
        return accenteeAdjustment - accentAdjustment
    }

    /// Recursively walks a display tree to find the first leaf glyph.
    /// Returns nil if no glyph can be extracted (falls back to center).
    private func findLeafGlyph(in display: MTDisplay) -> CGGlyph? {
        // Direct CTLine: extract from glyph runs
        if let ctDisplay = display as? MTCTLineDisplay,
           let line = ctDisplay.line,
           let runs = CTLineGetGlyphRuns(line) as? [CTRun] {
            for run in runs.reversed() {
                let glyphCount = CTRunGetGlyphCount(run)
                if glyphCount > 0 {
                    var glyphs = [CGGlyph](repeating: 0, count: glyphCount)
                    CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
                    return glyphs[glyphCount - 1]
                }
            }
        }
        // Direct glyph display
        if let gd = display as? MTGlyphDisplay {
            return gd.glyph
        }
        // Walk into wrapper displays
        if let list = display as? MTMathListDisplay {
            for sub in list.subDisplays {
                if let glyph = findLeafGlyph(in: sub) { return glyph }
            }
        }
        if let accent = display as? MTAccentDisplay {
            if let aee = accent.accentee, let glyph = findLeafGlyph(in: aee) { return glyph }
        }
        if let rad = display as? MTRadicalDisplay {
            if let radicand = rad.radicand, let glyph = findLeafGlyph(in: radicand) { return glyph }
        }
        if let frac = display as? MTFractionDisplay {
            if let n = frac.numerator, let glyph = findLeafGlyph(in: n) { return glyph }
        }
        if let ss = display as? MTSupSubDisplay {
            if let b = ss.base, let glyph = findLeafGlyph(in: b) { return glyph }
        }
        return nil
    }

    private func findHorizontalVariantGlyph(_ glyph: CGGlyph, withMaxWidth maxWidth: CGFloat,
                                             glyphAscent: inout CGFloat, glyphDescent: inout CGFloat,
                                             glyphWidth: inout CGFloat) -> CGGlyph {
        let mt = font.mathTable
        let variants = mt.getHorizontalVariantsForGlyph(glyph)
        guard !variants.isEmpty else { glyphAscent = 0; glyphDescent = 0; glyphWidth = 0; return glyph }
        let n = variants.count
        var gs = [CGGlyph](repeating: 0, count: n)
        var bb = [CGRect](repeating: .zero, count: n)
        var ad = [CGSize](repeating: .zero, count: n)
        for (i, v) in variants.enumerated() { gs[i] = CGGlyph(truncating: v ?? NSNumber(value: 0)) }
        CTFontGetBoundingRectsForGlyphs(font.ctFont, .horizontal, &gs, &bb, n)
        CTFontGetAdvancesForGlyphs(font.ctFont, .horizontal, &gs, &ad, n)
        var curGlyph = gs[0]
        for i in 0..<n {
            if ad[i].width > maxWidth {
                if i == 0 { glyphWidth = ad[0].width; glyphAscent = max(0, bb[0].maxY); glyphDescent = max(0, -bb[0].minY) }
                return curGlyph
            }
            curGlyph = gs[i]; glyphWidth = ad[i].width; glyphAscent = max(0, bb[i].maxY); glyphDescent = max(0, -bb[i].minY)
        }
        return curGlyph
    }

    private func buildHorizontalAssemblyDisplay(parts: [MTFontMathTable.GlyphPart], targetWidth: CGFloat,
                                                  ascent: inout CGFloat, descent: inout CGFloat) -> MTDisplay? {
        guard parts.count >= 2 else { return nil }
        var extenderPart: MTFontMathTable.GlyphPart?
        var fixedWidth: CGFloat = 0
        for p in parts { if p.isExtender { extenderPart = p } else { fixedWidth += p.fullAdvance } }
        guard let ext = extenderPart else { return nil }
        let remaining = max(0, targetWidth - fixedWidth)
        let extCount: Int
        if remaining <= 0 {
            extCount = 0
        } else if ext.fullAdvance > 0 {
            extCount = max(1, Int(ceil(remaining / ext.fullAdvance)))
        } else {
            extCount = 0
        }
        var glyphs: [CGGlyph] = []; var offsets: [CGFloat] = []; var x: CGFloat = 0
        var prev: MTFontMathTable.GlyphPart?
        for p in parts {
            if p.isExtender {
                for _ in 0..<extCount {
                    if let pr = prev { x -= min(pr.endConnectorLength, p.startConnectorLength) }
                    glyphs.append(CGGlyph(p.glyph)); offsets.append(x); x += p.fullAdvance; prev = p
                }
            } else {
                if let pr = prev { x -= min(pr.endConnectorLength, p.startConnectorLength) }
                glyphs.append(CGGlyph(p.glyph)); offsets.append(x); x += p.fullAdvance; prev = p
            }
        }
        var ma: CGFloat = 0, md: CGFloat = 0
        for g in glyphs { var gv = g; let b = CTFontGetBoundingRectsForGlyphs(font.ctFont, .horizontal, &gv, nil, 1); ma = max(ma, max(0, b.maxY)); md = max(md, max(0,-b.minY)) }
        ascent = ma; descent = md
        let disp = MTGlyphConstructionDisplay()
        disp.glyphs = glyphs; disp.positions = offsets.map { CGPoint(x: $0, y: 0) }; disp.font = font
        disp.width = x; disp.ascent = ascent; disp.descent = descent; disp.position = .zero
        return disp
    }

    /// Stretch a horizontal glyph construction to an exact layout width (MathJax `stretchy-h` box).
    /// Not a TeXbook rule — bridges OpenType assembly advance vs desired box width.
    private func scaleHorizontalConstruction(_ display: MTDisplay, toWidth target: CGFloat) {
        guard let c = display as? MTGlyphConstructionDisplay, c.width > 0 else { return }
        guard abs(c.width - target) > 0.01 else { c.width = target; return }
        let scale = target / c.width
        for i in 0..<c.positions.count { c.positions[i].x *= scale }
        c.width = target
    }

    private static let stretchyAccentOperators: [String: String] = [
        "overrightarrow": "\u{2192}",
        "overleftarrow": "\u{2190}",
        "overleftrightarrow": "\u{2194}",
        "overrightharpoonup": "\u{21C0}",
        "overrightharpoondown": "\u{21C1}",
        "overleftharpoonup": "\u{21BC}",
        "overleftharpoondown": "\u{21BD}",
        "overrightharpoon": "\u{21C0}",
        "overleftharpoon": "\u{21BC}",
        "overgroup": "\u{23E0}",
        "overlinesegment": "\u{23DC}",
        "widecheck": "\u{030C}",
    ]
    private static let alwaysStretchyAccents: Set<String> = [
        "overgroup", "overlinesegment", "widecheck",
        "overrightharpoonup", "overrightharpoondown",
        "overleftharpoonup", "overleftharpoondown",
        "overrightharpoon", "overleftharpoon",
    ]
    private static let stretchyAccentKernNames: Set<String> = [
        "overrightarrow", "overleftarrow", "overleftrightarrow", "vec",
        "overrightharpoonup", "overrightharpoondown",
        "overleftharpoonup", "overleftharpoondown",
        "overrightharpoon", "overleftharpoon",
    ]

    private func glyphForCharacter(_ ch: String) -> CGGlyph? {
        guard let scalar = ch.unicodeScalars.first else { return nil }
        let up = UnsafeMutablePointer<UniChar>.allocate(capacity: 1); defer { up.deallocate() }
        up[0] = UniChar(scalar.value)
        var g: CGGlyph = 0
        guard CTFontGetGlyphsForCharacters(font.ctFont, up, &g, 1) else { return nil }
        return g
    }

    private func glyphBounds(_ glyphs: [CGGlyph]) -> (minY: CGFloat, maxY: CGFloat) {
        var minY = CGFloat.infinity, maxY = -CGFloat.infinity
        for g in glyphs {
            var gv = g
            let b = CTFontGetBoundingRectsForGlyphs(font.ctFont, .horizontal, &gv, nil, 1)
            minY = min(minY, b.minY); maxY = max(maxY, b.maxY)
        }
        if minY == .infinity { return (0, 0) }
        return (minY, maxY)
    }

    /// Max Y of a horizontal accent assembly (or single glyph) at `width`.
    private func accentInkMaxY(baseGlyph: CGGlyph, targetWidth: CGFloat) -> CGFloat {
        var ga: CGFloat = 0, gd: CGFloat = 0, gw: CGFloat = 0
        let g = findHorizontalVariantGlyph(baseGlyph, withMaxWidth: targetWidth,
                                           glyphAscent: &ga, glyphDescent: &gd, glyphWidth: &gw)
        if gw < targetWidth * 0.95 {
            let parts = font.mathTable.getHorizontalGlyphAssembly(forGlyph: baseGlyph)
            if parts.count >= 2 {
                var ma = ga, md = gd
                if let asm = buildHorizontalAssemblyDisplay(parts: parts, targetWidth: targetWidth,
                                                            ascent: &ma, descent: &md) as? MTGlyphConstructionDisplay {
                    return glyphBounds(asm.glyphs).maxY
                }
            }
        }
        var gv = g
        return CTFontGetBoundingRectsForGlyphs(font.ctFont, .horizontal, &gv, nil, 1).maxY
    }

    /// Operator arrows (U+219x) are axis-centered; shift up so ink matches combining marks at Rule 12 height.
    private func applyStretchyOperatorArrowShift(accent: MTDisplay, accentName: String,
                                                 accenteeWidth: CGFloat) {
        guard let combChar = MTMathAtomFactory.accents[accentName],
              let combGlyph = glyphForCharacter(combChar) else { return }
        let combMaxY = accentInkMaxY(baseGlyph: combGlyph, targetWidth: accenteeWidth)
        let opBounds: (minY: CGFloat, maxY: CGFloat)
        if let construction = accent as? MTGlyphConstructionDisplay {
            opBounds = glyphBounds(construction.glyphs)
        } else if let glyphDisp = accent as? MTGlyphDisplay {
            var gv = glyphDisp.glyph
            let b = CTFontGetBoundingRectsForGlyphs(font.ctFont, .horizontal, &gv, nil, 1)
            opBounds = (b.minY, b.maxY)
        } else { return }
        let topAlign = opBounds.maxY - combMaxY
        if let construction = accent as? MTGlyphConstructionDisplay {
            construction.shiftDown = topAlign
        } else if let glyphDisp = accent as? MTGlyphDisplay {
            glyphDisp.shiftDown = topAlign
        }
    }

    private func renderAccent(_ node: ASTNode) -> MTDisplay? {
        guard let children = node.childNodes, !children.isEmpty else { return nil }
        guard let accentee = createDisplay(children) else { return nil }
        guard let accentName = node.text, !accentName.isEmpty else { return accentee }
        let mt = font.mathTable

        // For multi‑char accentees with \bar, use the standalone macron (U+00AF)
        // instead of the combining macron (U+0304), because the combining
        // mark has zero advance width and no horizontal variants in the MATH table.
        // Multi-char stretchy arrows stretch U+2190/2192/2194 (MathJax-sized ink)
        // but stay at Rule 12 height; shiftDown aligns ink with combining marks.
        let isMultiChar = !isSingleCharAccentee(node)
        let usesOperatorArrow = Self.stretchyAccentOperators[accentName] != nil
            && (isMultiChar || accentName.contains("harpoon") || Self.alwaysStretchyAccents.contains(accentName))
        let effectiveAccentChar: String
        if accentName == "bar" && isMultiChar {
            effectiveAccentChar = "\u{00AF}"  // ¯  standalone macron
        } else if usesOperatorArrow, let op = Self.stretchyAccentOperators[accentName] {
            effectiveAccentChar = op
        } else {
            effectiveAccentChar = MTMathAtomFactory.accents[accentName] ?? ""
        }
        guard !effectiveAccentChar.isEmpty else { return accentee }
        guard let ch = effectiveAccentChar.unicodeScalars.first else { return accentee }
        let up = UnsafeMutablePointer<UniChar>.allocate(capacity: 1); defer { up.deallocate() }
        up[0] = UniChar(ch.value)
        var accentGlyph: CGGlyph = 0
        guard CTFontGetGlyphsForCharacters(font.ctFont, up, &accentGlyph, 1) else { return accentee }
        let baseGlyph = accentGlyph
        let aw = accentee.width
        var ga: CGFloat = 0, gd: CGFloat = 0, gw: CGFloat = 0
        let accentBase: MTDisplay
        if isSingleCharAccentee(node) {
            var gv = accentGlyph; let a = CTFontGetAdvancesForGlyphs(font.ctFont, .horizontal, &gv, nil, 1)
            let b = CTFontGetBoundingRectsForGlyphs(font.ctFont, .horizontal, &gv, nil, 1)
            ga = max(0, b.maxY); gd = max(0, -b.minY); gw = a
            let g = MTGlyphDisplay(glyph: accentGlyph, range: node.indexRange, font: font)
            g.rawAscent = ga; g.rawDescent = gd; g.width = gw
            accentBase = g
        } else {
            accentGlyph = findHorizontalVariantGlyph(accentGlyph, withMaxWidth: aw, glyphAscent: &ga, glyphDescent: &gd, glyphWidth: &gw)
            if accentName == "bar" && gw < aw * 0.8 {
                // Draw a custom rule using Overbar metrics from the MATH table.
                let ruleThickness = mt.overbarRuleThickness
                let rule = MTRuleDisplay(width: aw, thickness: ruleThickness)
                rule.position = .zero
                ga = ruleThickness
                accentBase = rule
            } else if gw < aw * 0.95 {
                let parts = mt.getHorizontalGlyphAssembly(forGlyph: baseGlyph)
                if parts.count >= 2,
                   let asm = buildHorizontalAssemblyDisplay(parts: parts, targetWidth: aw,
                                                            ascent: &ga, descent: &gd) {
                    accentBase = asm
                } else {
                    let g = MTGlyphDisplay(glyph: accentGlyph, range: node.indexRange, font: font)
                    g.rawAscent = ga; g.rawDescent = gd; g.width = gw
                    accentBase = g
                }
            } else {
                let g = MTGlyphDisplay(glyph: accentGlyph, range: node.indexRange, font: font)
                g.rawAscent = ga; g.rawDescent = gd; g.width = gw
                accentBase = g
            }
        }
        let ax: CGFloat, ay: CGFloat
        if accentBase is MTRuleDisplay {
            // Position the rule's bottom edge at the same visual height as the
            // combining macron's visual bar bottom.
            // Combining macron (U+0304): bbox.origin.y=18 (at 30pt), bar sits
            // ~18 units above the glyph baseline.
            let delta = min(accentee.ascent, mt.accentBaseHeight)
            let macronBarBottomOffset: CGFloat = {
                let combiningMacron = "\u{0304}"
                let cmUp = UnsafeMutablePointer<UniChar>.allocate(capacity: 1); defer { cmUp.deallocate() }
                cmUp[0] = UniChar(combiningMacron.unicodeScalars.first!.value)
                var cmGlyph: CGGlyph = 0
                if CTFontGetGlyphsForCharacters(font.ctFont, cmUp, &cmGlyph, 1) {
                    let cmBbox = CTFontGetBoundingRectsForGlyphs(font.ctFont, .horizontal, &cmGlyph, nil, 1)
                    return cmBbox.origin.y
                }
                return 0
            }()
            ax = (aw - accentBase.width) / 2
            ay = accentee.ascent - delta + macronBarBottomOffset
        } else if accentName == "arc" {
            var ag = accentGlyph; let b = CTFontGetBoundingRectsForGlyphs(font.ctFont, .horizontal, &ag, nil, 1)
            ax = isSingleCharAccentee(node) ? getSkew(accentNode: node, accentee: accentee, accentGlyph: accentGlyph) : (aw - accentBase.width) / 2
            ay = accentee.ascent - max(0, b.origin.y) + 1
        } else {
            let delta = min(accentee.ascent, mt.accentBaseHeight)
            ax = isSingleCharAccentee(node) ? getSkew(accentNode: node, accentee: accentee, accentGlyph: accentGlyph) : (aw - accentBase.width) / 2
            // Rule 12 + 1.5μ kern (between 0 and thinmuskip) for stretchy arrows.
            let accentKern = Self.stretchyAccentKernNames.contains(accentName) ? 1.5 * mt.muUnit : 0
            ay = accentee.ascent - delta + accentKern
        }
        if usesOperatorArrow {
            applyStretchyOperatorArrowShift(accent: accentBase, accentName: accentName, accenteeWidth: aw)
        }
        accentBase.position = CGPoint(x: ax, y: ay)
        let display = MTAccentDisplay(accent: accentBase, accentee: accentee, range: node.indexRange)
        display.position = .zero
        return display
    }

    private static let horizBraceGlyphs: [String: String] = [
        "overbrace": "\u{23DE}",
        "underbrace": "\u{23DF}",
    ]

    private func buildStretchyGlyphDisplay(baseGlyph: CGGlyph, accentName: String,
                                           targetWidth: CGFloat, node: ASTNode) -> MTDisplay? {
        var ga: CGFloat = 0, gd: CGFloat = 0, gw: CGFloat = 0
        let g = findHorizontalVariantGlyph(baseGlyph, withMaxWidth: targetWidth,
                                         glyphAscent: &ga, glyphDescent: &gd, glyphWidth: &gw)
        if gw < targetWidth * 0.95 {
            let parts = font.mathTable.getHorizontalGlyphAssembly(forGlyph: baseGlyph)
            if parts.count >= 2,
               let asm = buildHorizontalAssemblyDisplay(parts: parts, targetWidth: targetWidth,
                                                        ascent: &ga, descent: &gd) {
                return asm
            }
        }
        let disp = MTGlyphDisplay(glyph: g, range: node.indexRange, font: font)
        disp.rawAscent = ga; disp.rawDescent = gd; disp.width = gw
        return disp
    }

    private func renderHorizBrace(_ node: ASTNode) -> MTDisplay? {
        guard let children = node.childNodes, let child = children.first else { return nil }
        guard let accentee = createDisplay([child]) else { return nil }
        guard let accentName = node.text, let chStr = Self.horizBraceGlyphs[accentName] else { return accentee }
        guard let ch = chStr.unicodeScalars.first else { return accentee }
        let up = UnsafeMutablePointer<UniChar>.allocate(capacity: 1); defer { up.deallocate() }
        up[0] = UniChar(ch.value)
        var baseGlyph: CGGlyph = 0
        guard CTFontGetGlyphsForCharacters(font.ctFont, up, &baseGlyph, 1) else { return accentee }
        guard let accentBase = buildStretchyGlyphDisplay(baseGlyph: baseGlyph, accentName: accentName,
                                                         targetWidth: accentee.width, node: node) else { return accentee }
        let placeAbove = accentName == "overbrace"
        let fs = font.size
        let bodyKern = TeXStackMetrics.horizBraceBodyKern(fs)
        let ax = (accentee.width - accentBase.width) / 2
        accentee.position = .zero
        let ay: CGFloat
        if placeAbove {
            let trim = TeXStackMetrics.horizBraceAscentTrim(fs)
            ay = accentee.ascent + bodyKern - accentBase.ascent * trim
        } else {
            ay = -(accentee.descent + bodyKern * 0.35 + accentBase.ascent * 0.45)
        }
        accentBase.position = CGPoint(x: ax, y: ay)
        return MTAccentDisplay(accent: accentBase, accentee: accentee, range: node.indexRange, placeAbove: placeAbove)
    }

    private func renderStack(_ node: ASTNode) -> MTDisplay? {
        guard let children = node.childNodes, children.count >= 2 else { return nil }
        let scriptAbove = node.text == "overset"
        let scriptNode = children[0]
        let baseNode = children[1]
        let subTS = Typesetter(font: font, style: style, cramped: cramped,
                               textColor: textColor, fontStyle: fontStyle)
        let scriptStyleTS = Typesetter(font: font, style: scriptStyle(), cramped: true,
                                       textColor: textColor, fontStyle: fontStyle)
        guard let script = scriptStyleTS.renderNode(scriptNode),
              let base = subTS.renderNode(baseNode) else { return nil }
        let fs = font.size
        let disp = MTStackDisplay(script: script, base: base, scriptAbove: scriptAbove, range: node.indexRange)
        disp.width = max(script.width, base.width)
        base.position = .zero
        if scriptAbove {
            // KaTeX assembleSupSub.ts: limits sup on op base (overset)
            let kern = max(TeXStackMetrics.bigOpSpacing1(fs),
                           TeXStackMetrics.bigOpSpacing3(fs) - script.descent)
            script.position = CGPoint(x: (disp.width - script.width) / 2,
                                      y: base.ascent + kern + script.descent)
            disp.ascent = script.position.y + script.ascent + TeXStackMetrics.bigOpSpacing5(fs)
            disp.descent = base.descent
        } else {
            // KaTeX assembleSupSub.ts: limits sub on op base (underset)
            let kern = max(TeXStackMetrics.bigOpSpacing2(fs),
                           TeXStackMetrics.bigOpSpacing4(fs) - script.ascent)
            script.position = CGPoint(x: (disp.width - script.width) / 2,
                                      y: -(base.descent + kern + script.ascent))
            disp.ascent = base.ascent
            disp.descent = base.descent + kern + script.ascent + script.descent
                + TeXStackMetrics.bigOpSpacing5(fs)
        }
        return disp
    }

    private static let xArrowGlyphs: [String: String] = [
        "xrightarrow": "\u{2192}", "xleftarrow": "\u{2190}",
        "xRightarrow": "\u{21D2}", "xLeftarrow": "\u{21D0}",
        "xleftrightarrow": "\u{2194}", "xLeftrightarrow": "\u{21D4}",
    ]

    private enum XArrowKind { case right, left, both }

    private static func xArrowKind(for name: String) -> XArrowKind {
        let hasLeft = name.localizedCaseInsensitiveContains("left")
        let hasRight = name.localizedCaseInsensitiveContains("right")
        if hasLeft && hasRight { return .both }
        if hasLeft { return .left }
        return .right
    }

    /// AMS extensible arrows (`\xrightarrow`, `\xleftarrow`, …).
    ///
    /// Box width and label placement use KaTeX/AMS rules (`TeXStackMetrics`).
    /// Arrow glyph position may add empirical ink shifts; labels anchor to the unshifted
    /// arrow top so only the stretchy operator moves. Horizontal assembly is scaled to the
    /// label box width (MathJax `stretchy-h` behavior).
    private func renderXArrow(_ node: ASTNode) -> MTDisplay? {
        guard let name = node.text, let arrowChar = Self.xArrowGlyphs[name] else { return nil }
        guard let children = node.childNodes, !children.isEmpty else { return nil }
        let aboveNode = children[0]
        let belowNode = children.count > 1 ? children[1] : nil
        let subTS = Typesetter(font: font, style: .script, cramped: true,
                               textColor: textColor, fontStyle: fontStyle)
        guard let above = subTS.renderNode(aboveNode) else { return nil }
        let below = belowNode.flatMap { subTS.renderNode($0) }
        let fs = font.size
        let kind = Self.xArrowKind(for: name)
        let minW = TeXStackMetrics.xArrowMinWidth(fs)
        let hPad = TeXStackMetrics.xArrowHBoxPad(fs)
        let contentW = max(above.width, below?.width ?? 0)
        var labelW = max(contentW + hPad, minW)
        if kind == .left {
            labelW += TeXStackMetrics.xArrowLeftExtraWidth(fs)
        }
        guard let ch = arrowChar.unicodeScalars.first else { return nil }
        let up = UnsafeMutablePointer<UniChar>.allocate(capacity: 1); defer { up.deallocate() }
        up[0] = UniChar(ch.value)
        var baseGlyph: CGGlyph = 0
        guard CTFontGetGlyphsForCharacters(font.ctFont, up, &baseGlyph, 1),
              let arrow = buildStretchyGlyphDisplay(baseGlyph: baseGlyph, accentName: name,
                                                    targetWidth: labelW, node: node) else { return nil }
        scaleHorizontalConstruction(arrow, toWidth: labelW)
        let axis = font.mathTable.axisHeight
        let padTop = TeXStackMetrics.xArrowLabelPadTop(fs)
        let underPad = TeXStackMetrics.xArrowUnderPadTop(fs)
        let disp = MTXArrowDisplay(above: above, below: below, arrow: arrow, range: node.indexRange)
        disp.width = labelW
        let axisNudge = below != nil ? TeXStackMetrics.xArrowAxisNudge(fs) : 0
        let (shiftX, shiftY): (CGFloat, CGFloat) = switch kind {
        case .right:
            (TeXStackMetrics.xArrowRightShiftX(fs), TeXStackMetrics.xArrowRightShiftY(fs))
        case .left:
            (TeXStackMetrics.xArrowLeftShiftX(fs), TeXStackMetrics.xArrowLeftShiftY(fs))
        case .both:
            (0, TeXStackMetrics.xArrowRightShiftY(fs))
        }
        let baseArrowY = axis - (arrow.ascent - arrow.descent) / 2 - axisNudge
        arrow.position = CGPoint(x: shiftX, y: baseArrowY + shiftY)
        let baseArrowTop = baseArrowY + arrow.ascent
        let arrowBottom = arrow.position.y - arrow.descent
        above.position = CGPoint(x: (disp.width - above.width) / 2,
                                 y: baseArrowTop + above.descent)
        var top = padTop + above.position.y + above.ascent
        var bottom = max(arrow.descent, -(arrow.position.y - arrow.descent))
        if let b = below {
            b.position = CGPoint(x: (disp.width - b.width) / 2,
                                 y: arrowBottom - underPad - b.ascent)
            let belowInkBottom = -(b.position.y - b.descent)
            bottom = max(bottom, belowInkBottom + TeXStackMetrics.xArrowUnderPadBottom(fs))
        }
        disp.ascent = top
        disp.descent = bottom
        return disp
    }

    private func renderOverline(_ node: ASTNode) -> MTDisplay? {
        renderLineDecoration(node, above: true)
    }

    private func renderUnderline(_ node: ASTNode) -> MTDisplay? {
        renderLineDecoration(node, above: false)
    }

    /// TeXbook Rule 9 (overline) / Rule 10 (underline) via OpenType MATH constants.
    private func renderLineDecoration(_ node: ASTNode, above: Bool) -> MTDisplay? {
        guard let children = node.childNodes, !children.isEmpty else { return nil }
        let mt = font.mathTable
        // KaTeX builds overline inner in cramped style (TeXbook Rule 9).
        let subTS = Typesetter(font: font, style: style, cramped: above,
                               textColor: textColor, fontStyle: fontStyle)
        guard let inner = subTS.createDisplay(children) else { return nil }
        inner.position = .zero

        let ruleThickness = above ? mt.overbarRuleThickness : mt.underbarRuleThickness
        let gap = above ? mt.overbarVerticalGap : mt.underbarVerticalGap
        let extra = above ? mt.overbarExtraAscender : mt.underbarExtraDescender
        let rule = MTRuleDisplay(width: inner.width, thickness: ruleThickness)
        if above {
            rule.position = CGPoint(x: 0, y: inner.ascent + gap)
        } else {
            rule.position = CGPoint(x: 0, y: -inner.descent - gap - ruleThickness)
        }

        let list = MTMathListDisplay(withDisplays: [inner, rule], range: node.indexRange)
        if above {
            list.ascent += extra
        } else {
            list.descent += extra
        }
        return list
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
