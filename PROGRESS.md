# AlphaEqt Progress Report — June 18, 2026

## Completed: Fraction Rendering with TeX Appendix G Rules

### Files Changed/Created

| File | Status | Description |
|---|---|---|
| `Sources/AlphaEqt/Render/DisplayAtoms.swift` | Modified | `MTFractionDisplay` with TeX gap-minimum clearance algorithm |
| `Sources/AlphaEqt/Render/MTTypesetter.swift` | Modified | Style cascading (D→T→S→SS), `\displaystyle` handling, `renderSizing()`, `getStyleSize()` |
| `Sources/AlphaEqt/Render/MTConfig.swift` | New | Configurable fraction scales (0.90/0.80) vs script scales (0.75/0.60) |
| `Sources/AlphaEqt/Render/MTColor.swift` | New | `MTColor` typealias with safe CGColor access |
| `Sources/AlphaEqt/Parser/CommandHandler/Sizing.swift` | New | Parser for `\displaystyle`/`\textstyle`/`\scriptstyle`/`\scriptscriptstyle` |
| `Sources/AlphaEqt/Parser/LatexParser.swift` | Modified | Registered 4 sizing command handlers |
| `Sources/AlphaEqt/Fonts/latinmodern-math.plist` | Modified | `ScriptPercentScaleDown` 70→75, `ScriptScriptPercentScaleDown` 50→60 |

### Key Design Decisions

1. **Style Cascading**: Matches iOSMath — `display → text → script → scriptOfScript` (stops at minimum)
2. **Fraction Scaling**: 0.90/0.80 (configurable) for nested fractions; 0.75/0.60 for scripts
3. **Gap Minimums**: Display-style gaps only for `.display` (matches iOSMath), not `.text`
4. **Bar Position**: Drawn at `axisHeight` above baseline (MATH table constant)
5. **Font Table Values**: All scaling from OpenType MATH plist via `percentFromTable()`

### Working Features

- `\frac{a}{b}` — single-level fractions
- `\frac{x^2}{\frac{y}{z}}` — nested fractions with style cascading
- `\displaystyle{\frac{a}{b}}` — style-change commands with braces
- `\displaystyle`, `\textstyle`, `\scriptstyle`, `\scriptscriptstyle` — all 4 TeX style tokens

---

## Next: Large Operators (`\sum`, `\int`, `\prod`, `\lim`)

### Why Large Operators Before Radicals?

1. **No stretcher assembly** — large operators use pre-built glyph variants, not extender construction
2. **Limits reuse existing superscript infrastructure** (`makeScripts` in Typesetter)
3. **More common** in math expressions
4. **Exercise glyph variant system** that radicals will also need

### Implementation Needs

| Component | Status |
|---|---|
| `MTLargeOpLimitsDisplay` | Need to create |
| `getLargerGlyph` / `getItalicCorrection` in math table | Need to add |
| `makeLargeOp` / `addLimitsToDisplay` in Typesetter | Need to implement |
| `\sum`, `\int`, `\prod`, `\lim` parser handlers | Need to create |
| Axis-height centering | Already available |

### After Large Operators → Radicals (`\sqrt`)

Radicals reuse the glyph variant infrastructure built for large operators plus fraction-style inner content rendering. The chain is: Large Operators → build variant glyph system → Radicals use it for stretchy √.
