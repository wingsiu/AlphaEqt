//
//  ASTNodeTests.swift
//  AlphaEqt
//
//  Created by Alpha Ng on 1/10/2025.
//

import XCTest
@testable import AlphaEqt

final class ASTNodeTests: XCTestCase {
    
    // MARK: - Base ASTNode Tests
    
    func testASTNodeInitialization() {
        let location = SourceLocation(start: 0, end: 5)
        let node = ASTNode(
            type: .mathord,
            parentNode: nil,
            location: location,
            mode: .math,
            sourceFormat: .latex,
            originalText: "x"
        )
        
        XCTAssertEqual(node.type, .mathord)
        XCTAssertNil(node.parentNode)
        XCTAssertEqual(node.location?.start, 0)
        XCTAssertEqual(node.location?.end, 5)
        XCTAssertEqual(node.mode, .math)
        XCTAssertEqual(node.sourceFormat, .latex)
        XCTAssertEqual(node.originalText, "x")
    }
    
    func testASTNodeWithDefaults() {
        let node = ASTNode(type: .mathord)
        
        XCTAssertEqual(node.type, .mathord)
        XCTAssertNil(node.parentNode)
        XCTAssertNil(node.location)
        XCTAssertEqual(node.mode, .math)
        XCTAssertEqual(node.sourceFormat, .latex)
        XCTAssertNil(node.originalText)
    }
    
    // MARK: - MathOrdNode Tests
    
    func testMathOrdNodeSimple() {
        let node = MathOrdNode(text: "x")
        
        XCTAssertEqual(node.type, .mathord)
        XCTAssertEqual(node.text, "x")
        XCTAssertEqual(node.originalText, "x")
        XCTAssertEqual(node.mode, .math)
        XCTAssertEqual(node.sourceFormat, .latex)
    }
    
    func testMathOrdNodeWithAllParameters() {
        let location = SourceLocation(start: 5, end: 6)
        let node = MathOrdNode(
            text: "α",
            parentNode: nil,
            location: location,
            mode: .math,
            sourceFormat: .latex,
            originalText: "\\alpha"
        )
        
        XCTAssertEqual(node.type, .mathord)
        XCTAssertEqual(node.text, "α")
        XCTAssertEqual(node.originalText, "\\alpha")
        XCTAssertEqual(node.location?.start, 5)
        XCTAssertEqual(node.location?.end, 6)
    }
    
    func testMathOrdNodeNumber() {
        let node = MathOrdNode(text: "42")
        
        XCTAssertEqual(node.type, .mathord)
        XCTAssertEqual(node.text, "42")
    }
    
    // MARK: - FracNode Tests
    
    func testFracNodeSimple() {
        let numerator = MathOrdNode(text: "a")
        let denominator = MathOrdNode(text: "b")
        let fracNode = FracNode(numerator: numerator, denominator: denominator)
        
        XCTAssertEqual(fracNode.type, .frac)
        XCTAssertEqual((fracNode.numerator as? MathOrdNode)?.text, "a")
        XCTAssertEqual((fracNode.denominator as? MathOrdNode)?.text, "b")
        XCTAssertTrue(fracNode.hasBarLine)
        XCTAssertNil(fracNode.leftDelim)
        XCTAssertNil(fracNode.rightDelim)
        XCTAssertNil(fracNode.barSize)
    }
    
    func testFracNodeParentReferences() {
        let numerator = MathOrdNode(text: "x")
        let denominator = MathOrdNode(text: "y")
        let fracNode = FracNode(numerator: numerator, denominator: denominator)
        
        // Check that parent references are set correctly
        XCTAssertTrue(numerator.parentNode === fracNode)
        XCTAssertTrue(denominator.parentNode === fracNode)
    }
    
    func testFracNodeWithoutBarLine() {
        let numerator = MathOrdNode(text: "n")
        let denominator = MathOrdNode(text: "k")
        let fracNode = FracNode(
            numerator: numerator,
            denominator: denominator,
            hasBarLine: false
        )
        
        XCTAssertEqual(fracNode.type, .frac)
        XCTAssertFalse(fracNode.hasBarLine)
    }
    
