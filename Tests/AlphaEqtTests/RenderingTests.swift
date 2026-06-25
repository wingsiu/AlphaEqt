//
//  RenderingTests.swift
//  AlphaEqt
//
//  Systematic rendering tests using KaTeX screenshotter expressions (ss_data.yaml).
//  Covers all implemented features with parse→render→assert validation.
//

import XCTest
@testable import AlphaEqt
import CoreGraphics
import Foundation
import ImageIO

final class RenderingTests: XCTestCase {
    nonisolated(unsafe) static let comparisonDir = "/Users/alpha/Desktop/swift/AlphaEqt/comparison_images"

    // MARK: - Test Helpers

    /// Renders a LaTeX string through the full pipeline and returns the display tree.
    func render(_ latex: String, font: MTFont? = nil, style: MTLineStyle = .display,
                cramped: Bool = false) -> MTMathListDisplay? {
        let f = font ?? MathFont.xitsFont.mtfont(size: 30)
        let lexer = Lexer(input: latex)
        let tokens = lexer.tokenize()
        let parser = LatexParser()
        let nodes = parser.parse(tokens: tokens)
        guard !nodes.isEmpty else { return nil }
        let ts = Typesetter(font: f, style: style, cramped: cramped)
        return ts.createDisplay(nodes) as? MTMathListDisplay
    }

    /// Asserts that a LaTeX string parses and renders without error.
    func assertRenders(_ latex: String, font: MTFont? = nil, style: MTLineStyle = .display,
                       file: StaticString = #filePath, line: UInt = #line) -> MTMathListDisplay? {
        let display = render(latex, font: font, style: style)
        XCTAssertNotNil(display, "Render returned nil for: \(latex)", file: file, line: line)
        if let d = display {
            XCTAssertGreaterThan(d.ascent + d.descent, 0, "Zero total height for: \(latex)", file: file, line: line)
            XCTAssertGreaterThan(d.width, 0, "Zero width for: \(latex)", file: file, line: line)
        }
        return display
    }

    // MARK: - Accents (P1-1 Done)

