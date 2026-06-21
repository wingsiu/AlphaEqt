//
//  MTFontMathTable.swift
//  AlphaEqt
//
//  Unified math table for OpenType math fonts, merging SwiftMath MTFontMathTable and MTFontMathTableV2 logic.
//

import Foundation
import CoreGraphics
import CoreText

public class MTFontMathTable {
    public let font: MTFont
    public let fontSize: CGFloat
    public let unitsPerEm: UInt
    private let mTable: NSDictionary
    private let tableLock = NSLock()

    // Constants keys
    private let kConstants = "constants"
    private let kVertVariants = "v_variants"
    private let kHorizVariants = "h_variants"

    private var constants: NSDictionary? { mTable[kConstants] as? NSDictionary }

    public init(font: MTFont, fontSize: CGFloat, unitsPerEm: UInt) {
        self.font = font
        self.fontSize = fontSize
        self.unitsPerEm = unitsPerEm

        guard let table = font.loadMathTable() else {
            fatalError("Failed to load math table for font \(font.font)")
        }
        self.mTable = table

        if let version = mTable["version"] as? String, version != "1.3" {
            fatalError("Invalid version of math table plist: \(version)")
        }
    }

    public func copy(withSize size: CGFloat) -> MTFontMathTable {
        // Note: for async actor cache, you must call font.copy(withSize:) with await
        // Example: let newFont = await font.copy(withSize: size)
        // For synchronous API, call directly.
        MTFontMathTable(font: font, fontSize: size, unitsPerEm: unitsPerEm)
    }

    public var muUnit: CGFloat { fontSize / 18 }
    public func fontUnitsToPt(_ fontUnits: Int) -> CGFloat { CGFloat(fontUnits) * fontSize / CGFloat(unitsPerEm) }

    // MARK: - Table Accessors
    public func constantFromTable(_ constName: String) -> CGFloat {
        tableLock.lock(); defer { tableLock.unlock() }
        guard let val = constants?[constName] as? NSNumber else { return .zero }
        return fontUnitsToPt(val.intValue)
    }

    public func percentFromTable(_ percentName: String) -> CGFloat {
        tableLock.lock(); defer { tableLock.unlock() }
        guard let val = constants?[percentName] as? NSNumber else { return .zero }
        return CGFloat(val.floatValue) / 100
    }

    // MARK: - Fractions
    public var fractionNumeratorDisplayStyleShiftUp: CGFloat { constantFromTable("FractionNumeratorDisplayStyleShiftUp") }
    public var fractionNumeratorShiftUp: CGFloat { constantFromTable("FractionNumeratorShiftUp") }
    public var fractionDenominatorDisplayStyleShiftDown: CGFloat { constantFromTable("FractionDenominatorDisplayStyleShiftDown") }
    public var fractionDenominatorShiftDown: CGFloat { constantFromTable("FractionDenominatorShiftDown") }
    public var fractionNumeratorDisplayStyleGapMin: CGFloat { constantFromTable("FractionNumDisplayStyleGapMin") }
    public var fractionNumeratorGapMin: CGFloat { constantFromTable("FractionNumeratorGapMin") }
    public var fractionDenominatorDisplayStyleGapMin: CGFloat { constantFromTable("FractionDenomDisplayStyleGapMin") }
    public var fractionDenominatorGapMin: CGFloat { constantFromTable("FractionDenominatorGapMin") }
    public var fractionRuleThickness: CGFloat { constantFromTable("FractionRuleThickness") }
    public var skewedFractionHorizonalGap: CGFloat { constantFromTable("SkewedFractionHorizontalGap") }
    public var skewedFractionVerticalGap: CGFloat { constantFromTable("SkewedFractionVerticalGap") }

    // MARK: - Sub/Superscripts
    public var subscriptShiftDown: CGFloat { constantFromTable("SubscriptShiftDown") }
    public var subscriptTopMax: CGFloat { constantFromTable("SubscriptTopMax") }
    public var subscriptBaselineDropMin: CGFloat { constantFromTable("SubscriptBaselineDropMin") }
    public var superscriptShiftUp: CGFloat { constantFromTable("SuperscriptShiftUp") }
    public var superscriptShiftUpCramped: CGFloat { constantFromTable("SuperscriptShiftUpCramped") }
    public var superscriptBottomMin: CGFloat { constantFromTable("SuperscriptBottomMin") }
    public var superscriptBaselineDropMax: CGFloat { constantFromTable("SuperscriptBaselineDropMax") }
    public var superscriptBottomMaxWithSubscript: CGFloat { constantFromTable("SuperscriptBottomMaxWithSubscript") }
    public var subSuperscriptGapMin: CGFloat { constantFromTable("SubSuperscriptGapMin") }

