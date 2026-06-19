//
//  MTColor.swift
//  AlphaEqt
//

import Foundation
#if os(iOS) || os(visionOS)
import UIKit
public typealias MTColor = UIColor
#elseif os(macOS)
import AppKit
public typealias MTColor = NSColor
#endif

extension MTColor {
    /// Safe CGColor access — uses the native property.
    /// On macOS 10.8+ / iOS, NSColor/UIColor natively provide `.cgColor`.
    var safeCGColor: CGColor { self.cgColor }
}
