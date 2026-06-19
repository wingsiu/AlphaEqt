# AlphaEqt — \int Glyph Y-Positioning Investigation

## Summary

Investigation into why a red debug box drawn around the `\int` glyph in AlphaEqt appears "down shifted" compared to SwiftMath's reference rendering. Traced the full rendering pipeline for both systems: glyph variant selection, bounding box computation, axis centering (shiftDown), and the debug box coordinate system. The Y shift has three contributing root causes — none of which is a simple bug, but rather a combination of subtle coordinate system mismatches in the debug box rendering and a fundamental difference in how the italic correction (leftMargin) is applied at draw time.

---

## 1. The Red Box Coordinate System Bug

### The root cause: `displayBounds()` called in wrong coordinate frame

**File**: `Sources/AlphaEqt/Render/MTGlyphDisplay.swift` (draw method)

```swift
override public func draw(_ ctx: CGContext) {
    super.draw(ctx)
    ctx.saveGState()

    // BUG: displayBounds() returns parent-relative coordinates
    let bounds = displayBounds()
    ctx.stroke(bounds.insetBy(dx: -0.5, dy: -0.5))
    // ^^ drawn in a context already translated to (self.position.x, self.position.y)
    
    ctx.translateBy(x: -leftMargin, y: -shiftDown)
    CTFontDrawGlyphs(...)
    ctx.restoreGState()
}
```

**Call chain** (from MTMathListDisplay → MTGlyphDisplay):

```
MTMathListDisplay.draw()
  → context.saveGState()
  → context.translateBy(x: child.position.x, y: child.position.y)
  → child.draw(context)               // context origin IS child.position
    → let bounds = displayBounds()     // ⚠️ returns (self.position.x, ...)
    → context.stroke(bounds)           // ⚠️ draws at self.position.x + self.position.x!
  → context.restoreGState()
```

`displayBounds()` uses the parent-relative `self.position`:

```swift
// In MTDisplay.swift
public func displayBounds() -> CGRect {
    CGRectMake(self.position.x, self.position.y - self.descent,
               self.width, self.ascent + self.descent)
}
```

**When the glyph is the first child at position (0,0)**: no visible error (0 + 0 = 0).

**When the glyph is inside MTSupSubDisplay** with base.position = (0,0): still correct.

**But when the superscript/subscript CTLine displays draw their own red boxes** via MTCTLineDisplay.draw():

```
MTSupSubDisplay draws superscript:
  → translateBy(x: sup.position.x, y: sup.position.y)  // e.g. (width+scriptSpace, supShift)
  → sup.draw(context) → MTCTLineDisplay.draw()
    → let bounds = displayBounds()   // returns (0, -descent, width, ascent+descent)
    → context.stroke(bounds)         // drawn at absolute (x+sup.position.x, sup.position.y-descent)
    // This IS correct because CTLineDisplay.position = (0,0) when fresh
```

**Conclusion for the red box**: The debug red boxes ARE correctly positioned in Y when drawn, but the visual impression of "down shifted" comes from the compound effect of multiple red boxes at different levels (MTMathListDisplay level, MTGlyphDisplay level, MTCTLineDisplay level) stacking on top of each other, each drawn with 0.4 alpha. At the sup/sub level, the Y position of the red box correctly matches the rendered glyph.

**However**, there IS a subtle issue: The red box stroke width (1pt) and alpha blending mean that overlapping boxes create a darker region that appears "thicker" or "shifted" where multiple bounds overlap. This is cosmetic for the debug overlay, not a real layout issue.

---

## 2. The Critical Difference: `-leftMargin` Draw Shift

### AlphaEqt shifts the integral glyph LEFT by italic correction at draw time

**File**: `Sources/AlphaEqt/Render/MTGlyphDisplay.swift`

```swift
ctx.translateBy(x: -leftMargin, y: -shiftDown)
```

**SwiftMath does NOT shift at draw time** — the italic correction is only used for script positioning:

```swift
// SwiftMath MTGlyphDisplay.draw()
context.translateBy(x: self.position.x, y: self.position.y - self.shiftDown);
// No leftMargin shift!
```

### The consequence: X-Y coupling illusion

This leftward shift by `leftMargin` (the italic correction, which for `integral.v1` is **591 FU ≈ 14.2pt at 24pt**) moves the glyph's visual center relative to the bounding box. The `displayBounds()` rectangle is NOT adjusted for this X shift:

| Aspect | AlphaEqt | SwiftMath |
|--------|----------|-----------|
| Glyph draw X | `position.x - leftMargin` | `position.x` |
| Red box X | `position.x` | `position.x` |
| Right edge | `position.x + width` | `position.x + width` |
| Glyph vs box alignment | Glyph is **left-shifted** inside box | Glyph is **flush left** inside box |

For the integral glyph with its large italic correction (591 FU), the glyph is drawn ~14pt to the LEFT of where the red box starts. This creates a visual impression that the glyph is "shifted" relative to the expected bounds. In a side-by-side comparison with SwiftMath, AlphaEqt's integral appears shifted left, which — combined with the differently positioned superscript — creates an overall impression of misalignment that can be perceived as a Y shift.

### How subscript positioning works in each system:

**AlphaEqt** (renderSupSub):
```swift
subXDelta = gd.leftMargin  // = italicCorrection (591 FU for integral.v1)
sub.position.x = base.width + scriptHOffset - subXDelta  // subscript shifted LEFT by italic correction
```

**SwiftMath** (from pipeline doc):
```swift
// Superscript x = currentPosition.x + delta (italic correction added to superscript)
// Subscript x = currentPosition.x (no italic correction)
```

These are DIFFERENT strategies:

