#!/usr/bin/env python3
"""Unified TeX + AlphaEqt per-element metrics dumper.

1. Renders expression via LuaLaTeX → PDF → PyMuPDF per-glyph extraction
2. Renders expression via AlphaEqt (swift run) → JSON display tree
3. Saves both to .json files for comparison
"""

import os, subprocess, json, sys

PREAMBLE = r'''\documentclass{article}
\usepackage{fontspec}
\usepackage{unicode-math}
\usepackage[active,tightpage]{preview}
\usepackage[margin=0pt]{geometry}
\setmainfont{xits-math-comparison.otf}[Path=/Users/alpha/Desktop/swift/AlphaEqt/comparison_images/]
\setmathfont{xits-math-comparison.otf}[Path=/Users/alpha/Desktop/swift/AlphaEqt/comparison_images/]
\pagestyle{empty}
\begin{document}
\fontsize{50}{60}\selectfont
\begin{preview}
'''

POSTAMBLE = r'''
\end{preview}
\end{document}
'''

EXPRESSIONS = {
    "frac":      r"$\displaystyle \frac{x}{y}$",
    "sqrt":      r"$\displaystyle \sqrt{x+1}$",
    "sup":       r"$\displaystyle x^{2}$",
    "sub":       r"$\displaystyle x_{1}$",
    "supsub":    r"$\displaystyle x_{i}^{2}$",
    "accent-hat": r"$\displaystyle \hat{x}$",
    "accent-bar": r"$\displaystyle \bar{x}$",
    "integral":  r"$\displaystyle \int_{0}^{\infty} f(x)\,dx$",
    "leftright": r"$\displaystyle \left(\frac{x}{y}\right)$",
    "frac-display": r"$\displaystyle \dfrac{1}{2}$",
}

def dump_tex_metrics(label: str, expr: str, tex_dir: str) -> dict:
    """Render TeX expression, extract glyph positions from PDF via PyMuPDF."""
    import fitz  # PyMuPDF

    # Write .tex file
    tex_file = os.path.join(tex_dir, f"{label}.tex")
    with open(tex_file, "w") as f:
        f.write(PREAMBLE + "\n" + expr + "\n" + POSTAMBLE)

    # Compile
    result = subprocess.run(
        ["/Library/TeX/texbin/lualatex",
         "-interaction=nonstopmode", "-halt-on-error",
         "-output-directory", tex_dir, tex_file],
        capture_output=True, text=True, timeout=30
    )

    pdf_file = os.path.join(tex_dir, f"{label}.pdf")
    if not os.path.exists(pdf_file):
        print(f"  TEX {label}: compile failed")
        print(f"  stderr: {result.stderr[-300:]}")
        return {"error": "compile_failed"}

    # Extract glyph positions from PDF
    doc = fitz.open(pdf_file)
    page = doc[0]

    items = []
    # Extract text with positions
    text_dict = page.get_text("dict")
    for block in text_dict.get("blocks", []):
        for line in block.get("lines", []):
            for span in line.get("spans", []):
                items.append({
                    "kind": "glyph",
                    "text": span["text"],
                    "x": round(span["bbox"][0], 2),
                    "y": round(span["bbox"][1], 2),
                    "w": round(span["bbox"][2] - span["bbox"][0], 2),
                    "h": round(span["bbox"][3] - span["bbox"][1], 2),
                    "font": span.get("font", ""),
                    "size": round(span.get("size", 0), 2),
                })

    # Also extract individual glyphs for more precision
    # Reset items for per-glyph approach instead of per-span
    items = []
    for block in text_dict.get("blocks", []):
        for line in block.get("lines", []):
            for span in line.get("spans", []):
                chars = span.get("chars", [])
                for ch in chars:
                    items.append({
                        "kind": "char",
                        "text": ch["c"],
                        "char": f"U+{ord(ch['c']):04X}",
                        "x": round(ch["bbox"][0], 2),
                        "y": round(ch["bbox"][1], 2),
                        "w": round(ch["bbox"][2] - ch["bbox"][0], 2),
                        "h": round(ch["bbox"][3] - ch["bbox"][1], 2),
                    })

    # Get page dimensions
    page_rect = page.rect
    metrics = {
        "label": label,
        "expression": expr,
        "page_width": round(page_rect.width, 2),
        "page_height": round(page_rect.height, 2),
        "items": items,
        "item_count": len(items),
    }

    doc.close()

    # Cleanup
    for ext in [".aux", ".log", ".pdf"]:
        f = os.path.join(tex_dir, f"{label}{ext}")
        if os.path.exists(f):
            os.remove(f)
    if os.path.exists(tex_file):
        os.remove(tex_file)

    return metrics


