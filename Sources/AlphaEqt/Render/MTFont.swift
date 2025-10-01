//
//  MTFont.swift
//  AlphaEqt
//
//  Created by Alpha Ng on 2/10/2025.
//  Modern math font class, adapted from SwiftMath MTFontV2
//

import Foundation
import CoreGraphics
import CoreText

public enum MathFont: String, CaseIterable, Identifiable {
    public var id: Self { self }

    case latinModernFont = "latinmodern-math"
    case kpMathLightFont = "KpMath-Light"
    case kpMathSansFont  = "KpMath-Sans"
    case xitsFont        = "xits-math"
    case termesFont      = "texgyretermes-math"
    case asanaFont       = "Asana-Math"
    case eulerFont       = "Euler-Math"
    case firaFont        = "FiraMath-Regular"
    case notoSansFont    = "NotoSansMath-Regular"
    case libertinusFont  = "LibertinusMath-Regular"
    // Add more fonts as needed

    public func mtfont(size: CGFloat) -> MTFont {
        MTFont(font: self, size: size)
    }
}

public final class MTFont {
    public let font: MathFont
    public let size: CGFloat
    private let _cgFont: CGFont
    private let _ctFont: CTFont
    private let unitsPerEm: UInt
    private var _mathTab: MTFontMathTable?
    private let mtfontLock = NSLock()

    public init(font: MathFont = .latinModernFont, size: CGFloat) {
        self.font = font
        self.size = size
        self._cgFont = font.cgFont()
        self._ctFont = font.ctFont(withSize: size)
        self.unitsPerEm = UInt(CTFontGetUnitsPerEm(self._ctFont))
        //self.unitsPerEm = self._ctFont.unitsPerEm
    }

    public var cgFont: CGFont { _cgFont }
    public var ctFont: CTFont { _ctFont }

    public var fontSize: CGFloat { size }

    /// Thread-safe lazy math table
    public var mathTable: MTFontMathTable? {
        get {
            mtfontLock.lock()
            defer { mtfontLock.unlock() }
            if _mathTab == nil {
                _mathTab = MTFontMathTable(font: self, fontSize: size, unitsPerEm: unitsPerEm)
            }
            return _mathTab
        }
    }

    /// Returns a copy of this font at a new size.
    public func copy(withSize size: CGFloat) -> MTFont {
        MTFont(font: font, size: size)
    }
}


// MARK: - MathFont helpers (stub implementations; you should provide these)
extension MathFont {
    public func cgFont() -> CGFont {
        // Load CGFont from bundle/resource using rawValue
        // For example, use Bundle.module or your own loader
        fatalError("Implement cgFont() resource loader for font: \(self.rawValue)")
    }
    public func ctFont(withSize size: CGFloat) -> CTFont {
        // Create CTFont from CGFont and size
        fatalError("Implement ctFont(withSize:) for font: \(self.rawValue)")
    }
}

extension MTFont {
    /// Gets the glyph name for a given glyph
    func get(nameForGlyph glyph: CGGlyph) -> String {
        let name = cgFont.name(for: glyph) as? String
        return name ?? ""
    }
    /// Gets the glyph for a given glyph name
    func get(glyphWithName name: String) -> CGGlyph {
        cgFont.getGlyphWithGlyphName(name: name as CFString)
    }
}
