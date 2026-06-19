//
//  Matrix.swift
//  AlphaEqt
//
//  Parser for \begin{matrix}...\end{matrix} environments.
//

import Foundation

/// Matrix environment definitions.
private struct MatrixEnv {
    let delimiters: (String, String)?
}

private let matrixEnvs: [String: MatrixEnv] = [
    "matrix":      MatrixEnv(delimiters: nil),
    "pmatrix":     MatrixEnv(delimiters: ("(", ")")),
    "bmatrix":     MatrixEnv(delimiters: ("[", "]")),
    "Bmatrix":     MatrixEnv(delimiters: ("{", "}")),
    "vmatrix":     MatrixEnv(delimiters: ("|", "|")),
    "Vmatrix":     MatrixEnv(delimiters: ("|", "|")),
]

/// Parses `\begin{env} ... \end{env}`.
/// The input consists of: `\begin`, `{`, `<envName>`, `}`, content..., `\end`, `{`, `<envName>`, `}`
func handleBeginMatrixCommand(tokens: ArraySlice<Token>, index: inout Int) -> ASTNode? {
    // tokens[tokens.startIndex] == "\begin"
    guard tokens.count >= 4 else {
        index = 1
        return nil
    }
    let t1 = tokens[tokens.startIndex + 1]  // should be `{`
    let t2 = tokens[tokens.startIndex + 2]  // env name
    let t3 = tokens[tokens.startIndex + 3]  // should be `}`
    guard t1.kind == .leftBrace, t3.kind == .rightBrace else {
        index = 1
        return nil
    }
    let envName = t2.text
    guard let env = matrixEnvs[envName] else {
        index = 4  // skip \begin{unknown}
        return nil
    }

    // Find matching \end{envName}
    var cellTokens: [[[Token]]] = [[[]]]  // rows × cols × tokens
    var i = tokens.startIndex + 4
    while i < tokens.endIndex {
        let t = tokens[i]
        // Check for `\end`, `{`, `<envName>`, `}`
        if t.kind == .command, t.text == "\\end",
           i + 3 < tokens.endIndex,
           tokens[i + 1].kind == .leftBrace,
           tokens[i + 2].text == envName,
           tokens[i + 3].kind == .rightBrace {
            i += 4
            break
        }
        if t.kind == .lineBreak {
            cellTokens.append([[]])
            i += 1
            continue
        }
        if t.kind == .alignmentTab {
            cellTokens[cellTokens.count - 1].append([])
            i += 1
            continue
        }
        let rowIdx = cellTokens.count - 1
        let colIdx = cellTokens[rowIdx].count - 1
        cellTokens[rowIdx][colIdx].append(t)
        i += 1
    }

    index = i - tokens.startIndex  // advance past \end{envName}

    // Parse each cell
    let parser = LatexParser()
    var rows: [ASTNode] = []
    for rowCells in cellTokens {
        var cols: [ASTNode] = []
        for colTokens in rowCells {
            let nodes = parser.parse(tokens: colTokens)
            if nodes.count == 1 {
                cols.append(nodes[0])
            } else if nodes.isEmpty {
                cols.append(ASTNode(type: .mathord, text: ""))
            } else {
                cols.append(ASTNode(type: .ordgroup, text: nil, childNodes: nodes))
            }
        }
        if !cols.isEmpty {
            rows.append(ASTNode(type: .array, text: envName, childNodes: cols))
        }
    }

    let tableNode = ASTNode(type: .array, text: envName, childNodes: rows)

    // Wrap with delimiters (pmatrix→(), bmatrix→[], etc.)
    if let (l, r) = env.delimiters {
        let inner = ASTNode(type: .ordgroup, text: nil, childNodes: [tableNode])
        return ASTNode(type: .leftright, text: "\(l)\0\(r)", childNodes: [inner])
    }
    return tableNode
}