    // MARK: - Large Operator Limits
    public var upperLimitGapMin: CGFloat { constantFromTable("UpperLimitGapMin") }
    public var upperLimitBaselineRiseMin: CGFloat { constantFromTable("UpperLimitBaselineRiseMin") }
    public var lowerLimitGapMin: CGFloat { constantFromTable("LowerLimitGapMin") }
    public var lowerLimitBaselineDropMin: CGFloat { constantFromTable("LowerLimitBaselineDropMin") }

    // MARK: - Accent and Over/Under Metrics
    public var accentBaseHeight: CGFloat { constantFromTable("AccentBaseHeight") }
    public var overbarVerticalGap: CGFloat { constantFromTable("OverbarVerticalGap") }
    public var overbarRuleThickness: CGFloat { constantFromTable("OverbarRuleThickness") }
    public var overbarExtraAscender: CGFloat { constantFromTable("OverbarExtraAscender") }
    public var underbarVerticalGap: CGFloat { constantFromTable("UnderbarVerticalGap") }
    public var underbarRuleThickness: CGFloat { constantFromTable("UnderbarRuleThickness") }
    public var underbarExtraDescender: CGFloat { constantFromTable("UnderbarExtraDescender") }

    // MARK: - Radical Metrics
    public var radicalDegreeBottomRaisePercent: CGFloat { percentFromTable("RadicalDegreeBottomRaisePercent") }
    public var radicalDisplayStyleVerticalGap: CGFloat { constantFromTable("RadicalDisplayStyleVerticalGap") }
    public var radicalVerticalGap: CGFloat { constantFromTable("RadicalVerticalGap") }
    public var radicalRuleThickness: CGFloat { constantFromTable("RadicalRuleThickness") }
    public var radicalExtraAscender: CGFloat { constantFromTable("RadicalExtraAscender") }
    public var radicalKernBeforeDegree: CGFloat { constantFromTable("RadicalKernBeforeDegree") }
    public var radicalKernAfterDegree: CGFloat { constantFromTable("RadicalKernAfterDegree") }

    // MARK: - Constants
    var scriptScaleDown:CGFloat { percentFromTable("ScriptPercentScaleDown")  }
    var scriptScriptScaleDown:CGFloat { percentFromTable("ScriptScriptPercentScaleDown")  }
    var delimitedSubFormulaMinHeight:CGFloat { constantFromTable("DelimitedSubFormulaMinHeight")  }
    
    // MARK: - Delimiter Metrics
    public var delimiterShortfall: CGFloat { constantFromTable("DelimiterShortfall") }
    public var delimiterFactor: CGFloat { percentFromTable("DelimiterFactor") }

    // MARK: - Miscellaneous
    public var minConnectorOverlap: CGFloat { constantFromTable("MinConnectorOverlap") }
    public var mathLeading: CGFloat { constantFromTable("MathLeading") }
    public var axisHeight: CGFloat { constantFromTable("AxisHeight") }
    public var scriptscriptSpace: CGFloat { constantFromTable("ScriptscriptSpace") }
    public var scriptSpace: CGFloat { constantFromTable("ScriptSpace") }

    // MARK: - Italic Correction
    public func getItalicCorrection(_ glyph: CGGlyph) -> CGFloat {
        let glyphName = font.get(nameForGlyph: glyph)
        tableLock.lock()
        defer { tableLock.unlock() }
        guard let italicDict = mTable["italic"] as? NSDictionary,
              let correction = italicDict[glyphName] as? NSNumber else { return 0 }
        return fontUnitsToPt(correction.intValue)
    }

    /// Returns the top accent attachment position (in points) for the given glyph.
    /// This is the vertical position from the glyph baseline to where the accent
    /// should be placed, as defined in the OpenType MATH table's `TopAccentAttachment`
    /// via the font's plist "accents" dictionary.
    public func getTopAccentAdjustment(_ glyph: CGGlyph) -> CGFloat {
        let glyphName = font.get(nameForGlyph: glyph)
        tableLock.lock()
        defer { tableLock.unlock() }
        if let accentsDict = mTable["accents"] as? NSDictionary,
           let adjustment = accentsDict[glyphName] as? NSNumber {
            return fontUnitsToPt(adjustment.intValue)
        }
        var gv = glyph
        var advances = CGSize.zero
        CTFontGetAdvancesForGlyphs(font.ctFont, .horizontal, &gv, &advances, 1)
        if advances.width > 0 { return advances.width / 2 }
        // Combining mark with zero advance — use bounding-box center
        let bbox = CTFontGetBoundingRectsForGlyphs(font.ctFont, .horizontal, &gv, nil, 1)
        return (bbox.origin.x + bbox.width / 2)
    }

    /// Returns the largest vertical variant glyph for large operators in display style,
    /// matching SwiftMath's `getLargerGlyph(forDisplayStyle: true)`.
    /// If no variants exist, returns the original glyph.
    public func getLargerGlyph(_ glyph: CGGlyph) -> CGGlyph {
        let variants = getVerticalVariantsForGlyph(glyph)
        // Return the last (largest) variant, matching SwiftMath's display‑style selection.
        if let lastNum = variants.last, let last = lastNum {
            return CGGlyph(truncating: last)
        }
        return glyph
    }

