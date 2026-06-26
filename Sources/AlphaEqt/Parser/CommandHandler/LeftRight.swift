//
//  LeftRight.swift
//  AlphaEqt
//
//  Parser handler for \left...\right delimiter pairs (with optional \middle).
//

import Foundation

/// Parses `\left<delim> ... [\middle<delim> ...]* \right<delim>` into a `.leftright` AST node.
func handleLeftRightCommand(tokens: ArraySlice<Token>, index: inout Int) -> ASTNode? {
    let leftToken = tokens[tokens.startIndex]
    guard leftToken.kind == .customDelimiterLeft else { return nil }
    let leftDelim = DelimiterUtils.leftDelimiter(from: leftToken.text)

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
                rightDelim = DelimiterUtils.rightDelimiter(from: t.text)
                i += 1
                break
            }
            depth -= 1
            innerTokens.append(t)
        } else {
            innerTokens.append(t)
        }
        i += 1
    }

    let segments = splitOnMiddle(innerTokens)
    let parser = LatexParser()
    var segmentNodes: [ASTNode] = []
    for seg in segments {
        let innerNodes = parser.parse(tokens: seg)
        let group = ASTNode(type: .ordgroup, text: nil,
                            childNodes: innerNodes.isEmpty ? nil : innerNodes)
        segmentNodes.append(group)
    }

    index = i - tokens.startIndex
    let middleDelims = extractMiddleDelimiters(innerTokens)
    let meta = "\(leftDelim)\0\(rightDelim)\0\(middleDelims.joined(separator: "\0"))"
    return ASTNode(type: .leftright, text: meta, childNodes: segmentNodes)
}

private func splitOnMiddle(_ tokens: [Token]) -> [[Token]] {
    var segments: [[Token]] = [[]]
    var depth = 0
    for t in tokens {
        if t.kind == .customDelimiterLeft { depth += 1 }
        else if t.kind == .customDelimiterRight { depth -= 1 }
        if t.kind == .customDelimiterMiddle && depth == 0 {
            segments.append([])
            continue
        }
        segments[segments.count - 1].append(t)
    }
    return segments
}

private func extractMiddleDelimiters(_ tokens: [Token]) -> [String] {
    var depth = 0
    var delims: [String] = []
    for t in tokens {
        if t.kind == .customDelimiterLeft { depth += 1 }
        else if t.kind == .customDelimiterRight { depth -= 1 }
        else if t.kind == .customDelimiterMiddle && depth == 0 {
            delims.append(DelimiterUtils.middleDelimiter(from: t.text))
        }
    }
    return delims
}
