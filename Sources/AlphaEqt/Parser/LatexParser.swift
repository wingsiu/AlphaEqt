import Foundation

/// Parses a sequence of Tokens into ASTNode objects for basic math.
/// Extendable for more complex LaTeX constructs.
public class LatexParser {
    public init() {}

    /// Parses an array of Token objects into ASTNode objects.
    /// Ignores whitespace and EOF tokens.
    public func parse(tokens: [Token]) -> [ASTNode] {
        var nodes: [ASTNode] = []
        for token in tokens {
            guard shouldParseToken(token) else { continue }
            let nodeType = mapTokenKindToASTNodeType(token)
            let node = ASTNode(
                type: nodeType,
                text: token.text,
                originalText: token.text
            )
            nodes.append(node)
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
            // You may want to handle commands later, e.g. \frac, \sqrt
            return .textord
        default:
            return .mathord // fallback for any other kind
        }
    }
}
