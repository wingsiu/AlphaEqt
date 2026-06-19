# AlphaEqt Handover — 2025-06-18

## Project Structure

```
/Users/alpha/Desktop/swift/AlphaEqt/           # Main library (SPM)
├── Sources/AlphaEqt/
│   ├── Render/
│   │   ├── MTDisplay.swift         # Base class (ascent/descent/width/textColor)
│   │   ├── MTCTLineDisplay.swift   # CoreText line renderer
│   │   ├── DisplayAtoms.swift      # MTSupSubDisplay, MTFractionDisplay
│   │   ├── MTTypesetter.swift      # AST→display tree (concurrent render, script-of-script)
│   │   ├── Spaces.swift            # KaTeX-compatible spacing table
│   │   ├── MTFont.swift            # Thread-safe font cache + MATH table
│   │   ├── MTFontMathTable.swift   # OpenType MATH table accessor
│   │   └── MTConfig.swift          # iOS/macOS typealiases
│   ├── MathView/
│   │   ├── MathView.swift          # UIView/NSView with CoreText drawing
│   │   └── SwiftMathView.swift     # SwiftUI MathText wrapper
│   ├── Lexer/  (Lexer.swift, Token.swift)
│   ├── Parser/ (LatexParser.swift — recursive ordinal parse)
│   └── AST/    (ASTNode.swift — @unchecked Sendable)
│
├── Demo/ (SPM CLI demo)
├── Tests/
└── AlphaEqtDemo.xcodeproj (in ../AlphaEqtDemo/)
    └── AlphaEqtDemo/
        ├── ContentView.swift      # TabView: Demo + Benchmark tabs
        ├── BenchmarkView.swift    # Seq vs Par vs SwiftMath
        └── SwiftMathWrapper.swift # Wraps SwiftMath MTMathUILabel
```

## Recent Changes (this session)

### 1. Speed Benchmark (`AlphaEqtDemo/AlphaEqtDemo/BenchmarkView.swift`)
- **Tab-based UI** — Demo tab + Benchmark tab
- Tests **3 configurations**: AlphaEqt sequential, AlphaEqt parallel, SwiftMath
- 18 benchmark expressions from simple to real-world formulas
- Slider for iterations (10–500)
- KaTeX/MathJax reference data section
- Color-coded speedup columns (green >1×, red <1×)

### 2. Concurrent Rendering (`Sources/AlphaEqt/Render/MTTypesetter.swift`)
- Added `concurrentRender()` — DispatchGroup-based parallel dispatch
- `Typesetter.useParallel` global toggle (default true)
- **`renderFraction`**: numerator/denominator run in parallel (only for non-trivial subtrees; trivial ≤2 chars → sequential)
- **`renderSupSub`**: superscript/subscript CTLines run in parallel (only when total script text >4 chars; tiny scripts like `x^2_i` → sequential to avoid DispatchGroup overhead)
- `Typesetter` marked `@unchecked Sendable` (all properties are `let` constants)
- `MTFont` marked `@unchecked Sendable` (thread-safe via serial queues)
- `ASTNode` marked `@unchecked Sendable` (renderer-read properties immutable after parse)

### 3. Script-of-Script Support (this session)
- **Parser** (`LatexParser.swift`): `consumeSupSub` now collects raw tokens inside `^{...}` and calls `self.parse(tokens:)` recursively, producing proper nested supsub AST nodes for `x^{y^z}` (previously flattened to literal string `"y^z"`)
- **Renderer** (`MTTypesetter.swift`): `renderSupSub` dispatches complex script subtrees through a **sub-Typesetter** with scaled font (script size) and `.script` line style, so `x^{y^z}` → `y` at ~17pt, `z` at ~12pt
- **Ordgroup rendering**: `renderTextNode` now calls `createDisplay(children)` for nodes with child nodes, fixing `x_{i+2}` (the `{i+2}` ordgroup was invisible)

### 4. Concurrency Safety
Types marked `@unchecked Sendable` with documented rationale:
- `Typesetter` — `let` constants only, serial cache for MTFont
- `MTFont` — serial queue guarded cache + math table
- `ASTNode` — immutable after parse (render only reads `text`, `type`, `childNodes`, `indexRange`); `weak var display` set post-render on caller thread
- `ConcurrentBox<T>` — `@unchecked Sendable` internal helper
- `concurrentRender` uses `@Sendable` closures

## Known Issues

### Rendering gaps
1. **`\text` command**: Only basic `\text` handler registered in `LatexParser` — needs full implementation (see `CommandHandler/Text.swift`)
2. **Fractions**: ✅ **Implemented** (2025-06-18). Parser `Frac.swift` produces `.frac` nodes with children `[numerator, denominator]`. `renderFraction` in `MTTypesetter.swift` renders them via `MTFractionDisplay` with optional concurrent dispatch for non-trivial subtrees.
3. **No radical/sqrt rendering**: AST has `.sqrt` but Typesetter has no `renderSqrt` — returns nil from default case in `renderNode`
4. **No operator/largeOp**: `\sum`, `\int`, `\sin` etc produce `.textord` nodes that just render raw text
5. **No matrix/table**: `\begin{matrix}` tokens just produce raw text
6. **Math italic for multi-char identifiers**: Only individual letters A-Za-z get italicized; `sin` in `\sin` renders as "sin" in default font

### Performance
7. **DispatchGroup overhead** (~5–20 µs per dispatch): currently guarded by character-count heuristics — may need tuning for more complex subtrees
8. **Lexer**: NSRegularExpression-based — decent but not optimal. Each call creates NSTextCheckingResult array

### Architecture
9. **Parser is fragile**: `consumeSupSub` mutates `nodes` by removing last and appending — okay for current linear scope but may break with nested commands
10. **No error recovery**: If parsing fails partway through, partial/broken AST is rendered silently
11. **`ordgroup` wrapping**: When script content has >1 node, a bare `ordgroup` wraps it — the node's `type` isn't in `renderNode`'s switch, so it falls through to `renderTextNode` which now handles child nodes
12. **sub-Typesetter overhead for scripts**: Each complex script subtree creates a new `Typesetter` instance — cheap but unnecessary; could be optimized to reuse the parent's `createDisplay` with the scaled font

## Build & Run

```bash
# Library
cd /Users/alpha/Desktop/swift/AlphaEqt && swift build --target AlphaEqt

# Xcode Demo app (iPhone / Catalyst)
open /Users/alpha/Desktop/swift/AlphaEqtDemo/AlphaEqtDemo.xcodeproj
# Select target → Run (⌘R)

# Benchmark
# Tap "Benchmark" tab → adjust iterations → tap "Run Benchmark"
```

## Next Priority Tasks

1. **Benchmark on-device**: Run on iPhone to get real Seq vs Par vs SwiftMath numbers — currently only simulator-tested for build
2. **`\frac` support**: ✅ **Done** (2025-06-18). Handler in `Sources/AlphaEqt/Parser/CommandHandler/Frac.swift`. Two brace groups parsed recursively, `.frac` node with two children produced. Verified with parser tests and demo app build.
3. **`\sqrt` support**: Parser needs to produce `.sqrt` nodes, Typesetter needs `renderSqrt` method. See `Sources/AlphaEqt/Render/MTTypesetter.swift` renderNode switch — currently falls through to renderTextNode for .sqrt
4. **Math italic for commands**: `\sin` → "sin" should render in roman (upright), not italic. Needs command-to-atom-type mapping in parser
5. **Benchmark for nested scripts**: Add `x^{y^z}` and `x_{i+2}^{2^j}` to the benchmark list to validate script-of-script rendering + timing
