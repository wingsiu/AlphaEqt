//
//  MTDisplay.swift
//  AlphaEqt
//
//  Created by Alpha Ng on 2/10/2025.
//
import Foundation
import QuartzCore
import CoreText

// MARK: - MTDisplay

/// The base class for rendering a math equation.
public class MTDisplay: NSObject {

    /// When `true`, every MTDisplay draws a semi‑transparent red box around its
    /// local bounds during `draw()`.  The box uses local coordinates
    /// (origin = baseline at (0,0)) so it is correct at any nesting depth.
    /// Set this to `true` before rendering to visually compare position / ascent /
    /// descent / width between AlphaEqt and the original SwiftMath.
    nonisolated(unsafe) public static var debugBoxesEnabled = true

    /// Draws itself in the given graphics context.
    public func draw(_ context: CGContext) {
        // Background fill (if a local background color was set).
        if self.localBackgroundColor != nil {
            context.saveGState()
            context.setBlendMode(.normal)
            context.setFillColor(self.localBackgroundColor!.cgColor)
            context.fill(self.displayBounds())
            context.restoreGState()
        }

        // ---- Debug: red outline of local bounds ----
        if MTDisplay.debugBoxesEnabled {
            context.saveGState()
            context.setStrokeColor(MTColor.red.withAlphaComponent(0.4).cgColor)
            context.setLineWidth(1)
            let localBounds = CGRect(
                x: 0,
                y: -self.descent,
                width: self.width,
                height: self.ascent + self.descent
            )
            context.stroke(localBounds)
            context.restoreGState()
        }
    }

    /// Gets the bounding rectangle for the MTDisplay
    //func displayBounds() -> CGRect {
    public func displayBounds() -> CGRect { //By Alpha
        CGRectMake(self.position.x, self.position.y - self.descent, self.width, self.ascent + self.descent)
    }

    /// The distance from the axis to the top of the display
    public var ascent: CGFloat = 0
    /// The distance from the axis to the bottom of the display
    public var descent: CGFloat = 0
    /// The width of the display
    public var width: CGFloat = 0
    /// Position of the display with respect to the parent view or display.
    //var position = CGPoint.zero
    public var position = CGPoint.zero //By alpha
    /// The range of characters supported by this item
    public var range: NSRange = NSMakeRange(0, 0)
    /// Whether the display has a subscript/superscript following it.
    public var hasScript: Bool = false
    /// The text color for this display
    var textColor: MTColor?
    /// The local color, if the color was mutated local with the color command
    var localTextColor: MTColor?
    /// The background color for this display
    var localBackgroundColor: MTColor?
    //By Alpha
    public weak var astNode: ASTNode?

    /// Recursively dumps the display tree to console for debug comparison.
    public func dumpDisplayTree(indent: String = "") {
        print("\(indent)\(type(of: self))"
              + " pos=(\(Int(position.x)),\(Int(position.y)))"
              + " ascent=\(Int(ascent)) descent=\(Int(descent))"
              + " width=\(Int(width))")
    }
}
