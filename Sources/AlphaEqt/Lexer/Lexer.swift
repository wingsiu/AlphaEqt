//
//  Lexer.swift
//  AlphaEqt
//
//  Created by Alpha Ng on 27/9/2025.
//
import Foundation

public class Lexer {
    public let input: String
    private let tokenRegex: NSRegularExpression

    public init(input: String) {
        self.input = input

        // Define regex components
        let spaceRegexString = "[ \\r\\n\\t]"
        let controlWordRegexString = #"\\[a-zA-Z@]+"#
        let controlSymbolRegexString = #"\\[^\uD800-\uDFFF]"#
        let controlWordWhitespaceRegexString = #"(\#(controlWordRegexString))\#(spaceRegexString)*"#
        let controlSpaceRegexString = #"\\(\n|[ \r\t]+\n?)[ \r\t]*"#
        let combiningDiacriticalMarkString = #"[\u0300-\u036f]"#

        // Use a single raw string literal for the regex
        let tokenRegexString = #"""
        (\#(spaceRegexString)+)
        | \#(controlSpaceRegexString)
        | ([!\-\[\]-\u2027\u202A-\uD7FF\uF900-\uFFFF] \#(combiningDiacriticalMarkString)* )
        | [\uD800-\uDBFF][\uDC00-\uDFFF] \#(combiningDiacriticalMarkString)*
        | \\verb\*([^]).*?\4
        | \\verb([^*a-zA-Z]).*?\5
        | \#(controlWordWhitespaceRegexString)
        | \#(controlSymbolRegexString)
        """#

        // Remove whitespace and line breaks for regex compatibility
        let compactRegexString = tokenRegexString.replacingOccurrences(of: "\n", with: "").replacingOccurrences(of: " ", with: "")

        self.tokenRegex = try! NSRegularExpression(pattern: compactRegexString, options: [])
    }

    public func tokenize() -> [Token] {
        var tokens: [Token] = []
        let nsInput = input as NSString
        let matches = tokenRegex.matches(in: input, range: NSRange(location: 0, length: nsInput.length))
        for match in matches {
            guard let swiftRange = Range(match.range, in: input) else { continue }
            let tokenText = String(input[swiftRange])
            let kind: TokenKind = classifyToken(tokenText)
            tokens.append(Token(kind: kind, text: tokenText, range: swiftRange))
        }
        tokens.append(Token(kind: .eof, text: "EOF", range: input.endIndex..<input.endIndex))
        return tokens
    }

    // Scan tokens for grouping, macro expansion, etc.
    public func scanTokens(_ tokens: [Token]) -> [Token] {
        // Example: process grouping, environments, etc.
        // For now, this is a stub; add your context logic here.
        return tokens
    }

    private func classifyToken(_ text: String) -> TokenKind {
        // This is a simplified classifier, you will expand this for full KaTeX compatibility.
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .whitespace
        }
        if text.hasPrefix("\\left") {
            return .customDelimiterLeft
        }
        if text.hasPrefix("\\right") {
            return .customDelimiterRight
        }
        if text.hasPrefix("\\verb") {
            return .verbatim
        }
        if text.hasPrefix("\\") {
            // Check second character is a letter
            if text.count > 1 {
                let secondIndex = text.index(text.startIndex, offsetBy: 1)
                if text[secondIndex].isLetter {
                    return .command
                }
            }
            // Could be a control symbol
            return .command
        }
        if text.range(of: #"^\d+$"#, options: .regularExpression) != nil {
            return .number
        }
        if text.range(of: #"^[+\-*/^_=]$"#, options: .regularExpression) != nil {
            return .operatorSymbol
        }
        if text == "{" { return .leftBrace }
        if text == "}" { return .rightBrace }
        if text == "(" { return .leftParen }
        if text == ")" { return .rightParen }
        if text == "[" { return .leftBracket }
        if text == "]" { return .rightBracket }
        if text.range(of: #"^[A-Za-z]+$"#, options: .regularExpression) != nil {
            return .identifier
        }
        return .error
    }
}
