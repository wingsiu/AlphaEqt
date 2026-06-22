#!/usr/bin/env python3
"""Analyze AlphaEqt vs KaTeX metrics report and generate a match summary."""
import os, json

REPORT_PATH = os.path.join(os.path.dirname(__file__), "metrics_report.txt")

# Manual analysis based on the full report:
results = {
    # Structure match, metrics differ due to font
    "fraction":         ("✅ MATCH",    "genfrac ↔ Fraction, numerator/denominator correct"),
    "nested-frac":      ("✅ MATCH",    "Nested genfrac ↔ nested Fraction, all 4 atoms correct"),
    "sqrt":             ("✅ MATCH",    "sqrt ↔ Radical, radicand x+1 correct"),
    "sqrt-nested":      ("✅ MATCH",    "sqrt(frac) ↔ Radical(Fraction), nested correctly"),
    "sup":              ("✅ MATCH",    "supsub ↔ SupSub, base x+superscript 2 correct"),
    "sub":              ("✅ MATCH",    "supsub ↔ SupSub, base x+subscript 1 correct"),
    "supsub":           ("✅ MATCH",    "supsub ↔ SupSub, x + i(↓) + 2(↑) correct"),
    "sum-display":      ("✅ MATCH",    "op+limits ↔ LargeOpLimits, sum with below/above correct"),
    "sum-inline":       ("❌ BROKEN",   "AlphaEqt renders \\textstyle as literal text, not inline sum"),
    "integral":         ("⚠️ CHECK",    "Integral + limits + f(x)dx — need visual verification"),
    "matrix":           ("✅ MATCH",    "array ↔ Matrix, 2×2 pmatrix cells correct"),
    "leftright":        ("⚠️ CHECK",    "left(frac)right ↔ LeftRight delimiters — need verification"),
    "accent-hat":       ("✅ MATCH",    "accent(hat) ↔ AccentDisplay, x + hat correct"),
    "accent-vec":       ("✅ MATCH",    "accent(vec) ↔ AccentDisplay, x + arrow correct"),
    "accent-bar":       ("✅ MATCH",    "accent(bar) ↔ AccentDisplay, x + overbar correct"),
    "accent-bar-multi": ("✅ MATCH",    "accent(bar) multi-char ↔ AccentDisplay ab + bar correct"),
    "accent-widehat":   ("✅ MATCH",    "accent(widehat) wide ↔ AccentDisplay AB + widehat"),
    "accent-tilde":     ("✅ MATCH",    "accent(tilde) ↔ AccentDisplay correct"),
    "accent-dot":       ("✅ MATCH",    "accent(dot) ↔ AccentDisplay correct"),
    "accent-ddot":      ("✅ MATCH",    "accent(ddot) ↔ AccentDisplay correct"),
    "color":            ("✅ MATCH",    "color ↔ ColorDisplay, red x correct"),
    "colorbox":         ("✅ MATCH",    "colorbox ↔ ColorboxDisplay, yellow bg x+y correct"),
    "frac-display":     ("❌ BROKEN",   "AlphaEqt renders \\dfrac as literal text, not display fraction"),
    "frac-text":        ("❌ BROKEN",   "AlphaEqt renders \\tfrac as literal text, not text fraction"),
    "sqrt-3":           ("✅ MATCH",    "sqrt[3]{x} ↔ Radical with degree 3 correct"),
    "greek":            ("✅ MATCH",    "αβγω all rendered as individual mathord atoms"),
    "sin-cos":          ("✅ MATCH",    "sin²θ+cos²θ — limits, supsub, atoms all correct"),
    "sum-limits":       ("✅ MATCH",    "sum with ∞ limit + frac — LargeOpLimits + Fraction correct"),
}

print("=" * 70)
print(" AlphaEqt vs KaTeX — Match Summary")
print("=" * 70)
print()

yes = no = check = 0
for label in [
    "fraction","nested-frac","sqrt","sqrt-nested","sup","sub","supsub",
    "sum-display","sum-inline","integral","matrix","leftright",
    "accent-hat","accent-vec","accent-bar","accent-bar-multi",
    "accent-widehat","accent-tilde","accent-dot","accent-ddot",
    "color","colorbox","frac-display","frac-text","sqrt-3",
    "greek","sin-cos","sum-limits",
]:
    status, note = results.get(label, ("?", ""))
    if status.startswith("✅"): yes += 1
    elif status.startswith("❌"): no += 1
    else: check += 1
    print(f"  {status:<20} {label:<22} {note}")

print()
print(f"  ✅ {yes} MATCH    ❌ {no} BROKEN    ⚠️ {check} CHECK")
print()

print("---")
print("KNOWN BUGS:")
print("  1. \\textstyle, \\displaystyle, \\dfrac, \\tfrac are rendered as literal")
print("     CTLine text instead of changing math style. These are in Sizing.swift")
print("     handler — the sizing command text passes through to CTLine.")
print()
print("  2. '\\dfrac' and '\\tfrac' need style-aware fraction rendering")
print("     (same as bug #1 — sizing is not applied)")
print()
print("---")
print("FONT DIFFERENCE:")
print("  AlphaEqt uses Latin Modern Math OTF (Computer Modern based)")
print("  KaTeX uses KaTeX_Main + KaTeX_AMS (Computer Modern clone)")
print("  → Metric values differ (expected), structure should match")
