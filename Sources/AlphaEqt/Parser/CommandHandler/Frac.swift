//
//  Frac.swift
//  AlphaEqt
//
//  Created by Alpha Ng on 18/6/2025.
//
//  Parser handler for \frac{numerator}{denominator}.
//

import Foundation

/// Handler for \frac{numerator}{denominator}.
/// Consumes the \frac token plus two brace-delimited groups,
/// parses each group into AST subtrees, and returns a .frac node
/// with children [numerator, denominator].
func handleFracCommand(tokens: ArraySlice<Token>, idx: inout Int) -> ASTNode? {
    let tokensArray = Array(tokens)
    guard idx < tokensArray.count else { return nil }

    let startIdx = idx
    idx += 1 // skip \frac

    // --- Consume first brace group (numerator) ---
    guard idx < tokensArray.count, tokensArray[idx].kind == .leftBrace else {
        // Could not find opening brace — back out
        idx = startIdx + 1
        return nil
    }
    idx += 1 // skip {
    var braceDepth = 1
    var numTokens: [Token] = []
    while idx < tokensArray.count, braceDepth > 0 {
        let t = tokensArray[idx]
        if t.kind == .leftBrace { braceDepth += 1 }
        if t.kind == .rightBrace { braceDepth -= 1 }
        if braceDepth > 0 { numTokens.append(t) }
        idx += 1
    }
    // idx is now past the closing }

    // --- Consume second brace group (denominator) ---
    guard idx < tokensArray.count, tokensArray[idx].kind == .leftBrace else {
        // Missing second brace group — back out
        idx = startIdx + 1
        return nil
    }
    idx += 1 // skip {
    braceDepth = 1
    var denTokens: [Token] = []
    while idx < tokensArray.count, braceDepth > 0 {
        let t = tokensArray[idx]
        if t.kind == .leftBrace { braceDepth += 1 }
        if t.kind == .rightBrace { braceDepth -= 1 }
        if braceDepth > 0 { denTokens.append(t) }
        idx += 1
    }
    // idx is now past the closing }

    // Parse numerator and denominator token sequences into AST subtrees
    let parser = LatexParser()
    let numNodes = parser.parse(tokens: numTokens)
    let denNodes = parser.parse(tokens: denTokens)

    let numNode: ASTNode
    if numNodes.count == 1 {
        numNode = numNodes[0]
    } else {
        numNode = ASTNode(type: .ordgroup, text: nil,
                          location: numTokens.first?.sourceLocation,
                          childNodes: numNodes.isEmpty ? nil : numNodes)
    }

    let denNode: ASTNode
    if denNodes.count == 1 {
        denNode = denNodes[0]
    } else {
        denNode = ASTNode(type: .ordgroup, text: nil,
                          location: denTokens.first?.sourceLocation,
                          childNodes: denNodes.isEmpty ? nil : denNodes)
    }

    let node = ASTNode(
        type: .frac,
        text: nil,
        location: tokensArray[startIdx].sourceLocation,
        originalText: tokensArray[startIdx].text,
        childNodes: [numNode, denNode]
    )
    return node
}
