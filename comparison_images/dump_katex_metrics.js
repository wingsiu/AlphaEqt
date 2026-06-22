#!/usr/bin/env node
/** KaTeX 指标导出器：解析树 + HTML 渲染，提取带 CSS 样式的 span。 */
const fs = require('fs');
const katex = require('./node_modules/katex');

const exprFile = process.argv[2];
if (!exprFile) { console.error('Usage: node dump_katex_metrics.js <expr_file>'); process.exit(1); }

const latex = fs.readFileSync(exprFile, 'utf8').trim();

try {
    // 1. 解析树（语义）
    const parseTree = katex.__parse(latex, { displayMode: true, throwOnError: false, strict: false });
    const parseItems = [];
    function walkParse(group, depth) {
        const info = { kind: group.type || 'unknown', depth };
        if (group.text) info.text = group.text;
        if (group.limits) info.limits = group.limits;
        if (group.style) info.style = group.style;
        if (group.color) info.color = group.color;
        if (group.label) info.accentLabel = group.label;
        parseItems.push(info);
        const children = [];
        if (group.body && Array.isArray(group.body)) children.push(...group.body);
        else if (group.body && typeof group.body === 'object') children.push(group.body);
        if (group.base) children.push(group.base);
        if (group.sup) children.push(group.sup);
        if (group.sub) children.push(group.sub);
        if (group.numer) children.push(group.numer);
        if (group.denom) children.push(group.denom);
        if (group.index) children.push(group.index);
        if (group.accent) children.push(group.accent);
        if (group.value && typeof group.value === 'object') children.push(group.value);
        for (const c of children) walkParse(c, depth + 1);
    }
    for (const g of parseTree) walkParse(g, 0);

    // 2. HTML 渲染（带定位数据）
    const html = katex.renderToString(latex, { displayMode: true, throwOnError: false, strict: false });

    // 3. 从 HTML 中提取 span + style 属性
    const spanPattern = /<span class="([^"]*)" style="([^"]*)">/g;
    const htmlItems = [];
    let match;
    while ((match = spanPattern.exec(html)) !== null) {
        const classes = match[1];
        const style = match[2];
        const item = { classes };

        // 解析样式属性
        const topMatch = style.match(/top:\s*([\d.-]+)em/);
        const leftMatch = style.match(/left:\s*([\d.-]+)em/);
        const heightMatch = style.match(/height:\s*([\d.-]+)em/);
        const widthMatch = style.match(/width:\s*([\d.-]+)em/);
        const fontSizeMatch = style.match(/font-size:\s*([\d.-]+)em/);
        const marginLeftMatch = style.match(/margin-left:\s*([\d.-]+)em/);
        const marginRightMatch = style.match(/margin-right:\s*([\d.-]+)em/);

        if (topMatch) item.topEm = parseFloat(topMatch[1]);
        if (leftMatch) item.leftEm = parseFloat(leftMatch[1]);
        if (heightMatch) item.heightEm = parseFloat(heightMatch[1]);
        if (widthMatch) item.widthEm = parseFloat(widthMatch[1]);
        if (fontSizeMatch) item.fontSizeEm = parseFloat(fontSizeMatch[1]);
        if (marginLeftMatch) item.marginLeftEm = parseFloat(marginLeftMatch[1]);
        if (marginRightMatch) item.marginRightEm = parseFloat(marginRightMatch[1]);

        // 提取内部文本
        const textEnd = html.indexOf('</span>', match.index);
        const innerHtml = html.substring(match.index + match[0].length, textEnd);
        item.text = innerHtml.replace(/<[^>]+>/g, '').replace(/&/g, '&').replace(/</g, '<').replace(/>/g, '>').replace(/"/g, '"');

        htmlItems.push(item);
    }

    // 4. 提取整体尺寸
    const outerSpan = html.match(/<span class="katex-html"[^>]*>/);
    const outerHeightMatch = html.match(/\.katex\s*\{[^}]*font-size:\s*([\d.]+)em/);
    const totalHeightMatch = html.match(/<span[^>]*style="[^"]*height:\s*([\d.]+)em[^"]*"[^>]*>/);

    const result = {
        expression: latex,
        parseTree: parseItems,
        parseTreeCount: parseItems.length,
        htmlSpans: htmlItems,
        htmlSpanCount: htmlItems.length,
        htmlPreview: html.substring(0, 400),
    };

    if (totalHeightMatch) result.totalHeightEm = parseFloat(totalHeightMatch[1]);

    console.log(JSON.stringify(result, null, 2));

} catch (e) {
    console.log(JSON.stringify({ error: e.message }, null, 2));
    process.exit(1);
}
