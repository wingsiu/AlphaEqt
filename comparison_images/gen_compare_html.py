# -*- coding: utf-8 -*-
import subprocess

pairs = [
    ('fraction.png',       'Frac', r'\frac{x}{y}', 'tex_ref_frac.png'),
    ('nested-frac.png',    'Nested Frac', r'\frac{\frac{a}{b}}{\frac{c}{d}}', 'tex_ref_nested-frac.png'),
    ('sqrt.png',           'Sqrt', r'\sqrt{x+1}', 'tex_ref_sqrt.png'),
    ('sqrt-nested.png',    'Sqrt Nested', r'\sqrt{\frac{x}{y}}', 'tex_ref_sqrt-nested.png'),
    ('sup.png',            'Superscript', r'x^{2}', 'tex_ref_sup.png'),
    ('sub.png',            'Subscript', r'x_{1}', 'tex_ref_sub.png'),
    ('supsub.png',         'Sup + Sub', r'x_{i}^{2}', 'tex_ref_supsub.png'),
    ('sum-display.png',    'Sum (display)', r'\sum_{i=0}^n i^2', 'tex_ref_sum-display.png'),
    ('sum-inline.png',     'Sum (inline)', r'\textstyle\sum_{i=0}^n i^2', 'tex_ref_sum-inline.png'),
    ('integral.png',       'Integral', r'\int_0^\infty f(x)dx', 'tex_ref_integral.png'),
    ('matrix.png',         'Matrix', r'\begin{pmatrix}...\end{pmatrix}', 'tex_ref_matrix.png'),
    ('leftright.png',      'Left-Right', r'\left(\frac{x}{y}\right)', 'tex_ref_leftright.png'),
    ('accent-hat.png',     'Hat', r'\hat{x}', 'tex_ref_accent-hat.png'),
    ('accent-vec.png',     'Vec', r'\vec{x}', 'tex_ref_accent-vec.png'),
    ('accent-bar.png',     'Bar (1 char)', r'\bar{x}', 'tex_ref_accent-bar.png'),
    ('accent-bar-multi.png','Bar (multi)', r'\bar{ab}', 'tex_ref_accent-bar-multi.png'),
    ('accent-widehat.png', 'Widehat', r'\widehat{AB}', 'tex_ref_accent-widehat.png'),
    ('accent-tilde.png',   'Tilde', r'\tilde{x}', 'tex_ref_accent-tilde.png'),
    ('accent-dot.png',     'Dot', r'\dot{x}', 'tex_ref_accent-dot.png'),
    ('accent-ddot.png',    'Ddot', r'\ddot{x}', 'tex_ref_accent-ddot.png'),
    ('color.png',          'Text Color', r'\textcolor{red}{x}', 'tex_ref_color.png'),
    ('colorbox.png',       'Color Box', r'\colorbox{yellow}{x+y}', 'tex_ref_colorbox.png'),
    ('frac-display.png',   'Frac Display', r'\dfrac{1}{2}', 'tex_ref_frac-display.png'),
    ('frac-text.png',      'Frac Text', r'\tfrac{1}{2}', 'tex_ref_frac-text.png'),
    ('sqrt-3.png',         'Sqrt[3]', r'\sqrt[3]{x}', 'tex_ref_sqrt-3.png'),
    ('greek.png',          'Greek', r'\alpha\beta\gamma\omega', 'tex_ref_greek.png'),
    ('sin-cos.png',        'Trig Identity', r'\sin^2\theta + \cos^2\theta', 'tex_ref_sin-cos.png'),
    ('sum-limits.png',     'Sum Limits', r'\sum_{i=0}^\infty \frac{1}{i}', 'tex_ref_sum-limits.png'),
]

def size(path):
    r = subprocess.run(['sips','-g','pixelWidth','-g','pixelHeight', path],
                       capture_output=True, text=True)
    lines = r.stdout.strip().split('\n')
    w = lines[1].split(':')[1].strip()
    h = lines[2].split(':')[1].strip()
    return w, h

rows = ''
for alpha, label, latex, tex in pairs:
    aw, ah = size(alpha)
    tw, th = size(tex)
    rows += '<tr>\n'
    rows += f'  <td class="label">{label}</td><td class="latex">{latex}</td>\n'
    rows += f'  <td class="img-cell"><span class="tag alpha">ALPHAEQT</span><br><img src="{alpha}" width="{aw}" height="{ah}"></td>\n'
    rows += f'  <td class="img-cell"><span class="tag tex">TEX REF</span><br><img src="{tex}" width="{tw}" height="{th}"></td>\n'
    rows += '</tr>\n'

html = f'''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8"><title>AlphaEqt vs TeX XITS Math</title>
<style>
  body{{background:#fff;font-family:-apple-system,sans-serif;padding:16px;}}
  h1{{text-align:center;font-size:18px;margin-bottom:4px;}}
  .sub{{text-align:center;color:#888;font-size:11px;margin-bottom:18px;}}
  table{{border-collapse:collapse;margin:0 auto;}}
  th{{font-size:11px;padding:5px 10px;background:#f5f5f5;border:1px solid #ddd;}}
  td{{padding:6px 8px;border:1px solid #eee;vertical-align:top;text-align:center;}}
  .label{{font-size:12px;font-weight:600;}}
  .latex{{font-size:10px;color:#888;font-family:monospace;}}
  .img-cell{{min-width:80px;}}
  .tag{{font-size:9px;font-weight:600;display:block;margin-bottom:4px;}}
  .tag.alpha{{color:#007aff;}} .tag.tex{{color:#e74c3c;}}
  img{{display:block;margin:0 auto;}}
</style>
</head>
<body>
<h1>AlphaEqt vs LuaLaTeX - XITS Math (50pt 1x no pad)</h1>
<p class="sub">28 test cases - each image at native pixel size, no HTML scaling</p>
<table>
<tr><th>Expression</th><th>LaTeX</th><th><span class="tag alpha">ALPHAEQT</span></th><th><span class="tag tex">TEX REF</span></th></tr>
{rows}
</table>
<p style="text-align:center;color:#aaa;font-size:10px;margin-top:16px;">Both XITS Math OTF | AlphaEqt 50pt/1x/0pad | TeX LuaLaTeX 50pt standalone crop</p>
</body>
</html>'''

with open('compare.html', 'w') as f:
    f.write(html)
print('compare.html generated')
