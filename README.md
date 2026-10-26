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

## M1 Analyse seeding

HKDSE Mathematics Module 1 past-paper topic maps load from the Synology workbook `math/M1/analyse.xlsx`. The topic number stored for a question is the number in that cell: 1–16 before 2012 and on the first column labelled `12`, and 1–12 for SP (sample paper, 2011), PP (practice paper, 2022), the second `12`, and later years. Seed order is SP, then PP, then those two 2012 columns. Compulsory-core Analyse tables are not modified.

```bash
python3 db/seed_analyse_m1.py --dry-run
```

Run details are in [db/README.md](db/README.md). The table layout is in [docs/CONTENT_MODEL.md](docs/CONTENT_MODEL.md).

## Pure Maths and M2 Analyse seeding

Pure Maths and DSE M2 past-paper topic maps load from the same Synology workbook, `math/M2/PManalyse.xlsx` (`M2_ANALYSE_XLSX`, often `/Volumes/math/M2/PManalyse.xlsx`). The upper block is Pure Maths Paper 1 for years before 2012, and M2 from SP, PP, and the single 2012 column onward. The lower block is Pure Maths Paper 2 through 2011. Topic tokens are the text in the cells, including Pure Maths codes past the M2 list (`16`, `17`, `0X`, `14X`, and the rest of the sheet). They are stored in `analyse_pm_*`. Compulsory-core Analyse and the M1 tables are not modified.

```bash
python3 db/seed_analyse_pm.py --dry-run
```

## M1 and M2 worked solutions

Hoksi suggested solutions for Module 1 and Module 2 load into `papers`, `questions`, and `solutions` from the packs AlphaEqtContent already saved next to core:

`/Users/alpha/Desktop/swift/AlphaEqtContent/downloads/hoksi/hkdse-maths-m1-solutions/` and `.../hkdse-maths-m2-solutions/` (zh-HK and en). Paper slugs look like `dse2015-math-m1`. Pure Maths and M&S are blocked. The core pack is not written.

```bash
export HOKSI_DOWNLOAD_ROOT="/Users/alpha/Desktop/swift/AlphaEqtContent/downloads/hoksi"
python3 db/seed_hoksi_solutions.py --dry-run --subject m1 --year 2015
```

The M1 2015 pilot, the batch commands, and the gaps are in [db/README.md](db/README.md). The table layout is in [docs/CONTENT_MODEL.md](docs/CONTENT_MODEL.md).

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
