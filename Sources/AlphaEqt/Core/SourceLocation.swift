//
//  SourceLocation.swift
//  AlphaEqt
//
//  Created by Alpha Ng on 1/10/2025.
//

import Foundation

/// Represents a location in the source input string
public struct SourceLocation: Equatable {
    /// Starting index in the source string
    public let start: Int
    /// Ending index in the source string
    public let end: Int
    
    public init(start: Int, end: Int) {
        self.start = start
        self.end = end
    }
}
