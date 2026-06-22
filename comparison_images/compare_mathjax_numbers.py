#!/usr/bin/env python3
"""Numeric comparison: AlphaEqt (pt) vs MathJax CHTML (px, via getBoundingClientRect)."""
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

TOLERANCE = 10  # percent

mj_all = json.load(open(os.path.join(COMPARE_DIR, 'mathjax_all_metrics.json')))

print("=" * 70)
print(" AlphaEqt (pt) vs MathJax v4 STIX2 (px) — Numeric Comparison")
print(f" Tolerance: {TOLERANCE}%")
print("=" * 70)

yes = no = warn = 0
for label in LABELS:
    try:
        am = json.load(open(os.path.join(COMPARE_DIR, f'metrics_alpha_{label}.json')))
        mjm = mj_all.get(label, {})
    except:
        continue

    mj_items = mjm.get('items', [])
    a_items = am.get('items', [])
    if not mj_items or not a_items:
        continue

    # Use mjx-math (depth 1, actual content) instead of mjx-container (depth 0, includes strut line-height)
    mj_content = mj_items[1] if len(mj_items) > 1 and mj_items[1].get('kind') == 'mjx-math' else mj_items[0]
    a_root = a_items[0]
    mj_w = mj_content.get('w', 0)
    mj_h = mj_content.get('h', 0)
    a_w = a_root.get('width', 0)
    a_h = a_root.get('ascent', 0) + a_root.get('descent', 0)

    h_diff = abs(mj_h - a_h) / max(mj_h, a_h) * 100 if mj_h and a_h else 100
    w_diff = abs(mj_w - a_w) / max(mj_w, a_w) * 100 if mj_w and a_w else 100

    status = "OK" if h_diff <= TOLERANCE else ("WARN" if h_diff <= 20 else "FAIL")
    if status == "OK": yes += 1
    elif status == "FAIL": no += 1
    else: warn += 1

    # Find best glyph match
    mj_texts = [i for i in mj_items if i.get('text')]
    a_texts = [i for i in a_items if i.get('text')]
    best_glyph = ""
    best_glyph_diff = 0
    for mj_t in mj_texts:
        text = mj_t['text'].strip()
        a_match = next((a for a in a_texts if a.get('text','').strip() == text), None)
        if a_match:
            mj_th = mj_t.get('h', 0)
            a_th = a_match.get('ascent', 0) + a_match.get('descent', 0)
            if mj_th and a_th:
                d = abs(mj_th - a_th) / max(mj_th, a_th) * 100
                if d > best_glyph_diff:
                    best_glyph_diff = d
                    best_glyph = text

    print(f"  {label:<22} MJ {mj_w:>5.1f}x{mj_h:>5.1f}px  AE {a_w:>5.1f}x{a_h:>5.1f}pt  h_d={h_diff:>5.1f}% w_d={w_diff:>5.1f}%  [{status}]  glyph='{best_glyph}' g_d={best_glyph_diff:.1f}%")

print(f"\n  OK: {yes}  WARN: {warn}  FAIL: {no}")
