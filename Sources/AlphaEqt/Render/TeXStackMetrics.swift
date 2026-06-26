//
//  TeXStackMetrics.swift
//  AlphaEqt
//
//  TeX / KaTeX font parameters (cmsy10 sigmas, xi values) for stacked math.
//  Values match KaTeX fontMetrics.ts — same source as MathJax uses via TeX rules.
//

import Foundation

/// TeXbook / KaTeX σ and ξ parameters, scaled by `fontSize`.
enum TeXStackMetrics {
    // σ8–σ12: fraction shifts (text / display style)
    static func num1(_ fs: CGFloat) -> CGFloat { 0.677 * fs }
    static func num2(_ fs: CGFloat) -> CGFloat { 0.394 * fs }
    static func num3(_ fs: CGFloat) -> CGFloat { 0.444 * fs }
    static func denom1(_ fs: CGFloat) -> CGFloat { 0.686 * fs }
    static func denom2(_ fs: CGFloat) -> CGFloat { 0.345 * fs }

    // ξ8: default rule thickness
    static func defaultRuleThickness(_ fs: CGFloat) -> CGFloat { 0.049 * fs }

    // σ20–σ21: minimum delimiter size for \binom delimiters
    static func delim1(_ fs: CGFloat) -> CGFloat { 2.39 * fs }
    static func delim2(_ fs: CGFloat) -> CGFloat { 1.01 * fs }

    // ξ9–ξ13: big-op limit spacing (\overset / \underset / overbrace labels)
    static func bigOpSpacing1(_ fs: CGFloat) -> CGFloat { 0.111 * fs }
    static func bigOpSpacing2(_ fs: CGFloat) -> CGFloat { 0.166 * fs }
    static func bigOpSpacing3(_ fs: CGFloat) -> CGFloat { 0.2 * fs }
    static func bigOpSpacing4(_ fs: CGFloat) -> CGFloat { 0.6 * fs }
    static func bigOpSpacing5(_ fs: CGFloat) -> CGFloat { 0.1 * fs }

    /// TeXbook Rule 15c clearance for rule-less stacks (\binom / \atop).
    static func atopClearance(displayStyle: Bool, fontSize: CGFloat) -> CGFloat {
        let rule = defaultRuleThickness(fontSize)
        return (displayStyle ? 7 : 3) * rule
    }

    /// MathJax v4 STIX2 trace: in-binom padding inside `\biggl`/`\biggr` (em).
    static func binomVerticalPad(displayStyle: Bool, fontSize: CGFloat) -> (top: CGFloat, bottom: CGFloat) {
        if displayStyle {
            return (0.168 * fontSize, 0.126 * fontSize)
        }
        return (0.08 * fontSize, 0.06 * fontSize)
    }

    /// Trim binom pads so the stack fits the MathJax delimiter cap (2.143em).
    static func binomPadsFittingCap(displayStyle: Bool,
                                    fontSize: CGFloat,
                                    numUp: CGFloat,
                                    numAscent: CGFloat,
                                    denDown: CGFloat,
                                    denDescent: CGFloat) -> (top: CGFloat, bottom: CGFloat) {
        var (top, bottom) = binomVerticalPad(displayStyle: displayStyle, fontSize: fontSize)
        guard displayStyle else { return (top, bottom) }
        let cap = binomDelimCap(fontSize)
        let core = numUp + numAscent + denDown + denDescent
        let total = top + core + bottom
        if total > cap, top + bottom > 0 {
            let trim = total - cap
            let padSum = top + bottom
            top = max(fontSize * 0.04, top - trim * (top / padSum))
            bottom = max(fontSize * 0.03, bottom - trim * (bottom / padSum))
        }
        return (top, bottom)
    }

    /// KaTeX genfrac Rule 15c for `\binom` (no axis nudge — TeX stacks on baseline).
    static func binomShifts(displayStyle: Bool,
                            fontSize: CGFloat,
                            numAscent: CGFloat,
                            numDescent: CGFloat,
                            denAscent: CGFloat,
                            denDescent: CGFloat) -> (numUp: CGFloat, denDown: CGFloat, hPad: CGFloat, padTop: CGFloat, padBottom: CGFloat) {
        let (numShift, denShift) = atopShifts(
            displayStyle: displayStyle, fontSize: fontSize,
            numAscent: numAscent, numDescent: numDescent,
            denAscent: denAscent, denDescent: denDescent)
        let pad = binomVerticalPad(displayStyle: displayStyle, fontSize: fontSize)
        return (numShift, denShift, fontSize * 0.1, pad.top, pad.bottom)
    }

    /// TeXbook Rule 15c: adjust num/den shifts for rule-less \atop (non-binom).
    static func atopShifts(displayStyle: Bool,
                             fontSize: CGFloat,
                             numAscent: CGFloat,
                             numDescent: CGFloat,
                             denAscent: CGFloat,
                             denDescent: CGFloat) -> (numUp: CGFloat, denDown: CGFloat) {
        let clearance = atopClearance(displayStyle: displayStyle, fontSize: fontSize)
        var numShift = displayStyle ? num1(fontSize) : num3(fontSize)
        var denShift = displayStyle ? denom1(fontSize) : denom2(fontSize)
        // KaTeX: (numShift - num.depth) - (den.height - denShift)
        let candidate = (numShift - numDescent) - (denAscent - denShift)
        if candidate < clearance {
            let delta = 0.5 * (clearance - candidate)
            numShift += delta
            denShift += delta
        }
        return (numShift, denShift)
    }

