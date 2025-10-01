//
//  Spaces.swift
//  SwiftMath (KaTeX-compatible spacing table)
//
//  This file defines the inter-element spacing table for math typesetting,
//  using KaTeX/TeX atom logic, but mapping the values to SwiftMath's spacing
//  types (which reference font metric mu units).
//

import Foundation

/// Atom types, following KaTeX/TeX logic
public enum InterElementSpaceType: Int, Sendable {
    case invalid = -1
    case none = 0
    case thin = 2
    case nsThin = 3
    case nsMedium = 4
    case nsThick = 5
}

public enum AtomType: Int, Sendable {
    case ord = 0
    case op = 1
    case bin = 2
    case rel = 3
    case open = 4
    case close = 5
    case punct = 6
    case inner = 7
}

public struct MathSpaces {
    public static let spaceTable: [[InterElementSpaceType]] = [
        [.none,    .thin,    .nsMedium, .nsThick, .none,   .none,  .none,   .thin],    // ord
        [.thin,    .thin,    .invalid,  .nsThick, .none,   .none,  .none,   .thin],    // op
        [.nsMedium,.nsMedium,.invalid,  .invalid, .nsMedium,.invalid,.invalid,.nsMedium],// bin
        [.nsThick, .nsThick, .invalid,  .invalid, .nsThick, .invalid,.invalid,.nsThick],// rel
        [.none,    .none,    .none,     .none,    .none,    .none,  .none,   .none],    // open
        [.none,    .thin,    .nsMedium, .nsThick, .none,    .none,  .none,   .thin],    // close
        [.thin,    .thin,    .invalid,  .thin,    .thin,    .thin,  .thin,   .thin],    // punct
        [.thin,    .thin,    .nsMedium, .nsThick, .thin,    .none,  .thin,   .thin],    // inner
    ]
    
    public static func getInterElementSpacing(left: AtomType, right: AtomType) -> InterElementSpaceType {
        return spaceTable[left.rawValue][right.rawValue]
    }
}
