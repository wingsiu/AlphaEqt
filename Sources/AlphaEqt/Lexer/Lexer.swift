import Foundation

@available(macOS 13.0, *)
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
        // Add more if needed
    ]

    // Patterns (unchanged)
    static let spacePattern = #"[ \r\n\t]+"#
    static let controlWordPattern = #"\\[a-zA-Z@]+"#
    static let controlSymbolPattern = #"\\[^a-zA-Z@]"#
    static let controlWordWhitespacePattern = #"\\([a-zA-Z@]+)([ \r\n\t]*)"#
    static let controlSpacePattern = #"\\(\n|[ \r\t]+\n?)[ \r\t]*"#
    static let identifierPattern = #"[A-Za-z]+"#
    static let numberPattern = #"\d+"#
    static let operatorPattern = #"[+\-*/^_=]"#
    //static let delimiterPattern = #"[{}()\[\]|]"#
    static let delimiterPattern = #"[{}()\[\]|~]"#
    static let tokenPattern = [
        spacePattern,
        controlWordWhitespacePattern,
        controlWordPattern,
        controlSymbolPattern,
        controlSpacePattern,
        identifierPattern,
        numberPattern,
        operatorPattern,
        delimiterPattern
    ].joined(separator: "|")

    public init(input: String) {
        self.input = input
    }

    public func tokenize() -> [Token] {
        var rawTokens: [Token] = []
        let regex = try! Regex(Self.tokenPattern)

        var currentIndex = input.startIndex
        while currentIndex < input.endIndex {
            if let match = input[currentIndex...].firstMatch(of: regex) {
                let tokenText = String(match.0)
                let range = input.range(of: tokenText, range: currentIndex..<input.endIndex)!
                // Check catcode for first character
                let catcode = Self.catcodes[tokenText.first ?? " "] ?? .other
                // If comment, skip to end of line
                if catcode == .comment {
                    if let nlIndex = input[currentIndex...].firstIndex(of: "\n") {
                        currentIndex = input.index(after: nlIndex)
                    } else {
                        // End of input
                        break
                    }
                    continue
                }
                rawTokens.append(Token(kind: classifyToken(tokenText, catcode: catcode), text: tokenText, range: range))
                currentIndex = range.upperBound
            } else {
                break
            }
        }

        // Custom delimiter combining logic (unchanged)
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
                    let combinedRange = rawTokens[i].range.lowerBound..<next.range.upperBound
                    tokens.append(Token(kind: .customDelimiterLeft, text: combinedText, range: combinedRange))
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
                    let combinedRange = rawTokens[i].range.lowerBound..<next.range.upperBound
                    tokens.append(Token(kind: .customDelimiterRight, text: combinedText, range: combinedRange))
                    i += 2
                    continue
                }
            }
            tokens.append(rawTokens[i])
            i += 1
        }

        tokens.append(Token(kind: .eof, text: "EOF", range: input.endIndex..<input.endIndex))
        return tokens
    }

    public func lexAll() -> [Token] {
        return tokenize()
    }

    public func scanTokens(_ tokens: [Token]) -> [Token] {
        return tokens
    }

    // Now pass catcode to classifyToken for advanced logic
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
        if text.range(of: #"^[+\-*/^_=]$"#, options: .regularExpression) != nil {
            return .operatorSymbol
        }
        return .error
    }
}
