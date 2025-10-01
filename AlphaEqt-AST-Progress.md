# AlphaEqt AST Design Progress

## Properties to Add
- [x] type (MTMathAtomType)
- [x] nucleus (value/content)
- [x] style (MTMathStyle)
- [x] color (MTMathColor)
- [x] fontVariant (MTFontVariant)
- [x] leftDelimiter/rightDelimiter (MTMathAtom/MTMathInner)
- [x] subScript/superScript (MTMathAtom)
- [x] sourceFormat (latex/asciimath)
- [x] originalText
- [x] location (SourceLocation)
- [x] mode (math/text)

## Decisions
- Use enums for fontVariant, sourceFormat, mode
- Add location property for source mapping/editing
- Add format marker and original text for round-trip conversion
- (Add more as we decide)

## Next Steps
- Implement AST class changes
- Draft conversion methods for LaTeX/AsciiMath
- (Add more as we progress)