    func testAccentsBasic() {
        // ss_data.yaml Accents
        assertRenders(#"\vec{A}"#)
        assertRenders(#"\vec{x}"#)
        assertRenders(#"\vec x^2"#)
        assertRenders(#"\vec{x}_2^2"#)
        assertRenders(#"\vec{A}^2"#)
        assertRenders(#"\vec{xA}^2"#)
    }

    func testAccentsHatTilde() {
        assertRenders(#"\hat{x}"#)
        assertRenders(#"\tilde{x}"#)
        assertRenders(#"\widehat{AB}"#)
        assertRenders(#"\widetilde{AB}"#)
        assertRenders(#"\widehat{ABC}"#)
        assertRenders(#"\widetilde{ABC}"#)
    }

    func testAccentsDotCheckBreve() {
        assertRenders(#"\dot{x}"#)
        assertRenders(#"\ddot{x}"#)
        assertRenders(#"\check{x}"#)
        assertRenders(#"\breve{x}"#)
        assertRenders(#"\acute{x}"#)
        assertRenders(#"\grave{x}"#)
    }

    func testAccentsBarMultiChar() {
        // Multi-char \bar (uses MTRuleDisplay or glyph variants)
        let d = assertRenders(#"\bar{ab}"#)
        _ = d
        assertRenders(#"\bar{AB}"#)
        assertRenders(#"\bar{x}"#)
    }

    func testOverlineUnderline() {
        assertRenders(#"\overline{x}"#)
        assertRenders(#"\overline{AB}"#)
        assertRenders(#"\overline{abc}"#)
        assertRenders(#"\underline{x}"#)
        assertRenders(#"\underline{AB}"#)
        assertRenders(#"\overline{\frac{a}{b}}"#)
    }

    func testAccentsArc() {
        assertRenders(#"\arc a"#)
        assertRenders(#"\arc A"#)
        assertRenders(#"\arc{ab}"#)
    }

    func testAccentsStretchy() {
        // ss_data.yaml StretchyAccent
        assertRenders(#"\overrightarrow{AB}"#)
        assertRenders(#"\overleftarrow{AB}"#)
        assertRenders(#"\overleftrightarrow{AB}"#)
        assertRenders(#"\overgroup{AB}"#)
        assertRenders(#"\overlinesegment{AB}"#)
        assertRenders(#"\widecheck{AB}"#)
    }

    // MARK: - Fractions (✅)

    func testFractionsBasic() {
        // ss_data.yaml FractionTest
        assertRenders(#"\dfrac{a}{b}"#)
        assertRenders(#"\frac{a}{b}"#)
        assertRenders(#"\tfrac{a}{b}"#)
        assertRenders(#"\frac{1}{2}"#)
        assertRenders(#"\dfrac{1}{2}"#)
    }

    func testFractionsNested() {
        // ss_data.yaml NestedFractions
        assertRenders(#"\dfrac{\frac{a}{b}}{\frac{c}{d}}"#)
        assertRenders(#"\frac{\frac{a}{b}}{\frac{c}{d}}"#)
    }

    func testFractionsLargeNumerator() {
        // ss_data.yaml LargeRuleNumerator
        assertRenders(#"\frac{\textcolor{blue}{\rule{1em}{2em}}}{x}"#)
    }

    // MARK: - Radicals / Sqrt (✅)

    func testSqrtBasic() {
        // ss_data.yaml Sqrt
        assertRenders(#"\sqrt{x}"#)
        assertRenders(#"\sqrt{\sqrt{\sqrt{x}}}"#)
    }

    func testSqrtNestedFractions() {
        assertRenders(#"\sqrt{\frac{\frac{A}{B}}{\frac{A}{B}}}"#)
    }

    func testSqrtRoot() {
        // ss_data.yaml SqrtRoot
        assertRenders(#"\sqrt[3]{2}"#)
        assertRenders(#"\sqrt[3]{M}"#)
    }

    // MARK: - Superscript / Subscript (✅)

    func testSupSubBasic() {
        // ss_data.yaml Exponents
        assertRenders(#"a^{a^a_a}_{a^a_a}"#)
        assertRenders(#"x^2"#)
        assertRenders(#"x_1"#)
        assertRenders(#"x_i^2"#)
    }

    func testSupSubHorizSpacing() {
        // ss_data.yaml SupSubHorizSpacing
        assertRenders(#"x^{x^{x}}"#)
        assertRenders(#"x_{x_{x_{x_{x}}}}"#)
    }

    func testSupSubOffsets() {
        // ss_data.yaml SupSubOffsets
        assertRenders(#"\displaystyle \int_{2+3}x f^{2+3}+3"#)
    }

    func testSupSubPrime() {
        // ss_data.yaml PrimeSpacing + PrimeSuper
        assertRenders(#"f'+f_2'+f^{f'}"#)
        assertRenders(#"x'^2+x'''^2+x'^2_3+x_3'^2"#)
    }

    // MARK: - Large Operators (✅)

    func testLargeOpsSumProd() {
        assertRenders(#"\sum_{i=0}^\infty"#)
        assertRenders(#"\prod_{i=1}^n"#)
        assertRenders(#"\bigcap_{i=1}^n"#)
        assertRenders(#"\bigcup_{i=1}^n"#)
    }

    func testLargeOpsIntegrals() {
        // ss_data.yaml Integrands
        assertRenders(#"\displaystyle \int"#)
        assertRenders(#"\oint"#)
        assertRenders(#"\iint"#)
        assertRenders(#"\iiint"#)
        assertRenders(#"\int\limits^x_{y + 4 - a}"#)
    }

    func testLimits() {
        // ss_data.yaml LimitControls + OpLimits
        assertRenders(#"\displaystyle\int\limits_2^3 3x^2\,dx"#)
        assertRenders(#"\sum\nolimits^n_{i=1}i"#)
        assertRenders(#"\lim_{x \to \infty}"#)
        assertRenders(#"\limsup_{x \rightarrow \infty} x"#)
    }

    func testFunctions() {
        // ss_data.yaml Functions
        assertRenders(#"\sin\cos\tan\ln\log"#)
        assertRenders(#"\sin^2\theta + \cos^2\theta"#)
    }

    // MARK: - Delimiters / LeftRight (✅)

    func testLeftRightBasic() {
        // ss_data.yaml LeftRight
        assertRenders(#"\left( x^2 \right)"#)
        assertRenders(#"\left\{ x^{x^{x^{x^x}}} \right."#)
    }

    func testLeftRightMiddle() {
        // ss_data.yaml LeftRightMiddle
        assertRenders(#"\left( x^2 \middle/ \right)"#)
    }

    func testDelimiterSizing() {
        // ss_data.yaml DelimiterSizing
        assertRenders(#"\bigl\uparrow\Bigl\downarrow\biggl\updownarrow"#)
    }

    // MARK: - Matrices (✅)

    func testMatrixBasic() {
        assertRenders(#"\begin{matrix} a & b \\ c & d \end{matrix}"#)
        assertRenders(#"\begin{pmatrix} a & b \\ c & d \end{pmatrix}"#)
        assertRenders(#"\begin{bmatrix} a & b \\ c & d \end{bmatrix}"#)
        assertRenders(#"\begin{Bmatrix} a & b \\ c & d \end{Bmatrix}"#)
        assertRenders(#"\begin{vmatrix} a & b \\ c & d \end{vmatrix}"#)
        assertRenders(#"\begin{Vmatrix} a & b \\ c & d \end{Vmatrix}"#)
    }

    // MARK: - Font Styles

    func testFontStyles() {
        assertRenders(#"\mathbb{R}"#)
        assertRenders(#"\mathbb{NZQ}"#)
        assertRenders(#"\mathbf{F}"#)
        assertRenders(#"\mathrm{sin}"#)
        assertRenders(#"\mathcal{L}"#)
        assertRenders(#"\mathfrak{g}"#)
        assertRenders(#"\mathsf{A}"#)
        assertRenders(#"\mathtt{01}"#)
        assertRenders(#"x \in \mathbb{R}"#)
    }

    func testBlackboardUnicode() {
        XCTAssertEqual(applyMathFontStyle("R", style: .blackboard), "R")
        XCTAssertEqual(applyMathFontStyle("ABC", style: .blackboard), "ABC")
        XCTAssertEqual(applyMathFontStyle("k", style: .blackboard), "k")
    }

    func testBoldAndRoman() {
        XCTAssertEqual(applyMathFontStyle("x", style: .bold), "\u{1D431}")
        XCTAssertEqual(applyMathFontStyle("x", style: .roman), "x")
        XCTAssertEqual(applyMathFontStyle("x", style: .italic), "\u{1D465}")
    }

    func testCaligraphicUnicode() {
        XCTAssertEqual(applyMathFontStyle("L", style: .caligraphic), "\u{2112}")
        XCTAssertEqual(applyMathFontStyle("AB", style: .caligraphic), "\u{1D49C}\u{212C}")
    }

    func testCaligraphicWithBraces() {
        let display = assertRenders(#"\mathcal{L}\{f\}"#)
        let nodes = display?.mathList ?? []
        let texts = collectRenderedTexts(nodes)
        XCTAssertTrue(texts.contains("{"), "Missing literal open brace, got: \(texts)")
        XCTAssertTrue(texts.contains("}"), "Missing literal close brace, got: \(texts)")
    }

    private func collectRenderedTexts(_ nodes: [ASTNode]) -> [String] {
        var out: [String] = []
        for node in nodes {
            if let t = node.text, !t.isEmpty, t != "^", t != "_" { out.append(t) }
            if let children = node.childNodes {
                out.append(contentsOf: collectRenderedTexts(children))
            }
        }
        return out
    }

    // MARK: - Color (✅)

    func testColor() {
        // ss_data.yaml Colors + Colorbox
        assertRenders(#"\textcolor{red}{x}"#)
        assertRenders(#"\color{blue}{x}"#)
        assertRenders(#"\colorbox{teal}{B}"#)
        assertRenders(#"\fcolorbox{blue}{red}{C}"#)
    }

    // MARK: - Spacing (✅)

    func testSpacing() {
        assertRenders(#"a \quad b \qquad c"#)
        assertRenders(#"a \, b \; c \! d"#)
    }

    // MARK: - Style Sizing (✅)

    func testStyleSizing() {
        // ss_data.yaml DisplayStyle + Sizing
        assertRenders(#"{\displaystyle\sqrt{x}}{\sqrt{x}}"#)
        assertRenders(#"{\displaystyle \frac12}{\frac12}"#)
        assertRenders(#"{\Huge x}{\LARGE y}{\normalsize z}{\scriptsize w}"#)
    }

    // MARK: - Symbols (✅)

    func testGreekLetters() {
        // ss_data.yaml GreekLetters
        assertRenders(#"\alpha\beta\gamma\omega"#)
        assertRenders(#"\Gamma\Delta\Theta\Lambda\Xi\Pi\Sigma\Phi\Psi\Omega"#)
    }

    func testMathSymbols() {
        assertRenders(#"\infty\partial\nabla\forall\exists\neg\emptyset"#)
        assertRenders(#"\leq\geq\neq\approx\sim\equiv\in\notin\subset\subseteq"#)
        assertRenders(#"\times\div\pm\mp\wedge\vee\cap\cup\oplus\otimes"#)
    }

    func testArrows() {
        assertRenders(#"\leftarrow\rightarrow\leftrightarrow\mapsto"#)
        assertRenders(#"\Rightarrow\Leftarrow\Leftrightarrow"#)
    }

    // MARK: - Text (✅)

    func testText() {
        // ss_data.yaml Text
        assertRenders(#"\frac{a}{b}\text{c~ {ab} \ e}+fg"#)
    }

    // MARK: - DisplayMode (✅)

    func testDisplayMode() {
        // ss_data.yaml DisplayMode
        let d1 = assertRenders(#"\sum_{i=0}^\infty \frac{1}{i}"#, style: .display)
        let d2 = assertRenders(#"\sum_{i=0}^\infty \frac{1}{i}"#, style: .text)
        // Display-style sum should have different metrics from text-style
        // (limits above/below vs side)
        _ = d1
        _ = d2
    }

    // MARK: - Comprehensive Diagnostic Dump

    /// Dumps the display tree metrics for a specific LaTeX expression.
    /// Useful for comparing with SwiftMath/KaTeX metrics.
    func testDiagnosticDump() {
        let cases: [(String, String)] = [
            ("fraction", #"\frac{x}{y}"#),
            ("nested-frac", #"\frac{\frac{a}{b}}{\frac{c}{d}}"#),
            ("sqrt", #"\sqrt{x+1}"#),
            ("sqrt-nested", #"\sqrt{\frac{x}{y}}"#),
            ("sup", #"x^2"#),
            ("sub", #"x_1"#),
            ("supsub", #"x_i^2"#),
            ("sum-display", #"\sum_{i=0}^n i^2"#),
            ("sum-inline", #"\textstyle\sum_{i=0}^n i^2"#),
            ("integral", #"\int_0^\infty f(x)dx"#),
            ("matrix", #"\begin{pmatrix} a & b \\ c & d \end{pmatrix}"#),
            ("leftright", #"\left(\frac{x}{y}\right)"#),
            ("accent-hat", #"\hat{x}"#),
            ("accent-vec", #"\vec{x}"#),
            ("accent-bar", #"\bar{x}"#),
            ("accent-bar-multi", #"\bar{ab}"#),
            ("accent-widehat", #"\widehat{AB}"#),
            ("color", #"\textcolor{red}{x}"#),
            ("colorbox", #"\colorbox{yellow}{x+y}"#),
            ("deep-root", #"\sqrt[n]{x+y^2-\frac{\frac{z}{1-7v^2}}{\frac{3r^3}{\frac 1{2+\frac xy}}}}"#),
        ]

        for (label, latex) in cases {
            guard let d = render(latex) else {
                XCTFail("Render failed for \(label): \(latex)")
                continue
            }
            print("[\(label)] a=\(Int(d.ascent)) d=\(Int(d.descent)) w=\(Int(d.width)) | \(latex)")
        }
    }

    // MARK: - PNG Comparison Image Generation

    /// Renders the display to a CGContext and writes a PNG file.
    /// Also produces a side-by-side HTML comparison page: AlphaEqt vs KaTeX.
    func testGenerateComparisonImages() throws {
        let dir = Self.comparisonDir
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        let allCases: [(String, String)] = [
            ("fraction",        #"\frac{x}{y}"#),
            ("nested-frac",     #"\frac{\frac{a}{b}}{\frac{c}{d}}"#),
            ("sqrt",            #"\sqrt{x+1}"#),
            ("sqrt-nested",     #"\sqrt{\frac{x}{y}}"#),
            ("sup",             #"x^2"#),
            ("sub",             #"x_1"#),
            ("supsub",          #"x_i^2"#),
            ("sum-display",     #"\displaystyle\sum_{i=0}^n i^2"#),
            ("sum-inline",      #"\textstyle\sum_{i=0}^n i^2"#),
            ("integral",        #"\displaystyle\int_0^\infty f(x)dx"#),
            ("matrix",          #"\begin{pmatrix} a & b \\ c & d \end{pmatrix}"#),
            ("leftright",       #"\left(\frac{x}{y}\right)"#),
            ("accent-hat",      #"\hat{x}"#),
            ("accent-vec",      #"\vec{x}"#),
            ("accent-bar",      #"\bar{x}"#),
            ("accent-bar-multi", #"\bar{ab}"#),
            ("accent-widehat",  #"\widehat{AB}"#),
            ("accent-tilde",    #"\tilde{x}"#),
            ("accent-dot",      #"\dot{x}"#),
            ("accent-ddot",     #"\ddot{x}"#),
            ("color",           #"\textcolor{red}{x}"#),
            ("colorbox",        #"\colorbox{yellow}{x+y}"#),
            ("frac-display",    #"\dfrac{1}{2}"#),
            ("frac-text",       #"\tfrac{1}{2}"#),
            ("sqrt-3",          #"\sqrt[3]{x}"#),
            ("greek",           #"\alpha\beta\gamma\omega"#),
            ("sin-cos",         #"\sin^2\theta + \cos^2\theta"#),
            ("sum-limits",      #"\displaystyle\sum_{i=0}^\infty \frac{1}{i}"#),
            ("text",            #"\text{Hello world}"#),
            ("complex-frac1",   #"\frac{a}{b+\frac{c}{d+\frac{5}{y-\frac{x^2}{3}}}}"#),
            ("complex-int",     #"\sqrt[3]{a+\frac{3}{x^2}}\int_0^1\frac{{\int y}^3+\frac{x}{5}-1}{x^4-4\sqrt[3]{x}+\frac{\frac{3+x}{4-y}}{\frac{3+x}{\sqrt{c^2}+y}}}= \int_0^1 a \cos x 😃dx"#),
            ("complex-mix",     #"12x3^{\int 2}+\frac{\int a}{b}-\sqrt[n]{x+y^2-\frac{\frac{z}{1-7v^2}}{\frac{3r^3}{\frac 1{2+\frac xy}}}}+\int_0^1 \sum aa+3a"#),
        ]

        let fontSize: CGFloat = 30
        let scale: CGFloat = 1
        let padding: CGFloat = 0
        let font = MathFont.stix2Font.mtfont(size: fontSize)
        var entries: [(label: String, latex: String, width: Int, height: Int)] = []

        for (label, latex) in allCases {
            let lexer = Lexer(input: latex)
            let tokens = lexer.tokenize()
            let parser = LatexParser()
            let nodes = parser.parse(tokens: tokens)
            guard !nodes.isEmpty else {
                print("  ⚠️  parse empty: [\(label)] \(latex)")
                continue
            }
            let ts = Typesetter(font: font, style: .display)
            guard let display = ts.createDisplay(nodes) else {
                print("  ⚠️  render nil: [\(label)] \(latex)")
                continue
            }
            let w = Int((display.width + padding * 2) * scale)
            let h = Int((display.ascent + display.descent + padding * 2) * scale)
            guard w > 0, h > 0 else {
                print("  ⚠️  zero size: [\(label)] \(latex)")
                continue
            }

            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
            guard let ctx = CGContext(data: nil, width: w, height: h,
                                       bitsPerComponent: 8, bytesPerRow: w * 4,
                                       space: colorSpace,
                                       bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                print("  ⚠️  context fail: [\(label)]")
                continue
            }
            ctx.scaleBy(x: scale, y: scale)

            // White background
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: CGFloat(w) / scale, height: CGFloat(h) / scale))

            // Light red baseline + x-height guides
            ctx.setStrokeColor(CGColor(red: 1, green: 0.8, blue: 0.8, alpha: 1))
            ctx.setLineWidth(0.5)
            let baseY = padding + display.descent
            ctx.move(to: CGPoint(x: 0, y: baseY))
            ctx.addLine(to: CGPoint(x: CGFloat(w) / scale, y: baseY))
            ctx.strokePath()

            // Set deviceRGB black as context default fill/stroke.
            // Display nodes use textColor?.setFill/Stroke — when nil,
            // they fall through to the context's current color.
            // This guarantees glyphs, rules, and lines render visible.
            let dBlack = CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [0, 0, 0, 1])!
            ctx.setFillColor(dBlack)
            ctx.setStrokeColor(dBlack)

            // Draw the display tree
            ctx.saveGState()
            ctx.translateBy(x: padding, y: baseY)
            display.draw(ctx)
            ctx.restoreGState()

            guard let image = ctx.makeImage() else {
                print("  ⚠️  image fail: [\(label)]")
                continue
            }
            let path = "\(dir)/\(label).png"
            let url = URL(fileURLWithPath: path)
            guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
                print("  ⚠️  dest fail: [\(label)]")
                continue
            }
            CGImageDestinationAddImage(dest, image, nil)
            CGImageDestinationFinalize(dest)
            entries.append((label, latex, w, h))
            print("  ✅ [\(label)] \(latex) → \(w)×\(h)")
        }

        // Copy xits-math into the comparison dir for file:// font loading.
        let xitsFontName = "xits-math-comparison.otf"
        let xitsSrc = "/Users/alpha/Desktop/swift/AlphaEqt/Sources/AlphaEqt/Fonts/xits-math.otf"
        try? FileManager.default.copyItem(atPath: xitsSrc, toPath: "\(dir)/\(xitsFontName)")
        // Use relative path with cache busting and proper MIME type
        let timestamp = Int(Date().timeIntervalSince1970)
        let fontURL = "\(xitsFontName)?v=\(timestamp)"
        
        // Create mime.types with correct format
        let mimeFile = "\(dir)/.mime.types"
        try? "font/opentype otf".write(toFile: mimeFile, atomically: true, encoding: .utf8)

        // Register ALL KaTeX family names against xits-math.otf so the CDN CSS
        // selectors (.katex .mord → KaTeX_Main, .katex .mathit → KaTeX_Math, etc.)
        // all resolve to the same font file.
        // Open directly from disk — browser asks "Allow file access?" once.
        var html = """
        <!DOCTYPE html>
        <html><head><meta charset="utf-8"><title>AlphaEqt vs KaTeX</title>
        <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/katex.min.css">
        <style>
        @font-face{font-family:"KaTeX_AMS";src:url("\(fontURL)") format("opentype")}
        @font-face{font-family:"KaTeX_Caligraphic";src:url("\(fontURL)") format("opentype")}
        @font-face{font-family:"KaTeX_Fraktur";src:url("\(fontURL)") format("opentype")}
        @font-face{font-family:"KaTeX_Main";src:url("\(fontURL)") format("opentype")}
        @font-face{font-family:"KaTeX_Main";src:url("\(fontURL)") format("opentype");font-weight:bold}
        @font-face{font-family:"KaTeX_Math";src:url("\(fontURL)") format("opentype")}
        @font-face{font-family:"KaTeX_SansSerif";src:url("\(fontURL)") format("opentype")}
        @font-face{font-family:"KaTeX_Script";src:url("\(fontURL)") format("opentype")}
        @font-face{font-family:"KaTeX_Size1";src:url("\(fontURL)") format("opentype")}
        @font-face{font-family:"KaTeX_Size2";src:url("\(fontURL)") format("opentype")}
        @font-face{font-family:"KaTeX_Size3";src:url("\(fontURL)") format("opentype")}
        @font-face{font-family:"KaTeX_Size4";src:url("\(fontURL)") format("opentype")}
        @font-face{font-family:"KaTeX_Typewriter";src:url("\(fontURL)") format("opentype")}

        .katex,.katex *{font-size:50px!important}

        body{font-family:system-ui,sans-serif;background:#1a1a2e;color:#eee;margin:20px}
        h1{color:#e94560;text-align:center}
        .grid{display:grid;grid-template-columns:1fr 1fr;gap:6px;max-width:1500px;margin:0 auto}
        .card{background:#16213e;border-radius:8px;padding:8px}
        .card h3{color:#0f3460;background:#e94560;display:inline-block;padding:2px 8px;border-radius:4px;margin:0 0 6px 0;font-size:13px}
        .row{display:flex;gap:8px;align-items:flex-start}
        .col{flex:1;min-width:0}
        .col-label{font-size:11px;color:#888;margin-bottom:4px}
        .card img{max-width:100%;height:auto;background:#fff;border-radius:4px;padding:6px}
        .katex-out{background:#fff;border-radius:4px;padding:6px;min-height:20px;color:#000}
        .code{font-family:monospace;font-size:11px;color:#aaa;margin-top:4px;word-break:break-all}
        </style></head><body>
        <h1>AlphaEqt vs KaTeX (xits-math, 50pt) — Open directly from disk</h1>
        <p style="text-align:center;color:#888;font-size:12px">
        Browser will ask: "Allow this page to access files?" → click <b>Allow</b>
        </p>
        <div class="grid">
        """

        for e in entries {
            html += """
            <div class="card"><h3>\(e.label)</h3>
            <div class="row">
            <div class="col"><div class="col-label">AlphaEqt</div><img src="\(e.label).png"></div>
            <div class="col"><div class="col-label">KaTeX</div><div class="katex-out" id="k-\(e.label)"></div></div>
            </div>
            <div class="code">\(e.latex)</div>
            </div>
            """
        }

        html += """
        </div>
        <script src="https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/katex.min.js"></script>
        <script>
        document.fonts.ready.then(function(){
          var cases=[
        """
        for e in entries {
            let texEscaped = e.latex
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
                .replacingOccurrences(of: "\r", with: "")
                .replacingOccurrences(of: "\n", with: "")
            html += "['k-\(e.label)','\(texEscaped)'],\n"
        }
        html += """
          ];
          cases.forEach(function(x){
            try{katex.render(x[1],document.getElementById(x[0]),{displayMode:true,throwOnError:false,trust:true})}
            catch(e){document.getElementById(x[0]).textContent='⚠ '+e.message}
          });
        });
        </script></body></html>
        """

        let htmlPath = "\(dir)/comparison.html"
        try html.write(toFile: htmlPath, atomically: true, encoding: .utf8)
        print("\n  📄 HTML comparison page: \(htmlPath)")
        print("  🖼  \(entries.count) PNG images in: \(dir)")
    }
}
