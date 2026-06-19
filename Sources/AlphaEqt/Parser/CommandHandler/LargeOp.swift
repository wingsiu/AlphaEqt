//
//  LargeOp.swift
//  AlphaEqt
//
//  Parser handler for large operator commands: \sum, \int, \prod, \lim, etc.
//

import Foundation

/// Handles large operator commands like \sum, \int, \prod, \coprod, \lim, etc.
/// These return `.op` AST nodes. The nucleus text is the operator name/symbol.
/// Limits (^ and _) are attached via the standard sup/sub script mechanism
/// during parsing.
public func handleLargeOpCommand(_ tokens: ArraySlice<Token>, _ relIdx: inout Int) -> ASTNode? {
    // tokens[0] is the command token, e.g., \sum, \int
    let cmd = tokens[tokens.startIndex].text
    let opName = String(cmd.dropFirst()) // remove the backslash

    // Map LaTeX command to Unicode operator symbol
    let nucleus: String
    switch opName {
    case "sum":       nucleus = "\u{2211}"  // ∑
    case "prod":      nucleus = "\u{220F}"  // ∏
    case "coprod":    nucleus = "\u{2210}"  // ∐
    case "int":       nucleus = "\u{222B}"  // ∫
    case "iint":      nucleus = "\u{222C}"  // ∬
    case "iiint":     nucleus = "\u{222D}"  // ∭
    case "oint":      nucleus = "\u{222E}"  // ∮
    case "bigcap":    nucleus = "\u{22C2}"  // ⋂
    case "bigcup":    nucleus = "\u{22C3}"  // ⋃
    case "bigvee":    nucleus = "\u{22C1}"  // ⋁
    case "bigwedge":  nucleus = "\u{22C0}"  // ⋀
    case "bigodot":   nucleus = "\u{2A00}"  // ⨀
    case "bigoplus":  nucleus = "\u{2A01}"  // ⨁
    case "bigotimes": nucleus = "\u{2A02}"  // ⨂
    case "bigsqcup":  nucleus = "\u{2A06}"  // ⨆
    case "biguplus":  nucleus = "\u{2A04}"  // ⨄
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
    default:          nucleus = opName
    }

    let node = ASTNode(type: .op, text: nucleus, mode: .math)
    relIdx = 1
    return node
}
