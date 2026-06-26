#!/usr/bin/env node
/**
 * Trace x-arrow metrics: MathJax v4 STIX2 (compare page) vs AlphaEqt.
 * Horizontal layout: label box, arrow box/ink, text content, protrusion past text.
 * Cases: xrightarrow, xleftarrow-below (from compare-cases.json).
 * Usage: node trace_xarrow_metrics.mjs [--url http://127.0.0.1:8080/compare_mathjax.html]
 */
import { chromium } from 'playwright';
import { spawnSync } from 'child_process';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';
import { writeFileSync } from 'fs';

const __dirname = dirname(fileURLToPath(import.meta.url));
const FS = 30;

const CASES = [
  { card: 'xrightarrow', latex: String.raw`\xrightarrow{f(x)}` },
  { card: 'xleftarrow-below', latex: String.raw`\xleftarrow[below]{above}` },
];

function hBox(leftPx, rightPx, FS) {
  const w = +(rightPx - leftPx).toFixed(2);
  return {
    leftPx: +leftPx.toFixed(2),
    rightPx: +rightPx.toFixed(2),
    widthPx: w,
    leftEm: +(leftPx / FS).toFixed(4),
    rightEm: +(rightPx / FS).toFixed(4),
    widthEm: +(w / FS).toFixed(4),
  };
}

function protrusion(arrow, text, label) {
  const pastText = text
    ? {
        leftPx: +(text.leftPx - arrow.leftPx).toFixed(2),
        rightPx: +(arrow.rightPx - text.rightPx).toFixed(2),
        leftEm: +((text.leftPx - arrow.leftPx) / FS).toFixed(4),
        rightEm: +((arrow.rightPx - text.rightPx) / FS).toFixed(4),
      }
    : null;
  const pastLabel = label
    ? {
        leftPx: +(label.leftPx - arrow.leftPx).toFixed(2),
        rightPx: +(arrow.rightPx - label.rightPx).toFixed(2),
      }
    : null;
  return { pastText, pastLabel };
}

