//
//  MTDisplay.swift
//  AlphaEqt
//
//  Created by Alpha Ng on 2/10/2025.
//
import Foundation
import QuartzCore
import CoreText
//import SwiftUI


// MARK: - MTDisplay

/// The base class for rendering a math equation.
public class MTDisplay:NSObject {
    // needed for isIos6Supported() func above
    /// Draws itself in the given graphics context.
    public func draw(_ context:CGContext) {
        if self.localBackgroundColor != nil {
            context.saveGState()
            context.setBlendMode(.normal)
            context.setFillColor(self.localBackgroundColor!.cgColor)
            context.fill(self.displayBounds())
            context.restoreGState()
        }
    }
    
    /// Gets the bounding rectangle for the MTDisplay
    //func displayBounds() -> CGRect {
    public func displayBounds() -> CGRect { //By Alpha
        CGRectMake(self.position.x, self.position.y - self.descent, self.width, self.ascent + self.descent)
    }

    /// The distance from the axis to the top of the display
    public var ascent:CGFloat = 0
    /// The distance from the axis to the bottom of the display
    public var descent:CGFloat = 0
    /// The width of the display
    public var width:CGFloat = 0
    /// Position of the display with respect to the parent view or display.
    //var position = CGPoint.zero
    public var position = CGPoint.zero //By alpha
    /// The range of characters supported by this item
    public var range:NSRange=NSMakeRange(0, 0)
    /// Whether the display has a subscript/superscript following it.
    public var hasScript:Bool = false
    /// The text color for this display
    var textColor: MTColor?
    /// The local color, if the color was mutated local with the color command
    var localTextColor: MTColor?
    /// The background color for this display
    var localBackgroundColor: MTColor?
    //By Alpha
    public weak var astNode : ASTNode?
    
    
}
