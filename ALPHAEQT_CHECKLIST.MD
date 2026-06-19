# AlphaEqt Project Checklist

## Phase 0: Foundation (✅ Complete)
- [x] GitHub repository (https://github.com/wingsiu/AlphaEqt)
- [x] Folder structure
- [x] Package.swift (SPM library + Demo)
- [x] README, LICENSE, .gitignore

## Phase 1: Lexer (✅ Complete)
| Token Type | KaTeX | SwiftMath | AlphaEqt | Status |
|-----------|-------|-----------|----------|--------|
| identifiers (a-Z) | ✅ | ✅ | ✅ | Done |
| numbers (0-9) | ✅ | ✅ | ✅ | Done |
| operators (+ - * / =) | ✅ | ✅ | ✅ | Done |
| superscript ^ | ✅ | ✅ | ✅ | Done |
| subscript _ | ✅ | ✅ | ✅ | Done |
| braces { } | ✅ | ✅ | ✅ | Done |
| backslash commands | ✅ | ✅ | ✅ partial | \text only |
| Greek letters (α, β...) | ✅ | ✅ | ❌ | P2 |
| \left, \right | ✅ | ✅ | ❌ | P3 |
| \frac | ✅ | ✅ | ❌ | P3 |
| \sqrt | ✅ | ✅ | ❌ | P3 |

## Phase 2: Parser (✅ Complete)
- [x] LaTeX → AST node conversion
- [x] Superscript/subscript parsing
- [x] Command handler framework (\text)
- [ ] \frac, \sqrt commands → P3
- [ ] Greek letter parsing → P2
- [ ] \left, \right → P3

## Phase 3: Renderer — Core (✅ Complete)
- [x] MTDisplay base class (ascent/descent/width/position)
- [x] MTCTLineDisplay (CoreText line rendering)
- [x] MTMathListDisplay (horizontal list of sub-displays)
- [x] Typesetter (AST → display tree)
- [x] Inter-element spacing (TeX rules via Spaces.swift)
- [x] Math italic (variables → Unicode math italic)
- [x] Superscript/subscript layout (MATH table per TeX Appendix G)
- [x] Supsub spacing fix (uses base child's atomType, not .inner)
- [x] Fraction layout
- [x] Text color system (kCTForegroundColorAttributeName)
- [x] Dark mode support (manual traitCollection check → concrete RGB)
- [x] Minus sign fix (U+002D → U+2212)

## Phase 4: MathView (✅ Complete)
- [x] iOS UIView with Y-flip for CoreText
- [x] macOS NSView with Y-up for CoreText
- [x] SwiftUI wrapper (MathText)
- [x] Intrinsic content size
- [x] xits-math font (default)
- [x] Color propagation through display tree

## Phase 5: Demo App (✅ Complete)
- [x] SwiftUI demo (Demo/Sources/DemoApp)
- [x] AlphaEqtDemo Xcode project (iOS + macOS Catalyst)
- [x] Side-by-side SwiftMath comparison (both using xits-math font)
- [x] Horizontal scroll for wide expressions on iPhone
- [x] Fixed: SwiftMath line wrapping (preferredMaxLayoutWidth = 0)
- [x] Fixed: iPhone deployment target lowered to iOS 16.0

## Known Issues
| Issue | Status | Plan |
|-------|--------|------|
| Single-char supsub (a^2) has extra space | Fixed | Use base child atomType for spacing |
| MathView frame clipping | Fixed | intrinsicContentSize + sizeThatFits |
| Xcode SPM cache stale | Workaround | Clear DerivedData before Xcode build |

## SwiftMath Comparison Reference
- Path: `/tmp/SwiftMathDemo`
- Font: xits-math (font files + plist copied to its mathFonts.bundle)
- Patch: Made `MTFont.init(fontWithName:size:)` public for external font selection
- Line wrapping: Disabled via `preferredMaxLayoutWidth = 0`

## Key Architectural Decisions
1. **Display tree**: Hierarchical (MTSupSubDisplay wraps children) vs SwiftMath's flat array
2. **Color**: kCTForegroundColorAttributeName on CTLine via recursive textColor setter
3. **Font**: xits-math OpenType MATH font with plist table
4. **Coordinates**: iOS Y-flip (with context translate+scale), macOS Y-up native
5. **Script positioning**: OpenType MATH table (superscriptShiftUp, subscriptShiftDown, subSuperscriptGapMin)
