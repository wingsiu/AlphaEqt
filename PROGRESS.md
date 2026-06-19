# AlphaEqt Progress Report — June 20, 2026

## Completed Features

### Rendering
| # | Feature | Description |
|---|---------|-------------|
| 1 | **Core Display Tree** | MTDisplay base, MTCTLineDisplay, MTMathListDisplay, Typesetter |
| 2 | **Superscript/Subscript** | TeX Appendix G rules via MATH table |
| 3 | **Fractions** | `\frac{num}{den}` with rule, clearance, style cascading |
| 4 | **Radicals** | `\sqrt{x}`, `\sqrt[n]{x}` with slope-extender + degree |
| 5 | **Large Operators** | Display-style variants for ∑,∏,∫, etc. via glyph variant chain |
| 6 | **Limits (above/below)** | ∑,∏,⋂,⋃,⋀,⋁,⨁,⨂ in display style |
| 7 | **Delimiters** | `\left(...\right)` with variant chain + glyph assembly fallback |
| 8 | **Spacing commands** | `\quad`, `\qquad`, `\,`, `\;`, `\!` |
| 9 | **Math italic** | ASCII a-z/A-Z + Greek lowercase α-ω → math-italic Unicode |
| 10 | **Style sizing** | `\displaystyle`/`\textstyle`/`\scriptstyle`/`\scriptscriptstyle` |
| 11 | **Font commands (pass-through)** | `\mathbf{F}`, `\mathbb{R}`, etc. — consume braced arg, parse content |
| 12 | **Inter-element spacing** | TeX atom type spacing via `Spaces.swift` |
| 13 | **Color** | kCTForegroundColorAttributeName propagation |
| 14 | **Debug boxes** | Red border rendering (enabled for development) |

### Parsing
| # | Feature | Description |
|---|---------|-------------|
| 15 | **Lexer** | Tokenizes all ASCII math + emoji/CJK + `.`, `,` |
| 16 | **Command handler framework** | Pluggable handlers for `/frac`, `/sqrt`, `/left`, etc. |
| 17 | **Greek letters** | 31 commands (lowercase + uppercase + variants) |
| 18 | **Math symbols** | 280+ commands cross-referenced with SwiftMath |
| 19 | **Named operators** | 56 operators (∑,∫,sin,cos,log,lim, etc.) |
| 20 | **Sup/sub parsing** | Recursive nested scripts |
| 21 | **Text command** | `\text{abc}` |

### MathView
| # | Feature | Description |
|---|---------|-------------|
| 22 | **iOS UIView** | Y-flip CoreText rendering |
| 23 | **macOS NSView** | Y-up CoreText rendering |
| 24 | **SwiftUI wrapper** | MathText UIViewRepresentable |
| 25 | **Dark mode** | Manual traitCollection → concrete RGB |

### Demo
| # | Feature | Description |
|---|---------|-------------|
| 26 | **Side-by-side comparison** | AlphaEqt vs SwiftMath, both with xits-math |
| 27 | **Bidirectional scroll** | ScrollView([.vertical, .horizontal]) |
| 28 | **35 comparison samples** | Covering all implemented features |
| 29 | **Benchmark tab** | Render timing measurement |

---

## Remaining Unimplemented Features

### ⭐ High Priority

| # | Feature | Effort | Description |
|---|---------|--------|-------------|
| **I1** | **Integrals with limits** | Medium | ∫∬∭∮ — limits as sub/superscripts (above in display, side in inline). Needs `\limits`/`\nolimits` support. |
| **I2** | **Debug cleanup** | Small | Disable `debugBoxesEnabled = true`, remove `print(...)` from `MTGlyphDisplay.draw()` and `getLargerGlyph()` |

### Medium Priority

| # | Feature | Effort | Description |
|---|---------|--------|-------------|
| **I3** | **Accents** | Medium | `\hat`, `\bar`, `\tilde`, `\dot`, `\ddot`, `\vec`, `\widehat`, `\widetilde` — combining characters or MATH table glyph assembly |
| **I4** | **Real font styles** | Medium | `\mathbf`, `\mathrm`, `\mathcal`, `\mathbb`, `\mathfrak`, `\mathit`, `\mathsf`, `\mathtt` with actual CTFont switching |
| **I5** | **Tests** | Ongoing | Expand LexerTests, ParserTests, renderer tests |
| **I6** | **Over/Underline** | Medium | `\overline{x}`, `\underline{x}` via MATH table constants |

### Lower Priority

| # | Feature | Effort | Description |
|---|---------|--------|-------------|
| **I7** | **Over/Under braces** | Large | `\overbrace`, `\underbrace` with horizontal extender |
| **I8** | **Matrices** | Large | `\begin{matrix}`, `\pmatrix`, `\bmatrix`, etc. |
| **I9** | **Cases** | Medium | `\begin{cases}` |
| **I10** | **Font commands (real)** | Medium | `\mathrm{x}`, `\mathcal{F}` with actual font change |
| **I11** | **Latin Modern Math** | Small | Verify xits-math constants work with LM Math font |
| **I12** | **`\limits`/`\nolimits`** | Small | Force limits above/below or side for any operator |
| **I13** | **`\operatorname`** | Small | Custom named operators |
| **I14** | **`\binom`** | Small | Generalized fraction with no rule bar |

### Files Created This Session
| File | Commit |
|------|--------|
| `Sources/AlphaEqt/Parser/CommandHandler/Symbols.swift` | `7040656` |
| `Sources/AlphaEqt/Parser/CommandHandler/LeftRight.swift` | `6696c36` |
