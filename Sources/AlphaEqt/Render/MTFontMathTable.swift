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
    private let kVertVariants = "verticalVariants"
    private let kHorizVariants = "horizontalVariants"

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
        MTFontMathTable(font: font.copy(withSize: size), fontSize: size, unitsPerEm: unitsPerEm)
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
    public var radicalVerticalGap: CGFloat { constantFromTable("RadicalVerticalGap") }
    public var radicalRuleThickness: CGFloat { constantFromTable("RadicalRuleThickness") }
    public var radicalExtraAscender: CGFloat { constantFromTable("RadicalExtraAscender") }
    public var radicalKernBeforeDegree: CGFloat { constantFromTable("RadicalKernBeforeDegree") }
    public var radicalKernAfterDegree: CGFloat { constantFromTable("RadicalKernAfterDegree") }

    // MARK: - Delimiter Metrics
    public var delimiterShortfall: CGFloat { constantFromTable("DelimiterShortfall") }
    public var delimiterFactor: CGFloat { percentFromTable("DelimiterFactor") }

    // MARK: - Miscellaneous
    public var minConnectorOverlap: CGFloat { constantFromTable("MinConnectorOverlap") }
    public var mathLeading: CGFloat { constantFromTable("MathLeading") }
    public var axisHeight: CGFloat { constantFromTable("AxisHeight") }
    public var scriptscriptSpace: CGFloat { constantFromTable("ScriptscriptSpace") }
    public var scriptSpace: CGFloat { constantFromTable("ScriptSpace") }

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

    // MARK: - Raw Table Access
    public var rawMathTable: NSDictionary { mTable }
}

// MARK: - MTFont extension for math table loading
extension MTFont {
    /// Load the math table plist for this font.
    public func loadMathTable() -> NSDictionary? {
        let tableName = "\(font.rawValue).plist"
        guard let url = Bundle.module.url(forResource: tableName, withExtension: nil),
              let data = try? Data(contentsOf: url),
              let dict = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? NSDictionary else {
            return nil
        }
        return dict
    }
}
