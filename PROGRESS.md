# AlphaEqt Progress Report — June 25, 2026

## KaTeX / MathJax Parity Snapshot

**Compare page:** [comparison_images/compare_mathjax.html](comparison_images/compare_mathjax.html) — 46 expressions, AlphaEqt STIX2 vs MathJax v4 STIX2 @ 30pt.

### ✅ Strong parity (production-ready for most school/university math)

| Area | AlphaEqt | KaTeX | MathJax STIX2 | Notes |
|------|----------|-------|---------------|-------|
| Fractions, sqrt, nested | ✅ | ✅ | ✅ | TeX Appendix G + style/cramped cascade |
| Sup/sub, limits, large ops | ✅ | ✅ | ✅ | `\limits`/`\nolimits` |
| Delimiters `\left...\right` | ✅ | ✅ | ✅ | Variant chain + assembly |
| Matrices (6 envs + cases) | ✅ | ✅ | ✅ | `\@arstrut` row spacing fixed (Jun 25) |
| Greek, 280+ symbols, arrows | ✅ | ✅ | ✅ | |
| Spacing `\, \; \quad \!` | ✅ | ✅ | ✅ | TeX atom-class spacing |
| Color / colorbox | ✅ | ✅ | ✅ | |
| Style sizing | ✅ | ✅ | ✅ | display/text/script |
| Basic accents (13) | ✅ | ✅ | ✅ | hat, bar, vec, widehat, … |
| `\text{}` | ✅ | ✅ | ✅ | Upright system font |
| Math italic a–z, A–Z, α–ω | ✅ | ✅ | ✅ | |

### ⚠️ Partial parity (works but gaps remain)

| Area | Status | Gap vs KaTeX/MathJax |
|------|--------|----------------------|
| **Font styles** | ✅ Implemented (Jun 25) | `\mathbb` uses **KaTeX AMS-Regular**; `\mathbf`/`\bm`/`\mathcal`/etc. use **Unicode variants in main OTF** (STIX2/XITS), not KaTeX Main-Bold / Caligraphic fonts |
| **Vectors** `\mathbf{v}` | ✅ | Heavier than KaTeX Main-Bold; matches MathJax STIX2 closely |
| **Sets** `\mathbb{R}` | ✅ | Now matches KaTeX AMS look (not STIX letterlike mix) |
| **Script** `\mathcal{L}` | ✅ | Unicode script capitals; not KaTeX Script-Regular |
| **Literal braces** `\{ \}` | ✅ Fixed (Jun 25) | Lexer no longer swallows as groups |
| **Stretchy accent arrows** | ❌ | `\overrightarrow`, `\overleftarrow`, `\overleftrightarrow` — not in accent handler |
| **Over/underline** | ✅ | `\overline`, `\underline` via MATH overbar/underbar constants |
| **Delimiter sizing** | Partial | No `\big`, `\Big`, `\middle` |
| **Environments** | Partial | `matrix`/`cases` yes; `\begin{align}` no |

### ❌ Not implemented (common KaTeX features still missing)

| Priority | Feature | KaTeX | Typical use |
|----------|---------|-------|-------------|
| **P1** | `\overrightarrow` etc. | ✅ | Vector arrows over symbols |
| **P2** | `\binom{n}{k}` | ✅ | Combinatorics |
| **P2** | `\operatorname` | ✅ | Custom operators |
| **P2** | `\phantom` | ✅ | Spacing alignment |
| **P2** | `\not` | ✅ | `\not=` |
| **P2** | `\begin{align}` | ✅ | Multi-line equations |
| **P2** | `\big`/`\middle` | ✅ | Sized delimiters |
| **P3** | `\overbrace`/`\underbrace` | ✅ | Annotations |
| **P3** | `\overset`/`\underset` | ✅ | Chemistry, custom ops |
| **P3** | `\html*` / `\href` | ✅ | Web-only (low priority) |

### Fonts in use (June 25, 2026)

