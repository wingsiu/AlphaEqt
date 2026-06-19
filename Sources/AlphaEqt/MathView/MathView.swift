//
//  MathView.swift
//  AlphaEqt
//

import Foundation
import CoreGraphics

#if os(iOS) || os(visionOS)
import UIKit

public class MathView: UIView {

    public var latex: String = "" {
        didSet { needsRebuild = true; setNeedsDisplay() }
    }
    public var mathFontSize: CGFloat = 24 {
        didSet { needsRebuild = true; setNeedsDisplay() }
    }
    public var mathColor: UIColor = .label {
        didSet { needsRebuild = true; setNeedsDisplay() }
    }
    public var mathFont: MathFont = .xitsFont {
        didSet { needsRebuild = true; setNeedsDisplay() }
    }

    private var display: MTDisplay?
    private var needsRebuild = true

    override public init(frame: CGRect) { super.init(frame: frame); backgroundColor = .clear; isOpaque = false }
    required init?(coder: NSCoder) { super.init(coder: coder); backgroundColor = .clear; isOpaque = false }

    public override var intrinsicContentSize: CGSize {
        rebuildIfNeeded()
        guard let d = display else { return CGSize(width: 80, height: 30) }
        let leftPad: CGFloat = d is MTMathListDisplay ? -(d as! MTMathListDisplay).minChildX : 0
        return CGSize(width: d.width + leftPad + 20, height: d.ascent + d.descent + 20)
    }

    override public func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        rebuildIfNeeded()
        guard let display = display else { return }

        let leftPad: CGFloat = display is MTMathListDisplay ? -(display as! MTMathListDisplay).minChildX : 0
        // Use leftPad + 10 for margin, but ensure at least 10pt minimum
        let m: CGFloat = max(10, leftPad + 10)
        ctx.saveGState()
        ctx.translateBy(x: 0, y: bounds.height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.translateBy(x: m, y: 10 + display.descent)
        display.draw(ctx)
        ctx.restoreGState()
    }

    override public func layoutSubviews() { needsRebuild = true; setNeedsDisplay() }

    private func rebuildIfNeeded() {
        guard needsRebuild else { return }
        needsRebuild = false
        guard !latex.isEmpty else { display = nil; return }
        MTDisplay.debugBoxesEnabled = true
        let lexer = Lexer(input: latex)
        let tokens = lexer.lexAll()
        let nodes = LatexParser().parse(tokens: tokens)
        guard !nodes.isEmpty else { display = nil; return }
        display = Typesetter(font: mathFont.mtfont(size: mathFontSize),
                             style: .display).createDisplay(nodes)
        // Resolve to concrete UIColor (not dynamic) so CTLineDraw gets real RGB values.
        // Dynamic colors (.label) produce proxy CGColors that render black in CoreText.
        let isDark = traitCollection.userInterfaceStyle == .dark
        let concreteColor = isDark
            ? UIColor(red: 1, green: 1, blue: 1, alpha: 1)
            : UIColor(red: 0, green: 0, blue: 0, alpha: 1)
        display?.textColor = concreteColor

        invalidateIntrinsicContentSize()
    }
}

#elseif os(macOS)
import AppKit

public class MathView: NSView {

    public var latex: String = "" {
        didSet { needsRebuild = true; needsDisplay = true }
    }
    public var mathFontSize: CGFloat = 24 {
        didSet { needsRebuild = true; needsDisplay = true }
    }
    public var mathColor: NSColor = .labelColor {
        didSet { needsRebuild = true; needsDisplay = true }
    }
    public var mathFont: MathFont = .xitsFont {
        didSet { needsRebuild = true; needsDisplay = true }
    }

    private var display: MTDisplay?
    private var needsRebuild = true

    override public init(frame: NSRect) { super.init(frame: frame); wantsLayer = true; layer?.backgroundColor = .clear }
    required init?(coder: NSCoder) { super.init(coder: coder); wantsLayer = true; layer?.backgroundColor = .clear }

    public override var intrinsicContentSize: NSSize {
        rebuildIfNeeded()
        guard let d = display else { return NSSize(width: 80, height: 30) }
        return NSSize(width: d.width + 20, height: d.ascent + d.descent + 20)
    }

    override public func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        rebuildIfNeeded()
        guard let display = display else { return }

        let m: CGFloat = 10
        ctx.saveGState()
        ctx.translateBy(x: m, y: m + display.descent)
        display.draw(ctx)
        ctx.restoreGState()
    }

    override public func viewDidEndLiveResize() { needsRebuild = true; needsDisplay = true }

    private func rebuildIfNeeded() {
        guard needsRebuild else { return }
        needsRebuild = false
        guard !latex.isEmpty else { display = nil; return }
        MTDisplay.debugBoxesEnabled = true
        let lexer = Lexer(input: latex)
        let tokens = lexer.lexAll()
        let nodes = LatexParser().parse(tokens: tokens)
        guard !nodes.isEmpty else { display = nil; return }
        display = Typesetter(font: mathFont.mtfont(size: mathFontSize),
                             style: .display).createDisplay(nodes)
        // Resolve to concrete NSColor so CTLineDraw gets real RGB values.
        let isDark = effectiveAppearance.name == .darkAqua
            || effectiveAppearance.name == .vibrantDark
        let concreteColor = isDark
            ? NSColor(red: 1, green: 1, blue: 1, alpha: 1)
            : NSColor(red: 0, green: 0, blue: 0, alpha: 1)
        display?.textColor = concreteColor

        // ---- Debug: dump display tree to console ----
        if let d = display {
            print("\n========== ALPHAEQT DISPLAY TREE ==========")
            print("LaTeX: \(latex)")
            d.dumpDisplayTree()
            print("============================================\n")
        }

        invalidateIntrinsicContentSize()
    }
}
#endif
