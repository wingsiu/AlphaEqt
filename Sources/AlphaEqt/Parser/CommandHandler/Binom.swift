//
//  Binom.swift
//  AlphaEqt
//

import Foundation

private func parseTwoBraceArgs(tokens: ArraySlice<Token>, idx: inout Int) -> (ASTNode, ASTNode)? {
    let tokensArray = Array(tokens)
    guard idx < tokensArray.count else { return nil }

    func consumeGroup() -> [ASTNode]? {
        guard idx < tokensArray.count, tokensArray[idx].kind == .leftBrace else { return nil }
        idx += 1
        var depth = 1
        var collected: [Token] = []
        while idx < tokensArray.count, depth > 0 {
            let t = tokensArray[idx]
            if t.kind == .leftBrace { depth += 1 }
            else if t.kind == .rightBrace { depth -= 1 }
            if depth > 0 { collected.append(t) }
            idx += 1
        }
        let parsed = LatexParser().parse(tokens: collected)
        if parsed.isEmpty { return [ASTNode(type: .mathord, text: "")] }
        if parsed.count == 1 { return parsed }
        return [ASTNode(type: .ordgroup, text: nil, childNodes: parsed)]
    }

    guard let numNodes = consumeGroup(), let denNodes = consumeGroup() else { return nil }
    return (numNodes[0], denNodes[0])
}

func handleBinomCommand(tokens: ArraySlice<Token>, idx: inout Int) -> ASTNode? {
    let tokensArray = Array(tokens)
    guard idx < tokensArray.count else { return nil }
    let loc = tokensArray[idx].sourceLocation
    idx += 1
    guard let (num, den) = parseTwoBraceArgs(tokens: tokens, idx: &idx) else { return nil }
    return ASTNode(type: .frac, text: "binom", location: loc, childNodes: [num, den])
}

func handleDBinomCommand(tokens: ArraySlice<Token>, idx: inout Int) -> ASTNode? {
    let tokensArray = Array(tokens)
    guard idx < tokensArray.count else { return nil }
    let loc = tokensArray[idx].sourceLocation
    idx += 1
    guard let (num, den) = parseTwoBraceArgs(tokens: tokens, idx: &idx) else { return nil }
    let frac = ASTNode(type: .frac, text: "dbinom", location: loc, childNodes: [num, den])
    return ASTNode(type: .sizing, text: "displaystyle", location: loc, childNodes: [frac])
}

func handleTBinomCommand(tokens: ArraySlice<Token>, idx: inout Int) -> ASTNode? {
    let tokensArray = Array(tokens)
    guard idx < tokensArray.count else { return nil }
    let loc = tokensArray[idx].sourceLocation
    idx += 1
    guard let (num, den) = parseTwoBraceArgs(tokens: tokens, idx: &idx) else { return nil }
    let frac = ASTNode(type: .frac, text: "tbinom", location: loc, childNodes: [num, den])
    return ASTNode(type: .sizing, text: "textstyle", location: loc, childNodes: [frac])
}
