#!/usr/bin/env node
/**
 * Trace \overbrace{x+y}^{n} metrics: MathJax v4 STIX2 (compare page) vs AlphaEqt.
 * Usage: node trace_overbrace_metrics.mjs [--url http://127.0.0.1:8080/compare_mathjax.html]
 */
import { chromium } from 'playwright';
import { spawnSync } from 'child_process';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';
import { writeFileSync } from 'fs';

const __dirname = dirname(fileURLToPath(import.meta.url));
const FS = 30;
const CARD = 'overbrace';
const LATEX = String.raw`\overbrace{x+y}^{n}`;

async function mathjaxLiveBBox(pageUrl) {
  const browser = await chromium.launch();
  const page = await browser.newPage();
  await page.goto(pageUrl, { waitUntil: 'networkidle', timeout: 60000 });
  await page.waitForSelector(`#mj-${CARD} mjx-mi`, { timeout: 30000 });
  const data = await page.evaluate(({ FS, CARD }) => {
    const card = [...document.querySelectorAll('.card')]
      .find((c) => c.querySelector('.card-label')?.textContent === CARD);
    const mjPane = card?.querySelector('.pane:last-child');
    const math = mjPane?.querySelector('mjx-math');
    if (!math) return { error: 'overbrace card not found' };
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
    const root = box('mjx-math mjx-mover', 'root');
    const label = box('mjx-mi[data-latex="n"]', 'label-n');
    const inner = box('mjx-TeXAtom[data-latex*="overbrace{x"]', 'inner-brace');
    const brace = box('mjx-TeXAtom[data-latex*="overbrace{x"] mjx-mo', 'brace-mo');
    const baseX = box('mjx-mi[data-latex="x"]', 'base-x');
    const baseY = box('mjx-mi[data-latex="y"]', 'base-y');
    const alphaImg = card?.querySelector('.alpha-img');
    const alphaH = alphaImg ? +alphaImg.style.height.replace('px', '') || null : null;
    const alphaW = alphaImg ? +alphaImg.style.width.replace('px', '') || null : null;
    return {
      source: 'mathjax-compare-page-bbox',
      fontSizePx: FS,
      root,
      inner,
      brace,
      baseX,
      baseY,
      label,
      gap_label_to_inner: label.bottomPx != null && inner.topPx != null
        ? { px: +(inner.topPx - label.bottomPx).toFixed(2), em: +((inner.topPx - label.bottomPx) / FS).toFixed(4) }
        : null,
      gap_brace_bottom_to_base_top: baseX.topPx != null && brace.bottomPx != null
        ? { px: +(baseX.topPx - brace.bottomPx).toFixed(2), em: +((baseX.topPx - brace.bottomPx) / FS).toFixed(4) }
        : null,
      gap_label_bottom_to_brace_top: label.bottomPx != null && brace.topPx != null
        ? { px: +(brace.topPx - label.bottomPx).toFixed(2), em: +((brace.topPx - label.bottomPx) / FS).toFixed(4) }
        : null,
      gap_above_label: label.topPx != null
        ? { px: +label.topPx.toFixed(2), em: +(label.topPx / FS).toFixed(4) }
        : null,
      compareAlphaImg: { widthPx: alphaW, heightPx: alphaH },
      styles: {
        outerMover: mjPane.querySelector('mjx-mover[data-latex*="overbrace"]')?.getAttribute('style'),
        script: mjPane.querySelector('mjx-mover[data-latex*="overbrace"] > mjx-script')?.getAttribute('style'),
        innerMover: mjPane.querySelector('mjx-TeXAtom[data-latex*="overbrace{x"] mjx-mover')?.getAttribute('style'),
      },
    };
  }, { FS, CARD });
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

  const label = json.items.find((i) => i.text === 'n')
    ?? json.items.find((i) => i.kind === 'MTCTLineDisplay' && i.depth === 2 && i.y > 10);
  const brace = json.items.find((i) => i.kind === 'MTAccentDisplay');
  const braceGlyph = json.items.find((i) => i.kind === 'MTGlyphDisplay' || i.kind === 'MTMathListDisplay' && i.depth === 3);
  const accentGlyph = json.items.find((i) =>
    i.kind === 'MTGlyphDisplay' && brace && i.depth > brace.depth);
  const baseX = json.items.find((i) => i.text === 'x' && i.depth >= 4);

  const rootH = json.root.ascent + json.root.descent;
  const rootAsc = json.root.ascent;

  function toTopDown(item, containerAsc) {
    if (!item) return null;
    const asc = containerAsc ?? rootAsc;
    const topPx = +(asc - (item.y + item.ascent)).toFixed(2);
    const bottomPx = +(asc - (item.y - item.descent)).toFixed(2);
    return {
      name: item.text || item.kind,
      baselineY: item.y,
      topPx,
      bottomPx,
      heightPx: +(bottomPx - topPx).toFixed(2),
      widthPx: +item.width.toFixed(2),
      topEm: +(topPx / FS).toFixed(4),
      bottomEm: +(bottomPx / FS).toFixed(4),
    };
  }

  const braceAccent = json.items.filter((i) => i.kind === 'MTGlyphDisplay' || (i.kind === 'MTMathListDisplay' && i.depth >= 3));
  const stretchy = braceAccent.find((i) => i.width > 20 && i.depth >= 3);

  const nTd = toTopDown(label, rootAsc);
  const baseTd = toTopDown(baseX, rootAsc);
  const braceTd = stretchy ? {
    topPx: +(rootAsc - (stretchy.y + stretchy.ascent)).toFixed(2),
    bottomPx: +(rootAsc - (stretchy.y - stretchy.descent)).toFixed(2),
    heightPx: +(stretchy.ascent + stretchy.descent).toFixed(2),
    widthPx: +stretchy.width.toFixed(2),
  } : null;

  return {
    source: 'alphaeqt-rendercompare',
    fontSizePx: FS,
    root: {
      widthPx: +json.root.width.toFixed(2),
      heightPx: +rootH.toFixed(2),
      ascentPx: +json.root.ascent.toFixed(2),
      descentPx: +json.root.descent.toFixed(2),
      heightEm: +(rootH / FS).toFixed(4),
    },
    brace: brace ? {
      y: brace.y,
      ascentPx: +brace.ascent.toFixed(2),
      descentPx: +brace.descent.toFixed(2),
      widthPx: +brace.width.toFixed(2),
      heightPx: +(brace.ascent + brace.descent).toFixed(2),
    } : null,
    stretchyGlyph: braceTd,
    label: nTd,
    base: baseTd,
    gap_above_label: nTd ? { px: nTd.topPx, em: +(nTd.topPx / FS).toFixed(4) } : null,
    gap_label_bottom_to_brace_top: nTd && braceTd
      ? { px: +(braceTd.topPx - nTd.bottomPx).toFixed(2), em: +((braceTd.topPx - nTd.bottomPx) / FS).toFixed(4) }
      : null,
    gap_brace_bottom_to_base_top: baseTd && braceTd
      ? { px: +(baseTd.topPx - braceTd.bottomPx).toFixed(2), em: +((baseTd.topPx - braceTd.bottomPx) / FS).toFixed(4) }
      : null,
    raw: { items: json.items },
  };
}

