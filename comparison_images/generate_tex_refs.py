#!/usr/bin/env python3
"""Generate TeX math reference images using matplotlib with XITS Math font."""
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib import font_manager as fm

font_path = 'xits-math-comparison.otf'
fm.fontManager.addfont(font_path)
prop = fm.FontProperties(fname=font_path, size=50)
font_name = prop.get_name()

plt.rcParams.update({
    'text.usetex': False,
    'mathtext.fontset': 'custom',
    'mathtext.rm': font_name,
    'mathtext.it': font_name + ':italic',
    'mathtext.bf': font_name + ':bold',
    'mathtext.default': 'rm'
})

test_cases = [
    (r'$\frac{x}{y}$', 'frac'),
    (r'$\frac{\frac{a}{b}}{\frac{c}{d}}$', 'nested-frac'),
    (r'$\sqrt{x+1}$', 'sqrt'),
    (r'$\sqrt{\frac{x}{y}}$', 'sqrt-nested'),
    (r'$x^2$', 'sup'),
    (r'$x_1$', 'sub'),
    (r'$x_i^2$', 'supsub'),
    (r'$\displaystyle\sum_{i=0}^n i^2$', 'sum-display'),
    (r'$\textstyle\sum_{i=0}^n i^2$', 'sum-inline'),
    (r'$\displaystyle\int_0^\infty f(x)dx$', 'integral'),
    (r'$\begin{pmatrix} a & b \\ c & d \end{pmatrix}$', 'matrix'),
    (r'$\left(\frac{x}{y}\right)$', 'leftright'),
    (r'$\hat{x}$', 'accent-hat'),
    (r'$\vec{x}$', 'accent-vec'),
    (r'$\bar{x}$', 'accent-bar'),
    (r'$\bar{ab}$', 'accent-bar-multi'),
    (r'$\widehat{AB}$', 'accent-widehat'),
    (r'$\tilde{x}$', 'accent-tilde'),
    (r'$\dot{x}$', 'accent-dot'),
    (r'$\ddot{x}$', 'accent-ddot'),
    (r'$\textcolor{red}{x}$', 'color'),
    (r'$\colorbox{yellow}{x+y}$', 'colorbox'),
    (r'$\dfrac{1}{2}$', 'frac-display'),
    (r'$\tfrac{1}{2}$', 'frac-text'),
    (r'$\sqrt[3]{x}$', 'sqrt-3'),
    (r'$\alpha\beta\gamma\omega$', 'greek'),
    (r'$\sin^2\theta + \cos^2\theta$', 'sin-cos'),
    (r'$\displaystyle\sum_{i=0}^\infty \frac{1}{i}$', 'sum-limits'),
]

for expr, name in test_cases:
    try:
        fig, ax = plt.subplots(figsize=(6, 1.2))
        ax.text(0.5, 0.5, expr,
                fontproperties=prop,
                fontsize=50,
                ha='center',
                va='center',
                transform=ax.transAxes)
        ax.axis('off')
        out = f'tex_xits_{name}.png'
        plt.savefig(out, dpi=150, bbox_inches='tight',
                    facecolor='white', edgecolor='none')
        plt.close()
        print(f'✅ {name}')
    except Exception as e:
        print(f'❌ {name}: {e}')

print('\nDone! XITS Math TeX reference images created.')
