//
//  Radical.swift
//  AlphaEqt
//
//  Command handlers for \sqrt{radicand} and \sqrt[degree]{radicand}
//

import Foundation

extension LatexParser {

    /// Handles `\sqrt` and `\sqrt[degree]{radicand}` commands.
    /// - `\sqrt{x}` → `.sqrt` with child `x`
    /// - `\sqrt[3]{x}` → `.root` with children `[3, x]`
    /// - `\sqrt[3]x` → `.root` with children `[3, x]`
    internal func handleSqrtCommand(_ tokens: ArraySlice<Token>, _ index: inout Int) -> ASTNode? {
        var i = 0
        guard i < tokens.count else { return nil }
        let cmdToken = tokens[tokens.startIndex + i]
        i += 1

        let hasDegree: Bool
        var degreeNodes: [ASTNode]? = nil

        // Check for optional [degree]
        if i < tokens.count, tokens[tokens.startIndex + i].kind == .leftBracket {
            i += 1
            // Collect tokens inside [ ... ]
            var depth = 1
            var collected: [Token] = []
            while i < tokens.count, depth > 0 {
                let t = tokens[tokens.startIndex + i]
                if t.kind == .leftBracket { depth += 1 }
                else if t.kind == .rightBracket { depth -= 1 }
                if depth > 0 { collected.append(t) }
                i += 1
            }
            degreeNodes = parse(tokens: collected)
            hasDegree = !(degreeNodes?.isEmpty ?? true)
        } else {
            hasDegree = false
        }

        // Parse radicand: { ... } or single token
        let radicandNodes: [ASTNode]
        if i < tokens.count, tokens[tokens.startIndex + i].kind == .leftBrace {
            i += 1
            var depth = 1
            var collected: [Token] = []
            while i < tokens.count, depth > 0 {
                let t = tokens[tokens.startIndex + i]
                if t.kind == .leftBrace { depth += 1 }
                else if t.kind == .rightBrace { depth -= 1 }
                if depth > 0 { collected.append(t) }
                i += 1
            }
            radicandNodes = parse(tokens: collected)
        } else if i < tokens.count {
            let t = tokens[tokens.startIndex + i]
            if t.kind != .whitespace, t.kind != .eof, t.kind != .error {
                radicandNodes = parse(tokens: [t])
                i += 1
            } else {
                radicandNodes = []
            }
        } else {
            radicandNodes = []
        }

        index = i

        let radicandChild = radicandNodes.count == 1
            ? radicandNodes[0]
            : ASTNode(type: .ordgroup, text: nil, childNodes: radicandNodes.isEmpty ? nil : radicandNodes)

        if hasDegree, let deg = degreeNodes {
            let degreeChild = deg.count == 1
                ? deg[0]
                : ASTNode(type: .ordgroup, text: nil, childNodes: deg.isEmpty ? nil : deg)
            return ASTNode(
                type: .root,
                text: cmdToken.text,
                location: cmdToken.sourceLocation,
                originalText: cmdToken.text,
                childNodes: [degreeChild, radicandChild]
            )
        }

        return ASTNode(
            type: .sqrt,
            text: cmdToken.text,
            location: cmdToken.sourceLocation,
            originalText: cmdToken.text,
            childNodes: [radicandChild]
        )
    }
}
