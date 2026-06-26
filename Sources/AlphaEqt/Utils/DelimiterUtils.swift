//
//  DelimiterUtils.swift
//  AlphaEqt
//

import Foundation

enum DelimiterUtils {
    static let namedDelimiters: [String: String] = [
        "\\langle": "\u{27E8}",
        "\\rangle": "\u{27E9}",
        "\\lfloor": "\u{230A}",
        "\\rfloor": "\u{230B}",
        "\\lceil": "\u{2308}",
        "\\rceil": "\u{2309}",
        "\\lvert": "|",
        "\\rvert": "|",
        "\\lVert": "\u{2016}",
        "\\rVert": "\u{2016}",
        "\\vert": "|",
        "\\Vert": "\u{2016}",
        "\\{": "{",
        "\\}": "}",
    ]

    static let leftPrefix = "\\left"
    static let rightPrefix = "\\right"
    static let middlePrefix = "\\middle"

    static func resolveDelimiter(_ raw: String) -> String {
        if raw == "." { return "." }
        if let mapped = namedDelimiters[raw] { return mapped }
        return raw
    }

    static func suffix(fromCombined token: String, prefix: String) -> String? {
        guard token.hasPrefix(prefix), token.count > prefix.count else { return nil }
        return String(token.dropFirst(prefix.count))
    }

    static func leftDelimiter(from token: String) -> String {
        guard let raw = suffix(fromCombined: token, prefix: leftPrefix) else { return "." }
        return resolveDelimiter(raw)
    }

    static func rightDelimiter(from token: String) -> String {
        guard let raw = suffix(fromCombined: token, prefix: rightPrefix) else { return "." }
        return resolveDelimiter(raw)
    }

    static func middleDelimiter(from token: String) -> String {
        guard let raw = suffix(fromCombined: token, prefix: middlePrefix) else { return "|" }
        return resolveDelimiter(raw)
    }

    static func tryCombineDelimiter(prefix: String, next: Token) -> String? {
        switch next.kind {
        case .leftParen: return prefix + "("
        case .rightParen: return prefix + ")"
        case .leftBracket: return prefix + "["
        case .rightBracket: return prefix + "]"
        case .leftBrace: return prefix + "{"
        case .rightBrace: return prefix + "}"
        case .operatorSymbol:
            if next.text == "." { return prefix + "." }
            return prefix + next.text
        case .command:
            if namedDelimiters.keys.contains(next.text) || next.text == "\\{" || next.text == "\\}" {
                return prefix + next.text
            }
            return nil
        default:
            return nil
        }
    }
}
