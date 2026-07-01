//
//  FracNode.swift
//  AlphaEqt
//
//  Created by Alpha Ng on 1/10/2025.
//

import Foundation

/// Represents a fraction in mathematical expressions
/// Examples: \frac{a}{b}, \dfrac{x+1}{y-2}, \tfrac{1}{2}
public final class FracNode: ASTNode {
    /// The numerator (top) of the fraction
    public let numerator: ASTNode
    
    /// The denominator (bottom) of the fraction
    public let denominator: ASTNode
    
    /// Whether to draw the fraction bar (true for normal fractions, false for binomial-style)
    public let hasBarLine: Bool
    
    /// Left delimiter for generalized fractions (optional, for \genfrac)
    public let leftDelim: String?
    
    /// Right delimiter for generalized fractions (optional, for \genfrac)
    public let rightDelim: String?
    
    /// Thickness of the bar line (optional, for \genfrac)
    public let barSize: Double?
    
    /// Initialize a FracNode
    /// - Parameters:
    ///   - numerator: The numerator node
    ///   - denominator: The denominator node
    ///   - hasBarLine: Whether to draw the fraction bar, defaults to true
    ///   - leftDelim: Optional left delimiter
    ///   - rightDelim: Optional right delimiter
    ///   - barSize: Optional bar line thickness
    ///   - parentNode: Optional parent node reference
    ///   - location: Optional source location
    ///   - mode: The mode (math or text), defaults to .math
    ///   - sourceFormat: The source format, defaults to .latex
    ///   - originalText: Optional original source text
    public init(
        numerator: ASTNode,
        denominator: ASTNode,
        hasBarLine: Bool = true,
        leftDelim: String? = nil,
        rightDelim: String? = nil,
        barSize: Double? = nil,
        parentNode: ASTNode? = nil,
        location: SourceLocation? = nil,
        mode: MathMode = .math,
        sourceFormat: SourceFormat = .latex,
        originalText: String? = nil
    ) {
        self.numerator = numerator
        self.denominator = denominator
        self.hasBarLine = hasBarLine
        self.leftDelim = leftDelim
        self.rightDelim = rightDelim
        self.barSize = barSize
        
        super.init(
            type: .frac,
            parentNode: parentNode,
            location: location,
            mode: mode,
            sourceFormat: sourceFormat,
            originalText: originalText
        )
        
        // Set parent references
        numerator.parentNode = self
        denominator.parentNode = self
    }
}