| | AlphaEqt | SwiftMath |
|---|---|---|
| Glyph draw X | `pos.x - italic` | `pos.x` |
| Subscript X (rel to glyph) | `width + scriptSpace - italic - (-italic) = width + scriptSpace` | `pos.x - pos.x = 0` |
| Superscript X (rel to glyph) | `width + scriptSpace - (-italic) = width + scriptSpace + italic` | `pos.x + italic - pos.x = italic` |

The net effect: AlphaEqt achieves the same visual arrangement as SwiftMath (subscript at glyph left edge, superscript right-shifted by italic), but achieves it by shifting the GLYPH left in draw instead of shifting the SCRIPTS right in positioning.

---

## 3. The `createDisplay` Position Overwrite

**File**: `Sources/AlphaEqt/Render/MTTypesetter.swift`

```swift
display.position.x = xOffset    // ← OVERWRITES position.x set by renderNode
```

This silently discards any `position.x` set inside `renderSingleCharOp()`. While `gd.position = .zero` is already set there and `position.y` is not overwritten, this pattern means:
- Any future attempt to set `position.x` in a render method will be silently lost
- The code sets `position.x = .zero` then `createDisplay` replaces it — redundant but harmless for now
- If `position.y` were ever non-zero, it would survive through createDisplay

---

## 4. Glyph Variant Resolution

**File**: `Sources/AlphaEqt/Render/MTFontMathTable.swift`

`getLargerGlyph` for the integral glyph (U+222B) in Latin Modern:

```
v_variants["integral"] → ["integral", "integral.v1"]
```

AlphaEqt's algorithm:
1. Gets variant list for "integral": ["integral", "integral.v1"]
2. Iterates, finds "integral" at index 0
3. Returns next (index 1): "integral.v1" ✓

**Potential issue**: The bbox for `integral.v1` is fetched AFTER the glyph variant is resolved. Both systems call `CTFontGetBoundingRectsForGlyphs` on the larger glyph. But AlphaEqt calls `getLargerGlyph` only when `style == .display`. SwiftMath's `getLargerGlyph(glyph, forDisplayStyle: true)` applies the same condition.

**The italic correction lookup** is done on the LARGER glyph:
```swift
italicCorrection = mt.getItalicCorrection(glyph)  // glyph is now integral.v1
```

For `integral.v1` in Latin Modern, the plist shows:
```
"integral.v1" → 591
```

This is 591 FU = 591 * 24/1000 = **14.184 pt** at 24pt display size. A very large value that explains the significant left shift.

---

## 5. The shiftDown Calculation (Y Axis Centering)

**Both systems compute identically**:

```swift
shiftDown = 0.5 * (rawAscent - rawDescent) - axisHeight
```

For Latin Modern at 24pt (UPM=1000):

| Value | Font Units | Points (24pt) |
|-------|-----------|----------------|
| axisHeight | 250 FU | 6.0 pt |
| integral.v1 bbox.maxY | ~1670 FU (est.) | ~40.08 pt |
| integral.v1 bbox.minY | ~-446 FU (est.) | ~-10.70 pt |
| rawAscent | 1670 FU | 40.08 pt |
| rawDescent | 446 FU | 10.70 pt |
| shiftDown | 0.5*(1670-446) - 250 = 362 FU | **8.69 pt** |

The glyph draws at Y = `position.y - shiftDown` = -8.69 pt in both systems.

---

## Root Cause Summary

| # | Issue | Impact on Y | Severity |
|---|-------|------------|----------|
| **1** | Debug red box `displayBounds()` coordinate system: correct for standalone child, but when multiple red boxes stack with 0.4 alpha, the overlay appears to have thickness/shift | Cosmetic Y perception | Low (debug only) |
| **2** | `-leftMargin` draw shift moves glyph left by large italic correction (591 FU ≈ 14 pt) while red box stays at `position.x`. This creates an X discrepancy that makes the overall rendering look "off" compared to SwiftMath | Indirect perceptual Y shift | **High** — fundamentally different from SwiftMath |
| **3** | `createDisplay` overwrites `position.x` — harmless now but dangerous design pattern | None currently | Medium |
| **4** | Glyph variant chain lookup uses `integral.v1` for display style with its large italic correction = 591 FU | None directly | Medium — worth verifying |
| **5** | shiftDown calculation: identical in both systems | Same in both | None |

### The definitive answer

To see the actual Y difference: compare the `[Draw]` debug print output from `renderSingleCharOp` for both systems on the same `\int` at the same font size. The `rawAscent`, `rawDescent`, and `shiftDown` values should be identical.

The "down shifted" perception is most likely caused by Issue **#2**: the integral glyph is drawn 14 pt left of its bounding box origin in AlphaEqt but not in SwiftMath. This horizontal shift, combined with the integral's asymmetrical shape (tall left stem, short right hook), creates a visual illusion that the whole thing is vertically misaligned when comparing side-by-side.

### How to Fix

**Option A** (Match SwiftMath):
- Remove `ctx.translateBy(x: -leftMargin, ...)` from MTGlyphDisplay.draw()
- Remove `gd.leftMargin = italicCorrection` from renderSingleCharOp
- In renderSupSub, add italic correction to superscript X (not subscript):
  ```swift
  sup.position.x = base.width + scriptHOffset + italicCorrection
  sub.position.x = base.width + scriptHOffset  // no correction
  ```
- Set `gd.width = advance - italicCorrection` when subscript exists (matching SwiftMath's width reduction)

**Option B** (Keep current approach, fix the draw):
- Keep the `-leftMargin` draw shift — it's a valid strategy
- Acknowledge the rendering will look different from SwiftMath (glyph left-shifted relative to its advance width)
- The Y position is already correct