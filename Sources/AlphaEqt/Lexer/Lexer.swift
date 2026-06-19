//
//  Lexer.swift
//  AlphaEqt
//
//  Tokenizer for LaTeX math input. Does NOT require macOS 13+.
//

import Foundation

/// A simple lexer/tokenizer for LaTeX math expressions.
/// Uses NSRegularExpression for broad platform compatibility (iOS 15+, macOS 12+).
public class Lexer {
    public let input: String

    // Catcode definitions (similar to TeX/KaTeX)
    public enum Catcode: Int, Sendable {
        case escape = 0
        case beginGroup = 1
        case endGroup = 2
        case mathShift = 3
        case alignmentTab = 4
        case endOfLine = 5
        case parameter = 6
        case superscript = 7
        case subscriptChar = 8
        case ignored = 9
        case space = 10
        case letter = 11
        case other = 12
        case active = 13
        case comment = 14
        case invalid = 15
    }

    public static let catcodes: [Character: Catcode] = [
        "%": .comment,
        "~": .active,
        "{": .beginGroup,
        "}": .endGroup,
        "\\": .escape
    ]

    // Combined token pattern as NSRegularExpression
    // Single-letter identifiers for math mode (mc^2 → m, c, ^, 2)
    // Commands like \text still work via \\[a-zA-Z@]+
    static let tokenPattern: NSRegularExpression = {
        let pattern = #"([ \r\n\t]+|\\([a-zA-Z@]+)([ \r\n\t]*)|\\[a-zA-Z@]+|\\[^a-zA-Z@]|\\(\n|[ \r\t]+\n?)[ \r\t]*|[A-Za-z]|\d+|[+\-*/^_=.,]|[{}()\[\]|~]|[^\x00-\x7F])"#
        return try! NSRegularExpression(pattern: pattern, options: [])
    }()

    public init(input: String) {
        self.input = input
    }

