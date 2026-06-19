//
//  ParserTests.swift
//  AlphaEqt
//
//  Created by Alpha Ng on 2/10/2025.
//
import XCTest
@testable import AlphaEqt

final class ParserTests: XCTestCase {
    func testSupSubscriptParsing() {
        let cases: [(String, Int)] = [
            ("x^2", 1),      // single supsub node
            ("x_1", 1),      // single subscript node
            ("x_i^2", 1),    // combined (nested supsub)
            ("a + b", 3),    // no supsub
            ("a_{ij}", 1),   // braced subscript
            ("E = mc^2", 4), // mixed
        ]
        for (input, expectedCount) in cases {
            let lexer = Lexer(input: input)
            let tokens = lexer.lexAll()
            let parser = LatexParser()
            let astNodes = parser.parse(tokens: tokens)
            print("Input: \(input) -> \(astNodes.count) nodes")
            for node in astNodes {
                print("  \(node.type.rawValue) text='\(node.text ?? "")'")
                if let kids = node.childNodes {
                    for k in kids {
                        print("    child: \(k.type.rawValue) text='\(k.text ?? "")'")
                    }
                }
            }
            XCTAssertEqual(astNodes.count, expectedCount, "Failed for input: \(input)")
        }
    }

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
    
    func testFracNode() {
        let input = "\\frac{a}{b}"
        let lexer = Lexer(input: input)
        let tokens = lexer.lexAll()
        let parser = LatexParser()
        let astNodes = parser.parse(tokens: tokens)
        print("Frac input: \(input)")
        for node in astNodes {
            print(node.description)
            if let kids = node.childNodes {
                for k in kids {
                    print("  child: \(k.type.rawValue) text='\(k.text ?? "")'")
                }
            }
        }
        XCTAssertEqual(astNodes.count, 1)
        XCTAssertEqual(astNodes[0].type, .frac)
        XCTAssertEqual(astNodes[0].childNodes?.count, 2)
        XCTAssertEqual(astNodes[0].childNodes?[0].text, "a")
        XCTAssertEqual(astNodes[0].childNodes?[1].text, "b")
    }

    func testFracWithComplexNumerator() {
        let input = "\\frac{x + 1}{y - 2}"
        let lexer = Lexer(input: input)
        let tokens = lexer.lexAll()
        let parser = LatexParser()
        let astNodes = parser.parse(tokens: tokens)
        print("Complex frac: \(input)")
        for node in astNodes {
            print(node.description)
            if let kids = node.childNodes {
                for k in kids {
                    print("  child: \(k.type.rawValue) text='\(k.text ?? "")'")
                    if let grandkids = k.childNodes {
                        for gk in grandkids {
                            print("    grand: \(gk.type.rawValue) text='\(gk.text ?? "")'")
                        }
                    }
                }
            }
        }
        XCTAssertEqual(astNodes.count, 1)
        XCTAssertEqual(astNodes[0].type, .frac)
        // Numerator "x + 1" should be an ordgroup wrapping 3 nodes
        let numChildren = astNodes[0].childNodes?[0].childNodes
        XCTAssertEqual(numChildren?.count, 3)
        XCTAssertEqual(numChildren?[0].text, "x")
        XCTAssertEqual(numChildren?[1].text, "+")
        XCTAssertEqual(numChildren?[2].text, "1")
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