| Command | Font file | Mechanism |
|---------|-----------|-----------|
| Default math, matrices | `stix2-math.otf` / `xits-math.otf` | OpenType MATH (demo default: **XITS**) |
| `\mathbb{R}` | `katex-ams-regular.ttf` | KaTeX AMS double-struck @ ASCII A–Z |
| `\mathbf{v}` | Main OTF | Unicode bold alphanumeric (U+1D400) |
| `\mathcal{L}` | Main OTF | Unicode script capitals + letterlike (U+2112, …) |
| `\mathfrak`, `\mathsf`, `\mathtt` | Main OTF | Unicode math alphanumeric |

### Session work (June 25, 2026)

| Item | Description |
|------|-------------|
| Real font styles | `MathVariant.swift`, `renderStyling()`, `KaTeXFont.swift` |
| `\mathbb` | KaTeX AMS-Regular (replaces STIX Unicode mix) |
| `\mathcal` | Official Unicode script A–Z table (fixes ℒ etc.) |
| `\{` `\}` | Lexer fix — literal braces render |
| Matrix `\@arstrut` | Row min height 0.7/0.3 × baselineskip |
| Compare page | 46 cards: fonts, vectors, matrices, complex exprs |
| Tests | `testFontStyles`, `testBlackboardUnicode`, `testCaligraphic*`, `testEscapedBraces`, `testOverlineUnderline` |
| Over/underline | `\overline` / `\underline` via `MTRuleDisplay` + MATH overbar/underbar metrics |

### Recommended next steps (by impact)

1. **P1** — Register stretchy arrows in accent handler (`\overrightarrow`, etc.)
2. **P2** — KaTeX **Main-Bold** for `\mathbf` (optional polish, like we did AMS for `\mathbb`)
3. **P2** — `\binom`, `\operatorname`, `\phantom`
4. **P2** — `\begin{align}` + `&` alignment

### Rough coverage estimate

| Corpus | AlphaEqt | Notes |
|--------|----------|-------|
| High-school / early undergrad | **~90%** | Frac, sqrt, matrices, Greek, sets, vectors |
| Typical LaTeX worksheet | **~78%** | Missing binom, align, stretchy arrows |
| Full KaTeX function list | **~45%** | Many primitives still N/A |
| MathJax STIX2 visual match | **~85%** | Same font family; spacing tweaks remain |

---

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
| 11 | **Font commands** ✅ | `\mathbf`, `\mathbb`, `\mathcal`, etc. — real styles (Jun 25); `\mathbb` uses KaTeX AMS |
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
| **P1‑1** | **Accents** ✅ | `\hat`, `\bar`, `\tilde`, `\dot`, `\ddot`, `\vec`, `\widehat`, `\widetilde`, `\check`, `\breve`, `\acute`, `\grave`, `\arc` |
| **P1‑2** | **Real font styles** ✅ | `\mathbf`, `\mathbb` (KaTeX AMS), `\mathcal`, `\mathfrak`, `\mathsf`, `\mathtt`, `\mathrm`, `\bm` via `MathVariant.swift` + `renderStyling()` |
| **P1‑3** | **`\color` / `\textcolor`** ✅ | Implemented. |
| **P1‑4** | **`\colorbox` / `\fcolorbox`** ✅ | Implemented. |
| **P1‑5** | **`\overline` / `\underline`** ✅ | `MTRuleDisplay` + MATH overbar/underbar constants; cramped inner for overline. |
| **P1‑6** | **Accent arrows** | Small | `\overrightarrow`, `\overleftarrow`, `\overleftrightarrow` — tables exist, not wired in parser. |

### ⭐ P2 — Medium Priority (Completeness)

| # | Feature | Effort | Description |
|---|---------|--------|-------------|
| **P2‑1** | **`\binom{n}{k}`** | Small | Generalized fraction with `ruleThickness = 0`. |
| **P2‑2** | **`\operatorname`** | Small | Custom named operator (upright roman with operator spacing). |
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

## June 21, 2026 — Accent Positioning Fixes ✅

