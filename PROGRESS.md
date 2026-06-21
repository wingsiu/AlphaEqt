# AlphaEqt Progress Report — June 21, 2026

## Milestone: TeX Style/Cramped Cascade Complete ✅

All TeX Appendix G style and cramped propagation rules are now implemented across the entire typesetter. This milestone marks the completion of nearly all basic rendering functions.

### Cramped Cascade Implementation (June 21, 2026)

| TeX Rule | Element | Style | Cramped |
|---|---|---|---|
| Rule 11 | Radicand (√) | parent | **true** |
| Rule 11 | Degree (nth-root) | scriptscript | false |
| Rule 15e | Fraction numerator | inc(parent) | parent.cramped |
| Rule 15e | Fraction denominator | inc(parent) | **true** |
| Rule 17 | Superscript style | inc(inc(parent)) | parent.cramped |
| Rule 17 | Subscript style | inc(inc(parent)) | **true** |
| Rule 18c | Superscript shift | — | `superscriptShiftUpCramped` if cramped |

### Font Scaling: All metrics now use style-scaled math tables
- `renderFraction`: `font.copy(withSize: fracFontSize).mathTable`
- `renderSupSub`: `font.copy(withSize: supSubFontSize).mathTable`
- `renderRadical`: `font.copy(withSize: radicalFontSize).mathTable` + scaled `radicalFont` + `measurementFont`
- `findGlyph`: New `measurementFont` parameter for correct variant bounding boxes
- `superscriptShiftUp()`: Uses style-scaled math table

### Frac Parser Enhancement
- Supports `\frac{1}{2}`, `\frac 1{2}`, `\frac x y`, `\frac{x}y`

### Files Modified
| File | Changes |
|------|---------|
| `Sources/AlphaEqt/Render/MTTypesetter.swift` | `cramped: Bool` property; style-scaled math tables in all renderers; `findGlyph(measurementFont:)`; `createDisplay` cramped propagation; all sub-typesetter call sites updated |
| `Sources/AlphaEqt/Parser/CommandHandler/Frac.swift` | Single-token numerator/denominator support |

---

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
| 14 | **Debug boxes** | Red border rendering (disabled for production) |

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
| 22 | **Color commands** | `\color{red}{x}`, `\textcolor{red}{x}`, `\colorbox{red}{x}`, `\fcolorbox{border}{fill}{x}` with 15 named colors + hex `#RRGGBB` |

### MathView
| # | Feature | Description |
|---|---------|-------------|
| 23 | **iOS UIView** | Y-flip CoreText rendering |
| 24 | **macOS NSView** | Y-up CoreText rendering |
| 25 | **SwiftUI wrapper** | MathText UIViewRepresentable |
| 26 | **Dark mode** | Manual traitCollection → concrete RGB |

### Demo
| # | Feature | Description |
|---|---------|-------------|
| 27 | **Side-by-side comparison** | AlphaEqt vs SwiftMath, both with xits-math |
| 28 | **Bidirectional scroll** | ScrollView([.vertical, .horizontal]) |
| 29 | **40 comparison samples** | Covering all implemented features |
| 30 | **Benchmark tab** | Render timing measurement |

---

## Remaining Unimplemented Features

### ⭐ P0 — Critical Fixes / Quick Wins ✅ All Done

| # | Feature | Effort | Description |
|---|---------|--------|-------------|
| **P0‑1** | **Debug cleanup** ✅ | 5 min | Disabled `debugBoxesEnabled`, removed `print(...)` spam. |
| **P0‑2** | **Integrals with limits** ✅ | Medium | `∫∬∭∮` now get above/below limits in display style, side in inline. |
| **P0‑3** | **`\limits` / `\nolimits`** ✅ | Small | Postfix modifier for `.op` nodes. Added `LimitMode` enum. |

### ⭐ P1 — High Priority (User-Visible Gaps)

| # | Feature | Effort | Description |
|---|---------|--------|-------------|
| **P1‑1** | **Accents** | Medium | `\hat`, `\bar`, `\tilde`, `\dot`, `\ddot`, `\vec`, `\widehat`, `\widetilde`. Need parser handler + `renderAccent()` in Typesetter. `AccentUtils.swift` has lookup tables. |
| **P1‑2** | **Real font styles** | Medium | `\mathbf`, `\mathbb`, `\mathcal`, `\mathfrak`, `\mathit`, `\mathsf`, `\mathtt` with actual CTFont switching or Unicode math alphanumerics. |
| **P1‑3** | **`\color` / `\textcolor`** ✅ | Small | Implemented. `Color.swift` handler + `renderColor()` + 15 named colors + hex. |
| **P1‑4** | **`\colorbox` / `\fcolorbox`** ✅ | Small | Implemented. `MTColorboxDisplay` class + `renderColorbox()`. |
| **P1‑5** | **Accent arrows** | Small | `\overrightarrow`, `\overleftarrow`, `\overleftrightarrow`. |

### ⭐ P2 — Medium Priority (Completeness)

