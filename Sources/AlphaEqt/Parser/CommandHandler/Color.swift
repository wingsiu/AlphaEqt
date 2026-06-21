//
//  Color.swift
//  AlphaEqt
//
//  Parser handler for \color, \textcolor, \colorbox, \fcolorbox.
//

import Foundation

// MARK: - Named Color Lookup

/// Maps common LaTeX color names to RGB hex values.
private let namedColors: [String: String] = [
    "red":     "#FF0000",
    "blue":    "#0000FF",
    "green":   "#00AA00",
    "yellow":  "#FFFF00",
    "cyan":    "#00FFFF",
    "magenta": "#FF00FF",
    "black":   "#000000",
    "white":   "#FFFFFF",
    "gray":    "#808080",
    "orange":  "#FF8800",
    "purple":  "#800080",
    "pink":    "#FF69B4",
    "brown":   "#8B4513",
    "teal":    "#008080",
    "violet":  "#8A2BE2",
]

/// Parses a color string (hex `#RRGGBB` or named) into an MTColor.
/// Returns nil if the color is unrecognized.
func parseColor(_ name: String) -> MTColor? {
    let trimmed = name.trimmingCharacters(in: .whitespaces)
    if trimmed.hasPrefix("#"), trimmed.count == 7 {
        let r = CGFloat(Int(trimmed.dropFirst(1).prefix(2), radix: 16) ?? 0) / 255
        let g = CGFloat(Int(trimmed.dropFirst(3).prefix(2), radix: 16) ?? 0) / 255
        let b = CGFloat(Int(trimmed.dropFirst(5).prefix(2), radix: 16) ?? 0) / 255
        return MTColor(red: r, green: g, blue: b, alpha: 1)
    }
    if let hex = namedColors[trimmed.lowercased()] {
        return parseColor(hex)
    }
    return nil
}

// MARK: - \color{...}{...} / \textcolor{...}{...}

/// Parses `\color{red}{content}` or `\textcolor{red}{content}`.
/// Returns a `.color` node with `text = colorName` and `childNodes = [content]`.
func handleColorCommand(tokens: ArraySlice<Token>, index: inout Int) -> ASTNode? {
    let tokensArray = Array(tokens)
    guard tokensArray.count >= 4 else { index = 1; return nil }

    // First brace group: color name
    guard tokensArray[tokensArray.startIndex + 1].kind == .leftBrace else {
        index = 1; return nil
    }
    var colorTokens: [Token] = []
    var depth = 1
    var i = tokensArray.startIndex + 2
    while i < tokensArray.endIndex, depth > 0 {
        let t = tokensArray[i]
        if t.kind == .leftBrace { depth += 1 }
        else if t.kind == .rightBrace { depth -= 1 }
        if depth > 0 { colorTokens.append(t) }
        i += 1
    }
    let colorName = colorTokens.map { $0.text }.joined()

    // Second brace group: content
    guard i < tokensArray.endIndex, tokensArray[i].kind == .leftBrace else {
        index = i - tokensArray.startIndex; return nil
    }
    depth = 1
    var contentTokens: [Token] = []
    i += 1
    while i < tokensArray.endIndex, depth > 0 {
        let t = tokensArray[i]
        if t.kind == .leftBrace { depth += 1 }
        else if t.kind == .rightBrace { depth -= 1 }
        if depth > 0 { contentTokens.append(t) }
        i += 1
    }

    let parser = LatexParser()
    let contentNodes = parser.parse(tokens: contentTokens)
    let childNodes: [ASTNode] = contentNodes.isEmpty
        ? [ASTNode(type: .mathord, text: "")]
        : contentNodes

    index = i - tokensArray.startIndex
    return ASTNode(
        type: .color,
        text: colorName,
        childNodes: childNodes
    )
}

// MARK: - \colorbox{...}{...} / \fcolorbox{...}{...}{...}

/// Parses `\colorbox{red}{content}` (same color for border and fill)
/// or `\fcolorbox{blue}{red}{content}` (border-color, fill-color, content).
/// Produces a `.colorbox` node with `text = "borderColor\0fillColor"` and
/// `childNodes = [content]`.
func handleColorboxCommand(tokens: ArraySlice<Token>, index: inout Int) -> ASTNode? {
    let tokensArray = Array(tokens)
    let isFcolorbox = tokensArray[tokensArray.startIndex].text == "\\fcolorbox"
    guard tokensArray.count >= (isFcolorbox ? 6 : 4) else { index = 1; return nil }

    // First brace: border color (for \fcolorbox) or fill color (for \colorbox)
    guard tokensArray[tokensArray.startIndex + 1].kind == .leftBrace else {
        index = 1; return nil
    }
    var borderTokens: [Token] = []
    var depth = 1
    var i = tokensArray.startIndex + 2
    while i < tokensArray.endIndex, depth > 0 {
        let t = tokensArray[i]
        if t.kind == .leftBrace { depth += 1 }
        else if t.kind == .rightBrace { depth -= 1 }
        if depth > 0 { borderTokens.append(t) }
        i += 1
    }
    let borderColor = borderTokens.map { $0.text }.joined()

    let fillColor: String
    if isFcolorbox {
        // Second brace for \fcolorbox: fill color
        guard i < tokensArray.endIndex, tokensArray[i].kind == .leftBrace else {
            index = i - tokensArray.startIndex; return nil
        }
        depth = 1
        var fillTokens: [Token] = []
        i += 1
        while i < tokensArray.endIndex, depth > 0 {
            let t = tokensArray[i]
            if t.kind == .leftBrace { depth += 1 }
            else if t.kind == .rightBrace { depth -= 1 }
            if depth > 0 { fillTokens.append(t) }
            i += 1
        }
        fillColor = fillTokens.map { $0.text }.joined()
    } else {
        fillColor = borderColor
    }

    // Content brace
    guard i < tokensArray.endIndex, tokensArray[i].kind == .leftBrace else {
        index = i - tokensArray.startIndex; return nil
    }
    depth = 1
    var contentTokens: [Token] = []
    i += 1
    while i < tokensArray.endIndex, depth > 0 {
        let t = tokensArray[i]
        if t.kind == .leftBrace { depth += 1 }
        else if t.kind == .rightBrace { depth -= 1 }
        if depth > 0 { contentTokens.append(t) }
        i += 1
    }

    let parser = LatexParser()
    let contentNodes = parser.parse(tokens: contentTokens)
    let childNodes: [ASTNode] = contentNodes.isEmpty
        ? [ASTNode(type: .mathord, text: "")]
        : contentNodes

    index = i - tokensArray.startIndex
    // Store both colors separated by \0: "borderColor\0fillColor"
    return ASTNode(
        type: .colorbox,
        text: "\(borderColor)\0\(fillColor)",
        childNodes: childNodes
    )
}
