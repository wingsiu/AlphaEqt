import AlphaEqt
import SwiftMath
import SwiftUI

struct DemoView: View {
    @Environment(\.colorScheme) var colorScheme

    let latex = #"\left(\sqrt{\frac{\displaystyle{\sum_0^1 \u{5927}\u{52DD}\sin \theta}}{\frac{\displaystyle{\int_0^1 \u{1F603}x^2 dx}}{2+\frac{x^2}{y}}}}\right)^n"#
    
    init() {
        if CommandLine.arguments.contains("--test-arc-position") {
            testArcPosition()
        }
    }

    func testArcPosition() {
        let latex = #"\arc a"#
        let fontSize: CGFloat = 40

        let font = AlphaEqt.MTFont(font: .latinModernFont, size: fontSize)
        let typesetter = AlphaEqt.Typesetter(font: font)
        
        // Tokenize and parse the LaTeX string
        let lexer = AlphaEqt.Lexer(input: latex)
        let tokens = lexer.tokenize()
        let parser = AlphaEqt.LatexParser()
        guard let nodes = try? parser.parse(tokens: tokens) else {
            print("Failed to parse LaTeX: \(latex)")
            return
        }
        
        let display = typesetter.createDisplay(nodes)

        print("Display Tree for: \(latex)")
        display?.dumpDisplayTree()

        // Measure the position of the accent (arc) relative to the base 'a'
        if let accentDisplay = display?.findDisplay(with: "arc") {
            let baseDisplay = display?.findDisplay(with: "a")
            let basePosition = baseDisplay?.position ?? .zero
            let accentPosition = accentDisplay.position
            
            print("\nAccent Position: \(accentPosition)")
            print("Base Position: \(basePosition)")
            print("Vertical Offset: \(accentPosition.y - basePosition.y)")
            print("Horizontal Offset: \(accentPosition.x - basePosition.x)")
        } else {
            print("Accent not found in display tree")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("SIDE-BY-SIDE — Check Console").font(.title2)

            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("AlphaEqt").font(.headline).foregroundColor(.blue)
                    MathText(latex, fontSize: 30)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(8)
                        .background(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
                        .cornerRadius(8)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("SwiftMath").font(.headline).foregroundColor(.green)
                    SwiftMathView(latex: latex, fontSize: 30)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(8)
                        .background(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
                        .cornerRadius(8)
                }
            }
            Spacer()
        }
        .padding(24)
        .frame(minWidth: 700, minHeight: 300)
    }
}

// Quick inline view to render via SwiftMath's pipeline directly
struct SwiftMathView: NSViewRepresentable {
    let latex: String
    let fontSize: CGFloat

    func makeNSView(context: Context) -> NSView {
        let container = NSView(frame: .zero)
        let label = MTMathUILabel()
        label.latex = latex
        label.fontSize = fontSize
        label.textColor = .labelColor
        container.addSubview(label)
        label.frame = container.bounds
        container.frame = CGRect(origin: .zero, size: label.intrinsicContentSize)
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

@main
struct DemoApp: App {
    var body: some Scene {
        WindowGroup {
            DemoView()
        }
    }
}
