#!/usr/bin/env node
/**
 * Trace \binom{n}{k} metrics: MathJax v4 STIX2 (compare page) vs AlphaEqt.
 * Usage: node trace_binom_metrics.mjs [--url http://127.0.0.1:8080/compare_mathjax.html]
 */
import { chromium } from 'playwright';
import { spawnSync } from 'child_process';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';
import MathJax from 'mathjax';

const __dirname = dirname(fileURLToPath(import.meta.url));
const FS = 30;
const LATEX = String.raw`\binom{n}{k}`;

async function mathjaxCHTMLMetrics() {
  await MathJax.init({
    loader: { load: ['input/tex', 'output/chtml'] },
    chtml: { font: 'mathjax-stix2', matchFontHeight: false, scale: 1, exFactor: 12 },
    tex: { packages: { '[+]': ['ams'] } },
  });
  await MathJax.startup.promise;
  const node = await MathJax.tex2chtmlPromise(LATEX, { display: true });
  const html = MathJax.startup.adaptor.outerHTML(node);

  function parseAttrs(tag, attrs) {
    const o = { kind: tag };
    const style = attrs.match(/style="([^"]*)"/);
    if (style) {
      for (const m of style[1].matchAll(/([\w-]+):\s*([\d.-]+)em/g)) {
        o[m[1]] = { em: +m[2], px: +(m[2] * FS).toFixed(3) };
      }
    }
    const cls = attrs.match(/class="([^"]*)"/);
    if (cls) o.classes = cls[1];
    for (const m of attrs.matchAll(/(\w+)="([^"]*)"/g)) {
      if (!['style', 'class', 'data-latex'].includes(m[1])) o[m[1]] = m[2];
    }
    return o;
  }

  const items = [];
  for (const m of html.matchAll(/<(mjx-\w+)([^>]*)>/g)) {
    items.push(parseAttrs(m[1], m[2]));
  }
  return { source: 'mathjax-chtml-node', fontSizePx: FS, latex: LATEX, items };
}

async function mathjaxLiveBBox(pageUrl) {
  const browser = await chromium.launch();
  const page = await browser.newPage();
  await page.goto(pageUrl, { waitUntil: 'networkidle', timeout: 60000 });
  await page.waitForSelector('#mj-binom mjx-mi', { timeout: 30000 });
  const data = await page.evaluate((FS) => {
    const card = [...document.querySelectorAll('.card')]
      .find((c) => c.querySelector('.card-label')?.textContent === 'binom');
    const mjPane = card?.querySelector('.pane:last-child');
    const math = mjPane?.querySelector('mjx-math');
    if (!math) return { error: 'binom card not found' };
    const br = math.getBoundingClientRect();
    function box(sel, name) {
      const el = mjPane.querySelector(sel);
      if (!el) return { name, error: 'missing' };
      const r = el.getBoundingClientRect();
      const topPx = +(r.top - br.top).toFixed(2);
      const bottomPx = +(r.bottom - br.top).toFixed(2);
      return {
        name,
        topPx,
        bottomPx,
        heightPx: +r.height.toFixed(2),
        widthPx: +r.width.toFixed(2),
        topEm: +(topPx / FS).toFixed(4),
        bottomEm: +(bottomPx / FS).toFixed(4),
      };
    }
    const n = box('mjx-num mjx-mi', 'n');
    const k = box('mjx-den mjx-mi', 'k');
    const root = box('mjx-math', 'root');
    const open = box('mjx-TeXAtom[texclass=OPEN] mjx-c', 'open-paren');
    const close = box('mjx-TeXAtom[texclass=CLOSE] mjx-c', 'close-paren');
    const numBox = box('mjx-num', 'num-box');
    const denBox = box('mjx-den', 'den-box');
    const gapPx = +(k.topPx - n.bottomPx).toFixed(2);
    return {
      source: 'mathjax-compare-page-bbox',
      fontSizePx: FS,
      root,
      open,
      close,
      n,
      k,
      numBox,
      denBox,
      gap_n_bottom_to_k_top: { px: gapPx, em: +(gapPx / FS).toFixed(4) },
      gap_below_k: { px: +(root.bottomPx - k.bottomPx).toFixed(2), em: +((root.bottomPx - k.bottomPx) / FS).toFixed(4) },
      styles: {
        frac: mjPane.querySelector('mjx-frac')?.getAttribute('style'),
        num: mjPane.querySelector('mjx-num')?.getAttribute('style'),
        fracType: mjPane.querySelector('mjx-frac')?.getAttribute('type'),
        atop: mjPane.querySelector('mjx-frac')?.getAttribute('atop'),
      },
    };
  }, FS);
  await browser.close();
  return data;
}

