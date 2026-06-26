//
//  XArrow.swift
//  AlphaEqt
//

import Foundation

private let xArrowNames: Set<String> = [
    "xrightarrow", "xleftarrow", "xRightarrow", "xLeftarrow",
    "xleftrightarrow", "xLeftrightarrow",
]

func handleXArrowCommand(tokens: ArraySlice<Token>, index: inout Int) -> ASTNode? {
    let tokensArray = Array(tokens)
    guard tokensArray.count >= 2 else { index = 1; return nil }
    let rawCmd = tokensArray[tokensArray.startIndex].text
    let name = rawCmd.hasPrefix("\\") ? String(rawCmd.dropFirst()) : ""
    guard xArrowNames.contains(name) else { index = 1; return nil }

    var i = tokensArray.startIndex + 1
    var below: ASTNode?
    if i < tokensArray.endIndex, tokensArray[i].kind == .leftBracket {
        i += 1
        var depth = 1
        var content: [Token] = []
        while i < tokensArray.endIndex, depth > 0 {
            let t = tokensArray[i]
            if t.kind == .leftBracket { depth += 1 }
            else if t.kind == .rightBracket { depth -= 1 }
            if depth > 0 { content.append(t) }
            i += 1
        }
        let nodes = LatexParser().parse(tokens: content)
        if !nodes.isEmpty {
            below = nodes.count == 1 ? nodes[0] : ASTNode(type: .ordgroup, text: nil, childNodes: nodes)
        }
    }

    guard i < tokensArray.endIndex, tokensArray[i].kind == .leftBrace else { index = 1; return nil }
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
    let above: ASTNode
    if nodes.isEmpty { above = ASTNode(type: .mathord, text: "") }
    else if nodes.count == 1 { above = nodes[0] }
    else { above = ASTNode(type: .ordgroup, text: nil, childNodes: nodes) }

    index = i - tokensArray.startIndex
    var children = [above]
    if let below { children.append(below) }
    return ASTNode(type: .xarrow, text: name, childNodes: children)
}
