//
//  LatexParser.swift
//  AlphaEqt
//
//  Created by Alpha Ng on 2/10/2025.
//

import Foundation

public class LatexParser {
    public typealias CommandHandler = (ArraySlice<Token>, inout Int) -> ASTNode?

    private var commandHandlers: [String: CommandHandler] = [:]

    public init() {
        commandHandlers["\\text"] = handleTextCommand
        commandHandlers["\\frac"] = handleFracCommand
        commandHandlers["\\sqrt"] = handleSqrtCommand
        // Style-change commands (TeX Appendix G)
        commandHandlers["\\displaystyle"] = handleSizingCommand
        commandHandlers["\\textstyle"] = handleSizingCommand
        commandHandlers["\\scriptstyle"] = handleSizingCommand
        commandHandlers["\\scriptscriptstyle"] = handleSizingCommand
        // \dfrac = displaystyle fraction, \tfrac = textstyle fraction
        commandHandlers["\\dfrac"] = handleFracSizingCommand(style: "displaystyle")
        commandHandlers["\\tfrac"] = handleFracSizingCommand(style: "textstyle")
        // Large operator commands
        let largeOps = ["\\sum", "\\prod", "\\coprod", "\\int", "\\iint", "\\iiint", "\\iiiint",
                        "\\oint", "\\bigcap", "\\bigcup", "\\bigvee", "\\bigwedge",
                        "\\bigodot", "\\bigoplus", "\\bigotimes", "\\bigsqcup", "\\biguplus",
                        "\\lim", "\\limsup", "\\liminf", "\\max", "\\min",
                        "\\sup", "\\inf", "\\det", "\\gcd", "\\Pr",
                        "\\sin", "\\cos", "\\tan", "\\csc", "\\sec", "\\cot",
                        "\\arcsin", "\\arccos", "\\arctan", "\\arccot", "\\arcsec", "\\arccsc",
                        "\\sinh", "\\cosh", "\\tanh", "\\coth", "\\sech", "\\csch",
                        "\\arcsinh", "\\arccosh", "\\arctanh", "\\arccoth", "\\arcsech", "\\arccsch",
                        "\\log", "\\lg", "\\ln", "\\exp",
                        "\\arg", "\\ker", "\\deg", "\\dim", "\\hom", "\\mod"]
        for op in largeOps {
            commandHandlers[op] = handleLargeOpCommand
        }
        // Greek letters + math symbols (Symbols.swift)
        for cmd in allSymbolCommands {
            commandHandlers[cmd] = handleSymbolCommand
        }
        // Spacing commands
        let spacingCmds = ["\\quad", "\\qquad", "\\,", "\\;", "\\!"]
        for cmd in spacingCmds {
            commandHandlers[cmd] = handleSpacingCommand
        }
        // Matrix environments (trigger on \begin)
        commandHandlers["\\begin"] = handleBeginMatrixCommand
        // Left/right delimiter pairs — trigger on \left + \right
        commandHandlers["\\left("] = handleLeftRightCommand
        commandHandlers["\\left["] = handleLeftRightCommand
        commandHandlers["\\left{"] = handleLeftRightCommand
        commandHandlers["\\left|"] = handleLeftRightCommand
        commandHandlers["\\left."] = handleLeftRightCommand
        // Accent commands
        let accentCmds = ["\\hat", "\\bar", "\\tilde", "\\dot", "\\ddot", "\\vec",
                          "\\widehat", "\\widetilde", "\\check", "\\breve", "\\acute", "\\grave",
                          "\\arc",
                          "\\overrightarrow", "\\overleftarrow", "\\overleftrightarrow"]
        for cmd in accentCmds {
            commandHandlers[cmd] = handleAccentCommand
        }
        commandHandlers["\\overline"] = handleOverlineCommand
        commandHandlers["\\underline"] = handleUnderlineCommand
        // Color commands
        commandHandlers["\\color"] = handleColorCommand
        commandHandlers["\\textcolor"] = handleColorCommand
        commandHandlers["\\colorbox"] = handleColorboxCommand
        commandHandlers["\\fcolorbox"] = handleColorboxCommand
        // Font commands — consume braced arg, parse content inline
        let fontCmds = ["\\mathbf", "\\mathrm", "\\mathit", "\\mathsf",
                        "\\mathtt", "\\mathcal", "\\mathbb", "\\mathfrak",
                        "\\mathbfit", "\\bm", "\\boldsymbol",
                        "\\rm", "\\bf", "\\cal", "\\mit", "\\frak", "\\Bbb",
                        "\\textsf", "\\texttt", "\\textit", "\\textbf",
                        "\\mathnormal", "\\boldsymbol"]
        for cmd in fontCmds {
            commandHandlers[cmd] = handleFontCommand
        }
    }

    // MARK: - Main parse

