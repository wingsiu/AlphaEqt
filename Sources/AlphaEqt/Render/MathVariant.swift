//
//  MathVariant.swift
//  AlphaEqt
//
//  Unicode Mathematical Alphanumeric Symbols (U+1D400–U+1D7FF) for font
//  style commands. Glyphs are rendered from the active OpenType MATH font
//  (STIX2, XITS, Latin Modern Math) at the corresponding code points.
//

import Foundation

// MARK: - Math Italic

func mathItalicize(_ text: String) -> String {
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
            let offset = scalar - 0x03B1
            result.append(Character(UnicodeScalar(0x1D6FC + offset)!))
        } else {
            result.append(ch)
        }
    }
    return result
}

/// Maps a LaTeX font command to an `MTFontStyle`.
func fontStyle(for command: String) -> MTFontStyle? {
    switch command {
    case "\\mathbf", "\\bf", "\\textbf":
        return .bold
    case "\\mathbfit", "\\bm", "\\boldsymbol":
        return .boldItalic
    case "\\mathrm", "\\rm":
        return .roman
    case "\\mathit", "\\mit", "\\textit", "\\mathnormal":
        return .italic
    case "\\mathcal", "\\cal":
        return .caligraphic
    case "\\mathbb", "\\Bbb":
        return .blackboard
    case "\\mathfrak", "\\frak":
        return .fraktur
    case "\\mathsf", "\\textsf":
        return .sansSerif
    case "\\mathtt", "\\texttt":
        return .typewriter
    default:
        return nil
    }
}

/// Applies a math font style to plain ASCII letters and digits.
func applyMathFontStyle(_ text: String, style: MTFontStyle) -> String {
    switch style {
    case .defaultStyle, .italic:
        return mathItalicize(text)
    case .roman:
        return text
    case .bold:
        return mapMathLetters(text, capBase: 0x1D400, lowerBase: 0x1D41A, digitBase: 0x1D7CE)
    case .boldItalic:
        return mapMathLetters(text, capBase: 0x1D468, lowerBase: 0x1D482)
    case .caligraphic:
        return mapCaligraphic(text)
    case .blackboard:
        return text
    case .fraktur:
        return mapMathLetters(text, capBase: 0x1D504, lowerBase: 0x1D51E)
    case .sansSerif:
        return mapMathLetters(text, capBase: 0x1D5A0, lowerBase: 0x1D5BA, digitBase: 0x1D7E2)
    case .typewriter:
        return mapMathLetters(text, capBase: 0x1D670, lowerBase: 0x1D68A, digitBase: 0x1D7F6)
    }
}

// MARK: - Letter mapping

private func mapMathLetters(
    _ text: String,
    capBase: UInt32,
    lowerBase: UInt32,
    digitBase: UInt32? = nil
) -> String {
    var result = ""
    for ch in text {
        guard let scalar = ch.unicodeScalars.first?.value else {
            result.append(ch)
            continue
        }
        if ch >= "A", ch <= "Z" {
            result.append(Character(UnicodeScalar(capBase + scalar - 0x41)!))
        } else if ch >= "a", ch <= "z" {
            result.append(Character(UnicodeScalar(lowerBase + scalar - 0x61)!))
        } else if let digitBase, ch >= "0", ch <= "9" {
            result.append(Character(UnicodeScalar(digitBase + scalar - 0x30)!))
        } else {
            result.append(ch)
        }
    }
    return result
}

/// Official Unicode code points for `\mathcal` capitals A–Z.
/// Several letters live in Letterlike Symbols, not the consecutive 1D49C block.
private let scriptCapitalScalars: [UInt32] = [
    0x1D49C, 0x212C, 0x1D49E, 0x1D49F, 0x2130, 0x2131, 0x1D4A2, 0x210B, 0x2110,
    0x1D4A5, 0x1D4A6, 0x2112, 0x2133, 0x1D4A9, 0x1D4AA, 0x1D4AB, 0x1D4AC, 0x211B,
    0x1D4AE, 0x1D4AF, 0x1D4B0, 0x1D4B1, 0x1D4B2, 0x1D4B3, 0x1D4B4, 0x1D4B5,
]

/// `\mathcal` — script capitals only (A–Z); lowercase passes through unchanged.
private func mapCaligraphic(_ text: String) -> String {
    var result = ""
    for ch in text {
        guard let scalar = ch.unicodeScalars.first?.value else {
            result.append(ch)
            continue
        }
        if ch >= "A", ch <= "Z" {
            let index = Int(scalar - 0x41)
            result.append(Character(UnicodeScalar(scriptCapitalScalars[index])!))
        } else {
            result.append(ch)
        }
    }
    return result
}
