//
//  MTFont.swift
//  AlphaEqt
//
//  Modern math font class with serial queue-based caching (Swift 6/Xcode 16 compliant).
//

import Foundation
import CoreGraphics
import CoreText

public enum MathFont: String, CaseIterable, Identifiable {
    public var id: Self { self }

    case latinModernFont = "latinmodern-math"
    case xitsFont = "xits-math"
    case stix2Font = "stix2-math"

    /// Fast cached font creation, concurrency-safe.
    public func mtfont(size: CGFloat) -> MTFont {
        MTFont.cached(font: self, size: size)
    }

    /// Returns the URL for this font's .otf resource in the module bundle.
    private var resourceURL: URL? {
        Bundle.module.url(forResource: self.rawValue, withExtension: "otf")
    }

    public func cgFont() -> CGFont {
        guard let url = resourceURL,
              let data = try? Data(contentsOf: url) as CFData,
              let provider = CGDataProvider(data: data),
              let cgFont = CGFont(provider) else {
            // Fallback: use system font
            return CTFontCopyGraphicsFont(CTFontCreateUIFontForLanguage(.system, 0, nil)!, nil)
        }
        return cgFont
    }

    public func ctFont(withSize size: CGFloat) -> CTFont {
        guard let url = resourceURL,
              let data = try? Data(contentsOf: url) as CFData,
              let provider = CGDataProvider(data: data),
              let cgFont = CGFont(provider) else {
            return CTFontCreateUIFontForLanguage(.system, size, nil)!
        }
        return CTFontCreateWithGraphicsFont(cgFont, size, nil, nil)
    }
}

/// Thread-safe: all properties are `let` constants, the font cache is serial-queue guarded,
/// and the math table is lazily initialized under a serial lock.
public final class MTFont: @unchecked Sendable {
    public let font: MathFont
    public let size: CGFloat
    private let _cgFont: CGFont
    private let _ctFont: CTFont
    private let unitsPerEm: UInt
    private var _mathTab: MTFontMathTable?

    nonisolated(unsafe) private static var cache: [String: MTFont] = [:]
    private static let cacheQueue = DispatchQueue(label: "com.alphaeqt.mtfontcache.serial")

    public static func cached(font: MathFont, size: CGFloat) -> MTFont {
        let key = "\(font.rawValue):\(size)"
        return cacheQueue.sync {
            if let cached = cache[key] {
                return cached
            }
            let newFont = MTFont(font: font, size: size)
            cache[key] = newFont
            return newFont
        }
    }

    public init(font: MathFont = .latinModernFont, size: CGFloat) {
        self.font = font
        self.size = size
        self._cgFont = font.cgFont()
        self._ctFont = font.ctFont(withSize: size)
        self.unitsPerEm = UInt(CTFontGetUnitsPerEm(self._ctFont))
    }

    public var cgFont: CGFont { _cgFont }
    public var ctFont: CTFont { _ctFont }
    public var fontSize: CGFloat { size }

    public var mathTable: MTFontMathTable {
        return MTFont.serialTableAccess { [weak self] in
            guard let self = self else { fatalError() }
            if let tab = self._mathTab { return tab }
            let tab = MTFontMathTable(font: self, fontSize: self.size, unitsPerEm: self.unitsPerEm)
            self._mathTab = tab
            return tab
        }
    }

    public func copy(withSize size: CGFloat) -> MTFont {
        MTFont.cached(font: font, size: size)
    }

    public func loadMathTable() -> NSDictionary? {
        let tableName = "\(font.rawValue).plist"
        guard let url = Bundle.module.url(forResource: tableName, withExtension: nil),
              let data = try? Data(contentsOf: url),
              let dict = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? NSDictionary else {
            return nil
        }
        return dict
    }

    private static let tableQueue = DispatchQueue(label: "com.alphaeqt.mtfont.table.serial")
    private static func serialTableAccess<T>(_ block: () -> T) -> T {
        return tableQueue.sync { block() }
    }

    func get(nameForGlyph glyph: CGGlyph) -> String {
        return MTFont.serialTableAccess { [weak self] in
            let name = self?._cgFont.name(for: glyph) as? String
            return name ?? ""
        }
    }
    func get(glyphWithName name: String) -> CGGlyph {
        return MTFont.serialTableAccess { [weak self] in
            self?._cgFont.getGlyphWithGlyphName(name: name as CFString) ?? 0
        }
    }
}
