//
//  ASTNode.swift
//  AlphaEqt
//
//  Created by Alpha Ng on 1/10/2025.
//

import Foundation

/// Base class for all AST nodes in AlphaEqt
/// Inspired by KaTeX's ParseNode architecture
open class ASTNode {
    /// The type of this node
    public let type: ASTNodeType
    
    /// Reference to the parent node in the tree (weak to avoid retain cycles)
    public weak var parentNode: ASTNode?
    
    /// Location in the source string where this node originated
    public let location: SourceLocation?
    
    /// The mode (math or text) in which this node was parsed
    public let mode: MathMode
    
    /// The source format (LaTeX or AsciiMath) that this node came from
    public let sourceFormat: SourceFormat
    
    /// The original text from the source that generated this node
    public let originalText: String?
    
    /// Initialize an ASTNode with all common fields
    /// - Parameters:
    ///   - type: The type of this node
    ///   - parentNode: Optional parent node reference
    ///   - location: Optional source location
    ///   - mode: The mode (math or text), defaults to .math
    ///   - sourceFormat: The source format, defaults to .latex
    ///   - originalText: Optional original source text
    public init(
        type: ASTNodeType,
        parentNode: ASTNode? = nil,
        location: SourceLocation? = nil,
        mode: MathMode = .math,
        sourceFormat: SourceFormat = .latex,
        originalText: String? = nil
    ) {
        self.type = type
        self.parentNode = parentNode
        self.location = location
        self.mode = mode
        self.sourceFormat = sourceFormat
        self.originalText = originalText
    }
}
