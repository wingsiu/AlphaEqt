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
        
        XCTAssertEqual(tokens[0].kind, .customDelimiterLeft)
        XCTAssertEqual(tokens[0].text, "\\left(")
        XCTAssertEqual(tokens[1].kind, .whitespace)
        // Print output for debugging:
            for token in tokens {
                print("kind: \(token.kind), text: '\(token.text)'")
            }
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
        let tokens = lexer.lexAll()
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
}
