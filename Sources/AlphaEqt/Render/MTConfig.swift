//
//  MTConfig.swift
//  AlphaEqt
//
//  Optional tuning overrides for MATH table constants.
//  Set any property to a non-nil value to override the font-table default.
//

import Foundation
import CoreGraphics

/// Global configuration for rendering tweaks.
/// These override the OpenType MATH table values when set.
public struct MTConfig: @unchecked Sendable {
    public nonisolated(unsafe) static var shared = MTConfig()

    /// Fraction script scale (font × value) — nil = use font table.
    /// Defaults to 0.90 for softer shrinking (scripts use 0.75).
    public var fractionScriptScaleDown: CGFloat? = 0.90

    /// Fraction script-of-script scale — nil = use font table.
    /// Defaults to 0.80 for softer shrinking (scripts use 0.60).
    public var fractionScriptScriptScaleDown: CGFloat? = 0.80

    /// Minimum font size for any level (prevents unreadable text).
    public var minimumFontSize: CGFloat = 6.0
}
