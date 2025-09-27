//
//  AccentUtils.swift
//  AlphaEqt
//
//  Created by Alpha Ng on 28/9/2025.
//
import Foundation

/// Utilities for converting between LaTeX accent macros and Unicode accents,
/// and for mapping precomposed accented characters to LaTeX macros.
/// Requires MTMathAtomFactory.swift to be present in your project.
public struct AccentUtils {
    
    /// Converts a base character + combining mark (e.g. "x̄") to LaTeX accent macro (e.g. "\bar{x}").
    /// If not a recognized accent, returns original string.
    public static func unicodeAccentToLatex(_ input: String) async -> String {
        let scalars = Array(input.unicodeScalars)
        guard scalars.count == 2 else { return input }
        let base = String(scalars[0])
        let accentMark = String(scalars[1])
        if let macro = await MTMathAtomFactory.accentValueToName()[accentMark] {
            return "\\\(macro){\(base)}"
        }
        return input
    }
    
    /// Converts a precomposed accented character (e.g. "á") to LaTeX accent macro (e.g. "\acute{a}")
    /// If not recognized, returns original string.
    private static let supportedAccentedCharactersActor = SupportedAccentedCharactersActor()

    public static func precomposedAccentToLatex(_ ch: Character) async -> String {
        if let value = await supportedAccentedCharactersActor.getValue(for: ch) {
            let (accent, base) = value
            if !base.isEmpty {
                return "\\\(accent){\(base)}"
            } else {
                return "\\\(accent)"
            }
        }
        return String(ch)
    }
    
    /// Converts a LaTeX macro (e.g. "bar") and base character (e.g. "x") to Unicode with combining mark (e.g. "x̄").
    /// If not recognized, returns base.
    public static func latexMacroToUnicode(_ macro: String, base: String) -> String {
        if let accentMark = MTMathAtomFactory.accents[macro] {
            return base + accentMark
        }
        return base
    }
}
