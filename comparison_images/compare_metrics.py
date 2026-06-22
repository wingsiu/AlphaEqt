#!/usr/bin/env python3
"""Run both metric dumpers and produce a side-by-side comparison for all 28 expressions."""
import os, subprocess, json, sys

COMPARE_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(COMPARE_DIR)

CASES = [
    ("fraction",        r"\frac{x}{y}"),
    ("nested-frac",     r"\frac{\frac{a}{b}}{\frac{c}{d}}"),
    ("sqrt",            r"\sqrt{x+1}"),
    ("sqrt-nested",     r"\sqrt{\frac{x}{y}}"),
    ("sup",             r"x^{2}"),
    ("sub",             r"x_{1}"),
    ("supsub",          r"x_{i}^{2}"),
    ("sum-display",     r"\displaystyle\sum_{i=0}^n i^2"),
    ("sum-inline",      r"\textstyle\sum_{i=0}^n i^2"),
    ("integral",        r"\int_{0}^{\infty} f(x)\,dx"),
    ("matrix",          r"\begin{pmatrix} a & b \\ c & d \end{pmatrix}"),
    ("leftright",       r"\left(\frac{x}{y}\right)"),
    ("accent-hat",      r"\hat{x}"),
    ("accent-vec",      r"\vec{x}"),
    ("accent-bar",      r"\bar{x}"),
    ("accent-bar-multi", r"\bar{ab}"),
    ("accent-widehat",  r"\widehat{AB}"),
    ("accent-tilde",    r"\tilde{x}"),
    ("accent-dot",      r"\dot{x}"),
    ("accent-ddot",     r"\ddot{x}"),
    ("color",           r"\textcolor{red}{x}"),
    ("colorbox",        r"\colorbox{yellow}{x+y}"),
    ("frac-display",    r"\dfrac{1}{2}"),
    ("frac-text",       r"\tfrac{1}{2}"),
    ("sqrt-3",          r"\sqrt[3]{x}"),
    ("greek",           r"\alpha\beta\gamma\omega"),
    ("sin-cos",         r"\sin^{2}\theta + \cos^{2}\theta"),
    ("sum-limits",      r"\displaystyle\sum_{i=0}^\infty \frac{1}{i}"),
]

def gen_katex_metrics(label, latex):
    """Generate KaTeX metrics JSON via node."""
    expr_file = "/tmp/katex_expr.txt"
    with open(expr_file, "w") as f:
        f.write(latex + "\n")
    result = subprocess.run(
        ["node", os.path.join(COMPARE_DIR, "dump_katex_metrics.js"), expr_file],
        capture_output=True, text=True, timeout=15,
        cwd=COMPARE_DIR
    )
    if result.returncode != 0:
        return {"error": f"node failed: {result.stderr[-200:]}"}
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError:
        return {"error": f"json parse: {result.stdout[:200]}"}

def gen_alpha_metrics(label, latex):
    """Generate AlphaEqt metrics JSON via swift."""
    result = subprocess.run(
        ["swift", "run", "AlphaMetricsDumper", label, latex],
        capture_output=True, text=True, timeout=60,
        cwd=os.path.join(PROJECT_DIR, "Tools", "AlphaMetricsDumper")
    )
    # Extract JSON from between lines containing '{' and '}'
    stdout = result.stdout + result.stderr
    # Find first '{' and last '}'
    start = stdout.find('{')
    end = stdout.rfind('}')
    if start < 0 or end < start:
        return {"error": f"no json: {stdout[-300:]}"}
    try:
        return json.loads(stdout[start:end+1])
    except json.JSONDecodeError:
        return {"error": f"bad json: {stdout[start:start+200]}"}

def build_comparison(label, alpha, katex):
    """Build per-expression comparison text."""
    lines = []
    lines.append(f"\n{'='*60}")
    lines.append(f" {label}")
    lines.append(f"{'='*60}")

    # AlphaEqt tree
    if "items" in alpha:
        lines.append(f"\nAlphaEqt ({alpha['itemCount']} nodes):")
        lines.append(f"  {'Kind':<22} {'x':>6} {'y':>6} {'a':>6} {'d':>6} {'w':>6}  Text")
        for n in alpha["items"]:
            indent = "  " * n["depth"]
            kind = n["kind"].replace("MT","").replace("Display","")
            text = n.get("text", "")
            lines.append(f"  {indent}{kind:<22} {n['x']:>5.1f} {n['y']:>5.1f} {n['ascent']:>5.1f} {n['descent']:>5.1f} {n['width']:>5.1f}  {text}")
    else:
        lines.append(f"\nAlphaEqt: {alpha.get('error','?')}")

    # KaTeX tree
    if "parseTree" in katex:
        lines.append(f"\nKaTeX ({katex.get('parseTreeCount',0)} parse nodes, {katex.get('htmlSpanCount',0)} HTML spans):")
        lines.append(f"  Parse tree:")
        for n in katex.get("parseTree", []):
            indent = "  " * n["depth"]
            text = n.get("text", "")
            style = f" [{n['style']}]" if n.get("style") else ""
            lines.append(f"  {indent}{n['kind']:<20} {text}{style}")

        if "htmlSpans" in katex:
            lines.append(f"\n  HTML spans (positioned):")
            for s in katex["htmlSpans"][:8]:
                h = s.get("heightEm", "?")
                w = s.get("widthEm", "?")
                lines.append(f"    {s['classes']:<30} h={h} w={w} \"{s['text']}\"")
    else:
        lines.append(f"\nKaTeX: {katex.get('error','?')}")

    return "\n".join(lines)


if __name__ == "__main__":
    print("Generating metrics for all 28 expressions...")
    all_comparisons = []
    for label, latex in CASES:
        print(f"  {label}...", end=" ", flush=True)
        katex = gen_katex_metrics(label, latex)
        alpha = gen_alpha_metrics(label, latex)

        # Save individual JSONs
        with open(os.path.join(COMPARE_DIR, f"metrics_katex_{label}.json"), "w") as f:
            json.dump(katex, f, indent=2)
        with open(os.path.join(COMPARE_DIR, f"metrics_alpha_{label}.json"), "w") as f:
            json.dump(alpha, f, indent=2)

        comp = build_comparison(label, alpha, katex)
        all_comparisons.append(comp)
        print("done")

    # Save full comparison
    report = "\n".join(all_comparisons)
    report_path = os.path.join(COMPARE_DIR, "metrics_report.txt")
    with open(report_path, "w") as f:
        f.write(report)
    print(f"\nFull report saved to {report_path}")
    print(report[:2000])
