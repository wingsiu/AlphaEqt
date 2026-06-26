//
//  HorizBrace.swift
//  AlphaEqt
//

import Foundation

private func parseHorizBraceArg(tokens: ArraySlice<Token>, index: inout Int) -> ASTNode? {
    let tokensArray = Array(tokens)
    guard tokensArray.count >= 3 else { index = 1; return nil }
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
    let nodes = LatexParser().parse(tokens: contentTokens)
    index = i - tokensArray.startIndex
    if nodes.isEmpty { return ASTNode(type: .mathord, text: "") }
    if nodes.count == 1 { return nodes[0] }
    return ASTNode(type: .ordgroup, text: nil, childNodes: nodes)
}

func handleHorizBraceCommand(tokens: ArraySlice<Token>, index: inout Int, name: String) -> ASTNode? {
    let tokensArray = Array(tokens)
    guard tokensArray.count >= 3 else { index = 1; return nil }
    let rawCmd = tokensArray[tokensArray.startIndex].text
    let braceName = rawCmd.hasPrefix("\\") ? String(rawCmd.dropFirst()) : name
    guard let child = parseHorizBraceArg(tokens: tokens, index: &index) else { return nil }
    return ASTNode(type: .horizBrace, text: braceName, childNodes: [child])
}
