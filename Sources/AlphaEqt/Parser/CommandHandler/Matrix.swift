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
func handleBeginMatrixCommand(tokens: ArraySlice<Token>, index: inout Int) -> ASTNode? {
    let tok = Array(tokens)
    guard tok.count >= 4 else { index = 1; return nil }

    // tok[0] = \begin, tok[1..3] should be `{`, envName, `}`
    var pos = 1
    while pos < tok.count, tok[pos].kind == .whitespace { pos += 1 }
    guard pos + 2 < tok.count else { index = pos; return nil }

    guard tok[pos].kind == .leftBrace,
          tok[pos + 2].kind == .rightBrace else {
        index = pos
        return nil
    }

    let envName = tok[pos + 1].text
    guard let env = matrixEnvs[envName] else {
        index = pos + 3
        return nil
    }

    // Find \end{envName}
    pos += 3  // skip past `}`
    var rows: [[[Token]]] = [[[]]]
    while pos < tok.count {
        let t = tok[pos]
        if t.kind == .command, t.text == "\\end",
           pos + 3 < tok.count,
           tok[pos + 1].kind == .leftBrace,
           tok[pos + 2].text == envName,
           tok[pos + 3].kind == .rightBrace {
            pos += 4
            break
        }
        if t.kind == .lineBreak {
            rows.append([[]]); pos += 1; continue
        }
        if t.kind == .alignmentTab {
            rows[rows.count - 1].append([]); pos += 1; continue
        }
        let r = rows.count - 1
        let c = rows[r].count - 1
        rows[r][c].append(t)
        pos += 1
    }

    index = pos - tokens.startIndex

    // Parse cells
    let parser = LatexParser()
    var rowNodes: [ASTNode] = []
    for rowCells in rows {
        var cols: [ASTNode] = []
        for colTokens in rowCells {
            let nodes = parser.parse(tokens: colTokens)
            cols.append(nodes.isEmpty
                ? ASTNode(type: .mathord, text: "")
                : (nodes.count == 1 ? nodes[0]
                   : ASTNode(type: .ordgroup, text: nil, childNodes: nodes)))
        }
        if !cols.isEmpty { rowNodes.append(ASTNode(type: .array, text: envName, childNodes: cols)) }
    }

    let tableNode = ASTNode(type: .array, text: envName, childNodes: rowNodes)
    if let (l, r) = env.delimiters {
        let inner = ASTNode(type: .ordgroup, text: nil, childNodes: [tableNode])
        return ASTNode(type: .leftright, text: "\(l)\0\(r)", childNodes: [inner])
    }
    return tableNode
}
