//
//  LargeOp.swift
//  AlphaEqt
//
//  Parser handler for large/small operator commands.
//  Cross-referenced against SwiftMath's MTMathAtomFactory.
//

import Foundation

/// Handles operator commands: \sum, \int, \prod, \lim, \sin, \cos, \log, etc.
/// Returns `.op` AST nodes with the operator name/symbol as nucleus text.
/// Limits (^ and _) attach via the standard sup/sub mechanism.
public func handleLargeOpCommand(_ tokens: ArraySlice<Token>, _ relIdx: inout Int) -> ASTNode? {
    let cmd = tokens[tokens.startIndex].text
    let opName = String(cmd.dropFirst())

    let nucleus: String
    switch opName {
    // ── Large operators (limits in display style) ────────────────────
    case "sum":       nucleus = "\u{2211}"  // ∑
    case "prod":      nucleus = "\u{220F}"  // ∏
    case "coprod":    nucleus = "\u{2210}"  // ∐
    case "int":       nucleus = "\u{222B}"  // ∫
    case "iint":      nucleus = "\u{222C}"  // ∬
    case "iiint":     nucleus = "\u{222D}"  // ∭
    case "iiiint":    nucleus = "\u{2A0C}"  // ⨌
    case "oint":      nucleus = "\u{222E}"  // ∮
    case "bigwedge":  nucleus = "\u{22C0}"  // ⋀
    case "bigvee":    nucleus = "\u{22C1}"  // ⋁
    case "bigcap":    nucleus = "\u{22C2}"  // ⋂
    case "bigcup":    nucleus = "\u{22C3}"  // ⋃
    case "bigodot":   nucleus = "\u{2A00}"  // ⨀
    case "bigoplus":  nucleus = "\u{2A01}"  // ⨁
    case "bigotimes": nucleus = "\u{2A02}"  // ⨂
    case "biguplus":  nucleus = "\u{2A04}"  // ⨄
    case "bigsqcup":  nucleus = "\u{2A06}"  // ⨆

    // ── Limits operators (display-style above/below) ─────────────────
    case "lim":       nucleus = "lim"
    case "limsup":    nucleus = "lim sup"
    case "liminf":    nucleus = "lim inf"
    case "max":       nucleus = "max"
    case "min":       nucleus = "min"
    case "sup":       nucleus = "sup"
    case "inf":       nucleus = "inf"
    case "det":       nucleus = "det"
    case "gcd":       nucleus = "gcd"
    case "Pr":        nucleus = "Pr"

    // ── No-limit operators (upright, no display-style limits) ────────
    case "sin":       nucleus = "sin"
    case "cos":       nucleus = "cos"
    case "tan":       nucleus = "tan"
    case "csc":       nucleus = "csc"
    case "sec":       nucleus = "sec"
    case "cot":       nucleus = "cot"
    case "arcsin":    nucleus = "arcsin"
    case "arccos":    nucleus = "arccos"
    case "arctan":    nucleus = "arctan"
    case "arccot":    nucleus = "arccot"
    case "arcsec":    nucleus = "arcsec"
    case "arccsc":    nucleus = "arccsc"
    case "sinh":      nucleus = "sinh"
    case "cosh":      nucleus = "cosh"
    case "tanh":      nucleus = "tanh"
    case "coth":      nucleus = "coth"
    case "sech":      nucleus = "sech"
    case "csch":      nucleus = "csch"
    case "arcsinh":   nucleus = "arcsinh"
    case "arccosh":   nucleus = "arccosh"
    case "arctanh":   nucleus = "arctanh"
    case "arccoth":   nucleus = "arccoth"
    case "arcsech":   nucleus = "arcsech"
    case "arccsch":   nucleus = "arccsch"
    case "log":       nucleus = "log"
    case "lg":        nucleus = "lg"
    case "ln":        nucleus = "ln"
    case "exp":       nucleus = "exp"
    case "arg":       nucleus = "arg"
    case "ker":       nucleus = "ker"
    case "deg":       nucleus = "deg"
    case "dim":       nucleus = "dim"
    case "hom":       nucleus = "hom"
    case "mod":       nucleus = "mod"
    default:          nucleus = opName
    }

    relIdx = 1
    return ASTNode(type: .op, text: nucleus, mode: .math)
}
