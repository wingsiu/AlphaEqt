//
//  SwiftMathView.swift
//  AlphaEqt
//
//  SwiftUI wrapper for MathView.
//

import SwiftUI

/// SwiftUI view that renders a LaTeX math expression.
///
/// Usage:
/// ```swift
/// MathText("E = mc^2")
///     .frame(height: 50)
/// ```
public struct MathText {

    public var latex: String
    public var fontSize: CGFloat
    public var fontName: MathFont

    public init(_ latex: String,
                fontSize: CGFloat = 24,
                font: MathFont = .xitsFont) {
        self.latex = latex
        self.fontSize = fontSize
        self.fontName = font
    }
}

#if os(macOS)
extension MathText: NSViewRepresentable {
    public func makeNSView(context: Context) -> MathView {
        let view = MathView()
        view.latex = latex
        view.mathFontSize = fontSize
        view.mathFont = fontName
        return view
    }

    public func updateNSView(_ nsView: MathView, context: Context) {
        nsView.latex = latex
        nsView.mathFontSize = fontSize
        nsView.mathFont = fontName
    }

    @available(macOS 13.0, *)
    public func sizeThatFits(_ proposal: ProposedViewSize, nsView: MathView, context: Context) -> CGSize? {
        nsView.intrinsicContentSize
    }
}
#else
@available(iOS 16.0, *)
extension MathText: UIViewRepresentable {
    public func makeUIView(context: Context) -> MathView {
        let view = MathView()
        view.latex = latex
        view.mathFontSize = fontSize
        view.mathFont = fontName
        view.setContentHuggingPriority(.required, for: .horizontal)
        view.setContentHuggingPriority(.required, for: .vertical)
        view.setContentCompressionResistancePriority(.required, for: .horizontal)
        view.setContentCompressionResistancePriority(.required, for: .vertical)
        return view
    }

    public func updateUIView(_ uiView: MathView, context: Context) {
        uiView.latex = latex
        uiView.mathFontSize = fontSize
        uiView.mathFont = fontName
    }

    public func sizeThatFits(_ proposal: ProposedViewSize, uiView: MathView, context: Context) -> CGSize? {
        let size = uiView.intrinsicContentSize
        return size
    }
}
#endif
