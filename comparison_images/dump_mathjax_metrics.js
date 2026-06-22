#!/usr/bin/env node
/** MathJax v4 metrics dumper — uses tex2chtml + adaptor for direct CHTML DOM. */
const mj = require('mathjax');
const fs = require('fs');

const exprFile = process.argv[2];
if (!exprFile) { console.error('Usage: node dump_mathjax_metrics.js <expr_file>'); process.exit(1); }
const latex = fs.readFileSync(exprFile, 'utf8').trim();

async function main() {
    // MathJax v4 Node: use init with options
    await mj.init({
        loader: { paths: { fonts: '@mathjax' } },
        options: { enableAssistiveMml: false },
    });

    // Load components
    mj.loader.preload('input/tex', 'output/chtml');
    await mj.startup.promise;

    // Access the TeX input and CHTML output
    const tex = mj.startup.input[0];
    const chtml = mj.startup.output;
    const adaptor = mj.startup.adaptor;

    // Parse + render
    const parsed = tex.parse(latex, { display: true });
    const doc = await chtml.render(parsed, { display: true });
    const html = adaptor.outerHTML(doc);

    // Parse CHTML elements with inline styles
    const items = [];
    const emToPt = 50;
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
                ['marginLeft', /margin-left:\s*([\d.-]+)em/],
                ['marginRight', /margin-right:\s*([\d.-]+)em/],
            ]) {
                const v = s.match(re);
                if (v) {
                    info[p + 'Em'] = parseFloat(v[1]);
                    info[p + 'Pt'] = +(parseFloat(v[1]) * emToPt).toFixed(2);
                }
            }
        }

        const classM = attrs.match(/class="([^"]*)"/);
        if (classM) info.classes = classM[1];

        // Extract text
        const endTag = '</' + tag + '>';
        const endIdx = html.indexOf(endTag, m.index);
        if (endIdx > m.index) {
            const inner = html.substring(m.index + m[0].length, endIdx);
            const text = inner.replace(/<[^>]+>/g, '').replace(/&/g, '&').replace(/</g, '<').replace(/>/g, '>');
            if (text.trim()) info.text = text.trim();
        }

        // Skip struts without text
        if (info.classes?.match(/mjx-strut|mjx-pstrut/) && !info.text) continue;

        if (info.topEm !== undefined || info.heightEm !== undefined || info.widthEm !== undefined || info.text) {
            items.push(info);
        }
    }

    // MathML tree
    const mmlItems = [];
    const mmlDoc = await mj.tex2mmlPromise(latex, { display: true }).catch(() => null);
    if (mmlDoc) {
        const mmlHtml = adaptor.outerHTML(mmlDoc);
        function walkMML(str, depth) {
            const mmlRe = /<(m\w+)([^>]*)>/g;
            let mm;
            while ((mm = mmlRe.exec(str)) !== null) {
                const tag = mm[1];
                const endTag = '</' + tag + '>';
                const endI = str.indexOf(endTag, mm.index);
                const inner = endI > -1 ? str.substring(mm.index + mm[0].length, endI) : '';
                const text = inner.match(/^([^<]+)/);
                const info = { kind: tag, depth };
                if (text) info.text = text[1].trim();
                const typeMap = { msup:'supsub', msub:'supsub', msubsup:'supsub', mfrac:'fraction', msqrt:'radical', mover:'accent', munder:'accent', munderover:'accent', mtable:'matrix', mo:'operator', mi:'identifier', mn:'number' };
                if (typeMap[tag]) info.type = typeMap[tag];
                mmlItems.push(info);
                if (endI > -1) walkMML(inner, depth + 1);
            }
        }
        walkMML(mmlHtml, 0);
    }

    console.log(JSON.stringify({
        expression: latex,
        chtmlItems: items,
        chtmlCount: items.length,
        mmlItems,
        mmlCount: mmlItems.length,
    }, null, 2));
}

main().catch(e => {
    console.log(JSON.stringify({ error: e.message }, null, 2));
    process.exit(1);
});