def dump_alpha_metrics(label: str, expr: str) -> dict:
    """Run AlphaEqt renderer with --dump-metrics flag, parse JSON output."""
    # AlphaEqt uses RenderCompare tool with metrics output
    # Write a small wrapper swift file
    swift_code = f'''
import AlphaEqt
import Foundation

let expr = {json.dumps(expr)}
let font = MathFont.xitsFont.mtfont(size: 50)
let lexer = Lexer(input: expr)
let tokens = lexer.tokenize()
let parser = LatexParser()
let nodes = parser.parse(tokens: tokens)
let ts = Typesetter(font: font, style: .display)
guard let display = ts.createDisplay(nodes) else {{ print("ERROR"); exit(1) }}

var items = [[String: Any]]()

func walk(_ d: MTDisplay, depth: Int) {{
    var pos = d.position
    var info: [String: Any] = [
        "kind": String(describing: type(of: d)),
        "depth": depth,
        "x": Double(pos.x),
        "y": Double(pos.y),
        "ascent": Double(d.ascent),
        "descent": Double(d.descent),
        "width": Double(d.width),
    ]
    if let ctLine = d as? MTCTLineDisplay, let atoms = ctLine.atoms {{
        info["text"] = atoms.compactMap {{ $0.text }}.joined()
    }}
    if let glyph = d as? MTGlyphDisplay {{
        info["glyph"] = glyph.glyph
        info["rawAscent"] = Double(glyph.rawAscent)
        info["rawDescent"] = Double(glyph.rawDescent)
        info["shiftDown"] = Double(glyph.shiftDown)
    }}
    items.append(info)

    if let frac = d as? MTFractionDisplay {{
        if let n = frac.numerator {{ walk(n, depth: depth + 1) }}
        if let de = frac.denominator {{ walk(de, depth: depth + 1) }}
    }} else if let sq = d as? MTSupSubDisplay {{
        if let b = sq.base {{ walk(b, depth: depth + 1) }}
        if let s = sq.superscript {{ walk(s, depth: depth + 1) }}
        if let s = sq.subscriptDisplay {{ walk(s, depth: depth + 1) }}
    }} else if let rad = d as? MTRadicalDisplay {{
        if let r = rad.radicand {{ walk(r, depth: depth + 1) }}
        if let deg = rad.degree {{ walk(deg, depth: depth + 1) }}
    }} else if let acc = d as? MTAccentDisplay {{
        if let a = acc.accent {{ walk(a, depth: depth + 1) }}
        if let ae = acc.accentee {{ walk(ae, depth: depth + 1) }}
    }} else if let list = d as? MTMathListDisplay {{
        for sub in list.subDisplays {{ walk(sub, depth: depth + 1) }}
    }} else if let cb = d as? MTColorboxDisplay {{
        if let inner = cb.inner {{ walk(inner, depth: depth + 1) }}
    }} else if let lim = d as? MTLargeOpLimitsDisplay {{
        if let n = lim.nucleus {{ walk(n, depth: depth + 1) }}
        if let u = lim.upperLimit {{ walk(u, depth: depth + 1) }}
        if let l = lim.lowerLimit {{ walk(l, depth: depth + 1) }}
    }} else if let cons = d as? MTGlyphConstructionDisplay {{
        info["glyphCount"] = cons.glyphs.count
    }}
}}

walk(display, depth: 0)
let result: [String: Any] = ["label": "{label}", "items": items]
let data = try! JSONSerialization.data(withJSONObject: result, options: .prettyPrinted)
print(String(data: data, encoding: .utf8)!)
'''

    tmp_file = "/tmp/alpha_dump.swift"
    with open(tmp_file, "w") as f:
        f.write(swift_code)

    result = subprocess.run(
        ["swift", tmp_file],
        capture_output=True, text=True, timeout=60,
        cwd="/Users/alpha/Desktop/swift/AlphaEqt"
    )

    if result.returncode != 0:
        return {"error": "swift_run_failed", "stderr": result.stderr[-500:]}

    try:
        metrics = json.loads(result.stdout)
    except json.JSONDecodeError as e:
        return {"error": "json_parse", "stdout": result.stdout[:500]}

    os.remove(tmp_file)
    return metrics


if __name__ == "__main__":
    tex_dir = "/tmp/tex_metrics"
    os.makedirs(tex_dir, exist_ok=True)

    comparison = {}

    for label, expr in EXPRESSIONS.items():
        print(f"\n=== {label} ===")

        # TeX metrics
        tex = dump_tex_metrics(label, expr, tex_dir)
        if "error" not in tex:
            print(f"  TEX: {tex['item_count']} chars, page={tex['page_width']:.1f}×{tex['page_height']:.1f} pt")
        else:
            print(f"  TEX: {tex['error']}")

        # AlphaEqt metrics
        alpha = dump_alpha_metrics(label, expr)
        if "error" not in alpha:
            print(f"  AEQ: {len(alpha['items'])} display nodes")
        else:
            print(f"  AEQ: {alpha['error']}")

        comparison[label] = {"tex": tex, "alpha": alpha}

        # Save individual JSONs
        out_dir = os.path.dirname(__file__)
        with open(os.path.join(out_dir, f"metrics_tex_{label}.json"), "w") as f:
            json.dump(tex, f, indent=2, default=str)
        with open(os.path.join(out_dir, f"metrics_alpha_{label}.json"), "w") as f:
            json.dump(alpha, f, indent=2)

    # Save combined comparison
    with open(os.path.join(os.path.dirname(__file__), "metrics_comparison.json"), "w") as f:
        json.dump(comparison, f, indent=2, default=str)

    print("\nDone — metrics saved to comparison_images/metrics_*.json")
