//
//  ASTNodeType.swift
//  AlphaEqt
//
//  Created by Alpha Ng on 1/10/2025.
//

import Foundation

/// Enumeration of all AST node types, based on KaTeX ParseNode types
public enum ASTNodeType: String {
    // Atoms and symbols
    case mathord        // Ordinary symbol (letters, numbers)
    case textord        // Text-mode ordinary character
    case spacing        // Spacing command
    case op             // Large operator (sum, integral, etc.)
    case bin            // Binary operator (+, -, etc.)
    case rel            // Relational operator (=, <, >, etc.)
    case open           // Opening delimiter
    case close          // Closing delimiter
    case punct          // Punctuation
    case inner          // Inner (delimited) expression
    
    // Scripts
    case supsub         // Superscript and/or subscript
    
    // Fractions and similar
    case genfrac        // Generalized fraction
    case frac           // Standard fraction
    case dfrac          // Display-style fraction
    case tfrac          // Text-style fraction
    
    // Roots
    case sqrt           // Square root
    case root           // nth root
    
    // Delimiters
    case leftright      // Left-right delimited expression
    case middle         // Middle delimiter
    
    // Accents
    case accent         // Accent over base
    case accentUnder    // Accent under base
    
    // Environments
    case array          // Array/matrix environment
    case matrix         // Matrix
    case pmatrix        // Parenthesized matrix
    case bmatrix        // Bracketed matrix
    case vmatrix        // Vertical bar matrix
    case cases          // Cases environment
    
    // Text
    case text           // Text mode
    case texttt         // Typewriter text
    case textbf         // Bold text
    case textit         // Italic text
    
    // Styling
    case color          // Color
    case size           // Size change
    case styling        // Style change (display, text, script, scriptscript)
    
    // Spacing
    case kern           // Kern (horizontal spacing)
    case hskip          // Horizontal skip
    case vskip          // Vertical skip
    
    // Special
    case phantom        // Phantom (invisible but takes up space)
    case smash          // Smash (takes up no vertical space)
    case raise          // Raise or lower
    
    // Symbols and special characters
    case atom           // Generic atom
    case ordgroup       // Ordered group of nodes
    
    // Fonts
    case font           // Font change
    case mathbb         // Blackboard bold
    case mathcal        // Calligraphic
    case mathfrak       // Fraktur
    case mathscr        // Script
    case mathrm         // Roman
    case mathsf         // Sans-serif
    case mathtt         // Typewriter
    case mathbf         // Bold
    case mathit         // Italic
    
    // Limits
    case op_limits      // Operator with limits
    case underlap       // Underlap
    case overlap        // Overlap
    
    // Horizontal and vertical alignment
    case hbox           // Horizontal box
    case vbox           // Vertical box
    case rule           // Rule (line)
    
    // Greek and symbols
    case greek          // Greek letter
    case symbol         // Special symbol
    
    // Extensible arrows
    case xarrow         // Extensible arrow
    
    // Over/under
    case overline       // Overline
    case underline      // Underline
    case overbrace      // Overbrace
    case underbrace     // Underbrace
    
    // Horizontal rules
    case horizBrace     // Horizontal brace
    
    // HTML-like
    case html           // HTML
    case htmlmathml     // HTML MathML
    
    // Other
    case cr             // Carriage return (line break in array)
    case tag            // Tag for equation numbering
    case verb           // Verbatim
}