| File | Change |
|------|--------|
| `Sources/AlphaEqt/Render/MTTypesetter.swift` | `getSkew` now extracts math-italic rendered glyph from `MTCTLineDisplay`/`MTGlyphDisplay` for correct `Atop(nucleus)` lookup (TeX Rule 12); multi-char `\bar` uses `MTRuleDisplay` positioned via combining macron `bbox.origin.y` |
| `Sources/AlphaEqt/Render/DisplayAtoms.swift` | Added `MTRuleDisplay` class (simple filled rectangle) |

Accepts P1‑1 is now complete: `\hat`, `\bar`, `\tilde`, `\dot`, `\ddot`, `\vec`, `\widehat`, `\widetilde`, `\check`, `\breve`, `\acute`, `\grave`, `\arc` — all parsed and rendered.

---

## June 21, 2026 — KaTeX/TeX Complete Function Audit

Full cross-reference of `ASTNodeType` enum, parser `commandHandlers`, renderer `renderNode()` dispatch,
and KaTeX's complete function catalog (`src/functions/*`).

### ✅ Fully Implemented (Parser + Renderer)

| # | Feature | AST Node | Handler | Renderer |
|---|---------|----------|---------|----------|
| 1 | `\frac` | `.frac` | `handleFracCommand` | `renderFraction` |
| 2 | `\sqrt` / `\root` | `.sqrt` / `.root` | `handleSqrtCommand` | `renderRadical` |
| 3 | Large operators (56) | `.op` | `handleLargeOpCommand` | `renderLargeOp` + limits |
| 4 | `\limits` / `\nolimits` | `.op.limitMode` | inline in `parse()` | `renderLargeOp` |
| 5 | `\left(...\right)` | `.leftright` | `handleLeftRightCommand` | `renderLeftRight` |
| 6 | Spaces (`\quad`, `\,`, `\;`, `\!`) | `.spacing` | `handleSpacingCommand` | `renderSpacing` |
| 7 | Accents (13) | `.accent` | `handleAccentCommand` | `renderAccent` |
| 8 | `\color` / `\textcolor` | `.color` | `handleColorCommand` | `renderColor` |
| 9 | `\colorbox` / `\fcolorbox` | `.colorbox` | `handleColorboxCommand` | `renderColorbox` |
| 10 | `\text` | `.text` | `handleTextCommand` | `renderTextNode` |
| 11 | Greek + 280+ symbols | `.mathord`/`.bin`/`.rel` | `handleSymbolCommand` | `renderTextNode` |
| 12 | Style sizing | `.sizing` | `handleSizingCommand` | `renderStyle` |
| 13 | Supsub (`^`, `_`) | `.supsub` | `consumeSupSub` | `renderSupSub` |
| 14 | Matrix (6 variants) | `.array` | `handleBeginMatrixCommand` | `renderMatrix` |
| 15 | Braced groups | `.ordgroup` | inline `parse()` | `renderOrdGroup` |
| 16 | Math italic (a-z, A-Z, α-ω) | `.mathord` | — | `mathItalicize` |

### ⚠️ Stub / Partial (updated Jun 25)

| # | Feature | Status |
|---|---------|--------|
| S1 | Font styles | ✅ **Done** — see `MathVariant.swift`, `KaTeXFont.swift` |
| S2 | Legacy `\rm`, `\bf`, `\cal`, etc. | ✅ Aliased to same handler |
| S3 | KaTeX font parity for all styles | ⚠️ Only `\mathbb` uses KaTeX font; `\mathbf` still Unicode/STIX |

### ❌ Not Implemented (AST type defined, no handler, no renderer)