async function mathjaxLiveBBox(pageUrl, card) {
  const browser = await chromium.launch();
  const page = await browser.newPage();
  await page.goto(pageUrl, { waitUntil: 'networkidle', timeout: 60000 });
  await page.waitForSelector(`#mj-${card}`, { timeout: 30000 });
  const data = await page.evaluate(({ FS, card }) => {
    const cardEl = [...document.querySelectorAll('.card')]
      .find((c) => c.querySelector('.card-label')?.textContent === card);
    const mjPane = cardEl?.querySelector('.pane:last-child');
    const math = mjPane?.querySelector('mjx-math');
    if (!math) return { error: `${card} card not found` };
    const br = math.getBoundingClientRect();
    function box(el, name) {
      if (!el) return { name, error: 'missing' };
      const r = el.getBoundingClientRect();
      const topPx = +(r.top - br.top).toFixed(2);
      const bottomPx = +(r.bottom - br.top).toFixed(2);
      const leftPx = +(r.left - br.left).toFixed(2);
      const rightPx = +(r.right - br.left).toFixed(2);
      return {
        name,
        topPx,
        bottomPx,
        leftPx,
        rightPx,
        heightPx: +r.height.toFixed(2),
        widthPx: +r.width.toFixed(2),
        topEm: +(topPx / FS).toFixed(4),
        bottomEm: +(bottomPx / FS).toFixed(4),
        leftEm: +(leftPx / FS).toFixed(4),
        rightEm: +(rightPx / FS).toFixed(4),
      };
    }
    function wideArrowBox() {
      const mos = [...mjPane.querySelectorAll('mjx-mo')];
      const el = mos.find((m) => m.getBoundingClientRect().width > 30);
      return el ? box(el, 'arrow-mo') : { name: 'arrow-mo', error: 'missing' };
    }
    function textSpanIn(container) {
      if (!container) return null;
      const leaves = [...container.querySelectorAll('[data-latex]')]
        .filter((el) => {
          const r = el.getBoundingClientRect();
          return r.width > 0.5 && r.height > 0.5;
        });
      if (!leaves.length) return null;
      const leftPx = Math.min(...leaves.map((el) => el.getBoundingClientRect().left - br.left));
      const rightPx = Math.max(...leaves.map((el) => el.getBoundingClientRect().right - br.left));
      return {
        name: 'text-ink',
        leftPx: +leftPx.toFixed(2),
        rightPx: +rightPx.toFixed(2),
        widthPx: +(rightPx - leftPx).toFixed(2),
        glyphs: leaves.map((el) => el.getAttribute('data-latex')).filter(Boolean),
      };
    }
    const root = box(mjPane.querySelector('mjx-math'), 'root');
    const arrow = wideArrowBox();
    const isUnderOver = !!mjPane.querySelector('mjx-munderover');
    const labelAbove = isUnderOver
      ? box(mjPane.querySelector('mjx-munderover > mjx-over'), 'label-above')
      : box(mjPane.querySelector('mjx-mover > mjx-over'), 'label-above');
    const labelBelow = isUnderOver
      ? box(mjPane.querySelector('mjx-munderover mjx-under'), 'label-below')
      : null;
    const textAbove = textSpanIn(
      mjPane.querySelector('mjx-mover > mjx-over') ??
        mjPane.querySelector('mjx-munderover > mjx-over'),
    );
    const textBelow = textSpanIn(mjPane.querySelector('mjx-munderover mjx-under'));
    const stretchy = mjPane.querySelector('mjx-stretchy-h');
    const stretchyStyle = stretchy?.getAttribute('style') ?? '';
    const stretchyWEm = stretchyStyle.match(/width:\s*([\d.]+)em/)?.[1];
    const gap = (a, b) => (a?.bottomPx != null && b?.topPx != null)
      ? { px: +(b.topPx - a.bottomPx).toFixed(2), em: +((b.topPx - a.bottomPx) / FS).toFixed(4) }
      : null;
    return {
      source: 'mathjax-compare-page-bbox',
      fontSizePx: FS,
      card,
      root,
      arrow,
      labelAbove,
      labelBelow,
      textAbove,
      textBelow,
      stretchy: stretchy
        ? { widthEm: stretchyWEm ? +stretchyWEm : null, widthPx: stretchyWEm ? +(stretchyWEm * FS).toFixed(2) : null }
        : null,
      gap_label_to_arrow: gap(labelAbove, arrow),
      gap_arrow_to_below: gap(arrow, labelBelow),
      gap_above_top_label: labelAbove?.topPx != null
        ? { px: labelAbove.topPx, em: +(labelAbove.topPx / FS).toFixed(4) }
        : null,
      styles: {
        mover: mjPane.querySelector('mjx-mover')?.getAttribute('style'),
        munderover: mjPane.querySelector('mjx-munderover')?.getAttribute('style'),
        over: mjPane.querySelector('mjx-over')?.getAttribute('style'),
        under: mjPane.querySelector('mjx-under')?.getAttribute('style'),
      },
    };
  }, { FS, card });
  await browser.close();

  if (data.error) return data;

  const labelBox = hBox(data.labelAbove.leftPx, data.labelAbove.rightPx, FS);
  const arrowBox = hBox(data.arrow.leftPx, data.arrow.rightPx, FS);
  const textAbove = data.textAbove
    ? hBox(data.textAbove.leftPx, data.textAbove.rightPx, FS)
    : null;
  const textBelow = data.textBelow
    ? hBox(data.textBelow.leftPx, data.textBelow.rightPx, FS)
    : null;

  data.horizontal = {
    labelBox,
    arrowBox,
    textAbove,
    textBelow,
    arrowPastTextAbove: protrusion(arrowBox, textAbove, labelBox).pastText,
    arrowPastTextBelow: textBelow ? protrusion(arrowBox, textBelow, null).pastText : null,
    arrowPastLabel: protrusion(arrowBox, null, labelBox).pastLabel,
    note: 'MathJax: arrow-mo box = label-over box; arrowheads align to box edges, past narrower text ink.',
  };
  return data;
}