const pageUrl = process.argv.includes('--url')
  ? process.argv[process.argv.indexOf('--url') + 1]
  : 'http://127.0.0.1:8080/compare_mathjax.html';

const out = {
  latex: LATEX,
  fontSizePx: FS,
  mathjaxBBox: await mathjaxLiveBBox(pageUrl).catch((e) => ({
    error: e.message,
    hint: 'Serve comparison_images: python3 -m http.server 8080',
  })),
  alphaEqt: alphaEqtMetrics(),
};

const outPath = join(__dirname, 'metrics_trace_overbrace.json');
writeFileSync(outPath, JSON.stringify(out, null, 2) + '\n');

const mj = out.mathjaxBBox?.root?.heightPx;
const al = out.alphaEqt?.root?.heightPx;
console.log('Wrote', outPath);
if (mj && al) {
  console.log(`MathJax root: ${mj}px × ${out.mathjaxBBox.root.widthPx}px`);
  console.log(`Alpha root:   ${al}px × ${out.alphaEqt.root.widthPx}px`);
  console.log(`Δ height: ${(al - mj).toFixed(2)}px`);
  const rows = [
    ['pad above n', out.mathjaxBBox.label?.topPx, out.alphaEqt.gap_above_label?.px],
    ['n → brace top', out.mathjaxBBox.gap_label_bottom_to_brace_top?.px, out.alphaEqt.gap_label_bottom_to_brace_top?.px],
    ['brace top', out.mathjaxBBox.brace?.topPx, out.alphaEqt.stretchyGlyph?.topPx],
    ['brace bottom', out.mathjaxBBox.brace?.bottomPx, out.alphaEqt.stretchyGlyph?.bottomPx],
    ['base x top', out.mathjaxBBox.baseX?.topPx, out.alphaEqt.base?.topPx],
  ];
  for (const [name, m, a] of rows) {
    if (m != null && a != null) console.log(`  ${name}: MJ ${m}px  Alpha ${a}px  Δ ${(a - m).toFixed(2)}px`);
  }
}
