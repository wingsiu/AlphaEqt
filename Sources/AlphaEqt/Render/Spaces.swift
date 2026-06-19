//
//  Spaces.swift
//  AlphaEqt
//
//  KaTeX-compatible spacing table for math typesetting.
//

import Foundation

/// Types of inter-element spacing
public enum InterElementSpaceType: Int, Sendable {
    case invalid = -1
    case none = 0
    case thin = 2
    case nsThin = 3
    case nsMedium = 4
    case nsThick = 5
}

/// Atom types following KaTeX/TeX logic
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

/// Spacing table based on KaTeX rules
public class Spaces: @unchecked Sendable {
    public static let shared = Spaces()

    private let spaceTable: [[InterElementSpaceType]] = [
        [.none,    .thin,    .nsMedium, .nsThick, .none,   .none,  .none,   .thin],    // ord
        [.thin,    .thin,    .invalid,  .nsThick, .none,   .none,  .none,   .thin],    // op
        [.nsMedium,.nsMedium,.invalid,  .invalid, .nsMedium,.invalid,.invalid,.nsMedium],// bin
        [.nsThick, .nsThick, .invalid,  .invalid, .nsThick, .invalid,.invalid,.nsThick],// rel
        [.none,    .none,    .none,     .none,    .none,    .none,  .none,   .none],    // open
        [.none,    .thin,    .nsMedium, .nsThick, .none,    .none,  .none,   .thin],    // close
        [.thin,    .thin,    .invalid,  .thin,    .thin,    .thin,  .thin,    .thin],    // punct
        [.thin,    .thin,    .nsMedium, .nsThick, .thin,    .none,  .thin,   .thin],    // inner
    ]

    public func getInterElementSpaceType(_ left: AtomType, right: AtomType) -> InterElementSpaceType {
        let l = left.rawValue
        let r = right.rawValue
        guard l >= 0, l < spaceTable.count, r >= 0, r < spaceTable[l].count else {
            return .invalid
        }
        return spaceTable[l][r]
    }
}
