# SwiftMath Red Box Y Position — Why It's "Down Shifted"

## Short Answer

There is **no bug**. The red box correctly encloses the `\int` glyph. It appears "down shifted" because **`shiftDown` intentionally pushes the integral glyph below the math baseline** to center it on the math axis (TeX Appendix G). The red box faithfully reflects this -19.4 pt position (at 24pt).

But there **is** a second, subtler issue: `displayBounds()` uses the **overridden** `ascent`/`descent` (which subtract `shiftDown`), while the red box is drawn **after** `restoreGState()` — meaning the box is in the **parent frame**, not the glyph frame. This creates a Y discrepancy of exactly `shiftDown` vs. what you might expect if it were in the glyph's local frame.

---

## Detailed Explanation

### Where the red box draws (MTGlyphDisplay.draw)

```swift
context.saveGState()
context.translateBy(x: self.position.x, y: self.position.y - self.shiftDown)  // ①
CTFontDrawGlyphs(...)                                                           // ② draws at origin
context.restoreGState()                                                        // ③ pop

let rb = self.displayBounds()                                                  // ④ computed in parent frame
context.stroke(rb)                                                             // ⑤ drawn in parent frame
```

### ascent/descent overrides

```swift
override var ascent:  CGFloat { get { super.ascent  - self.shiftDown } }
override var descent: CGFloat { get { super.descent + self.shiftDown } }
```

### displayBounds() computation

```swift
func displayBounds() -> CGRect {
    CGRectMake(self.position.x, self.position.y - self.descent,
               self.width, self.ascent + self.descent)
}
```

Substituting overrides:
```
box.origin.y = position.y - (rawDescent + shiftDown)     // = -rawDescent - shiftDown (when position.y=0)
box.size.h   = (rawAscent - shiftDown) + (rawDescent + shiftDown)  // = rawAscent + rawDescent ✓
```

### The mismatch

The **glyph draws** at `y = -shiftDown` (line ①) in the **parent frame**.

The **red box draws** from `y = -rawDescent - shiftDown` in the **grandparent frame** (after `restoreGState` pops to MTMathListDisplay's translate).

But they **still match** geometrically because the parent translate was by `(0, 0)`.

### Why it looks "down shifted"

| Value | at 24pt |
|-------|---------|
| rawAscent (integral.v1) | ≈ 40.1 pt |
| rawDescent | ≈ 10.7 pt |
| axisHeight | 6.0 pt |
| **shiftDown** | **8.7 pt** |
| **box.origin.y** | **-19.4 pt** |

A regular letter "x" has box.origin.y ≈ -3.6 pt. The integral's box extends **5× lower** because `shiftDown` moves it down to center on the math axis. The red box is **correct** — it's just showing the genuine vertical position of the integral.

---

## Summary

| Question | Answer |
|----------|--------|
| Is the red box buggy? | **No** — it correctly matches the glyph extent |
| Why does it appear low? | `shiftDown` (≈ 8.7pt) centers the tall glyph on the math axis |
| Where does the "shift" come from? | TeX Appendix G centering: `0.5×(ascent−descent) − axisHeight` |
| Does the coordinate system matter? | Only the translation chain — and it's consistent |
