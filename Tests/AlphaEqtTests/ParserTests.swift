//
//  ParserTests.swift
//  AlphaEqt
//
//  Created by Alpha Ng on 2/10/2025.
//
import XCTest
@testable import AlphaEqt

final class ParserTests: XCTestCase {
    func testSimpleLatexParsing() {
        let input = "a + b - 3 = 4"
        let lexer = Lexer(input: input)
        let tokens = lexer.lexAll()
        let parser = LatexParser()
        let astNodes = parser.parse(tokens: tokens)
        
        for node in astNodes {
            print(node.description)
        }
    }
    
    func testOpenCloseTextordErrorWhitespace() {
        let cases: [(String, [ASTNodeType])] = [
            // Flat bracket cases remain unchanged
            ("(a) [b] {c}", [.open, .mathord, .close, .open, .mathord, .close, .open, .mathord, .close]),
            ("$ a + b", [.mathord, .bin, .mathord]), // error/skipped
            // \text{hello} now yields one .text node
            ("\\text{hello}", [.text]),
            ("a   +    b", [.mathord, .bin, .mathord]), // whitespace skipped
            // \text{ x } + [ y ] now yields .text, .bin, .open, .mathord, .close
            ("\\text{ x } + [ y ]", [.text, .bin, .open, .mathord, .close])
        ]
        for (input, expectedTypes) in cases {
            let lexer = Lexer(input: input)
            let tokens = lexer.lexAll()
            let parser = LatexParser()
            let astNodes = parser.parse(tokens: tokens)
            print("Input: \(input)")
            for node in astNodes {
                print(node.description)
            }
            XCTAssertEqual(astNodes.map{ $0.type }, expectedTypes)
        }
    }
}
