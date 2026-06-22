#!/usr/bin/env python3
"""Resize TeX reference PNGs to match AlphaEqt PNG dimensions."""
import os
import subprocess

mapping = {
    'fraction.png': 'tex_ref_frac.png',
    'nested-frac.png': 'tex_ref_nested-frac.png',
    'sqrt.png': 'tex_ref_sqrt.png',
    'sqrt-nested.png': 'tex_ref_sqrt-nested.png',
    'sup.png': 'tex_ref_sup.png',
    'sub.png': 'tex_ref_sub.png',
    'supsub.png': 'tex_ref_supsub.png',
    'sum-display.png': 'tex_ref_sum-display.png',
    'sum-inline.png': 'tex_ref_sum-inline.png',
    'integral.png': 'tex_ref_integral.png',
    'matrix.png': 'tex_ref_matrix.png',
    'leftright.png': 'tex_ref_leftright.png',
    'accent-hat.png': 'tex_ref_accent-hat.png',
    'accent-vec.png': 'tex_ref_accent-vec.png',
    'accent-bar.png': 'tex_ref_accent-bar.png',
    'accent-bar-multi.png': 'tex_ref_accent-bar-multi.png',
    'accent-widehat.png': 'tex_ref_accent-widehat.png',
    'accent-tilde.png': 'tex_ref_accent-tilde.png',
    'accent-dot.png': 'tex_ref_accent-dot.png',
    'accent-ddot.png': 'tex_ref_accent-ddot.png',
    'color.png': 'tex_ref_color.png',
    'colorbox.png': 'tex_ref_colorbox.png',
    'frac-display.png': 'tex_ref_frac-display.png',
    'frac-text.png': 'tex_ref_frac-text.png',
    'sqrt-3.png': 'tex_ref_sqrt-3.png',
    'greek.png': 'tex_ref_greek.png',
    'sin-cos.png': 'tex_ref_sin-cos.png',
    'sum-limits.png': 'tex_ref_sum-limits.png',
}

for alpha_img, tex_img in mapping.items():
    if not os.path.exists(alpha_img):
        print(f'SKIP missing: {alpha_img}')
        continue
    if not os.path.exists(tex_img):
        print(f'SKIP missing: {tex_img}')
        continue

    r = subprocess.run(['sips', '-g', 'pixelWidth', '-g', 'pixelHeight', alpha_img],
                       capture_output=True, text=True)
    lines = r.stdout.strip().split('\n')
    w = lines[1].split(':')[1].strip()
    h = lines[2].split(':')[1].strip()

    subprocess.run(['sips', '-z', h, w, tex_img],
                   capture_output=True)
    print(f'{alpha_img} ({w}x{h}) -> {tex_img}')

print('Done.')
