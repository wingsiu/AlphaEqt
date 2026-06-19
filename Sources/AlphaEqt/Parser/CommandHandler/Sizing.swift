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
