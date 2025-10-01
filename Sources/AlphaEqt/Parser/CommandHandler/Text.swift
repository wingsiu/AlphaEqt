//
//  Text.swift
//  AlphaEqt
//
//  Created by Alpha Ng on 2/10/2025.
//

import Foundation

func handleTextCommand(tokens: ArraySlice<Token>, idx: inout Int) -> ASTNode? {
    let tokensArray = Array(tokens)
    guard idx + 1 < tokensArray.count, tokensArray[idx + 1].kind == .leftBrace else {
        idx += 1
        return nil
    }
    var j = idx + 2
    var braceDepth = 1
    var childTokens: [Token] = []
    while j < tokensArray.count && braceDepth > 0 {
        let t = tokensArray[j]
        if t.kind == .leftBrace { braceDepth += 1 }
        if t.kind == .rightBrace { braceDepth -= 1 }
        if braceDepth > 0 { childTokens.append(t) }
        j += 1
    }
    let textContent = childTokens.map { $0.text }.joined(separator: " ")
    let childNode = ASTNode(type: .textord,
                            text: textContent,
                            location: childTokens.first?.sourceLocation,
                            originalText: textContent,
                            childNodes: nil)
    let node = ASTNode(type: .text,
                       text: nil,
                       location: tokensArray[idx].sourceLocation,
                       originalText: tokensArray[idx].text,
                       childNodes: [childNode])
    idx = j
    return node
}
