# SwiftMath ∫ Red Box Y-Position — ASCII Diagram

## CGContext Y Axis: UP = POSITIVE, DOWN = NEGATIVE

```
                    +Y
                     ↑
                ascent│  (positive number)
                     │
    ─── baseline ── y=0 ──────────→ +X
                     │
               descent│  (positive number, but goes downward)
                     │
                    -Y
```

## x vs ∫ — Side by Side

```
  Regular "x" (no shiftDown)          ∫ integral (with shiftDown)

         +Y ↑                              +Y ↑
             │                                  │
             │                                  │
       57pt  │  ┌──────────┐              50pt  │  ┌──────────────────┐
             │  │          │                   │  │                  │
             │  │          │                   │  │   ∫  glyph       │
             │  │    x     │                   │  │                  │
       7pt   │  │          │             31pt  │  │                  │
     ────────┼──│── 0 ─────┼───          ──────┼──│── baseline ──────┼──
             │  │          │                   │  │                  │
       -7pt  │  └──────────┘              -8pt │  │ ◄── glyph draws  │
             │  box.y = -7pt              22pt │  │      here         │
             │                                  │  │                  │
             │                              -19pt│  └──────────────────┘
             │                                  │  box.y = -19.4pt
             │                                  │
```

## The Numbers

For the integral glyph at 24pt font size:

```
rawAscent  = bbox.maxY   = 40.1 pt   (glyph extends 40pt above baseline)
rawDescent = -bbox.minY  = 10.7 pt   (glyph extends 11pt below baseline)
axisHeight               =  6.0 pt   (the math axis is 6pt above baseline)

shiftDown = 0.5 × (rawAscent - rawDescent) - axisHeight
          = 0.5 × (40.1 - 10.7) - 6.0
          = 14.7 - 6.0
          = 8.7 pt
```

The glyph is drawn at y = `-shiftDown` = **-8.7 pt** (below baseline).

The red box `displayBounds()` is computed using **overridden** ascent/descent:
```
descent (overridden) = rawDescent + shiftDown = 10.7 + 8.7 = 19.4 pt
ascent  (overridden) = rawAscent - shiftDown  = 40.1 - 8.7 = 31.4 pt

displayBounds = CGRect(x: 0, y: 0 - 19.4, width: ..., height: 31.4 + 19.4 = 50.8)
              = CGRect(x: 0, y: -19.4, w: ..., h: 50.8)
```

**The red box starts at y = -19.4 pt and extends to y = 31.4 pt**

## Why It Looks "Down Shifted"

Compare the red box Y positions:

| Glyph | box.origin.y | shiftDown |
|-------|-------------|-----------|
| Regular "x" | -7 pt | 0 pt |
| ∫ integral | **-19 pt** | **+8.7 pt** |

The integral's red box starts **12 pt lower** on screen than "x"'s box. This is **not a bug** — it's the correct TeX behavior:

1. The integral must be **centered on the math axis** (a horizontal line 6 pt above baseline)
2. Centering a 50pt-tall glyph pushes its baseline down by 8.7 pt
3. The red box correctly shows the glyph's actual position

## Draw Flow (Code Path)

```
MTGlyphDisplay.draw(context):
  1. saveGState()
  2. translateBy(x: position.x, y: position.y - shiftDown)    ← moves to (0, -8.7)
  3. CTFontDrawGlyphs(ctFont, &glyph, &pos, 1, context)       ← draws ∫ at origin
  4. restoreGState()                                           ← back to (0, 0)
  5. let rb = displayBounds()                                  ← computes (-19.4, ..., 50.8)
  6. context.stroke(rb)                                        ← draws red box at (-19.4)
```

Step 2 pushes the context origin down by 8.7pt for the glyph draw.
After restore, the red box is drawn in the parent frame using the overridden dimensions that account for that shift.

## Summary

- **Up = +Y**, Down = -Y
- shiftDown = 8.7pt moves the glyph baseline down to center it on the math axis
- The overridden descent adds shiftDown back, so box.origin.y = -10.7 - 8.7 = -19.4pt
- The red box correctly reflects the integral's true vertical position
