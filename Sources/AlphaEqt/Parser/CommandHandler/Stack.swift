//
//  Stack.swift
//  AlphaEqt
//

import Foundation

private func parseStackArgs(tokens: ArraySlice<Token>, index: inout Int) -> (ASTNode, ASTNode)? {
    let tokensArray = Array(tokens)
    guard tokensArray.count >= 5 else { index = 1; return nil }

    func parseOneArg(start: Int) -> (ASTNode, Int)? {
        var i = start
        guard i < tokensArray.endIndex, tokensArray[i].kind == .leftBrace else { return nil }
        i += 1
        var depth = 1
        var content: [Token] = []
        while i < tokensArray.endIndex, depth > 0 {
            let t = tokensArray[i]
            if t.kind == .leftBrace { depth += 1 }
            else if t.kind == .rightBrace { depth -= 1 }
            if depth > 0 { content.append(t) }
            i += 1
        }
        let nodes = LatexParser().parse(tokens: content)
        let node: ASTNode
        if nodes.isEmpty { node = ASTNode(type: .mathord, text: "") }
        else if nodes.count == 1 { node = nodes[0] }
        else { node = ASTNode(type: .ordgroup, text: nil, childNodes: nodes) }
        return (node, i)
    }

    guard let (script, nextIdx) = parseOneArg(start: tokensArray.startIndex + 1) else {
        index = 1; return nil
    }
    guard let (base, endIdx) = parseOneArg(start: nextIdx) else { index = 1; return nil }
    index = endIdx - tokensArray.startIndex
    return (script, base)
}

func handleOversetCommand(tokens: ArraySlice<Token>, index: inout Int) -> ASTNode? {
    guard let (script, base) = parseStackArgs(tokens: tokens, index: &index) else { return nil }
    return ASTNode(type: .stack, text: "overset", childNodes: [script, base])
}

func handleUndersetCommand(tokens: ArraySlice<Token>, index: inout Int) -> ASTNode? {
    guard let (script, base) = parseStackArgs(tokens: tokens, index: &index) else { return nil }
    return ASTNode(type: .stack, text: "underset", childNodes: [script, base])
}
