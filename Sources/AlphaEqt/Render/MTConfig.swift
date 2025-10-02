//
//  MTConfig.swift
//  AlphaEqt
//
//  Created by Alpha Ng on 2/10/2025.
//
import Foundation

#if os(iOS) || os(visionOS)

import UIKit

public typealias MTView = UIView
public typealias MTColor = UIColor
public typealias MTBezierPath = UIBezierPath
public typealias MTLabel = UILabel
public typealias MTEdgeInsets = UIEdgeInsets
public typealias MTRect = CGRect
public typealias MTImage = UIImage

let MTEdgeInsetsZero = UIEdgeInsets.zero
func MTGraphicsGetCurrentContext() -> CGContext? { UIGraphicsGetCurrentContext() }

#else

import AppKit

public typealias MTView = NSView
public typealias MTColor = NSColor
public typealias MTBezierPath = NSBezierPath
public typealias MTEdgeInsets = NSEdgeInsets
public typealias MTRect = NSRect
public typealias MTImage = NSImage

let MTEdgeInsetsZero = NSEdgeInsets.init(top: 0, left: 0, bottom: 0, right: 0)
func MTGraphicsGetCurrentContext() -> CGContext? { NSGraphicsContext.current?.cgContext }

#endif
