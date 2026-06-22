# -*- coding: utf-8 -*-
import subprocess

pairs = [
    ('accent-hat.png',     'tex_ref_accent-hat.png'),
    ('fraction.png',       'tex_ref_frac.png'),
    ('sqrt.png',           'tex_ref_sqrt.png'),
    ('integral.png',       'tex_ref_integral.png'),
    ('supsub.png',         'tex_ref_supsub.png'),
    ('matrix.png',         'tex_ref_matrix.png'),
    ('sum-display.png',    'tex_ref_sum-display.png'),
]

def get_info(path):
    r = subprocess.run(['sips', '-g', 'pixelWidth', '-g', 'pixelHeight',
                        '-g', 'dpiWidth', '-g', 'dpiHeight', path],
                       capture_output=True, text=True)
    lines = r.stdout.strip().split('\n')
    info = {}
    for line in lines:
        if ':' in line:
            k, v = line.split(':', 1)
            info[k.strip()] = v.strip()
    return info

for alpha, tex in pairs:
    ai = get_info(alpha)
    ti = get_info(tex)
    aw = ai.get('pixelWidth', '?')
    ah = ai.get('pixelHeight', '?')
    tw = ti.get('pixelWidth', '?')
    th = ti.get('pixelHeight', '?')
    adpi = ai.get('dpiWidth', '?')
    tdpi = ti.get('dpiWidth', '?')
    match = 'YES' if (aw == tw and ah == th) else 'NO'
    print(f'{alpha:<22} AlphaEqt: {aw:>4}x{ah:<4} @ {adpi} DPI | TeX: {tw:>4}x{th:<4} @ {tdpi} DPI | Match: {match}')
