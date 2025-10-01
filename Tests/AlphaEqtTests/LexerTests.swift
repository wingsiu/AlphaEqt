
//
//  LexerTests.swift
//  AlphaEqt
//
//  Created by Alpha Ng on 27/9/2025.
//

import XCTest
@testable import AlphaEqt

final class LexerTests: XCTestCase {
    func testCustomDelimiterParentheses() {
        let input = "\\left( x + y \\right)"
        let lexer = Lexer(input: input)
        let tokens = lexer.lexAll()
        for token in tokens {
            print("kind: \(token.kind), text: '\(token.text)'")
        }
        XCTAssertEqual(tokens[0].kind, .customDelimiterLeft)
        XCTAssertEqual(tokens[0].text, "\\left(")
        XCTAssertEqual(tokens[1].kind, .whitespace)
        // Print output for debugging:

        XCTAssertEqual(tokens[2].kind, .identifier)
        XCTAssertEqual(tokens[2].text, "x")
        XCTAssertEqual(tokens[3].kind, .whitespace)
        XCTAssertEqual(tokens[4].kind, .operatorSymbol)
        XCTAssertEqual(tokens[4].text, "+")
        XCTAssertEqual(tokens[5].kind, .whitespace)
        XCTAssertEqual(tokens[6].kind, .identifier)
        XCTAssertEqual(tokens[6].text, "y")
        XCTAssertEqual(tokens[7].kind, .whitespace)
        XCTAssertEqual(tokens[8].kind, .customDelimiterRight)
        XCTAssertEqual(tokens[8].text, "\\right)")
        XCTAssertEqual(tokens.last?.kind, .eof)
    }

    func testCustomDelimiterBrackets() {
        let input = "\\left[ a \\right]"
        let lexer = Lexer(input: input)
        let tokens = lexer.lexAll()
        for token in tokens {
            print("kind: \(token.kind), text: '\(token.text)'")
        }
        XCTAssertEqual(tokens[0].kind, .customDelimiterLeft)
        XCTAssertEqual(tokens[0].text, "\\left[")
        XCTAssertEqual(tokens[1].kind, .whitespace)
        XCTAssertEqual(tokens[2].kind, .identifier)
        XCTAssertEqual(tokens[2].text, "a")
        XCTAssertEqual(tokens[3].kind, .whitespace)
        XCTAssertEqual(tokens[4].kind, .customDelimiterRight)
        XCTAssertEqual(tokens[4].text, "\\right]")
        XCTAssertEqual(tokens.last?.kind, .eof)
    }

    func testCustomDelimiterBraces() {
        let input = "\\left\\{ x \\right\\}"
        let lexer = Lexer(input: input)
        let rawTokens = lexer.tokenize() // or whatever produces raw tokens
        for token in rawTokens {
            print("kind: \(token.kind), text: '\(token.text)'")
        }
        let tokens = lexer.lexAll()
        
        for token in tokens {
            print("kind: \(token.kind), text: '\(token.text)'")
        }
        XCTAssertEqual(tokens[0].kind, .customDelimiterLeft)
        XCTAssertEqual(tokens[0].text, "\\left{")
        XCTAssertEqual(tokens[1].kind, .whitespace)
        XCTAssertEqual(tokens[2].kind, .identifier)
        XCTAssertEqual(tokens[2].text, "x")
        XCTAssertEqual(tokens[3].kind, .whitespace)
        XCTAssertEqual(tokens[4].kind, .customDelimiterRight)
        XCTAssertEqual(tokens[4].text, "\\right}")
        XCTAssertEqual(tokens.last?.kind, .eof)
    }

    func testCustomDelimiterVerticalBar() {
        let input = "\\left| y \\right|"
        let lexer = Lexer(input: input)
        let tokens = lexer.lexAll()
        for token in tokens {
            print("kind: \(token.kind), text: '\(token.text)'")
        }
        XCTAssertEqual(tokens[0].kind, .customDelimiterLeft)
        XCTAssertEqual(tokens[0].text, "\\left|")
        XCTAssertEqual(tokens[1].kind, .whitespace)
        XCTAssertEqual(tokens[2].kind, .identifier)
        XCTAssertEqual(tokens[2].text, "y")
        XCTAssertEqual(tokens[3].kind, .whitespace)
        XCTAssertEqual(tokens[4].kind, .customDelimiterRight)
        XCTAssertEqual(tokens[4].text, "\\right|")
        XCTAssertEqual(tokens.last?.kind, .eof)
    }
    
