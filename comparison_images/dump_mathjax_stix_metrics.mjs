#!/usr/bin/env node
/** Dump MathJax v4 STIX2 CHTML metrics at 30px (matches compare page). */
import MathJax from 'mathjax';

const latex = process.argv[2];
if (!latex) {
  console.error('Usage: node dump_mathjax_stix_metrics.mjs <latex>');
  process.exit(1);
}

const FONT_PX = 30;

await MathJax.init({
  loader: { load: ['input/tex', 'output/chtml'] },
  chtml: {
    font: 'mathjax-stix2',
    matchFontHeight: false,
    scale: 1,
    exFactor: 12,
  },
  tex: { packages: { '[+]': ['ams'] } },
});
await MathJax.startup.promise;

const node = await MathJax.tex2chtmlPromise(latex, { display: true });
const adaptor = MathJax.startup.adaptor;
const html = adaptor.outerHTML(node);

const emToPx = FONT_PX;
const items = [];
const tagRe = /<(mjx-\w+)([^>]*)>/g;
let m;
while ((m = tagRe.exec(html)) !== null) {
  const tag = m[1];
  const attrs = m[2];
  const info = { kind: tag };
  const styleM = attrs.match(/style="([^"]*)"/);
  if (styleM) {
    const s = styleM[1];
    for (const [p, re] of [
      ['top', /top:\s*([\d.-]+)em/],
      ['left', /left:\s*([\d.-]+)em/],
      ['height', /height:\s*([\d.-]+)em/],
      ['width', /width:\s*([\d.-]+)em/],
    ]) {
      const v = s.match(re);
      if (v) {
        info[p + 'Em'] = parseFloat(v[1]);
        info[p + 'Px'] = +(parseFloat(v[1]) * emToPx).toFixed(2);
      }
    }
  }
  const classM = attrs.match(/class="([^"]*)"/);
  if (classM) info.classes = classM[1];
  const endTag = '</' + tag + '>';
  const endIdx = html.indexOf(endTag, m.index);
  if (endIdx > m.index) {
    const inner = html.substring(m.index + m[0].length, endIdx);
    const text = inner.replace(/<[^>]+>/g, '').trim();
    if (text) info.text = text;
  }
  if (info.topEm !== undefined || info.heightEm !== undefined || info.widthEm !== undefined || info.text) {
    items.push(info);
  }
}

const root = items.find(i => i.kind === 'mjx-math');
console.log(JSON.stringify({
  expression: latex,
  fontSizePx: FONT_PX,
  root: root ? { w: root.widthPx ?? 0, h: root.heightPx ?? 0 } : null,
  items,
}, null, 2));
