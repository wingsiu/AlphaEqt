# SwiftMath vs AlphaEqt — Rendering Pipeline Comparison

## 1. Coordinate System

Both share the same fundamental model:
- `MTDisplay.position` = offset from parent's origin (where `(0,0)` = parent's baseline)
- `MTDisplay.ascent/descent` = vertical extent from this position
- `MTDisplay.width` = horizontal extent from this position
- Parent (`MTMathListDisplay`) translates to its own position, then draws each child at its `position`

## 2. Typesetter State

| Aspect | SwiftMath | AlphaEqt |
|---|---|---|
| Position tracking | Mutable `currentPosition` on typesetter instance | Local `xOffset` in `createDisplay()` |
| How position flows | Each `make*` method mutates `currentPosition` | `createDisplay` overwrites `display.position.x` after `renderNode` |
| Width consumption | `currentPosition.x += display.width` inside make methods | `xOffset += display.width` in `createDisplay` |

## 3. Large Operator Flow — Side by Side

### SwiftMath `makeLargeOp`
```swift
// 1. Get glyph & enlarge for display
glyph = styleFont.mathTable.getLargerGlyph(glyph, forDisplayStyle: true)

// 2. Italic correction from MATH table italic dict
delta = styleFont.mathTable.getItalicCorrection(glyph)

// 3. Bbox → raw ascent/descent, width = advance
CTFontGetBoundingRectsForGlyphs(...) → ascent, descent
glyphDisplay.width = CTFontGetAdvancesForGlyphs(...)

// 4. Width reduction ONLY if subscript exists AND not limits
if op.subScript != nil && !limits {
    glyphDisplay.width -= delta
}

// 5. Center on axis
shiftDown = 0.5*(ascent - descent) - axisHeight
glyphDisplay.shiftDown = shiftDown

// 6. Set position to currentPosition (typesetter cursor)
glyphDisplay.position = currentPosition

// 7. Handle scripts
return addLimitsToDisplay(glyphDisplay, delta: delta)

// 8. In addLimitsToDisplay (side scripts):
currentPosition.x += display.width   // advance by (possibly reduced) width
makeScripts(op, display, delta: delta)
```

### SwiftMath `makeScripts` (side scripts)
```swift
// Superscript x = currentPosition.x + delta
// Subscript x = currentPosition.x
// Only superscript gets the italic correction
superScript.position = (currentPosition.x + delta, y)
subscript.position = (currentPosition.x, y)
```

### AlphaEqt `renderSingleCharOp` (current)
```swift
// 1. Get glyph & enlarge for display
glyph = mt.getLargerGlyph(glyph)

// 2. Italic correction from MATH table italic dict
italicCorrection = mt.getItalicCorrection(glyph)

// 3. Bbox → raw ascent/descent, width = advance
gd.width = advance

// 4. Store italic correction on display (used later in renderSupSub)
gd.leftMargin = italicCorrection

// 5. Center on axis
shiftDown = 0.5*(rawAscent - rawDescent) - mt.axisHeight

// 6. Position = .zero (will be overwritten by createDisplay)
gd.position = .zero

// 7. Script handling happens in renderSupSub
//    NOT in renderSingleCharOp
```

### AlphaEqt `renderSupSub` (current — subscript left-shift)
```swift
// Subscript x = base.width + scriptHOffset - subXDelta
// Superscript x = base.width + scriptHOffset    (no left-shift)
// subXDelta = gd.leftMargin (italic correction)
```

## 4. Critical Difference: Position Overwrite Bug

**AlphaEqt `createDisplay()` overwrites position.x:**
```swift
guard let display = tsWithStyle.renderNode(node) else { continue }
display.position.x = xOffset    // ← OVERWRITES whatever renderNode set
xOffset += display.width
```

**SwiftMath never overwrites position** — each `make*` method sets `position = currentPosition` and advances `currentPosition.x` itself.

**Impact**: Any `position.x` set inside `renderSingleCharOp()` is silently discarded. This is why all our attempts to set `gd.position = something` failed — `createDisplay` immediately overwrote it.

## 5. How to Fix AlphaEqt — Two Approaches

### Approach A: Match SwiftMath Exactly
- Change renderNode/display flow to use typesetter-level `currentPosition`
- Each `render*` method gets passed currentPosition and advances it
- Remove `display.position.x = xOffset` from `createDisplay` — position is set inside render methods
- Glyph not left-shifted at draw time — just advances width correctly
- Width reduction for subscript: `gd.width -= italicCorrection` when subscript exists
- Superscript x-offset: add `italicCorrection` to superscript's x-position

### Approach B: Fix the Overwrite Bug (Simpler)
- In `createDisplay`, instead of:
  ```swift
  display.position.x = xOffset    // overwrite
  ```
  Use:
  ```swift
  display.position.x += xOffset   // relative offset
  ```
- Keep all other logic as-is
- Left-shift by `leftMargin` in draw, scripts subtract `leftMargin` from x

## 6. Key SwiftMath Behaviors to Replicate

1. **Width reduction for integrals**: `width -= italicCorrection` only when subscript exists, non-limits. NOT for standalone integrals.
2. **Superscript x-offset**: `currentPosition.x + delta` (italic correction added to superscript, not subscript).
3. **Subscript x-offset**: `currentPosition.x` (no italic correction).
4. **No draw-time glyph shift**: The glyph draws at origin after axis-centering translate. No x-offset.
5. **CurrentPosition advances by display.width** (already reduced) before scripts are placed.

## 7. Open Questions

- The italic correction for `integral.v1` is 591 FU (~14pt at 24pt). This is a stretchy constructor piece. Does SwiftMath actually use it as the display variant, or does it skip it? Need to verify with the `getLargerGlyph(forDisplayStyle:)` implementation.