    func testFracNodeWithDelimiters() {
        let numerator = MathOrdNode(text: "n")
        let denominator = MathOrdNode(text: "k")
        let fracNode = FracNode(
            numerator: numerator,
            denominator: denominator,
            hasBarLine: false,
            leftDelim: "(",
            rightDelim: ")"
        )
        
        XCTAssertEqual(fracNode.leftDelim, "(")
        XCTAssertEqual(fracNode.rightDelim, ")")
        XCTAssertFalse(fracNode.hasBarLine)
    }
    
    func testFracNodeWithBarSize() {
        let numerator = MathOrdNode(text: "a")
        let denominator = MathOrdNode(text: "b")
        let fracNode = FracNode(
            numerator: numerator,
            denominator: denominator,
            barSize: 0.5
        )
        
        XCTAssertEqual(fracNode.barSize, 0.5)
    }
    
    func testFracNodeNested() {
        // Create a/b
        let innerNum = MathOrdNode(text: "a")
        let innerDenom = MathOrdNode(text: "b")
        let innerFrac = FracNode(numerator: innerNum, denominator: innerDenom)
        
        // Create (a/b)/c
        let outerDenom = MathOrdNode(text: "c")
        let outerFrac = FracNode(numerator: innerFrac, denominator: outerDenom)
        
        XCTAssertEqual(outerFrac.type, .frac)
        XCTAssertTrue(innerFrac.parentNode === outerFrac)
        XCTAssertTrue(outerDenom.parentNode === outerFrac)
        
        // Verify inner fraction
        XCTAssertEqual((innerFrac.numerator as? MathOrdNode)?.text, "a")
        XCTAssertEqual((innerFrac.denominator as? MathOrdNode)?.text, "b")
    }
    
    func testFracNodeWithLocation() {
        let location = SourceLocation(start: 0, end: 13)
        let numerator = MathOrdNode(text: "x", location: SourceLocation(start: 6, end: 7))
        let denominator = MathOrdNode(text: "y", location: SourceLocation(start: 9, end: 10))
        let fracNode = FracNode(
            numerator: numerator,
            denominator: denominator,
            location: location,
            originalText: "\\frac{x}{y}"
        )
        
        XCTAssertEqual(fracNode.location?.start, 0)
        XCTAssertEqual(fracNode.location?.end, 13)
        XCTAssertEqual(fracNode.originalText, "\\frac{x}{y}")
    }
}

final class SourceLocationTests: XCTestCase {
    
    func testSourceLocationInitialization() {
        let location = SourceLocation(start: 10, end: 20)
        
        XCTAssertEqual(location.start, 10)
        XCTAssertEqual(location.end, 20)
    }
    
    func testSourceLocationEquality() {
        let location1 = SourceLocation(start: 5, end: 10)
        let location2 = SourceLocation(start: 5, end: 10)
        let location3 = SourceLocation(start: 5, end: 11)
        
        XCTAssertEqual(location1, location2)
        XCTAssertNotEqual(location1, location3)
    }
}

final class EnumTests: XCTestCase {
    
    func testMathModeRawValues() {
        XCTAssertEqual(MathMode.math.rawValue, "math")
        XCTAssertEqual(MathMode.text.rawValue, "text")
    }
    
    func testSourceFormatRawValues() {
        XCTAssertEqual(SourceFormat.latex.rawValue, "latex")
        XCTAssertEqual(SourceFormat.asciimath.rawValue, "asciimath")
    }
    
    func testASTNodeTypeRawValues() {
        XCTAssertEqual(ASTNodeType.mathord.rawValue, "mathord")
        XCTAssertEqual(ASTNodeType.frac.rawValue, "frac")
        XCTAssertEqual(ASTNodeType.sqrt.rawValue, "sqrt")
        XCTAssertEqual(ASTNodeType.matrix.rawValue, "matrix")
    }
}
