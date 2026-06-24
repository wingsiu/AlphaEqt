import AlphaEqt
import CoreGraphics
import Foundation
import ImageIO

// Match MathJax compare page: 30px logical size, 2× pixel density for crisp PNGs.
let logicalFontSize: CGFloat = 30
let pixelScale: CGFloat = 2

func renderToPNG(_ latex: String, outputPath: String) -> Bool {
    let font = MathFont.stix2Font.mtfont(size: logicalFontSize)
    let lexer = Lexer(input: latex)
    let tokens = lexer.tokenize()
    let parser = LatexParser()
    let nodes = parser.parse(tokens: tokens)
    guard !nodes.isEmpty else { print("  parse empty"); return false }
    let ts = Typesetter(font: font, style: .display)
    guard let display = ts.createDisplay(nodes) else { print("  render nil"); return false }

    let padding: CGFloat = 0
    let logicalW = display.width + padding * 2
    let logicalH = display.ascent + display.descent + padding * 2
    let width = Int(logicalW * pixelScale)
    let height = Int(logicalH * pixelScale)
    guard width > 0, height > 0 else { print("  zero size"); return false }

    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let ctx = CGContext(data: nil, width: width, height: height,
                               bitsPerComponent: 8, bytesPerRow: width * 4,
                               space: colorSpace,
                               bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
    ctx.scaleBy(x: pixelScale, y: pixelScale)
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: logicalW, height: logicalH))
    ctx.saveGState()
    ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
    ctx.translateBy(x: padding, y: padding + display.descent)
    display.draw(ctx)
    ctx.restoreGState()
    // Red debug box
    ctx.setStrokeColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
    ctx.setLineWidth(1 / pixelScale)
    ctx.stroke(CGRect(x: padding, y: padding, width: display.width, height: display.ascent + display.descent))

    guard let image = ctx.makeImage() else { return false }

    let url = URL(fileURLWithPath: outputPath)
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { return false }
    let dpi: CGFloat = 72 * pixelScale
    let props: [CFString: Any] = [
        kCGImagePropertyDPIWidth: dpi,
        kCGImagePropertyDPIHeight: dpi,
    ]
    CGImageDestinationAddImage(dest, image, props as CFDictionary)
    CGImageDestinationFinalize(dest)
    return true
}

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
    ("text",            #"\text{Hello world}"#),
    ("complex-frac1",   #"\frac{a}{b+\frac{c}{d+\frac{5}{y-\frac{x^2}{3}}}}"#),
    ("complex-int",     #"\sqrt[3]{a+\frac{3}{x^2}}\int_0^1\frac{{\int y}^3+\frac{x}{5}-1}{x^4-4\sqrt[3]{x}+\frac{\frac{3+x}{4-y}}{\frac{3+x}{\sqrt{c^2}+y}}}= \int_0^1 a \cos x 😃dx"#),
    ("complex-mix",     #"12x3^{\int 2}+\frac{\int a}{b}-\sqrt[n]{x+y^2-\frac{\frac{z}{1-7v^2}}{\frac{3r^3}{\frac 1{2+\frac xy}}}}+\int_0^1 \sum aa+3a"#),
]

let outputDir = "/Users/alpha/Desktop/swift/AlphaEqt/comparison_images"
try? FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

print("Rendering \(cases.count) expressions...")
var success = 0
for (label, latex) in cases {
    if renderToPNG(latex, outputPath: "\(outputDir)/\(label).png") {
        success += 1
        print("  OK \(label)")
    }
}
print("Done: \(success)/\(cases.count)")

let config: [String: Any] = [
    "logicalFontSize": Double(logicalFontSize),
    "pixelScale": Double(pixelScale),
]
let configURL = URL(fileURLWithPath: "\(outputDir)/compare-config.json")
let configData = try! JSONSerialization.data(withJSONObject: config, options: .prettyPrinted)
try! configData.write(to: configURL)
print("Wrote \(configURL.path)")
