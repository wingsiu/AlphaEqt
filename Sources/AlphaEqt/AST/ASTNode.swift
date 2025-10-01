//
//  ASTNode.swift
//  AlphaEqt
//
//  Created by Alpha Ng on 2025-10-01.
//

import Foundation

/// KaTeX-style AST node type enumeration.
/// Each case represents a different type of math structure or LaTeX construct.
public enum ASTNodeType: String {
    case mathord        // Ordinary math symbol, letter, or number, e.g. x, 2
    case textord        // Text symbol/word in math mode, e.g. \text{foo}
    case bin            // Binary operator, e.g. +
    case rel            // Relation operator, e.g. =
    case open           // Opening delimiter, e.g. (
    case close          // Closing delimiter, e.g. )
    case punct          // Punctuation, e.g. ,
    case accent         // Accent node, e.g. \hat{x}
    case supsub         // Superscript/subscript node, e.g. x^2, x_1
    case frac           // Fraction node, e.g. \frac{a}{b}
    case sqrt           // Square root node, e.g. \sqrt{x}
    case root           // N-th root node, e.g. \sqrt[3]{x}
    case ordgroup       // Grouped expressions, e.g. {xyz}
    case color          // Color node, e.g. \color{red}{x}
    case styling        // Font style node, e.g. \mathbb{x}
    case sizing         // Math style node, e.g. \displaystyle
    case array          // Array or matrix node, e.g. \begin{matrix}
    case environment    // General LaTeX environment, e.g. align, cases
    case htmlmathml     // HTML/MathML wrappers
    case raw            // Raw text or LaTeX
    case phantom        // Invisible box, e.g. \phantom{x}
    case spacing        // Spacing command, e.g. \,
    case tag            // Equation tag, e.g. \tag{n}
    case operatorname   // Named operator, e.g. \operatorname{sin}
    case infix          // Infix operator, e.g. \over
    case leftright      // Paired delimiters, e.g. \left( ... \right)
    case hbox           // Horizontal box, e.g. \hbox{}
    case fontsize       // Font size change, e.g. \large
    case kern           // Kerning/spacing
    case rule           // Rule/line, e.g. \rule{1em}{1pt}
    case op             // Operator node, e.g. \sum, \int
    case genfrac        // Generalized fraction
    case mathchoice     // \mathchoice node
    case text           // LaTeX text node, e.g. \text{abc}
    case font           // Font change node, e.g. \fontseries{}
    case mclass         // Math class node (internal)
    case subarray       // Subarray node
    case underline      // Underline, e.g. \underline{x}
    case overline       // Overline, e.g. \overline{x}
    case unicode        // Unicode character node
    case verb           // Verbatim node
    case pmb            // Bold math, e.g. \pmb{x}
    case lap            // Overlapping symbols, e.g. \llap, \rlap
    case raise          // Raise/lower box, e.g. \raisebox{}
    case inner          // Inner node
    case error          // Parse error node
    // Add more as needed
}

/// Math mode for AST nodes.
/// Indicates whether the node is in math mode or text mode.
public enum MathMode: String {
    case math      // Math mode, e.g. $...$
    case text      // Text mode, e.g. \text{...}
}

/// Source format for AST nodes.
/// Describes the format of the original input, e.g. LaTeX, MathML, AsciiMath.
public enum MathFormat: String {
    case latex     // LaTeX input
    case mathml    // MathML input
    case asciiMath // AsciiMath input
    // Extend as needed
}

/// Records the location of an AST node in the original source string.
/// Useful for error reporting, highlighting, and debugging.
public struct SourceLocation {
    public let line: Int      // Line number (1-based)
    public let column: Int    // Column number (1-based)
    public let offset: Int    // Absolute character offset (0-based)
    public let length: Int    // Length in characters

    /// Construct a SourceLocation for a node.
    /// - Parameters:
    ///   - line: The line number (starting at 1) where this node begins.
    ///   - column: The column number (starting at 1) where this node begins.
    ///   - offset: The absolute character position in the source string (starting at 0).
    ///   - length: The length in characters of the source string for this node.
    public init(line: Int, column: Int, offset: Int, length: Int) {
        self.line = line
        self.column = column
        self.offset = offset
        self.length = length
    }
}

extension SourceLocation: CustomStringConvertible {
    public var description: String {
        "line \(line), col \(column), offset \(offset), length \(length)"
    }
}

/// Base class for all AST nodes in the KaTeX-style AST.
/// Subclasses will represent specific node types (e.g. MathOrdNode, FracNode).
public class ASTNode: CustomStringConvertible {
    public let type: ASTNodeType           // The node's type
    public weak var parentNode: ASTNode?        // Reference to parent node in the AST tree (optional)
    public var location: SourceLocation?   // Location in the original source (optional)
    public var mode: MathMode              // Math or text mode
    public var sourceFormat: MathFormat    // Input format (LaTeX, MathML, etc.)
    public var originalText: String?       // The original source string for this node (optional)
    
    // CHANGE 1: Added `text` property for simple node types (mathord, bin, rel, etc).
    public var text: String?               // Value for symbol/operator (optional, used for simple nodes)
    
    /// All child nodes of this node; subclasses override this for their specific children.
    public var childNodes: [ASTNode]?
    
    /// Initializes a base AST node.
    /// Use subclasses for nodes with additional fields/children.
    /// - Parameters:
    ///   - type: The AST node type.
    ///   - text: Symbol/operator value for simple nodes (optional).
    ///   - mode: Math mode or text mode.
    ///   - sourceFormat: Original input format.
    ///   - parentNode: Parent node in the AST tree.
    ///   - location: Location in the source string.
    ///   - originalText: The original source for this node.
    public init(type: ASTNodeType,
                text: String? = nil,       // CHANGE 2: Added text parameter
                mode: MathMode = .math,
                sourceFormat: MathFormat = .latex,
                parentNode: ASTNode? = nil,
                location: SourceLocation? = nil,
                originalText: String? = nil,
                childNodes: [ASTNode]? = nil) {
        self.type = type
        self.text = text                  // CHANGE 3: Initialize text
        self.mode = mode
        self.sourceFormat = sourceFormat
        self.parentNode = parentNode
        self.location = location
        self.originalText = originalText
        self.childNodes = childNodes
    }
    
    /// Debug-friendly string description for printing the node and its children.
    public var description: String {
        var fields: [String] = ["\"type\": \"\(type)\""]
        if let text = text, !text.isEmpty {
            fields.append("\"text\": \"\(text)\"")
        }
        if let children = childNodes, !children.isEmpty {
            fields.append("\"body\": [\n  \(children.map { $0.description }.joined(separator: ",\n  "))\n]")
        }
        if let location = location {
            fields.append("\"location\": \"\(location.description)\"")
        }
        return "{ " + fields.joined(separator: ", ") + " }"
    }
}
