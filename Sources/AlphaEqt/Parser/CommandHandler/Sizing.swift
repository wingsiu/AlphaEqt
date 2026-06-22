//
//  Sizing.swift
//  AlphaEqt
//
//  Parser handler for \displaystyle \textstyle \scriptstyle \scriptscriptstyle
//

import Foundation

/// Handler for sizing commands that change the math style.
/// These produce a .sizing AST node. If followed by { ... }, the
/// braced group is parsed as child content so it renders under the
/// new style while the braces are not rendered as literal text.
func handleSizingCommand(tokens: ArraySlice<Token>, idx: inout Int) -> ASTNode? {
    let tokensArray = Array(tokens)
    guard idx < tokensArray.count else { return nil }

    let cmdToken = tokensArray[idx]
    let startIdx = idx
    idx += 1 // consume the command token

    // Map the command text to the sizing keyword
    let sizingKeyword: String
    switch cmdToken.text {
    case "\\displaystyle":       sizingKeyword = "displaystyle"
    case "\\textstyle":          sizingKeyword = "textstyle"
    case "\\scriptstyle":        sizingKeyword = "scriptstyle"
    case "\\scriptscriptstyle":  sizingKeyword = "scriptscriptstyle"
    default:                     sizingKeyword = "displaystyle"
    }

    // If followed by { ... }, collect tokens and parse them as child nodes.
    var childNodes: [ASTNode]? = nil
    if idx < tokensArray.count, tokensArray[idx].kind == .leftBrace {
        idx += 1 // skip {
        var depth = 1
        var collected: [Token] = []
        while idx < tokensArray.count, depth > 0 {
            let t = tokensArray[idx]
            if t.kind == .leftBrace { depth += 1 }
            else if t.kind == .rightBrace { depth -= 1 }
            if depth > 0 { collected.append(t) }
            idx += 1
        }
        // idx is now past closing }
        let parser = LatexParser()
        let parsed = parser.parse(tokens: collected)
        if !parsed.isEmpty {
            childNodes = parsed.count == 1
                ? parsed
                : [ASTNode(type: .ordgroup, text: nil, childNodes: parsed)]
        }
    }

    return ASTNode(
        type: .sizing,
        text: sizingKeyword,
        location: tokensArray[startIdx].sourceLocation,
        originalText: tokensArray[startIdx].text,
        childNodes: childNodes
    )
}

/// Handler for \dfrac and \tfrac — renders as a fraction with forced style.
/// \dfrac forces `displaystyle` (display-style fraction).
/// \tfrac forces `textstyle` (text-style fraction).
func handleFracSizingCommand(style: String) -> ((ArraySlice<Token>, inout Int) -> ASTNode?) {
    return { tokens, idx in
        let tokensArray = Array(tokens)
        guard idx < tokensArray.count else { return nil }
        let startIdx = idx
        idx += 1 // consume \dfrac or \tfrac

        // Parse the two braced arguments: {num}{den}
        guard idx < tokensArray.count, tokensArray[idx].kind == .leftBrace else { return nil }
        idx += 1
        var depth = 1
        var numTokens: [Token] = []
        while idx < tokensArray.count, depth > 0 {
            let t = tokensArray[idx]
            if t.kind == .leftBrace { depth += 1 }
            else if t.kind == .rightBrace { depth -= 1 }
            if depth > 0 { numTokens.append(t) }
            idx += 1
        }

        guard idx < tokensArray.count, tokensArray[idx].kind == .leftBrace else { return nil }
        idx += 1
        depth = 1
        var denTokens: [Token] = []
        while idx < tokensArray.count, depth > 0 {
            let t = tokensArray[idx]
            if t.kind == .leftBrace { depth += 1 }
            else if t.kind == .rightBrace { depth -= 1 }
            if depth > 0 { denTokens.append(t) }
            idx += 1
        }

        let parser = LatexParser()
        let numNodes = parser.parse(tokens: numTokens)
        let denNodes = parser.parse(tokens: denTokens)

        // Build: sizing{style} > frac{num}{den}
        let numChild = numNodes.count == 1 ? numNodes[0] : ASTNode(type: .ordgroup, text: nil, childNodes: numNodes)
        let denChild = denNodes.count == 1 ? denNodes[0] : ASTNode(type: .ordgroup, text: nil, childNodes: denNodes)
        let fracNode = ASTNode(type: .frac, text: nil, childNodes: [numChild, denChild])

        return ASTNode(
            type: .sizing,
            text: style,
            location: tokensArray[startIdx].sourceLocation,
            originalText: tokensArray[startIdx].text,
            childNodes: [fracNode]
        )
    }
}
