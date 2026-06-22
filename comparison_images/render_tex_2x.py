#!/usr/bin/env python3
"""Render TeX PDFs to PNG at native 1x size with red debug boxes around entire expression."""
import os, subprocess

PREAMBLE = r'''\documentclass{article}
\usepackage{fontspec}
\usepackage{unicode-math}
\usepackage{xcolor}
\usepackage[active,tightpage]{preview}
\usepackage[margin=0pt]{geometry}
\setmainfont{xits-math-comparison.otf}[Path=/Users/alpha/Desktop/swift/AlphaEqt/comparison_images/]
\setmathfont{xits-math-comparison.otf}[Path=/Users/alpha/Desktop/swift/AlphaEqt/comparison_images/]
\pagestyle{empty}
\setlength{\fboxsep}{0pt}
\setlength{\fboxrule}{1pt}
\begin{document}
\fontsize{50}{60}\selectfont
\begin{preview}
'''

POSTAMBLE = r'''
\end{preview}
\end{document}
'''

expressions = {
    'tex_ref_frac':               r'$\displaystyle \frac{x}{y}$',
    'tex_ref_nested-frac':        r'$\displaystyle \frac{\frac{a}{b}}{\frac{c}{d}}$',
    'tex_ref_sqrt':               r'$\displaystyle \sqrt{x+1}$',
    'tex_ref_sqrt-nested':        r'$\displaystyle \sqrt{\frac{x}{y}}$',
    'tex_ref_sup':                r'$\displaystyle x^{2}$',
    'tex_ref_sub':                r'$\displaystyle x_{1}$',
    'tex_ref_supsub':             r'$\displaystyle x_{i}^{2}$',
    'tex_ref_sum-display':        r'$\displaystyle \sum_{i=0}^{n} i^{2}$',
    'tex_ref_sum-inline':         r'$\textstyle \sum_{i=0}^{n} i^{2}$',
    'tex_ref_integral':           r'$\displaystyle \int_{0}^{\infty} f(x)\,dx$',
    'tex_ref_matrix':             r'$\displaystyle \begin{pmatrix} a & b \\ c & d \end{pmatrix}$',
    'tex_ref_leftright':          r'$\displaystyle \left(\frac{x}{y}\right)$',
    'tex_ref_accent-hat':         r'$\displaystyle \hat{x}$',
    'tex_ref_accent-vec':         r'$\displaystyle \vec{x}$',
    'tex_ref_accent-bar':         r'$\displaystyle \bar{x}$',
    'tex_ref_accent-bar-multi':   r'$\displaystyle \bar{ab}$',
    'tex_ref_accent-widehat':     r'$\displaystyle \widehat{AB}$',
    'tex_ref_accent-tilde':       r'$\displaystyle \tilde{x}$',
    'tex_ref_accent-dot':         r'$\displaystyle \dot{x}$',
    'tex_ref_accent-ddot':        r'$\displaystyle \ddot{x}$',
    'tex_ref_color':              r'$\displaystyle \textcolor{red}{x}$',
    'tex_ref_colorbox':           r'$\displaystyle \colorbox{yellow}{x+y}$',
    'tex_ref_frac-display':       r'$\displaystyle \dfrac{1}{2}$',
    'tex_ref_frac-text':          r'$\displaystyle \tfrac{1}{2}$',
    'tex_ref_sqrt-3':             r'$\displaystyle \sqrt[3]{x}$',
    'tex_ref_greek':              r'$\displaystyle \alpha\beta\gamma\omega$',
    'tex_ref_sin-cos':            r'$\displaystyle \sin^{2}\theta + \cos^{2}\theta$',
    'tex_ref_sum-limits':         r'$\displaystyle \sum_{i=0}^{\infty} \frac{1}{i}$',
}

print("Rendering 28 TeX references at native 1x size...")
for tex_base, expr in expressions.items():
    tex_file = f'{tex_base}.tex'
    # Wrap entire math expression in red fcolorbox (outer box only)
    wrapped = r'\fcolorbox{red}{white}{' + expr + '}'
    latex = PREAMBLE + '\n' + wrapped + '\n' + POSTAMBLE
    with open(tex_file, 'w') as f:
        f.write(latex)

    result = subprocess.run(
        ['/Library/TeX/texbin/lualatex',
         '-interaction=nonstopmode', '-halt-on-error',
         tex_file],
        capture_output=True, text=True, timeout=30
    )
    pdf_file = f'{tex_base}.pdf'
    if result.returncode != 0 or not os.path.exists(pdf_file):
        print(f'SKIP {tex_base}: lualatex failed')
        continue

    output_png = f'{tex_base}.png'
    subprocess.run([
        'gs', '-dNOPAUSE', '-dBATCH', '-sDEVICE=png16m',
        '-r72', '-dTextAlphaBits=4', '-dGraphicsAlphaBits=4',
        f'-sOutputFile={output_png}', pdf_file
    ], capture_output=True)

    r = subprocess.run(['sips', '-g', 'pixelWidth', '-g', 'pixelHeight', output_png],
                       capture_output=True, text=True)
    lines = r.stdout.strip().split('\n')
    w = lines[1].split(':')[1].strip()
    h = lines[2].split(':')[1].strip()

    for f in [pdf_file, f'{tex_base}.aux', f'{tex_base}.log']:
        if os.path.exists(f):
            os.remove(f)

    print(f'  OK {tex_base}.png ({w}x{h})')

print('Done - all TeX refs at native 1x size with red debug box.')
