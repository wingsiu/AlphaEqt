import AlphaEqt
import CoreGraphics
import CoreText
import Foundation
import ImageIO

// ── Render a LaTeX expression to PNG ──────────────────────────────
func renderToPNG(_ latex: String, outputPath: String, fontSize: CGFloat = 50, scale: CGFloat = 1) -> Bool {
    let font = MathFont.xitsFont.mtfont(size: fontSize)
    let lexer = Lexer(input: latex)
    let tokens = lexer.tokenize()
    let parser = LatexParser()
    let nodes = parser.parse(tokens: tokens)
    guard !nodes.isEmpty else { print("  ⚠️  parse empty: \(latex)"); return false }
    let ts = Typesetter(font: font, style: .display)
    guard let display = ts.createDisplay(nodes) else { print("  ⚠️  render nil: \(latex)"); return false }

    let padding: CGFloat = 0
    let width = Int((display.width + padding * 2) * scale)
    let height = Int((display.ascent + display.descent + padding * 2) * scale)
    guard width > 0, height > 0 else { print("  ⚠️  zero size: \(latex)"); return false }

    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let ctx = CGContext(data: nil, width: width, height: height,
                               bitsPerComponent: 8, bytesPerRow: width * 4,
                               space: colorSpace,
                               bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        print("  ⚠️  context failed: \(latex)"); return false
    }
    ctx.scaleBy(x: scale, y: scale)

    // White background
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: CGFloat(width) / scale, height: CGFloat(height) / scale))

    // Draw at origin with padding
    ctx.saveGState()
    ctx.translateBy(x: padding, y: padding + display.descent)
    display.draw(ctx)
    ctx.restoreGState()

    guard let image = ctx.makeImage() else { print("  ⚠️  image failed: \(latex)"); return false }

    let url = URL(fileURLWithPath: outputPath)
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        print("  ⚠️  dest failed: \(latex)"); return false
    }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
    return true
}

// ── Test cases matching testDiagnosticDump ────────────────────────
let cases: [(String, String)] = [
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
]

let outputDir = "/Users/alpha/Desktop/swift/AlphaEqt/comparison_images"
try? FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

print("Rendering \(cases.count) expressions to \(outputDir)/...")
var success = 0
for (label, latex) in cases {
    let path = "\(outputDir)/\(label).png"
    if renderToPNG(latex, outputPath: path) {
        success += 1
        print("  ✅ \(label)")
    }
}
print("\nDone: \(success)/\(cases.count) rendered successfully.")
print("Output: \(outputDir)")
