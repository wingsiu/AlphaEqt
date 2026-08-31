# ASTNode Types Implementation Checklist

This document tracks the implementation status of all AST node types for AlphaEqt, based on KaTeX's ParseNode architecture.

## Legend
- [x] Implemented
- [ ] Planned for implementation

## Core Node Types

### Atoms and Symbols
- [x] `mathord` - Ordinary math symbol (letters, numbers) - **MathOrdNode**
- [ ] `textord` - Text-mode ordinary character
- [ ] `spacing` - Spacing command
- [ ] `op` - Large operator (sum, integral, etc.)
- [ ] `bin` - Binary operator (+, -, etc.)
- [ ] `rel` - Relational operator (=, <, >, etc.)
- [ ] `open` - Opening delimiter
- [ ] `close` - Closing delimiter
- [ ] `punct` - Punctuation
- [ ] `inner` - Inner (delimited) expression
- [ ] `atom` - Generic atom
- [ ] `ordgroup` - Ordered group of nodes

### Scripts
- [ ] `supsub` - Superscript and/or subscript

### Fractions
- [x] `frac` - Standard fraction - **FracNode**
- [ ] `genfrac` - Generalized fraction
- [ ] `dfrac` - Display-style fraction
- [ ] `tfrac` - Text-style fraction

### Roots
- [ ] `sqrt` - Square root
- [ ] `root` - nth root

### Delimiters
- [ ] `leftright` - Left-right delimited expression
- [ ] `middle` - Middle delimiter

### Accents
- [ ] `accent` - Accent over base
- [ ] `accentUnder` - Accent under base

### Environments
- [ ] `array` - Array/matrix environment
- [ ] `matrix` - Matrix
- [ ] `pmatrix` - Parenthesized matrix
- [ ] `bmatrix` - Bracketed matrix
- [ ] `vmatrix` - Vertical bar matrix
- [ ] `cases` - Cases environment

### Text Modes
- [ ] `text` - Text mode
- [ ] `texttt` - Typewriter text
- [ ] `textbf` - Bold text
- [ ] `textit` - Italic text

### Styling
- [ ] `color` - Color
- [ ] `size` - Size change
- [ ] `styling` - Style change (display, text, script, scriptscript)

### Spacing
- [ ] `kern` - Kern (horizontal spacing)
- [ ] `hskip` - Horizontal skip
- [ ] `vskip` - Vertical skip

### Special Constructs
- [ ] `phantom` - Phantom (invisible but takes up space)
- [ ] `smash` - Smash (takes up no vertical space)
- [ ] `raise` - Raise or lower

### Font Changes
- [ ] `font` - Generic font change
- [ ] `mathbb` - Blackboard bold
- [ ] `mathcal` - Calligraphic
- [ ] `mathfrak` - Fraktur
- [ ] `mathscr` - Script
- [ ] `mathrm` - Roman
- [ ] `mathsf` - Sans-serif
- [ ] `mathtt` - Typewriter
- [ ] `mathbf` - Bold
- [ ] `mathit` - Italic

### Limits and Alignment
- [ ] `op_limits` - Operator with limits
- [ ] `underlap` - Underlap
- [ ] `overlap` - Overlap

### Boxes
- [ ] `hbox` - Horizontal box
- [ ] `vbox` - Vertical box
- [ ] `rule` - Rule (line)

### Greek and Symbols
- [ ] `greek` - Greek letter
- [ ] `symbol` - Special symbol

### Extensible Constructs
- [ ] `xarrow` - Extensible arrow
- [ ] `overline` - Overline
- [ ] `underline` - Underline
- [ ] `overbrace` - Overbrace
- [ ] `underbrace` - Underbrace
- [ ] `horizBrace` - Horizontal brace

### HTML-like
- [ ] `html` - HTML
- [ ] `htmlmathml` - HTML MathML

### Other
- [ ] `cr` - Carriage return (line break in array)
- [ ] `tag` - Tag for equation numbering
- [ ] `verb` - Verbatim

---

## Implementation Notes

### Completed (2 nodes)
1. **MathOrdNode** - Basic ordinary symbols, foundation for variables and constants
2. **FracNode** - Fractions with support for bar line, delimiters, and bar thickness

### Priority for Next Implementation
1. **Scripts (supsub)** - Essential for exponents and subscripts
2. **Roots (sqrt, root)** - Common mathematical notation
3. **Delimiters (leftright)** - For parentheses, brackets, and other delimiters
4. **Operators (op, bin, rel)** - For mathematical operators
5. **Text modes (text)** - For mixing text with math

### Design Considerations
- All nodes inherit from `ASTNode` base class
- Common fields: `type`, `parentNode`, `location`, `mode`, `sourceFormat`, `originalText`
- Parent-child relationships maintained through weak references to avoid retain cycles
- Each node type has specific fields appropriate to its mathematical construct
- Source location tracking enables error reporting and editor integration

---

Last updated: October 1, 2025
