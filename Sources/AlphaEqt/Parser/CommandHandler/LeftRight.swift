//
//  LeftRight.swift
//  AlphaEqt
//
//  Parser handler for \left...\right delimiter pairs.
//  The lexer already combines \left( → \left( token, etc.
//

import Foundation

/// Parses `\left<delim> ... \right<delim>` into a `.leftright` AST node.
/// The lexer already merges `\left` + delimiter into a single
/// `.customDelimiterLeft` token (e.g., `\left(`), and similarly
/// `\right` + delimiter into `.customDelimiterRight`.
func handleLeftRightCommand(tokens: ArraySlice<Token>, index: inout Int) -> ASTNode? {
    let leftToken = tokens[tokens.startIndex]
    // Extract delimiter char from combined token text
    let leftText = leftToken.text  // e.g., "\left(", "\left[", "\left|"
    guard leftText.hasPrefix("\\left"), leftText.count > 5 else { return nil }
    let leftDelim = String(leftText.suffix(from: leftText.index(leftText.startIndex, offsetBy: 5)))

    // Find matching \right
    var depth = 0
    var innerTokens: [Token] = []
    var rightDelim = ""
    var i = tokens.startIndex + 1
    while i < tokens.endIndex {
        let t = tokens[i]
        if t.kind == .customDelimiterLeft {
            depth += 1
            innerTokens.append(t)
        } else if t.kind == .customDelimiterRight {
            if depth == 0 {
                // Found matching \right
                let rightText = t.text  // e.g., "\right)", "\right]"
                if rightText.hasPrefix("\\right"), rightText.count > 6 {
                    rightDelim = String(rightText.suffix(from: rightText.index(rightText.startIndex, offsetBy: 6)))
                }
                break
            } else {
                depth -= 1
                innerTokens.append(t)
            }
        } else {
            innerTokens.append(t)
        }
        i += 1
    }

    // Parse inner content
    let parser = LatexParser()
    let innerNodes = parser.parse(tokens: innerTokens)

    // Build .leftright node with children: [innerGroup, left, right]
    // left and right are stored as metadata (the delimiter chars)
    let innerGroup = ASTNode(type: .ordgroup, text: nil, childNodes: innerNodes.isEmpty ? nil : innerNodes)

    index = i - tokens.startIndex + 1  // advance past \right token
    // Use \0 separator to avoid collisions with delimiter chars (e.g. "|")
    return ASTNode(
        type: .leftright,
        text: "\(leftDelim)\0\(rightDelim)",
        childNodes: [innerGroup]
    )
}
