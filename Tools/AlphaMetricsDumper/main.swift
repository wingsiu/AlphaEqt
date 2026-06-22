import AlphaEqt
import Foundation

let args = CommandLine.arguments
guard args.count >= 3 else { print("Usage: AlphaMetricsDumper <label> <latex>"); exit(1) }
let label = args[1]
let latex = args[2]

let font = MathFont.xitsFont.mtfont(size: 50)
let lexer = Lexer(input: latex)
let tokens = lexer.tokenize()
let parser = LatexParser()
let nodes = parser.parse(tokens: tokens)
guard !nodes.isEmpty else { print("{\"error\":\"parse_empty\"}"); exit(1) }
let ts = Typesetter(font: font, style: .display)
guard let display = ts.createDisplay(nodes) else { print("{\"error\":\"render_nil\"}"); exit(1) }

@MainActor func walk(_ d: MTDisplay, depth: Int, items: inout [[String: Any]]) {
    var info: [String: Any] = [
        "kind": String(describing: type(of: d)),
        "depth": depth,
        "x": Double(d.position.x),
        "y": Double(d.position.y),
        "ascent": Double(d.ascent),
        "descent": Double(d.descent),
        "width": Double(d.width),
    ]
    if let ctLine = d as? MTCTLineDisplay, let atoms = ctLine.atoms {
        info["text"] = atoms.compactMap { $0.text }.joined()
    }
    if let glyph = d as? MTGlyphDisplay {
        info["glyph"] = glyph.glyph
        info["rawAscent"] = Double(glyph.rawAscent)
        info["rawDescent"] = Double(glyph.rawDescent)
        info["shiftDown"] = Double(glyph.shiftDown)
    }
    if let frac = d as? MTFractionDisplay {
        info["numeratorUp"] = Double(frac.numeratorUp)
        info["denominatorDown"] = Double(frac.denominatorDown)
        info["lineThickness"] = Double(frac.lineThickness)
    }
    if let radical = d as? MTRadicalDisplay {
        info["topKern"] = Double(radical.topKern)
        info["lineThickness"] = Double(radical.lineThickness)
    }
    items.append(info)

    if let frac = d as? MTFractionDisplay {
        if let n = frac.numerator { walk(n, depth: depth + 1, items: &items) }
        if let de = frac.denominator { walk(de, depth: depth + 1, items: &items) }
    } else if let sq = d as? MTSupSubDisplay {
        if let b = sq.base { walk(b, depth: depth + 1, items: &items) }
        if let s = sq.superscript { walk(s, depth: depth + 1, items: &items) }
        if let s = sq.subscriptDisplay { walk(s, depth: depth + 1, items: &items) }
    } else if let rad = d as? MTRadicalDisplay {
        if let r = rad.radicand { walk(r, depth: depth + 1, items: &items) }
        if let deg = rad.degree { walk(deg, depth: depth + 1, items: &items) }
    } else if let acc = d as? MTAccentDisplay {
        if let a = acc.accent { walk(a, depth: depth + 1, items: &items) }
        if let ae = acc.accentee { walk(ae, depth: depth + 1, items: &items) }
    } else if let list = d as? MTMathListDisplay {
        for sub in list.subDisplays { walk(sub, depth: depth + 1, items: &items) }
    } else if let cb = d as? MTColorboxDisplay {
        if let inner = cb.inner { walk(inner, depth: depth + 1, items: &items) }
    } else if let lim = d as? MTLargeOpLimitsDisplay {
        if let n = lim.nucleus { walk(n, depth: depth + 1, items: &items) }
        if let u = lim.upperLimit { walk(u, depth: depth + 1, items: &items) }
        if let l = lim.lowerLimit { walk(l, depth: depth + 1, items: &items) }
    } else if let cons = d as? MTGlyphConstructionDisplay {
        info["glyphCount"] = cons.glyphs.count
    }
}

var items = [[String: Any]]()
walk(display, depth: 0, items: &items)
let result: [String: Any] = ["label": label, "expression": latex, "items": items, "itemCount": items.count]
let data = try! JSONSerialization.data(withJSONObject: result, options: .prettyPrinted)
print(String(data: data, encoding: .utf8)!)
