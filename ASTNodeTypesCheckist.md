# AST Node Types Implementation Checklist

This checklist tracks the implementation progress of planned KaTeX-style AST node types for AlphaEqt.

## Node Types

- [ ] `mathord` – Ordinary math symbols, letters, numbers (`x`, `2`)
- [ ] `textord` – Text symbols/words in math mode (`\text{foo}`)
- [ ] `bin` – Binary operators (`+`, `-`, `*`)
- [ ] `rel` – Relation operators (`=`, `<`, `\leq`)
- [ ] `open` – Opening delimiters (`(`, `[`)
- [ ] `close` – Closing delimiters (`)`, `]`)
- [ ] `punct` – Punctuation in math (`;`, `,`)
- [ ] `accent` – Accents (`\hat{x}`, `\overline{x}`)
- [ ] `supsub` – Superscript/subscript (`x^2`, `x_1`, `x_1^2`)
- [ ] `frac` – Fractions (`\frac{a}{b}`)
- [ ] `sqrt` – Square roots (`\sqrt{x}`)
- [ ] `root` – N-th roots (`\sqrt[3]{x}`)
- [ ] `ordgroup` – Grouped expressions (`{xyz}`)
- [ ] `color` – Color nodes (`\color{red}{x}`)
- [ ] `styling` – Font style nodes (`\mathbb{x}`, `\mathbf{x}`)
- [ ] `sizing` – Math style nodes (`\displaystyle`, `\textstyle`)
- [ ] `array` – Arrays/matrices (`\begin{matrix}...\end{matrix}`)
- [ ] `environment` – General environments (`\begin{align}...\end{align}`)
- [ ] `htmlmathml` – HTML/MathML wrappers
- [ ] `raw` – Raw text or raw LaTeX
- [ ] `phantom` – Invisible box (`\phantom{x}`)
- [ ] `spacing` – Spacing commands (`\,`, `\!`, `\quad`)
- [ ] `tag` – Equation tags (`\tag{n}`)
- [ ] `operatorname` – Named operators (`\operatorname{sin}`)
- [ ] `infix` – Infix operator (`\over`, `\atop`)
- [ ] `leftright` – Paired delimiters (`\left( ... \right)`)
- [ ] `hbox` – Horizontal box (`\hbox{}`)
- [ ] `fontsize` – Font size change (`\large`, `\small`)
- [ ] `kern` – Kerning/spacing
- [ ] `rule` – Rule/line (`\rule{1em}{1pt}`)
- [ ] `op` – Operator node (`\sum`, `\int`)
- [ ] `genfrac` – Generalized fraction
- [ ] `mathchoice` – `\mathchoice` node
- [ ] `text` – LaTeX text node (`\text{abc}`)
- [ ] `font` – Font change node (`\fontseries{}`)
- [ ] `mclass` – Math class node (internal)
- [ ] `subarray` – Subarray node
- [ ] `underline` – Underline (`\underline{x}`)
- [ ] `overline` – Overline (`\overline{x}`)
- [ ] `unicode` – Unicode character node
- [ ] `verb` – Verbatim node
- [ ] `pmb` – Bold math (`\pmb{x}`)
- [ ] `lap` – Overlapping symbols (`\llap`, `\rlap`)
- [ ] `raise` – Raise/lower box (`\raisebox{}`)
- [ ] `inner` – Inner node
- [ ] `error` – Parse error node

---

Mark each node as implemented when ready. Add details or files as needed.
