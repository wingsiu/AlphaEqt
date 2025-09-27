//
//  Token.swift
//  AlphaEqt
//
//  Created by Alpha Ng on 27/9/2025.
//
public enum Token {
    case number(String)         // e.g. "123", "3.14"
    case identifier(String)     // e.g. "x", "y"
    case operatorSymbol(String) // "+", "-", "*", "/", "^", "_"
    case command(String)        // LaTeX command e.g. "\\frac", "\\sqrt"
    case leftParen              // "("
    case rightParen             // ")"
    case leftBracket            // "["
    case rightBracket           // "]"
    case leftBrace              // "{"
    case rightBrace             // "}"
    case whitespace
    case error(String)          // For unknown/invalid input
}