function alphaEqtMetrics(latex) {
  const renderCompare = join(__dirname, '../Tools/RenderCompare');
  const res = spawnSync('swift', ['run', '-q', 'RenderCompare', '--metrics', latex], {
    cwd: renderCompare,
    encoding: 'utf8',
  });
  const text = (res.stdout || '') + (res.stderr || '');
  const start = text.indexOf('{');
  const end = text.lastIndexOf('}');
  if (start < 0) throw new Error('AlphaEqt metrics failed: ' + text.slice(-400));
  const json = JSON.parse(text.slice(start, end + 1));

  const rootAsc = json.root.ascent;
  const rootH = json.root.ascent + json.root.descent;
  const dispW = json.root.width;

  function toTopDown(item) {
    if (!item) return null;
    const topPx = +(rootAsc - (item.y + item.ascent)).toFixed(2);
    const bottomPx = +(rootAsc - (item.y - item.descent)).toFixed(2);
    return {
      name: item.text || item.kind,
      baselineY: item.y,
      topPx,
      bottomPx,
      heightPx: +(bottomPx - topPx).toFixed(2),
      widthPx: +item.width.toFixed(2),
      xPx: +item.x.toFixed(2),
    };
  }

  const arrow = json.items.find((i) =>
    i.kind === 'MTGlyphDisplay' || i.kind === 'MTGlyphConstructionDisplay');
  const labelRows = json.items.filter((i) =>
    i.kind === 'MTMathListDisplay' && i.depth === 2);
  const labelAbove = labelRows.find((i) => i.y > 0) ?? labelRows[0];
  const labelBelow = labelRows.find((i) => i.y < 0);

  const arrowTd = toTopDown(arrow);
  const labelAboveTd = toTopDown(labelAbove);
  const labelBelowTd = toTopDown(labelBelow);

  const gap = (a, b) => (a && b)
    ? { px: +(b.topPx - a.bottomPx).toFixed(2), em: +((b.topPx - a.bottomPx) / FS).toFixed(4) }
    : null;

  const labelBox = hBox(0, dispW, FS);
  const textAbove = labelAbove
    ? hBox(labelAbove.x, labelAbove.x + labelAbove.width, FS)
    : null;
  const textBelow = labelBelow
    ? hBox(labelBelow.x, labelBelow.x + labelBelow.width, FS)
    : null;
  const arrowAdvance = arrow
    ? hBox(arrow.x, arrow.x + arrow.width, FS)
    : null;
  const arrowInk = arrow && arrow.inkMinX != null
    ? hBox(arrow.x + arrow.inkMinX, arrow.x + arrow.inkMaxX, FS)
    : arrowAdvance;

  const horizontal = {
    labelBox,
    textAbove,
    textBelow,
    arrowAdvance,
    arrowInk,
    arrowPastTextAbove: arrowInk && textAbove
      ? protrusion(arrowInk, textAbove, labelBox).pastText
      : null,
    arrowPastTextBelow: arrowInk && textBelow
      ? protrusion(arrowInk, textBelow, null).pastText
      : null,
    arrowPastLabel: arrowInk
      ? protrusion(arrowInk, null, labelBox).pastLabel
      : null,
    hPadEachSide: textAbove
      ? {
          leftPx: +(textAbove.leftPx - labelBox.leftPx).toFixed(2),
          rightPx: +(labelBox.rightPx - textAbove.rightPx).toFixed(2),
          leftEm: +((textAbove.leftPx - labelBox.leftPx) / FS).toFixed(4),
          rightEm: +((labelBox.rightPx - textAbove.rightPx) / FS).toFixed(4),
        }
      : null,
    note: 'Alpha: labelBox = disp.width; text = centered MTMathListDisplay; arrow ink from glyph bboxes.',
  };

  return {
    source: 'alphaeqt-rendercompare',
    fontSizePx: FS,
    root: {
      widthPx: +json.root.width.toFixed(2),
      heightPx: +rootH.toFixed(2),
      ascentPx: +json.root.ascent.toFixed(2),
      descentPx: +json.root.descent.toFixed(2),
    },
    arrow: arrowTd,
    labelAbove: labelAboveTd,
    labelBelow: labelBelowTd,
    horizontal,
    gap_above_top_label: labelAboveTd
      ? { px: labelAboveTd.topPx, em: +(labelAboveTd.topPx / FS).toFixed(4) }
      : null,
    gap_label_to_arrow: gap(labelAboveTd, arrowTd),
    gap_arrow_to_below: gap(arrowTd, labelBelowTd),
    raw: { items: json.items },
  };
}

