//
//  MathOrdNode.swift
//  AlphaEqt
//
//  Created by Alpha Ng on 1/10/2025.
//

import Foundation

/// Represents an ordinary mathematical symbol (letter, number, or simple symbol)
/// Examples: variables like x, y, constants like 1, 2, Greek letters like α, β
public final class MathOrdNode: ASTNode {
    /// The text content of this ordinary symbol
    public let text: String
    
    /// Initialize a MathOrdNode
    /// - Parameters:
    ///   - text: The text content of the symbol
    ///   - parentNode: Optional parent node reference
    ///   - location: Optional source location
    ///   - mode: The mode (math or text), defaults to .math
    ///   - sourceFormat: The source format, defaults to .latex
    ///   - originalText: Optional original source text
    public init(
        text: String,
        parentNode: ASTNode? = nil,
        location: SourceLocation? = nil,
        mode: MathMode = .math,
        sourceFormat: SourceFormat = .latex,
        originalText: String? = nil
    ) {
        self.text = text
        super.init(
            type: .mathord,
            parentNode: parentNode,
            location: location,
            mode: mode,
            sourceFormat: sourceFormat,
            originalText: originalText ?? text
        )
    }
}
