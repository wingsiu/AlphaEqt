//
//  LatexParser.swift
//  AlphaEqt
//
//  Created by Alpha Ng on 2/10/2025.
//
import Foundation

// Import command handlers from separate files
// Each handler should be defined as: func handle<Text|Sqrt|Frac|...>Command(tokens: ArraySlice<Token>, idx: inout Int) -> ASTNode?
// For example, Text.swift contains handleTextCommand

public class LatexParser {
    public typealias CommandHandler = (ArraySlice<Token>, inout Int) -> ASTNode?

    private var commandHandlers: [String: CommandHandler] = [:]

    public init() {
        // Register built-in commands with their handlers
        commandHandlers["\\text"] = handleTextCommand
        // Example: commandHandlers["\\sqrt"] = handleSqrtCommand
        // Add more as needed
    }

    /// Main parse function
    public func parse(tokens: [Token]) -> [ASTNode] {
        var nodes: [ASTNode] = []
        var i = 0
        let tokenCount = tokens.count
        while i < tokenCount {
            let token = tokens[i]
            guard shouldParseToken(token) else { i += 1; continue }

            // Command handler dispatch
            if token.kind == .command, let handler = commandHandlers[token.text] {
                let slice = tokens[i..<tokenCount]
                var relIdx = 0 // index relative to slice
                if let node = handler(slice, &relIdx) {
                    nodes.append(node)
                }
                i += relIdx
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

    /// Determines if a token should be parsed into an ASTNode
    private func shouldParseToken(_ token: Token) -> Bool {
        switch token.kind {
        case .whitespace, .eof, .error:
            return false
        default:
            return true
        }
    }

    /// Maps TokenKind and text to ASTNodeType
    private func mapTokenKindToASTNodeType(_ token: Token) -> ASTNodeType {
        switch token.kind {
        case .identifier, .number, .verbatim:
            return .mathord
        case .operatorSymbol:
            switch token.text {
            case "+", "-", "*", "/":
                return .bin
            case "=", "<", ">", "<=", ">=":
                return .rel
            default:
                return .bin // fallback for other operators
            }
        case .leftParen, .leftBracket, .leftBrace, .customDelimiterLeft:
            return .open
        case .rightParen, .rightBracket, .rightBrace, .customDelimiterRight:
            return .close
        case .command:
            return .textord
        default:
            return .mathord // fallback for any other kind
        }
    }

    /// Register a new command handler externally
    public func registerCommand(_ name: String, handler: @escaping CommandHandler) {
        commandHandlers[name] = handler
    }
}
