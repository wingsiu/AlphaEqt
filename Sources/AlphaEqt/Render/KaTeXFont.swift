//
//  KaTeXFont.swift
//  AlphaEqt
//
//  KaTeX AMS double-struck font for `\mathbb{}` (SIL Open Font License 1.1).
//

import CoreText
import Foundation

enum KaTeXFont {
    private static let resourceName = "katex-ams-regular"

    nonisolated(unsafe) private static var cache: [CGFloat: CTFont] = [:]
    private static let cacheQueue = DispatchQueue(label: "com.alphaeqt.katexfont.cache")

    /// KaTeX AMS-Regular — cohesive double-struck capitals at ASCII A–Z.
    static func amsRegular(size: CGFloat) -> CTFont {
        cacheQueue.sync {
            if let cached = cache[size] { return cached }
            let ctFont: CTFont
            if let url = Bundle.module.url(forResource: resourceName, withExtension: "ttf"),
               let data = try? Data(contentsOf: url) as CFData,
               let provider = CGDataProvider(data: data),
               let cgFont = CGFont(provider) {
                ctFont = CTFontCreateWithGraphicsFont(cgFont, size, nil, nil)
            } else {
                ctFont = CTFontCreateWithName("Times New Roman" as CFString, size, nil)
            }
            cache[size] = ctFont
            return ctFont
        }
    }
}