function alphaEqtMetrics() {
  const renderCompare = join(__dirname, '../Tools/RenderCompare');
  const res = spawnSync('swift', ['run', '-q', 'RenderCompare', '--metrics', LATEX], {
    cwd: renderCompare,
    encoding: 'utf8',
  });
  const text = (res.stdout || '') + (res.stderr || '');
  const start = text.indexOf('{');
  const end = text.lastIndexOf('}');
  if (start < 0) throw new Error('AlphaEqt metrics failed: ' + text.slice(-400));
  const json = JSON.parse(text.slice(start, end + 1));

  const n = json.items.find((i) => i.text === 'n');
  const k = json.items.find((i) => i.text === 'k');
  const frac = json.items.find((i) => i.kind === 'MTFractionDisplay');
  const open = json.items.find((i) => i.kind === 'MTGlyphDisplay' && i.x === 0);
  const close = json.items.find((i) => i.kind === 'MTGlyphDisplay' && i.x > 30);

  // AlphaEqt: y-up, baseline at 0 inside fraction; convert to top-down em like MathJax.
  const asc = frac?.ascent ?? json.root.ascent;
  function toTopDown(item) {
    if (!item) return null;
    const topPx = +(asc - (item.y + item.ascent)).toFixed(2);
    const bottomPx = +(asc - (item.y - item.descent)).toFixed(2);
    return {
      name: item.text || item.kind,
      baselineY: item.y,
      topPx,
      bottomPx,
      heightPx: +(bottomPx - topPx).toFixed(2),
      topEm: +(topPx / FS).toFixed(4),
      bottomEm: +(bottomPx / FS).toFixed(4),
    };
  }

  const nTd = toTopDown(n);
  const kTd = toTopDown(k);
  const gapPx = nTd && kTd ? +(kTd.topPx - nTd.bottomPx).toFixed(2) : null;

  return {
    source: 'alphaeqt-rendercompare',
    fontSizePx: FS,
    root: {
      widthPx: +json.root.width.toFixed(2),
      heightPx: +(json.root.ascent + json.root.descent).toFixed(2),
      ascentPx: +json.root.ascent.toFixed(2),
      descentPx: +json.root.descent.toFixed(2),
      heightEm: +((json.root.ascent + json.root.descent) / FS).toFixed(4),
    },
    n: nTd,
    k: kTd,
    delimiters: {
      open: open ? { widthPx: +open.width.toFixed(2), heightPx: +(open.ascent + open.descent).toFixed(2) } : null,
      close: close ? { widthPx: +close.width.toFixed(2), heightPx: +(close.ascent + close.descent).toFixed(2) } : null,
    },
    gap_n_bottom_to_k_top: gapPx != null ? { px: gapPx, em: +(gapPx / FS).toFixed(4) } : null,
    gap_below_k: kTd ? {
      px: +(json.root.descent - (asc - kTd.bottomPx)).toFixed(2),
      em: +((json.root.descent - (asc - kTd.bottomPx)) / FS).toFixed(4),
    } : null,
    raw: { n, k, frac },
  };
}

const pageUrl = process.argv.includes('--url')
  ? process.argv[process.argv.indexOf('--url') + 1]
  : 'http://127.0.0.1:8080/compare_mathjax.html';

const out = {
  latex: LATEX,
  fontSizePx: FS,
  mathjaxCHTML: await mathjaxCHTMLMetrics(),
  mathjaxBBox: await mathjaxLiveBBox(pageUrl).catch((e) => ({ error: e.message, hint: 'Serve compare_images and pass --url' })),
  alphaEqt: alphaEqtMetrics(),
};

console.log(JSON.stringify(out, null, 2));