    /// KaTeX horizBrace.ts kerns (em); MathJax v4 STIX2 trace for `\overbrace{…}^{n}`.
    static func horizBraceBodyKern(_ fs: CGFloat) -> CGFloat { 0.1 * fs }
    static func horizBraceLabelKern(_ fs: CGFloat) -> CGFloat { 0.2 * fs }
    /// Pad above the script on `\overbrace{…}^{label}` (MathJax trace: 0.1em).
    static func horizBraceLabelPadTop(_ fs: CGFloat) -> CGFloat { 0.1 * fs }
    /// Gap from script bottom to brace top (MathJax trace ≈0.191em; KaTeX 0.2em).
    static func horizBraceLabelGap(_ fs: CGFloat) -> CGFloat { 0.1907 * fs }
    /// OT stretchy-brace bbox trim (0.55 KaTeX default; tuned to MJ brace top).
    static func horizBraceAscentTrim(_ fs: CGFloat) -> CGFloat { 0.70 }

    /// MathJax v4 STIX2: `\binom` stretchy-paren cap (~2.14em @ 30px).
    static func binomDelimCap(_ fs: CGFloat) -> CGFloat { 2.143 * fs }

    // MARK: - Extensible arrows (`\xrightarrow`, `\xleftarrow`, …)
    //
    // Layout follows AMS/KaTeX (`arrow.ts`): mover/munderover stack, scriptstyle labels,
    // stretchy operator on the math axis, OpenType MATH horizontal assembly.
    //
    // **TeX / AMS / KaTeX (principled):**
    // - `xArrowHBoxPad` — KaTeX `mpadded` width +0.6em (label box wider than text).
    // - `xArrowMinWidth` — KaTeX `minsize` 1.75em on stretchy operator.
    // - `xArrowMuKern` — amsmath.dtx 2μ (0.111em) between label and arrow body.
    // - Script labels — TeX `\scriptstyle`; arrow vertical center — `axisHeight`.
    //
    // **MathJax v4 STIX2 trace** (`comparison_images/trace_xarrow_metrics.mjs`):
    // - `xArrowLabelPadTop/Bottom`, `xArrowUnderPadTop/Bottom`, `xArrowAxisNudge`.
    //
    // **Empirical ink tuning (not TeXbook rules):** STIX stretchy-arrow ink does not match
    // MathJax CHTML box edges; these nudge the glyph relative to the label box.
    // Prefer removing them once assembly/ink metrics are axis-correct.
    // - `xArrowRightShiftX/Y` — `\xrightarrow` ink vs label.
    // - `xArrowLeftExtraWidth`, `xArrowLeftShiftX/Y` — `\xleftarrow` length and ink.

    /// amsmath.dtx 2μ kern between script label and arrow (KaTeX `arrow.ts`).
    static func xArrowMuKern(_ fs: CGFloat) -> CGFloat { 0.111 * fs }
    /// KaTeX `mpadded` +0.6em horizontal box (MathJax arrow W ≈ content + 0.6em).
    static func xArrowHBoxPad(_ fs: CGFloat) -> CGFloat { 0.6 * fs }
    /// KaTeX stretchy `minsize` for `\x…` arrows.
    static func xArrowMinWidth(_ fs: CGFloat) -> CGFloat { 1.75 * fs }
    /// Outer pad above script labels (MathJax `mjx-over` trace: 0.1em).
    static func xArrowLabelPadTop(_ fs: CGFloat) -> CGFloat { 0.1 * fs }
    static func xArrowLabelPadBottom(_ fs: CGFloat) -> CGFloat { 0.1 * fs }
    /// MathJax `mjx-under` padding-top on `\xleftarrow[below]{…}`.
    static func xArrowUnderPadTop(_ fs: CGFloat) -> CGFloat { 0.167 * fs }
    /// Pad below the under script (MathJax trace ≈0.197em).
    static func xArrowUnderPadBottom(_ fs: CGFloat) -> CGFloat { 0.197 * fs }
    /// Nudge stretchy arrow down for under-label stacks (MathJax trace ≈0.107em).
    static func xArrowAxisNudge(_ fs: CGFloat) -> CGFloat { 0.107 * fs }
    /// Empirical: `\xrightarrow` ink nudge right (STIX vs MathJax compare).
    static func xArrowRightShiftX(_ fs: CGFloat) -> CGFloat { 0.12 * fs }
    /// Empirical: `\xrightarrow` ink nudge up relative to label.
    static func xArrowRightShiftY(_ fs: CGFloat) -> CGFloat { 0.065 * fs }
    /// Empirical: `\xleftarrow` extra stretch width.
    static func xArrowLeftExtraWidth(_ fs: CGFloat) -> CGFloat { 0.15 * fs }
    /// Empirical: `\xleftarrow` ink nudge left (negative = left).
    static func xArrowLeftShiftX(_ fs: CGFloat) -> CGFloat { -0.04 * fs }
    /// Empirical: `\xleftarrow` ink nudge up relative to label.
    static func xArrowLeftShiftY(_ fs: CGFloat) -> CGFloat { 0.07 * fs }
}
