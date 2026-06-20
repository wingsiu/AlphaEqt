//
//  Matrix.swift
//  AlphaEqt
//
//  Parser for \begin{matrix}...\end{matrix} environments.
//

import Foundation

private let matrixEnvs: Set<String> = [
    "matrix", "pmatrix", "bmatrix", "Bmatrix", "vmatrix", "Vmatrix", "cases"
]

func handleBeginMatrixCommand(tokens: ArraySlice<Token>, index: inout Int) -> ASTNode? {
    let tok = Array(tokens)
    guard tok.count >= 4 else { index = 1; return nil }

    var pos = 1
    while pos < tok.count, tok[pos].kind == .whitespace { pos += 1 }
    guard pos < tok.count, tok[pos].kind == .leftBrace else { index = pos; return nil }

    // Collect environment name spanning multiple tokens (lexer splits
    // identifiers into single-code-unit tokens, e.g. "matrix" → m,a,t,r,i,x)
    var envName = ""
    pos += 1
    while pos < tok.count, tok[pos].kind != .rightBrace {
        envName += tok[pos].text
        pos += 1
    }
    guard pos < tok.count, tok[pos].kind == .rightBrace else { index = pos; return nil }
    pos += 1  // past '}'

    guard matrixEnvs.contains(envName) else { index = pos; return nil }

    // Collect rows × columns × tokens
    var rows: [[[Token]]] = [[[]]]
    while pos < tok.count {
        let t = tok[pos]
        if t.kind == .command, t.text == "\\end",
           pos + 1 < tok.count, tok[pos + 1].kind == .leftBrace {
            // Collect end-env name across multiple single-char tokens
            var endEnvName = ""
            var scan = pos + 2
            while scan < tok.count, tok[scan].kind != .rightBrace {
                endEnvName += tok[scan].text
                scan += 1
            }
            if scan < tok.count, tok[scan].kind == .rightBrace, endEnvName == envName {
                pos = scan + 1; break
            }
        }
        if t.kind == .lineBreak { rows.append([[]]); pos += 1; continue }
        if t.kind == .alignmentTab { rows[rows.count - 1].append([]); pos += 1; continue }
        rows[rows.count - 1][rows[rows.count - 1].count - 1].append(t)
        pos += 1
    }

    index = pos  // pos is already relative to tok[0] == slice start
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

    let table = ASTNode(type: .array, text: envName, childNodes: rowNodes)

    // Wrap with stretchy delimiters: pmatrix→(), bmatrix→[], etc.
    let delimMap: [String: (String, String)] = [
        "pmatrix": ("(", ")"), "bmatrix": ("[", "]"),
        "Bmatrix": ("{", "}"), "vmatrix": ("|", "|"), "Vmatrix": ("|", "|"),
    ]
    if let (l, r) = delimMap[envName] {
        let inner = ASTNode(type: .ordgroup, text: nil, childNodes: [table])
        return ASTNode(type: .leftright, text: "\(l)\0\(r)", childNodes: [inner])
    }
    if envName == "cases" {
        // cases: left brace, no right delimiter
        let inner = ASTNode(type: .ordgroup, text: nil, childNodes: [table])
        return ASTNode(type: .leftright, text: "{\0.", childNodes: [inner])
    }
    return table
}