    public func parse(tokens: [Token]) -> [ASTNode] {
        var nodes: [ASTNode] = []
        var i = 0
        let tokenCount = tokens.count
        while i < tokenCount {
            let token = tokens[i]
            guard shouldParseToken(token) else { i += 1; continue }

            // Command handler dispatch (handles .command and .customDelimiterLeft)
            if (token.kind == .command || token.kind == .customDelimiterLeft),
               let handler = commandHandlers[token.text] {
                let slice = tokens[i..<tokenCount]
                var relIdx = 0
                if let node = handler(slice, &relIdx) {
                    nodes.append(node)
                }
                i += relIdx
                continue
            }

            // Handle braced groups: {...} → ordgroup
            if token.kind == .leftBrace {
                i += 1
                var depth = 1
                var groupTokens: [Token] = []
                while i < tokenCount, depth > 0 {
                    let t = tokens[i]
                    if t.kind == .leftBrace { depth += 1 }
                    else if t.kind == .rightBrace { depth -= 1 }
                    if depth > 0 { groupTokens.append(t) }
                    i += 1
                }
                let groupNodes = parse(tokens: groupTokens)
                let groupNode = ASTNode(type: .ordgroup, text: nil, childNodes: groupNodes.isEmpty ? nil : groupNodes)
                nodes.append(groupNode)
                continue
            }

            // Handle ^ and _ (superscript/subscript)
            if (token.text == "^" || token.text == "_") && !nodes.isEmpty {
                i = consumeSupSub(tokens, at: i, nodes: &nodes)
                continue
            }

            // Handle \limits / \nolimits (postfix modifier for .op nodes)
            if (token.text == "\\limits" || token.text == "\\nolimits"),
               token.kind == .command,
               let lastNode = nodes.last,
               lastNode.type == .op {
                lastNode.limitMode = (token.text == "\\limits") ? .limits : .nolimits
                i += 1
                continue
            }

            let nodeType = mapTokenKindToASTNodeType(token)
            let node = ASTNode(
                type: nodeType,
                text: token.text,
                location: token.sourceLocation,
                originalText: token.text,
                childNodes: nil
            )
            nodes.append(node)
            i += 1
        }
        return nodes
    }

    // MARK: - Superscript / Subscript (recursive)

    private func consumeSupSub(_ tokens: [Token], at i: Int, nodes: inout [ASTNode]) -> Int {
        let isSup = tokens[i].text == "^"
        var idx = i + 1

        let scriptTokens: [Token]
        if idx < tokens.count, tokens[idx].kind == .leftBrace {
            idx += 1
            var depth = 1
            var collected: [Token] = []
            while idx < tokens.count, depth > 0 {
                let t = tokens[idx]
                if t.kind == .leftBrace { depth += 1 }
                else if t.kind == .rightBrace { depth -= 1 }
                if depth > 0 { collected.append(t) }
                idx += 1
            }
            scriptTokens = collected
        } else if idx < tokens.count, shouldParseToken(tokens[idx]) {
            scriptTokens = [tokens[idx]]
            idx += 1
        } else {
            scriptTokens = []
        }

        let scriptNodes = parse(tokens: scriptTokens)
        let base = nodes.removeLast()

        let supNode: ASTNode
        let subNode: ASTNode
        if isSup {
            supNode = scriptNodes.count == 1
                ? scriptNodes[0]
                : ASTNode(type: .ordgroup, text: nil, childNodes: scriptNodes.isEmpty ? nil : scriptNodes)
            subNode = ASTNode(type: .mathord, text: "")
        } else {
            supNode = ASTNode(type: .mathord, text: "")
            subNode = scriptNodes.count == 1
                ? scriptNodes[0]
                : ASTNode(type: .ordgroup, text: nil, childNodes: scriptNodes.isEmpty ? nil : scriptNodes)
        }

        if base.type == .supsub {
            var children = base.childNodes ?? []
            while children.count < 3 {
                children.append(ASTNode(type: .mathord, text: ""))
            }
            if isSup { children[1] = supNode }
            else { children[2] = subNode }
            base.childNodes = children
            nodes.append(base)
        } else {
            let supsub = ASTNode(type: .supsub, text: nil, childNodes: [base, supNode, subNode])
            nodes.append(supsub)
        }
        return idx
    }

    // MARK: - Token helpers

    private func shouldParseToken(_ token: Token) -> Bool {
        switch token.kind {
        case .whitespace, .eof, .error, .lineBreak, .alignmentTab: return false
        default: return true
        }
    }

    private func mapTokenKindToASTNodeType(_ token: Token) -> ASTNodeType {
        switch token.kind {
        case .identifier, .number, .verbatim: return .mathord
        case .operatorSymbol:
            switch token.text {
            case "+", "-", "*", "/": return .bin
            case "=", "<", ">": return .rel
            case ".", ",": return .mathord
            default: return .bin
            }
        case .leftParen, .leftBracket, .leftBrace, .customDelimiterLeft: return .open
        case .rightParen, .rightBracket, .rightBrace, .customDelimiterRight: return .close
        case .command: return .textord
        default: return .mathord
        }
    }

    public func registerCommand(_ name: String, handler: @escaping CommandHandler) {
        commandHandlers[name] = handler
    }
}