| # | Feature | Effort | Description |
|---|---------|--------|-------------|
| **P2‑1** | **`\overline` / `\underline`** | Medium | Rule bar above/below content via MATH table constants. |
| **P2‑2** | **`\binom{n}{k}`** | Small | Generalized fraction with `ruleThickness = 0`. |
| **P2‑3** | **`\operatorname`** | Small | Custom named operator (upright roman with operator spacing). |
| **P2‑4** | **`\genfrac`** | Medium | Fully generalized fraction with custom delimiters/rule/style. |
| **P2‑5** | **Nested constructs** | Medium | Systematic testing of fractions in radicals, matrices in delimiters, etc. |
| **P2‑6** | **`\phantom{x}`** | Small | Invisible content that still takes space. |
| **P2‑7** | **`\hbox{...}`** | Small | Horizontal box in text mode. |
| **P2‑8** | **Adjacent matrices** | Small | Verify inter‑matrix spacing works correctly. |

### ⭐ P3 — Lower Priority (Nice to Have)

| # | Feature | Effort | Description |
|---|---------|--------|-------------|
| **P3‑1** | **`\overbrace` / `\underbrace`** | Large | Over/under braces with horizontal extender glyph assembly. |
| **P3‑2** | **Extended arrows** | Medium | `\overrightarrow` / `\widehat` / `\widetilde` with horizontal stretching. |
| **P3‑3** | **Latin Modern Math font** | Small | Verify MATH table compatibility with `latinmodern-math.otf`. |
| **P3‑4** | **`\raisebox`** | Medium | Raise/lower box by specified amount. |
| **P3‑5** | **Legacy font commands** | Small | `\rm`, `\bf`, `\cal`, `\mit`, `\frak`, `\Bbb`. |
| **P3‑6** | **`\mathchoice`** | Large | TeX primitive for style‑dependent rendering. |
| **P3‑7** | **`\mod` / `\pmod`** | Small | Modular arithmetic operators. |
| **P3‑8** | **`\not` operator** | Small | Strike‑through for relations via combining solidus U+0338. |
| **P3‑9** | **Error recovery** | Large | Parse errors → partial AST with error nodes. |
| **P3‑10** | **Tests** | Ongoing | Expand Lexer/Parser/renderer test coverage. |
| **P3‑11** | **Performance tuning** | Ongoing | NSRegularExpression overhead, DispatchGroup heuristics. |

---

> **Implemented this session (June 20, 2026):** P0-1 (debug cleanup), P0-2 (integral limits), P0-3 (`\limits`/`\nolimits`), P1‑3 (`\color`/`\textcolor`), P1‑4 (`\colorbox`/`\fcolorbox`).

### Files Created This Session
| File | Description |
|------|-------------|
| `Sources/AlphaEqt/Parser/CommandHandler/Color.swift` | Parser handler for `\color`, `\textcolor`, `\colorbox`, `\fcolorbox` |

---

## June 20, 2026 (late session) — Color Rendering Wired + Bugfixes

### Color / Colorbox Rendering (P1-3, P1-4 — actually working now)
The parser had `Color.swift` producing `.color` and `.colorbox` AST nodes, but the Typesetter had no render paths — they fell through to `renderTextNode` which ignored color. The MathView then blanket-overwrote all colors post-render.

| File | Change |
|------|--------|
| `Sources/AlphaEqt/Parser/CommandHandler/Color.swift` | `parseColor()` made `internal` (was `private`) so Typesetter can resolve colors |
| `Sources/AlphaEqt/Render/MTTypesetter.swift` | Added `.color` → `renderColor()` and `.colorbox` → `renderColorbox()` dispatch in `renderNode()` |
| `Sources/AlphaEqt/MathView/MathView.swift` | Default `textColor` passed to `Typesetter` constructor instead of blanket `display?.textColor = ...` post-render overwrite |

**How color flows:** `\color{red}{x}` → parser → `.color(text:"red", children:[x])` → `renderColor` resolves `"red"` via `parseColor()` → `MTColor` → sets `inner.textColor` → propagates via `MTCTLineDisplay.textColor` setter (rebuilds CTLine with `kCTForegroundColorAttributeName`) and via `.textColor` setters on all container displays (`MTSupSubDisplay`, `MTFractionDisplay`, `MTRadicalDisplay`, `MTMathListDisplay`).

`\colorbox` uses pre-existing `MTColorboxDisplay` (was defined but never instantiated).

### Braced Group Parsing Fix
`x^{{y+x}^3}` rendered literal `{` characters because `LatexParser.parse()` had no handler for `leftBrace` tokens — they fell through to `mapTokenKindToASTNodeType` which mapped `.leftBrace` → `.open` → rendered as literal `{`.

| File | Change |
|------|--------|
| `Sources/AlphaEqt/Parser/LatexParser.swift` | Added `leftBrace` handler before `^`/`_` handler: tracks brace depth, recursively parses inner tokens, produces `.ordgroup` node |

### Matrix Row Spacing Fix
AlphaEqt matrices were taller than SwiftMath/TeX. The `\jot` increment (0.3× fontSize) was incorrectly baked into matrix constants. Per The TeXbook §22, `\matrix` uses `\normalbaselines` (`\baselineskip=12pt, \lineskip=1pt, \lineskiplimit=0pt` at 10pt) — `\jot` is only for display alignments like `\eqalign`.

| Constant | Before (wrong) | After (correct) |
|----------|---------------|-----------------|
| `baselineSkip` | `1.5 × fontSize` | `1.2 × fontSize` |
| `lineSkip` | `0.4 × fontSize` | `0.1 × fontSize` |
| `lineSkipLimit` | `0.3 × fontSize` | `0.0 × fontSize` |
