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
    case kpMathLightFont = "KpMath-Light"
    case kpMathSansFont  = "KpMath-Sans"
    case xitsFont        = "xits-math"
    case termesFont      = "texgyretermes-math"
    case asanaFont       = "Asana-Math"
    case eulerFont       = "Euler-Math"
    case firaFont        = "FiraMath-Regular"
    case notoSansFont    = "NotoSansMath-Regular"
    case libertinusFont  = "LibertinusMath-Regular"

    /// Fast cached font creation, synchronous and concurrency-safe.
    public func mtfont(size: CGFloat) -> MTFont {
        MTFont.cached(font: self, size: size)
    }

    // MARK: - Resource loader stubs (implement these for your bundle)
    public func cgFont() -> CGFont {
        fatalError("Implement cgFont() resource loader for font: \(self.rawValue)")
    }
    public func ctFont(withSize size: CGFloat) -> CTFont {
        fatalError("Implement ctFont(withSize:) for font: \(self.rawValue)")
    }
}

public final class MTFont {
    public let font: MathFont
    public let size: CGFloat
    private let _cgFont: CGFont
    private let _ctFont: CTFont
    private let unitsPerEm: UInt
    private var _mathTab: MTFontMathTable?

    // ---- Serial queue for concurrency-safe cache access ----
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

    /// Lazy math table (readonly after init, so thread-safe for reads)
    public var mathTable: MTFontMathTable {
        return MTFont.serialTableAccess { [weak self] in
            if let tab = self?._mathTab { return tab }
            let tab = MTFontMathTable(font: self!, fontSize: self!.size, unitsPerEm: self!.unitsPerEm)
            self?._mathTab = tab
            return tab
        }
    }

    /// Returns a copy of this font at a new size (uses cache).
    public func copy(withSize size: CGFloat) -> MTFont {
        MTFont.cached(font: font, size: size)
    }

    /// Loads the math table plist for this font.
    public func loadMathTable() -> NSDictionary? {
        let tableName = "\(font.rawValue).plist"
        guard let url = Bundle.module.url(forResource: tableName, withExtension: nil),
              let data = try? Data(contentsOf: url),
              let dict = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? NSDictionary else {
            return nil
        }
        return dict
    }

    /// Serializes access to math table for thread safety.
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
