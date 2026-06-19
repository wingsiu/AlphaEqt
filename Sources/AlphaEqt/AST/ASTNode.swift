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
}

/// Math mode for AST nodes.
public enum MathMode: String {
    case math      // Math mode, e.g. $...$
    case text      // Text mode, e.g. \text{...}
}

/// Source format for AST nodes.
public enum MathFormat: String {
    case latex     // LaTeX input
    case mathml    // MathML input
    case asciiMath // AsciiMath input
}

/// Records the location of an AST node in the original source string.
public struct SourceLocation {
    public let line: Int
    public let column: Int
    public let offset: Int
    public let length: Int

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

/// The font style of a character.
public enum MTFontStyle: Int {
    case defaultStyle = 0
    case roman
    case bold
    case caligraphic
    case typewriter
    case italic
    case sansSerif
    case fraktur
    case blackboard
    case boldItalic
}

public enum MTLineStyle: Int, Comparable {
    case display
    case text
    case script
    case scriptOfScript

    public func inc() -> MTLineStyle {
        let raw = self.rawValue + 1
        if let style = MTLineStyle(rawValue: raw) { return style }
        return .display
    }

    public var isNotScript: Bool { self < .script }
    public static func < (lhs: MTLineStyle, rhs: MTLineStyle) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Base class for all AST nodes.
/// Thread-safe for rendering: all properties read by Typesetter (`text`, `type`,
/// `childNodes`, `indexRange`, `fontStyle`) are set during parsing and remain
/// immutable thereafter. The `weak var display` is set post-render on the caller's
/// thread, never concurrently.
public class ASTNode: CustomStringConvertible, @unchecked Sendable {
    public var type: ASTNodeType
    public weak var parentNode: ASTNode?
    public var location: SourceLocation?
    public var mode: MathMode
    public var sourceFormat: MathFormat
    public var originalText: String?
    public var text: String?
    public var indexRange = NSRange(location: 0, length: 0)
    var fontStyle: MTFontStyle = .defaultStyle

    /// All child nodes of this node.
    public var childNodes: [ASTNode]?

    // Weak reference back to display (set during rendering)
    public weak var display: AnyObject?

    public var atomType: AtomType {
        switch type {
        case .mathord, .textord, .text, .unicode, .raw, .phantom, .font, .fontsize, .styling, .sizing, .operatorname, .pmb, .color, .raise, .verb:
            return .ord
        case .op:
            return .op
        case .bin, .infix:
            return .bin
        case .rel:
            return .rel
        case .open:
            return .open
        case .close:
            return .close
        case .punct:
            return .punct
        case .accent, .supsub, .frac, .genfrac, .sqrt, .root, .ordgroup, .array, .environment, .htmlmathml, .subarray, .underline, .overline, .lap, .inner, .hbox, .rule, .mathchoice, .tag:
            return .inner
        case .spacing, .kern:
            return .ord
        case .error:
            return .ord
        default:
            return .ord
        }
    }

    public init(type: ASTNodeType,
                text: String? = nil,
                mode: MathMode = .math,
                sourceFormat: MathFormat = .latex,
                parentNode: ASTNode? = nil,
                location: SourceLocation? = nil,
                originalText: String? = nil,
                childNodes: [ASTNode]? = nil) {
        self.type = type
        self.text = text
        self.mode = mode
        self.sourceFormat = sourceFormat
        self.parentNode = parentNode
        self.location = location
        self.originalText = originalText
        self.childNodes = childNodes
    }

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