function summarizeHorizontal(caseName, mj, al) {
  const lines = [`\n--- ${caseName} horizontal ---`];
  const fmt = (name, m, a) => {
    if (!m && !a) return;
    if (m && a) {
      lines.push(`  ${name}: MJ L${m.leftPx} R${m.rightPx} W${m.widthPx}  Alpha L${a.leftPx} R${a.rightPx} W${a.widthPx}`);
    } else if (m) lines.push(`  ${name}: MJ L${m.leftPx} R${m.rightPx} W${m.widthPx}`);
    else lines.push(`  ${name}: Alpha L${a.leftPx} R${a.rightPx} W${a.widthPx}`);
  };
  fmt('label box', mj?.horizontal?.labelBox, al?.horizontal?.labelBox);
  fmt('text above', mj?.horizontal?.textAbove, al?.horizontal?.textAbove);
  fmt('text below', mj?.horizontal?.textBelow, al?.horizontal?.textBelow);
  fmt('arrow box (MJ) / advance (Alpha)', mj?.horizontal?.arrowBox, al?.horizontal?.arrowAdvance);
  fmt('arrow ink', mj?.horizontal?.arrowBox, al?.horizontal?.arrowInk);

  const ptMj = mj?.horizontal?.arrowPastTextAbove;
  const ptAl = al?.horizontal?.arrowPastTextAbove;
  if (ptMj || ptAl) {
    lines.push(`  arrow past text above: MJ L${ptMj?.leftPx ?? '?'} R${ptMj?.rightPx ?? '?'}px  Alpha L${ptAl?.leftPx ?? '?'} R${ptAl?.rightPx ?? '?'}px`);
  }
  const pbMj = mj?.horizontal?.arrowPastTextBelow;
  const pbAl = al?.horizontal?.arrowPastTextBelow;
  if (pbMj || pbAl) {
    lines.push(`  arrow past text below: MJ L${pbMj?.leftPx ?? '?'} R${pbMj?.rightPx ?? '?'}px  Alpha L${pbAl?.leftPx ?? '?'} R${pbAl?.rightPx ?? '?'}px`);
  }
  const plMj = mj?.horizontal?.arrowPastLabel;
  const plAl = al?.horizontal?.arrowPastLabel;
  if (plMj || plAl) {
    lines.push(`  arrow past label box: MJ L${plMj?.leftPx ?? '?'} R${plMj?.rightPx ?? '?'}px  Alpha L${plAl?.leftPx ?? '?'} R${plAl?.rightPx ?? '?'}px`);
  }
  if (mj?.stretchy) lines.push(`  MJ stretchy-h width: ${mj.stretchy.widthEm}em (${mj.stretchy.widthPx}px)`);
  if (al?.horizontal?.hPadEachSide) {
    const h = al.horizontal.hPadEachSide;
    lines.push(`  Alpha text margin in label box: L${h.leftPx} R${h.rightPx}px (${h.leftEm}/${h.rightEm}em)`);
  }
  return lines.join('\n');
}

function summarize(caseName, mj, al) {
  const lines = [`\n=== ${caseName} ===`];
  if (mj?.root?.heightPx && al?.root?.heightPx) {
    lines.push(`Root: MJ ${mj.root.heightPx}×${mj.root.widthPx}px  Alpha ${al.root.heightPx}×${al.root.widthPx}px  ΔH ${(al.root.heightPx - mj.root.heightPx).toFixed(2)}px  ΔW ${(al.root.widthPx - mj.root.widthPx).toFixed(2)}px`);
  }
  const rows = [
    ['pad above label', mj?.gap_above_top_label?.px, al?.gap_above_top_label?.px],
    ['label top', mj?.labelAbove?.topPx, al?.labelAbove?.topPx],
    ['arrow top', mj?.arrow?.topPx, al?.arrow?.topPx],
    ['arrow H', mj?.arrow?.heightPx, al?.arrow?.heightPx],
    ['label→arrow gap', mj?.gap_label_to_arrow?.px, al?.gap_label_to_arrow?.px],
    ['arrow→below gap', mj?.gap_arrow_to_below?.px, al?.gap_arrow_to_below?.px],
  ].filter(([name]) => name !== 'arrow→below gap' || mj?.labelBelow || al?.labelBelow);
  for (const [name, m, a] of rows) {
    if (m != null && a != null) lines.push(`  ${name}: MJ ${m}px  Alpha ${a}px  Δ ${(a - m).toFixed(2)}px`);
    else if (m != null) lines.push(`  ${name}: MJ ${m}px`);
    else if (a != null) lines.push(`  ${name}: Alpha ${a}px`);
  }
  lines.push(summarizeHorizontal(caseName, mj, al));
  return lines.join('\n');
}

const pageUrl = process.argv.includes('--url')
  ? process.argv[process.argv.indexOf('--url') + 1]
  : 'http://127.0.0.1:8080/compare_mathjax.html';

const out = { fontSizePx: FS, cases: {} };

for (const { card, latex } of CASES) {
  out.cases[card] = {
    latex,
    mathjaxBBox: await mathjaxLiveBBox(pageUrl, card).catch((e) => ({
      error: e.message,
      hint: 'Serve comparison_images: python3 -m http.server 8080',
    })),
    alphaEqt: alphaEqtMetrics(latex),
  };
}

const outPath = join(__dirname, 'metrics_trace_xarrow.json');
writeFileSync(outPath, JSON.stringify(out, null, 2) + '\n');
console.log('Wrote', outPath);
for (const { card } of CASES) {
  console.log(summarize(card, out.cases[card].mathjaxBBox, out.cases[card].alphaEqt));
}
