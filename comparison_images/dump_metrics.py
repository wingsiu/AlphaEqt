#!/usr/bin/env python3
"""Run both LaTeX and AlphaEqt metric dumpers and compare results."""
import os, subprocess, json, sys

EXPRESSIONS = {
    "frac":       r"$\displaystyle \frac{x}{y}$",
    "sqrt":       r"$\displaystyle \sqrt{x+1}$",
    "sup":        r"$\displaystyle x^{2}$",
    "accent-hat": r"$\displaystyle \hat{x}$",
    "integral":   r"$\displaystyle \int_{0}^{\infty} f(x)\,dx$",
}

def dump_tex_metrics(label, expr):
    """Run LuaLaTeX metrics dumper, return parsed JSON."""
    # Write expression file
    tex_expr_path = os.path.join(os.path.dirname(__file__), "tex_expr.tex")
    with open(tex_expr_path, "w") as f:
        f.write(expr + "\n")

    tex_file = os.path.join(os.path.dirname(__file__), "dump_tex_metrics.tex")
    result = subprocess.run(
        ["/Library/TeX/texbin/lualatex", "-interaction=nonstopmode", "-halt-on-error",
         "-output-directory=/tmp/tex_metrics", tex_file],
        capture_output=True, text=True, timeout=30,
        cwd=os.path.dirname(__file__)
    )

    # Extract JSON from between markers
    stdout = result.stdout + result.stderr
    begin = stdout.find("METRICS_JSON_BEGIN")
    end = stdout.find("METRICS_JSON_END")
    if begin < 0 or end < 0:
        print(f"  TEX {label}: no metrics output")
        print(f"  STDERR: {result.stderr[-300:]}")
        return None
    json_str = stdout[begin + 19:end].strip()

    try:
        metrics = json.loads(json_str)
    except json.JSONDecodeError:
        print(f"  TEX {label}: JSON parse error")
        print(f"  RAW: {json_str[:200]}")
        return None
    return metrics

def dump_alpha_metrics(label, expr):
    """Run AlphaEqt metrics dumper, return parsed JSON."""
    # Build and run the AlphaEqt dumper via swift
    swift_code = f'''
import AlphaEqt
import Foundation

let font = MathFont.xitsFont.mtfont(size: 50)
let lexer = Lexer(input: "{expr.replac("\\", "\\\\\\\\").replace("\"", "\\\"")}")
let tokens = lexer.tokenize()
let parser = LatexParser()
let nodes = parser.parse(tokens: tokens)
let ts = Typesetter(font: font, style: .display)
guard let display = ts.createDisplay(nodes) else {{ exit(1) }}

func dumpMetrics(_ d: MTDisplay, indent: Int = 0) -> [String: Any] {{
    var info: [String: Any] = [
        "kind": String(describing: type(of: d)),
        "x": Double(d.position.x),
        "y": Double(d.position.y),
        "ascent": Double(d.ascent),
        "descent": Double(d.descent),
        "width": Double(d.width),
    ]
    // Recurse into children for known display types
    return info
}}

let root = dumpMetrics(display)
let jsonData = try JSONSerialization.data(withJSONObject: root, options: .prettyPrinted))
print(String(data: jsonData, encoding: .utf8)!)
'''
    # Write temp swift file and run
    tmp_dir = "/tmp/alpha_metrics"
    os.makedirs(tmp_dir, exist_ok=True)
    tmp_file = os.path.join(tmp_dir, f"dump_{label}.swift")
    with open(tmp_file, "w") as f:
        f.write(swift_code)

    # This approach is too complex inline. Let me create a proper tool instead.
    print(f"  AlphaEqt metric dumper: use Tools/RenderCompare/main.swift with --dump-metrics flag")
    return None


if __name__ == "__main__":
    os.makedirs("/tmp/tex_metrics", exist_ok=True)
    for label, expr in EXPRESSIONS.items():
        print(f"\n=== {label} ===")
        tex = dump_tex_metrics(label, expr)
        if tex:
            print(f"  TEX items: {len(tex.get('items', []))}")
            print(f"  TEX bounds: w={tex.get('total_width',0):.1f} h={tex.get('total_height',0):.1f} d={tex.get('total_depth',0):.1f}")