    // MARK: - Glyph Variant Methods
    public func getVerticalVariantsForGlyph(_ glyph: CGGlyph) -> [NSNumber?] {
        tableLock.lock(); defer { tableLock.unlock() }
        guard let variants = mTable[kVertVariants] as? NSDictionary else { return [] }
        return getVariantsForGlyph(glyph, inDictionary: variants)
    }
    public func getHorizontalVariantsForGlyph(_ glyph: CGGlyph) -> [NSNumber?] {
        tableLock.lock(); defer { tableLock.unlock() }
        guard let variants = mTable[kHorizVariants] as? NSDictionary else { return [] }
        return getVariantsForGlyph(glyph, inDictionary: variants)
    }
    public func getVariantsForGlyph(_ glyph: CGGlyph, inDictionary variants: NSDictionary) -> [NSNumber?] {
        let glyphName = font.get(nameForGlyph: glyph)
        var glyphArray = [NSNumber]()
        let variantGlyphs = variants[glyphName] as? NSArray
        guard let variantGlyphs = variantGlyphs, variantGlyphs.count != .zero else {
            let glyph = font.get(glyphWithName: glyphName)
            glyphArray.append(NSNumber(value: glyph))
            return glyphArray
        }
        for gvn in variantGlyphs {
            if let glyphVariantName = gvn as? String {
                let variantGlyph = font.get(glyphWithName: glyphVariantName)
                glyphArray.append(NSNumber(value: variantGlyph))
            }
        }
        return glyphArray
    }

    // MARK: - Glyph Assembly

    /// Part of a vertical/horizontal glyph construction assembly.
    public struct GlyphPart {
        public var glyph: CGGlyph = 0
        public var fullAdvance: CGFloat = 0
        public var startConnectorLength: CGFloat = 0
        public var endConnectorLength: CGFloat = 0
        public var isExtender: Bool = false
    }

    /// Returns the horizontal glyph assembly parts for the given glyph.
    /// If no assembly is defined, returns an empty array.
    public func getHorizontalGlyphAssembly(forGlyph glyph: CGGlyph) -> [GlyphPart] {
        tableLock.lock(); defer { tableLock.unlock() }
        guard let assemblyTable = mTable["h_assembly"] as? NSDictionary else { return [] }
        let glyphName = font.get(nameForGlyph: glyph)
        guard let assemblyInfo = assemblyTable[glyphName] as? NSDictionary,
              let parts = assemblyInfo["parts"] as? NSArray else { return [] }
        var rv: [GlyphPart] = []
        for partDict in parts {
            guard let info = partDict as? NSDictionary,
                  let glyphNameStr = info["glyph"] as? String,
                  let advNum = info["advance"] as? NSNumber else { continue }
            var part = GlyphPart()
            part.glyph = font.get(glyphWithName: glyphNameStr)
            part.fullAdvance = fontUnitsToPt(advNum.intValue)
            part.startConnectorLength = fontUnitsToPt((info["startConnector"] as? NSNumber)?.intValue ?? 0)
            part.endConnectorLength = fontUnitsToPt((info["endConnector"] as? NSNumber)?.intValue ?? 0)
            part.isExtender = (info["extender"] as? NSNumber)?.boolValue ?? false
            rv.append(part)
        }
        return rv
    }

    /// Returns the vertical glyph assembly parts for the given glyph.
    /// If no assembly is defined, returns an empty array.
    public func getVerticalGlyphAssembly(forGlyph glyph: CGGlyph) -> [GlyphPart] {
        tableLock.lock(); defer { tableLock.unlock() }
        guard let assemblyTable = mTable["v_assembly"] as? NSDictionary else { return [] }
        let glyphName = font.get(nameForGlyph: glyph)
        guard let assemblyInfo = assemblyTable[glyphName] as? NSDictionary,
              let parts = assemblyInfo["parts"] as? NSArray else { return [] }
        var rv: [GlyphPart] = []
        for partDict in parts {
            guard let info = partDict as? NSDictionary,
                  let glyphNameStr = info["glyph"] as? String,
                  let advNum = info["advance"] as? NSNumber else { continue }
            var part = GlyphPart()
            part.glyph = font.get(glyphWithName: glyphNameStr)
            part.fullAdvance = fontUnitsToPt(advNum.intValue)
            part.startConnectorLength = fontUnitsToPt((info["startConnector"] as? NSNumber)?.intValue ?? 0)
            part.endConnectorLength = fontUnitsToPt((info["endConnector"] as? NSNumber)?.intValue ?? 0)
            part.isExtender = (info["extender"] as? NSNumber)?.boolValue ?? false
            rv.append(part)
        }
        return rv
    }

    // MARK: - Raw Table Access
    public var rawMathTable: NSDictionary { mTable }
}