    func testCommentSkipped() {
        let lexer = Lexer(input: "x % this is a comment\ny")
        let tokens = lexer.lexAll()
        let tokenTexts = tokens.map { $0.text }
        // Should skip everything after '%' until newline
        XCTAssertTrue(tokenTexts.contains("x"))
        XCTAssertFalse(tokenTexts.contains("%"))
        XCTAssertTrue(tokenTexts.contains("y"))
    }

    func testActiveChar() {
        let lexer = Lexer(input: "x~y")
        let tokens = lexer.lexAll()
        for token in tokens {
            print("token: \(token.text), kind: \(token.kind)")
        }
        // Should recognize '~' as active character
        XCTAssertTrue(tokens.contains { $0.kind == .activeChar && $0.text == "~" })
    }

    func testGroupingCharacters() {
        let lexer = Lexer(input: "{x}")
        let tokens = lexer.lexAll()
        // Should recognize '{' and '}' as left/right brace
        XCTAssertTrue(tokens.contains { $0.kind == .leftBrace && $0.text == "{" })
        XCTAssertTrue(tokens.contains { $0.kind == .rightBrace && $0.text == "}" })
    }

    func testCommandToken() {
        let lexer = Lexer(input: "\\left(")
        let tokens = lexer.lexAll()
        // Should recognize custom delimiter
        XCTAssertTrue(tokens.contains { $0.kind == .customDelimiterLeft && $0.text == "\\left(" })
    }

    func testIdentifierAndNumber() {
        let lexer = Lexer(input: "abc 123")
        let tokens = lexer.lexAll()
        XCTAssertTrue(tokens.contains { $0.kind == .identifier && $0.text == "abc" })
        XCTAssertTrue(tokens.contains { $0.kind == .number && $0.text == "123" })
    }

    func testOperatorToken() {
        let lexer = Lexer(input: "+ - * / ^ = _")
        let tokens = lexer.lexAll()
        let ops = ["+", "-", "*", "/", "^", "=", "_"]
        for op in ops {
            XCTAssertTrue(tokens.contains { $0.kind == .operatorSymbol && $0.text == op })
        }
    }

}

final class AccentUtilsTests: XCTestCase {

    func testUnicodeAccentToLatex_bar() async throws {
        let result = await AccentUtils.unicodeAccentToLatex("x̄") // x + U+0304
        XCTAssertEqual(result, "\\bar{x}")
    }

    func testUnicodeAccentToLatex_hat() async throws {
        let result = await AccentUtils.unicodeAccentToLatex("x̂") // x + U+0302
        XCTAssertEqual(result, "\\hat{x}")
    }

    func testUnicodeAccentToLatex_nonAccent() async throws {
        let result = await AccentUtils.unicodeAccentToLatex("x")
        XCTAssertEqual(result, "x")
    }

    func testPrecomposedAccentToLatex_acute() async throws {
        let result = await AccentUtils.precomposedAccentToLatex("á")
        XCTAssertEqual(result, "\\acute{a}")
    }

    func testPrecomposedAccentToLatex_cc() async throws {
        let result = await AccentUtils.precomposedAccentToLatex("ç")
        XCTAssertEqual(result, "\\cc")
    }

    func testPrecomposedAccentToLatex_nonAccent() async throws {
        let result = await AccentUtils.precomposedAccentToLatex("x")
        XCTAssertEqual(result, "x")
    }

    func testLatexMacroToUnicode_bar() {
        let result = AccentUtils.latexMacroToUnicode("bar", base: "x")
        XCTAssertEqual(result, "x̄")
    }

    func testLatexMacroToUnicode_hat() {
        let result = AccentUtils.latexMacroToUnicode("hat", base: "x")
        XCTAssertEqual(result, "x̂")
    }

    func testLatexMacroToUnicode_unknown() {
        let result = AccentUtils.latexMacroToUnicode("unknown", base: "x")
        XCTAssertEqual(result, "x")
    }
}

