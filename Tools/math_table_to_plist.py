#!/usr/bin/env python3
"""Dump OpenType MATH table to SwiftMath/iosMath plist format (version 1.3).

Based on iosMath / mathView math_table_to_plist.py — includes h_assembly
(which the stock SwiftMath script omits).
"""
import plistlib
import sys
from fontTools.ttLib import TTFont


def usage(code):
    print("Usage: math_table_to_plist.py <font.otf> <output.plist>")
    sys.exit(code)


def get_constants(math_table):
    constants = math_table.MathConstants
    if constants is None:
        raise RuntimeError("Cannot find MathConstants in MATH table")

    int_consts = [
        "ScriptPercentScaleDown",
        "ScriptScriptPercentScaleDown",
        "DelimitedSubFormulaMinHeight",
        "DisplayOperatorMinHeight",
        "RadicalDegreeBottomRaisePercent",
    ]
    consts = {c: getattr(constants, c) for c in int_consts}

    record_consts = [
        "MathLeading", "AxisHeight", "AccentBaseHeight", "FlattenedAccentBaseHeight",
        "SubscriptShiftDown", "SubscriptTopMax", "SubscriptBaselineDropMin",
        "SuperscriptShiftUp", "SuperscriptShiftUpCramped", "SuperscriptBottomMin",
        "SuperscriptBaselineDropMax", "SubSuperscriptGapMin",
        "SuperscriptBottomMaxWithSubscript", "SpaceAfterScript",
        "UpperLimitGapMin", "UpperLimitBaselineRiseMin",
        "LowerLimitGapMin", "LowerLimitBaselineDropMin",
        "StackTopShiftUp", "StackTopDisplayStyleShiftUp",
        "StackBottomShiftDown", "StackBottomDisplayStyleShiftDown",
        "StackGapMin", "StackDisplayStyleGapMin",
        "StretchStackTopShiftUp", "StretchStackBottomShiftDown",
        "StretchStackGapAboveMin", "StretchStackGapBelowMin",
        "FractionNumeratorShiftUp", "FractionNumeratorDisplayStyleShiftUp",
        "FractionDenominatorShiftDown", "FractionDenominatorDisplayStyleShiftDown",
        "FractionNumeratorGapMin", "FractionNumDisplayStyleGapMin",
        "FractionRuleThickness", "FractionDenominatorGapMin",
        "FractionDenomDisplayStyleGapMin",
        "SkewedFractionHorizontalGap", "SkewedFractionVerticalGap",
        "OverbarVerticalGap", "OverbarRuleThickness", "OverbarExtraAscender",
        "UnderbarVerticalGap", "UnderbarRuleThickness", "UnderbarExtraDescender",
        "RadicalVerticalGap", "RadicalDisplayStyleVerticalGap",
        "RadicalRuleThickness", "RadicalExtraAscender",
        "RadicalKernBeforeDegree", "RadicalKernAfterDegree",
    ]
    consts.update({c: getattr(constants, c).Value for c in record_consts})

    variants = math_table.MathVariants
    consts["MinConnectorOverlap"] = variants.MinConnectorOverlap
    return consts


def get_italic_correction(math_table):
    glyph_info = math_table.MathGlyphInfo
    italic = glyph_info.MathItalicsCorrectionInfo
    glyphs = italic.Coverage.glyphs
    records = italic.ItalicsCorrection
    italic_dict = {}
    for name, record in zip(glyphs, records):
        italic_dict[name] = record.Value
    return italic_dict


def get_accent_attachments(math_table):
    glyph_info = math_table.MathGlyphInfo
    attach = glyph_info.MathTopAccentAttachment
    glyphs = attach.TopAccentCoverage.glyphs
    records = attach.TopAccentAttachment
    attach_dict = {}
    for name, record in zip(glyphs, records):
        attach_dict[name] = record.Value
    return attach_dict


def get_v_variants(math_table):
    variants = math_table.MathVariants
    vglyphs = variants.VertGlyphCoverage.glyphs
    vconstruction = variants.VertGlyphConstruction
    variant_dict = {}
    for name, record in zip(vglyphs, vconstruction):
        if record.MathGlyphVariantRecord:
            variant_dict[name] = [x.VariantGlyph for x in record.MathGlyphVariantRecord]
    return variant_dict


def get_h_variants(math_table):
    variants = math_table.MathVariants
    hglyphs = variants.HorizGlyphCoverage.glyphs
    hconstruction = variants.HorizGlyphConstruction
    variant_dict = {}
    for name, record in zip(hglyphs, hconstruction):
        if record.MathGlyphVariantRecord:
            variant_dict[name] = [x.VariantGlyph for x in record.MathGlyphVariantRecord]
    return variant_dict


def part_dict(part):
    return {
        "glyph": part.glyph,
        "startConnector": part.StartConnectorLength,
        "endConnector": part.EndConnectorLength,
        "advance": part.FullAdvance,
        "extender": bool(part.PartFlags & 0x0001),
    }


def get_v_assembly(math_table):
    variants = math_table.MathVariants
    vglyphs = variants.VertGlyphCoverage.glyphs
    vconstruction = variants.VertGlyphConstruction
    assembly_dict = {}
    for name, record in zip(vglyphs, vconstruction):
        assembly = record.GlyphAssembly
        if assembly is not None:
            parts = [part_dict(part) for part in assembly.PartRecords]
            assembly_dict[name] = {
                "italic": assembly.ItalicsCorrection.Value,
                "parts": parts,
            }
    return assembly_dict


def get_h_assembly(math_table):
    variants = math_table.MathVariants
    hglyphs = variants.HorizGlyphCoverage.glyphs
    hconstruction = variants.HorizGlyphConstruction
    assembly_dict = {}
    for name, record in zip(hglyphs, hconstruction):
        assembly = record.GlyphAssembly
        if assembly is not None:
            parts = [part_dict(part) for part in assembly.PartRecords]
            assembly_dict[name] = {
                "italic": assembly.ItalicsCorrection.Value,
                "parts": parts,
            }
    return assembly_dict


def process_font(font_file, out_file):
    font = TTFont(font_file)
    math_table = font["MATH"].table
    pl = {
        "version": "1.3",
        "constants": get_constants(math_table),
        "v_variants": get_v_variants(math_table),
        "h_variants": get_h_variants(math_table),
        "italic": get_italic_correction(math_table),
        "accents": get_accent_attachments(math_table),
        "v_assembly": get_v_assembly(math_table),
        "h_assembly": get_h_assembly(math_table),
    }
    with open(out_file, "wb") as ofile:
        plistlib.dump(pl, ofile)


def main():
    if len(sys.argv) != 3:
        usage(1)
    process_font(sys.argv[1], sys.argv[2])


if __name__ == "__main__":
    main()
