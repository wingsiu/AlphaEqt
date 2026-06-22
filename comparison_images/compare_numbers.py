#!/usr/bin/env python3
"""Numeric metric comparison between AlphaEqt (pt) and KaTeX (em → pt at 50px)."""
import json, os

COMPARE_DIR = os.path.dirname(os.path.abspath(__file__))
LABELS = [
    "fraction","nested-frac","sqrt","sqrt-nested","sup","sub","supsub",
    "sum-display","sum-inline","integral","matrix","leftright",
    "accent-hat","accent-vec","accent-bar","accent-bar-multi",
    "accent-widehat","accent-tilde","accent-dot","accent-ddot",
    "color","colorbox","frac-display","frac-text","sqrt-3",
    "greek","sin-cos","sum-limits",
]

FONT_SIZE_PX = 50  # KaTeX font-size: 50px
TOLERANCE_PCT = 15  # allow 15% difference due to font differences

def compare_value(a_val, k_val_em, metric_name, tolerance_pct=TOLERANCE_PCT):
    """Compare AlphaEqt pt value to KaTeX em value converted to pt."""
    k_val_pt = k_val_em * FONT_SIZE_PX
    if a_val == 0 and k_val_pt == 0:
        return "✅", 0
    if a_val == 0 or k_val_pt == 0:
        return "❌", 100
    diff_pct = abs(a_val - k_val_pt) / max(abs(a_val), abs(k_val_pt)) * 100
    if diff_pct <= tolerance_pct:
        return "✅", round(diff_pct, 1)
    elif diff_pct <= 2 * tolerance_pct:
        return "⚠️", round(diff_pct, 1)
    else:
        return "❌", round(diff_pct, 1)

def compare_expression(label):
    """Compare AlphaEqt and KaTeX metrics for one expression."""
    alpha_path = os.path.join(COMPARE_DIR, f"metrics_alpha_{label}.json")
    katex_path = os.path.join(COMPARE_DIR, f"metrics_katex_{label}.json")

    try:
        alpha = json.load(open(alpha_path))
        katex = json.load(open(katex_path))
    except FileNotFoundError:
        return None

    lines = [f"\n{'='*60}", f" {label}", f"{'='*60}"]

    if "error" in alpha or "error" in katex:
        lines.append("  ERROR loading metrics")
        return "\n".join(lines)

    # AlphaEqt: extract total dimensions from root MathList
    a_items = alpha.get("items", [])
    if not a_items:
        lines.append("  No AlphaEqt items")
        return "\n".join(lines)

    a_root = a_items[0]
    a_total_w = a_root["width"]
    a_total_a = a_root["ascent"]
    a_total_d = a_root["descent"]
    a_total_h = a_total_a + a_total_d

    # KaTeX: extract total height from HTML
    k_total_h_em = katex.get("totalHeightEm")
    if k_total_h_em is None:
        # Get from first strut
        for s in katex.get("htmlSpans", []):
            if "strut" in s.get("classes", "") and s.get("heightEm"):
                k_total_h_em = s["heightEm"]
                break

    lines.append(f"\n  {'':20} {'AlphaEqt':>10} {'KaTeX':>10} {'KaTeX(pt)':>10} {'Diff%':>8} {'Status'}")
    lines.append(f"  {'-'*66}")

    # Compare total height
    if k_total_h_em:
        status, diff = compare_value(a_total_h, k_total_h_em, "totalH")
        k_h_pt = k_total_h_em * FONT_SIZE_PX
        lines.append(f"  {'total height':20} {a_total_h:>8.1f}pt {k_total_h_em:>8.3f}em {k_h_pt:>8.1f}pt {diff:>6.1f}%  {status}")

    # Compare total width
    k_widths = [s.get("widthEm", 0) for s in katex.get("htmlSpans", []) if s.get("widthEm") and s.get("widthEm", 0) > 0]
    if k_widths and a_total_w:
        k_max_w = max(k_widths)
        status, diff = compare_value(a_total_w, k_max_w, "totalW")
        k_w_pt = k_max_w * FONT_SIZE_PX
        lines.append(f"  {'total width':20} {a_total_w:>8.1f}pt {k_max_w:>8.3f}em {k_w_pt:>8.1f}pt {diff:>6.1f}%  {status}")

    # Compare individual glyph/atom metrics for simple cases
    a_atoms = [n for n in a_items if n.get("text")]
    k_atoms = [n for n in katex.get("parseTree", []) if n.get("text")]
    k_spans_with_text = [s for s in katex.get("htmlSpans", []) if s.get("text") and s.get("text").strip()]

    if len(a_atoms) <= 5 and len(k_spans_with_text) <= 5:
        # Compare span heights
        for i, k_span in enumerate(k_spans_with_text):
            if k_span.get("heightEm"):
                k_h = k_span["heightEm"]
                # Find closest AlphaEqt atom
                if i < len(a_atoms):
                    a_h = a_atoms[i]["ascent"] + a_atoms[i]["descent"]
                    status, diff = compare_value(a_h, k_h, "atomH")
                    a_text = a_atoms[i].get("text", "")
                    k_text = k_span.get("text", "")
                    k_h_pt = k_h * FONT_SIZE_PX
                    lines.append(f"  {'atom height':20} {a_h:>8.1f}pt {k_h:>8.3f}em {k_h_pt:>8.1f}pt {diff:>6.1f}%  {status} \"{a_text}\" vs \"{k_text}\"")

    # Node count comparison
    lines.append(f"\n  Nodes: AlphaEqt={a_root.get('itemCount', len(a_items))}, KaTeX parse={katex.get('parseTreeCount',0)}, spans={katex.get('htmlSpanCount',0)}")

    return "\n".join(lines)

# Main
print("Numeric Metric Comparison — AlphaEqt (pt) vs KaTeX (em→pt")
print(f"Font size: {FONT_SIZE_PX}px, Tolerance: {TOLERANCE_PCT}%")
for label in LABELS:
    result = compare_expression(label)
    if result:
        print(result)
