# AlphaEqt
Math typesetting engine in Swift, inspired by KaTeX and SwiftMath.

# AlphaEqt

**AlphaEqt** is a high-performance, extensible math typesetting engine written in Swift, inspired by the architecture and design principles of [KaTeX](https://katex.org).  
It aims to provide robust LaTeX/TeX math parsing, AST construction, and context-aware rendering for iOS, macOS, and cross-platform Swift apps.

---

## Features

- **Modern AST-based architecture:** Every math construct is represented as a node in an abstract syntax tree, enabling context-aware layout and precise rendering.
- **LaTeX/TeX Math Input:** Parse and display complex math expressions, equations, and environments.
- **Extensible Node Types:** Easily support fractions, roots, matrices, scripts, accents, and more.
- **Context-sensitive Spacing and Layout:** Inspired by KaTeX and TeX’s typesetting rules.
- **SwiftUI & UIKit Compatible:** Designed for easy integration with modern Apple UI frameworks.
- **Unit-tested Design:** Modular pipeline for robust testing and future growth.

---

## Architecture

AlphaEqt is built in distinct stages:

1. **Lexer/Tokenizer:** Converts input math strings into a stream of tokens.
2. **Parser:** Parses tokens into an AST (Abstract Syntax Tree) of nodes.
3. **AST Nodes:** Each node represents a math construct (symbol, operator, fraction, etc.).
4. **Renderer/Layout Engine:** Walks the AST and produces a display tree for rendering.
5. **View Layer:** Renders math visually in SwiftUI or UIKit.

---

## Getting Started

**Requirements:**  
- Swift 5.7+  
- iOS 15.0+ / macOS 12.0+

**Usage Example:**  
(Coming soon)

---

## Project Roadmap

- [x] Repository and project skeleton
- [ ] Lexer/tokenizer implementation
- [ ] Parser and AST construction
- [ ] Renderer and layout engine
- [ ] SwiftUI/UIView math view integration
- [ ] Unit tests and documentation
- [ ] Demo app and sample expressions

---

## Contributing

Contributions are welcome! Please open issues or pull requests for suggestions, bug reports, or feature requests.

---

## License

MIT License

---

## Acknowledgements

- [KaTeX](https://katex.org) – for architectural inspiration and design.
- [SwiftMath](https://github.com/wingsiu/SwiftMath) – prior art and reference implementation.
