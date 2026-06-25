//
//  Overline.swift
//  AlphaEqt
//
//  Parser handlers for \overline and \underline.
//

import Foundation

func handleOverlineCommand(tokens: ArraySlice<Token>, index: inout Int) -> ASTNode? {
    handleLineCommand(tokens: tokens, index: &index, type: .overline)
}

func handleUnderlineCommand(tokens: ArraySlice<Token>, index: inout Int) -> ASTNode? {
    handleLineCommand(tokens: tokens, index: &index, type: .underline)
}

private func handleLineCommand(
    tokens: ArraySlice<Token>,
    index: inout Int,
    type: ASTNodeType
) -> ASTNode? {
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

    let parser = LatexParser()
    let contentNodes = parser.parse(tokens: contentTokens)
    let childNodes: [ASTNode] = contentNodes.isEmpty
        ? [ASTNode(type: .mathord, text: "")]
        : contentNodes

    index = i - tokensArray.startIndex
    return ASTNode(type: type, childNodes: childNodes)
}
