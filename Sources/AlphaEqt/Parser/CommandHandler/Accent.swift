//
//  Accent.swift
//  AlphaEqt
//
//  Parser handler for \hat, \bar, \tilde, \dot, \ddot, \vec,
//  \widehat, \widetilde, \check, \breve, \acute, \grave.
//

import Foundation

/// Parses `\accentcmd{content}` → `.accent` node.
/// - `node.text` = accent name without backslash (e.g. "hat", "tilde")
/// - `node.childNodes` = parsed content inside the braces
func handleAccentCommand(tokens: ArraySlice<Token>, index: inout Int) -> ASTNode? {
    let tokensArray = Array(tokens)
    guard tokensArray.count >= 3 else { index = 1; return nil }

    // Extract accent name (strip leading backslash)
    let rawCmd = tokensArray[tokensArray.startIndex].text
    let accentName = rawCmd.hasPrefix("\\") ? String(rawCmd.dropFirst()) : rawCmd

    // Consume braced content
    guard tokensArray[tokensArray.startIndex + 1].kind == .leftBrace else {
        index = 1; return nil
    }
    var depth = 1
    var contentTokens: [Token] = []
    var i = tokensArray.startIndex + 2
    while i < tokensArray.endIndex, depth > 0 {
        let t = tokensArray[i]
        if t.kind == .leftBrace { depth += 1 }
        else if t.kind == .rightBrace { depth -= 1 }
        if depth > 0 { contentTokens.append(t) }
        i += 1
    }

    let parser = LatexParser()
    let contentNodes = parser.parse(tokens: contentTokens)
    let childNodes: [ASTNode] = contentNodes.isEmpty
        ? [ASTNode(type: .mathord, text: "")]
        : contentNodes

    index = i - tokensArray.startIndex
    return ASTNode(
        type: .accent,
        text: accentName,
        childNodes: childNodes
    )
}