    public func tokenize() -> [Token] {
        let nsRange = NSRange(location: 0, length: input.utf16.count)
        let matches = Self.tokenPattern.matches(in: input, options: [], range: nsRange)
        var rawTokens: [Token] = []
        var lastEnd = 0

        for match in matches {
            let matchRange = match.range
            // If there's a gap (non-matching characters), skip them
            if matchRange.location > lastEnd {
                // Skip unrecognized characters (they'll be treated as individual symbols)
            }
            lastEnd = matchRange.upperBound

            guard let range = Range(matchRange, in: input) else { continue }
            var tokenText = String(input[range])

            // Determine catcode from first character
            let catcode = Self.catcodes[tokenText.first ?? " "] ?? .other

            // Handle comments - skip until end of line
            if catcode == .comment {
                continue
            }

            // Strip trailing whitespace from command tokens: the regex
            // \\\\[a-zA-Z@]+([ \\r\\n\\t]*) captures the trailing space
            // into the token, which breaks handler lookups (e.g. "\alpha "
            // does not match "\alpha" in the commandHandlers dictionary).
            if catcode == .escape && tokenText.hasPrefix("\\") {
                tokenText = tokenText.trimmingCharacters(in: .whitespacesAndNewlines)
            }

            let offset = input.distance(from: input.startIndex, to: range.lowerBound)
            let length = input.distance(from: range.lowerBound, to: range.upperBound)

            // Compute line/column
            let substring = input[input.startIndex..<range.lowerBound]
            let lineNumber = substring.reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
            let columnNumber: Int
            if let lastNewline = substring.lastIndex(of: "\n") {
                columnNumber = input.distance(from: lastNewline, to: range.lowerBound)
            } else {
                columnNumber = offset + 1
            }

            let sourceLocation = SourceLocation(line: lineNumber, column: columnNumber, offset: offset, length: length)
            let kind = classifyToken(tokenText, catcode: catcode)
            rawTokens.append(Token(kind: kind, text: tokenText, sourceLocation: sourceLocation))
        }

        // Combine \left/ \right with delimiter
        var tokens: [Token] = []
        var i = 0
        while i < rawTokens.count {
            if rawTokens[i].kind == .command && rawTokens[i].text == "\\left" && (i + 1) < rawTokens.count {
                let next = rawTokens[i + 1]
                let delimMap: [TokenKind: String] = [
                    .leftParen: "\\left(",
                    .leftBracket: "\\left[",
                    .leftBrace: "\\left{",
                    .operatorSymbol: "\\left|"
                ]
                if let combinedText = delimMap[next.kind] {
                    let combinedLoc = rawTokens[i].sourceLocation
                    let combinedEnd = next.sourceLocation
                    let combinedSourceLocation = SourceLocation(
                        line: combinedLoc.line,
                        column: combinedLoc.column,
                        offset: combinedLoc.offset,
                        length: (combinedEnd.offset + combinedEnd.length) - combinedLoc.offset
                    )
                    tokens.append(Token(kind: .customDelimiterLeft, text: combinedText, sourceLocation: combinedSourceLocation))
                    i += 2
                    continue
                }
            }
            if rawTokens[i].kind == .command && rawTokens[i].text == "\\right" && (i + 1) < rawTokens.count {
                let next = rawTokens[i + 1]
                let delimMap: [TokenKind: String] = [
                    .rightParen: "\\right)",
                    .rightBracket: "\\right]",
                    .rightBrace: "\\right}",
                    .operatorSymbol: "\\right|"
                ]
                if let combinedText = delimMap[next.kind] {
                    let combinedLoc = rawTokens[i].sourceLocation
                    let combinedEnd = next.sourceLocation
                    let combinedSourceLocation = SourceLocation(
                        line: combinedLoc.line,
                        column: combinedLoc.column,
                        offset: combinedLoc.offset,
                        length: (combinedEnd.offset + combinedEnd.length) - combinedLoc.offset
                    )
                    tokens.append(Token(kind: .customDelimiterRight, text: combinedText, sourceLocation: combinedSourceLocation))
                    i += 2
                    continue
                }
            }
            tokens.append(rawTokens[i])
            i += 1
        }

        // Add EOF token
        let eofLine = input.reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
        let eofOffset = input.count
        let eofLocation = SourceLocation(line: eofLine, column: 1, offset: eofOffset, length: 0)
        tokens.append(Token(kind: .eof, text: "EOF", sourceLocation: eofLocation))
        return tokens
    }

    public func lexAll() -> [Token] {
        return tokenize()
    }

    public func scanTokens(_ tokens: [Token]) -> [Token] {
        return tokens
    }

    private func classifyToken(_ text: String, catcode: Catcode) -> TokenKind {
        switch catcode {
        case .comment:
            return .comment
        case .active:
            return .activeChar
        case .beginGroup:
            return .leftBrace
        case .endGroup:
            return .rightBrace
        case .escape:
            if text == "\\left" { return .command }
            if text == "\\right" { return .command }
            if text == "\\{" { return .leftBrace }
            if text == "\\}" { return .rightBrace }
            if text == "\\|" { return .operatorSymbol }
            return .command
        default:
            break
        }
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .whitespace
        }
        if text == "(" { return .leftParen }
        if text == ")" { return .rightParen }
        if text == "[" { return .leftBracket }
        if text == "]" { return .rightBracket }
        if text == "|" { return .operatorSymbol }
        if text.range(of: #"^[A-Za-z]+$"#, options: .regularExpression) != nil {
            return .identifier
        }
        if text.range(of: #"^\d+$"#, options: .regularExpression) != nil {
            return .number
        }
        if text.range(of: #"^[+\-*/^_=.,]$"#, options: .regularExpression) != nil {
            return .operatorSymbol
        }
        // Non-ASCII characters (emoji, Chinese, etc.) → mathord identifiers
        if let first = text.unicodeScalars.first, first.value > 0x7F {
            return .identifier
        }
        return .error
    }
}