| # | Feature | AST Type | KaTeX File | Effort |
|---|---------|----------|------------|--------|
| N1 | `\overline` | `.overline` | `overline.js` | Medium |
| N2 | `\underline` | `.underline` | `underline.js` | Medium |
| N3 | `\overrightarrow` | — | `enclose.js` | Medium |
| N4 | `\overleftarrow` | — | `enclose.js` | Medium |
| N5 | `\overleftrightarrow` | — | `enclose.js` | Medium |
| N6 | `\binom{n}{k}` | `.genfrac` | `genfrac.js` | Small |
| N7 | `\operatorname` | `.operatorname` | `operatorname.js` | Small |
| N8 | `\genfrac` | `.genfrac` | `genfrac.js` | Medium |
| N9 | `\phantom`, `\vphantom`, `\hphantom` | `.phantom` | `phantom.js` | Small |
| N10 | `\hbox` | `.hbox` | `hbox.js` | Small |
| N11 | `\overbrace` | — | `horizBrace.js` | Large |
| N12 | `\underbrace` | — | `horizBrace.js` | Large |
| N13 | `\raisebox` | `.raise` | `raisebox.js` | Medium |
| N14 | `\mathchoice` | `.mathchoice` | `mathchoice.js` | Large |
| N15 | `\mod` / `\pmod` | — | `mod.js` | Small |
| N16 | `\not` | — | `not.js` | Small |
| N17 | `\tag{n}` | `.tag` | `tag.js` | Small |
| N18 | `\rule` | `.rule` | `rule.js` | Small |
| N19 | `\kern` / `\mkern` | `.kern` | `kern.js` | Small |
| N20 | `\pmb{x}` | `.pmb` | `pmb.js` | Small |
| N21 | `\llap` / `\rlap` | `.lap` | `lap.js` | Small |
| N22 | `\verb` / `\verb*` | `.verb` | `verb.js` | Small |
| N23 | `\overset` / `\underset` | — | `op.js` helpers | Medium |
| N24 | `\stackrel` | — | `stackrel.js` | Small |
| N25 | `\xleftarrow` / `\xrightarrow` | — | `xArrow.js` | Large |
| N26 | `\smash` | — | `smash.js` | Small |
| N27 | `\mathop`, `\mathbin`, `\mathrel`, `\mathopen`, `\mathclose`, `\mathpunct`, `\mathinner` | `.mclass`? | `mclass.js` | Small |
| N28 | `\mathstrut` | — | (inline def) | Small |
| N29 | Legacy primitives (`\over`, `\atop`, `\choose`, `\brack`, `\brace`) | `.infix` | (TeX prims) | Low |
| N30 | `\operatorname*` (limits) | `.operatorname` | `operatorname.js` | Small |
| N31 | `\href` | — | `href.js` | Low |
| N32 | `\htmlClass`, `\htmlId`, `\htmlStyle` | — | `html.js` | Low |
| N33 | `\cr` / `\crcr` / `\hdashline` / `\hline` (array internals) | — | `cr.js`, `hline.js` | Medium |
| N34 | `\unit` (physical units) | — | `unit.js` | Low |

### 📊 Updated Priority List (June 25, 2026)

```
P0 — All Done ✅

P1 — User-Visible Gaps:
  P1-1: Accents (basic) ✅
  P1-2: Real font styles ✅ (mathbb=KaTeX AMS; rest=Unicode/STIX)
  P1-3: \color / \textcolor ✅
  P1-4: \colorbox / \fcolorbox ✅
  P1-5: \overline / \underline ✅
  P1-6: \overrightarrow / \overleftarrow / \overleftrightarrow  ← NEXT
  P1-7: KaTeX Main-Bold for \mathbf     ← optional polish

P2 — Completeness:
  P2-1: \binom{n}{k}
  P2-2: \operatorname
  P2-3: \genfrac
  P2-4: \phantom
  P2-5: \begin{align}
  P2-6: \big / \middle delimiter sizing
  P2-7: \not, \mod / \pmod
  P2-8: \overset / \underset

P3 — Lower Priority: overbrace, xarrow, raisebox, mathchoice, tag, …
```

### Files Reviewed This Audit
| File | Purpose |
|------|---------|
| `Sources/AlphaEqt/AST/ASTNode.swift` | All 40+ AST node types |
| `Sources/AlphaEqt/Parser/LatexParser.swift` | All registered command handlers |
| `Sources/AlphaEqt/Parser/CommandHandler/Symbols.swift` | 280+ symbol mappings |
| `Sources/AlphaEqt/Parser/CommandHandler/Accent.swift` | 13 accent commands |
| `Sources/AlphaEqt/Render/MTTypesetter.swift` | All render dispatch paths |
| `PROGRESS.md` | Prior state for diff |
| `ALPHAEQT_CHECKLIST.MD` | Historical checklist |

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
