//
//  Token.swift
//  AlphaEqt
//
//  Created by Alpha Ng on 27/9/2025.
//
/// Represents the type/kind of a token in AlphaEqt's math parser.
public enum TokenKind {
    case whitespace
    case command
    case identifier
    case number
    case operatorSymbol
    case leftBrace, rightBrace, leftParen, rightParen, leftBracket, rightBracket
    case customDelimiterLeft
    case customDelimiterRight
    case verbatim 
    case eof
    case error
    case comment        // <-- Add this!
    case activeChar     // <-- Add if handling ~ as active character

}

public struct Token {
    public let kind: TokenKind
    public let text: String
    public let sourceLocation: SourceLocation   // <-- use your struct

    // Optionally, keep 'range' for backward compatibility if needed
}


