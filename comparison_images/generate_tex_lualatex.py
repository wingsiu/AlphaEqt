#!/usr/bin/env python3
"""Generate TeX math reference images using LuaLaTeX with XITS Math font.
Uses article class + preview package (more reliable than standalone)."""
import os
import subprocess
import sys

OUTPUT_DIR = os.path.dirname(os.path.abspath(__file__))

PREAMBLE = r'''\documentclass[preview,border=0pt,varwidth=50cm]{standalone}
\usepackage{fontspec}
\usepackage{unicode-math}
\usepackage{xcolor}
\setmainfont{xits-math-comparison.otf}[Path=/Users/alpha/Desktop/swift/AlphaEqt/comparison_images/]
\setmathfont{xits-math-comparison.otf}[Path=/Users/alpha/Desktop/swift/AlphaEqt/comparison_images/]
\begin{document}
\fontsize{50}{60}\selectfont
'''

POSTAMBLE = r'''
\end{document}
'''

test_cases = [
    (r'$\displaystyle \frac{x}{y}$', 'frac'),
    (r'$\displaystyle \frac{\frac{a}{b}}{\frac{c}{d}}$', 'nested-frac'),
    (r'$\displaystyle \sqrt{x+1}$', 'sqrt'),
    (r'$\displaystyle \sqrt{\frac{x}{y}}$', 'sqrt-nested'),
    (r'$\displaystyle x^{2}$', 'sup'),
    (r'$\displaystyle x_{1}$', 'sub'),
    (r'$\displaystyle x_{i}^{2}$', 'supsub'),
    (r'$\displaystyle \sum_{i=0}^{n} i^{2}$', 'sum-display'),
    (r'$\textstyle \sum_{i=0}^{n} i^{2}$', 'sum-inline'),
    (r'$\displaystyle \int_{0}^{\infty} f(x)\,dx$', 'integral'),
    (r'$\displaystyle \begin{pmatrix} a & b \\ c & d \end{pmatrix}$', 'matrix'),
    (r'$\displaystyle \left(\frac{x}{y}\right)$', 'leftright'),
    (r'$\displaystyle \hat{x}$', 'accent-hat'),
    (r'$\displaystyle \vec{x}$', 'accent-vec'),
    (r'$\displaystyle \bar{x}$', 'accent-bar'),
    (r'$\displaystyle \bar{ab}$', 'accent-bar-multi'),
    (r'$\displaystyle \widehat{AB}$', 'accent-widehat'),
    (r'$\displaystyle \tilde{x}$', 'accent-tilde'),
    (r'$\displaystyle \dot{x}$', 'accent-dot'),
    (r'$\displaystyle \ddot{x}$', 'accent-ddot'),
    (r'$\displaystyle \textcolor{red}{x}$', 'color'),
    (r'$\displaystyle \colorbox{yellow}{x+y}$', 'colorbox'),
    (r'$\displaystyle \dfrac{1}{2}$', 'frac-display'),
    (r'$\displaystyle \tfrac{1}{2}$', 'frac-text'),
    (r'$\displaystyle \sqrt[3]{x}$', 'sqrt-3'),
    (r'$\displaystyle \alpha\beta\gamma\omega$', 'greek'),
    (r'$\displaystyle \sin^{2}\theta + \cos^{2}\theta$', 'sin-cos'),
    (r'$\displaystyle \sum_{i=0}^{\infty} \frac{1}{i}$', 'sum-limits'),
]

texbin = '/Library/TeX/texbin'
env = os.environ.copy()
env['PATH'] = texbin + ':' + env.get('PATH', '')

for expr, name in test_cases:
    latex_content = PREAMBLE + '\n' + expr + '\n' + POSTAMBLE

    tex_file = os.path.join(OUTPUT_DIR, f'tmp_tex_{name}.tex')

    with open(tex_file, 'w') as f:
        f.write(latex_content)

    try:
        result = subprocess.run(
            [os.path.join(texbin, 'lualatex'),
             '-interaction=nonstopmode',
             '-halt-on-error',
             '-output-directory=' + OUTPUT_DIR,
             tex_file],
            cwd=OUTPUT_DIR,
            env=env,
            capture_output=True,
            text=True,
            timeout=30
        )
        if result.returncode != 0:
            print(f'❌ {name}: lualatex failed')
            last_lines = result.stdout.strip().split('\n')[-10:]
            print('\n'.join(last_lines))
        else:
            pdf_file = tex_file.replace('.tex', '.pdf')
            png_file = os.path.join(OUTPUT_DIR, f'tex_ref_{name}.png')
            subprocess.run(
                ['sips', '-s', 'format', 'png', pdf_file, '--out', png_file],
                capture_output=True, timeout=10
            )
            print(f'✅ {name}')
    except subprocess.TimeoutExpired:
        print(f'❌ {name}: timeout')
    except Exception as e:
        print(f'❌ {name}: {e}')

    # Cleanup
    base = os.path.join(OUTPUT_DIR, f'tmp_tex_{name}')
    for ext in ['.tex', '.pdf', '.aux', '.log']:
        f = os.path.join(OUTPUT_DIR, f'tmp_tex_{name}{ext}')
        if os.path.exists(f):
            os.remove(f)

print('\nDone! Check comparison_images/tex_ref_*.png')
