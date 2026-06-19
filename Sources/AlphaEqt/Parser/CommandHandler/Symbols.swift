//
//  Symbols.swift
//  AlphaEqt
//
//  LaTeX command → Unicode math symbol mappings.
//  Cross-referenced against SwiftMath's MTMathAtomFactory.supportedLatexSymbols.
//  Covers Greek letters (#23), math symbols (#24), and spacing (#26).
//

import Foundation

// MARK: - Symbol Entry

private struct SymbolEntry {
    let unicode: String
    let atomType: AtomType
}

// MARK: - Complete Symbol Table (matches SwiftMath atom types)

private let symbolTable: [String: SymbolEntry] = {
    var table: [String: SymbolEntry] = [:]

    // ── Greek Lowercase (standard — .variable → will be italicized) ──
    // SwiftMath marks these as .variable so they auto-italicize.
    // We use the base Greek codepoint; mathItalicize() converts them.
    let greekLowerVar: [(String, String)] = [
        ("\\alpha",      "\u{03B1}"),  // α
        ("\\beta",       "\u{03B2}"),  // β
        ("\\gamma",      "\u{03B3}"),  // γ
        ("\\delta",      "\u{03B4}"),  // δ
        ("\\zeta",       "\u{03B6}"),  // ζ
        ("\\eta",        "\u{03B7}"),  // η
        ("\\theta",      "\u{03B8}"),  // θ
        ("\\iota",       "\u{03B9}"),  // ι
        ("\\kappa",      "\u{03BA}"),  // κ
        ("\\lambda",     "\u{03BB}"),  // λ
        ("\\mu",         "\u{03BC}"),  // μ
        ("\\nu",         "\u{03BD}"),  // ν
        ("\\xi",         "\u{03BE}"),  // ξ
        ("\\omicron",    "\u{03BF}"),  // ο
        ("\\pi",         "\u{03C0}"),  // π
        ("\\rho",        "\u{03C1}"),  // ρ
        ("\\sigma",      "\u{03C3}"),  // σ
        ("\\tau",        "\u{03C4}"),  // τ
        ("\\upsilon",    "\u{03C5}"),  // υ
        ("\\chi",        "\u{03C7}"),  // χ
        ("\\psi",        "\u{03C8}"),  // ψ
        ("\\omega",      "\u{03C9}"),  // ω
    ]
    for (cmd, ch) in greekLowerVar {
        table[cmd] = SymbolEntry(unicode: ch, atomType: .ord) // .ord → will be italicized like .variable
    }

    // ── Greek Variants (.ordinary — pre-styled math italic codepoints) ──
    // SwiftMath stores these as .ordinary with pre-computed math-italic chars.
    // This prevents double-italicization and ensures correct glyphs.
    let greekVariants: [(String, String)] = [
        ("\\epsilon",    "\u{03F5}"),   // ϵ (lunate, rendered via mathItalicize)
        ("\\varepsilon", "\u{1D700}"),  // 𝜀
        ("\\vartheta",   "\u{1D717}"),  // 𝜗
        ("\\phi",        "\u{1D719}"),  // 𝜙
        ("\\varphi",     "\u{1D711}"),  // 𝜑
        ("\\varrho",     "\u{1D71A}"),  // 𝜚
        ("\\varpi",      "\u{1D71B}"),  // 𝜛
        ("\\varsigma",   "\u{03C2}"),   // ς (final sigma)
        ("\\varkappa",   "\u{03F0}"),   // ϰ
    ]
    for (cmd, ch) in greekVariants {
        table[cmd] = SymbolEntry(unicode: ch, atomType: .ord)
    }

    // ── Greek Uppercase (.variable) ──
    let greekUpper: [(String, String)] = [
        ("\\Gamma",      "\u{0393}"),  // Γ
        ("\\Delta",      "\u{0394}"),  // Δ
        ("\\Theta",      "\u{0398}"),  // Θ
        ("\\Lambda",     "\u{039B}"),  // Λ
        ("\\Xi",         "\u{039E}"),  // Ξ
        ("\\Pi",         "\u{03A0}"),  // Π
        ("\\Sigma",      "\u{03A3}"),  // Σ
        ("\\Upsilon",    "\u{03A5}"),  // Υ
        ("\\Phi",        "\u{03A6}"),  // Φ
        ("\\Psi",        "\u{03A8}"),  // Ψ
        ("\\Omega",      "\u{03A9}"),  // Ω
    ]
    for (cmd, ch) in greekUpper {
        table[cmd] = SymbolEntry(unicode: ch, atomType: .ord)
    }

    // ── Open Delimiters ──────────────────────────────────────────────
    let opens: [(String, String)] = [
        ("\\lceil",      "\u{2308}"),  // ⌈
        ("\\lfloor",     "\u{230A}"),  // ⌊
        ("\\langle",     "\u{27E8}"),  // ⟨
        ("\\lgroup",     "\u{27EE}"),  // ⟮
    ]
    for (cmd, ch) in opens {
        table[cmd] = SymbolEntry(unicode: ch, atomType: .open)
    }

    // ── Close Delimiters ─────────────────────────────────────────────
    let closes: [(String, String)] = [
        ("\\rceil",      "\u{2309}"),  // ⌉
        ("\\rfloor",     "\u{230B}"),  // ⌋
        ("\\rangle",     "\u{27E9}"),  // ⟩
        ("\\rgroup",     "\u{27EF}"),  // ⟯
    ]
    for (cmd, ch) in closes {
        table[cmd] = SymbolEntry(unicode: ch, atomType: .close)
    }

    // ── Arrows ───────────────────────────────────────────────────────
    let arrows: [(String, String)] = [
        ("\\leftarrow",       "\u{2190}"),  // ←
        ("\\uparrow",         "\u{2191}"),  // ↑
        ("\\rightarrow",      "\u{2192}"),  // →
        ("\\downarrow",       "\u{2193}"),  // ↓
        ("\\leftrightarrow",  "\u{2194}"),  // ↔
        ("\\updownarrow",     "\u{2195}"),  // ↕
        ("\\nwarrow",         "\u{2196}"),  // ↖
        ("\\nearrow",         "\u{2197}"),  // ↗
        ("\\searrow",         "\u{2198}"),  // ↘
        ("\\swarrow",         "\u{2199}"),  // ↙
        ("\\mapsto",          "\u{21A6}"),  // ↦
        ("\\Leftarrow",       "\u{21D0}"),  // ⇐
        ("\\Uparrow",         "\u{21D1}"),  // ⇑
        ("\\Rightarrow",      "\u{21D2}"),  // ⇒
        ("\\Downarrow",       "\u{21D3}"),  // ⇓
        ("\\Leftrightarrow",  "\u{21D4}"),  // ⇔
        ("\\Updownarrow",     "\u{21D5}"),  // ⇕
        ("\\longleftarrow",   "\u{27F5}"),  // ⟵
        ("\\longrightarrow",  "\u{27F6}"),  // ⟶
        ("\\longleftrightarrow","\u{27F7}"),// ⟷
        ("\\Longleftarrow",   "\u{27F8}"),  // ⟸
        ("\\Longrightarrow",  "\u{27F9}"),  // ⟹
        ("\\Longleftrightarrow","\u{27FA}"),// ⟺
        ("\\longmapsto",      "\u{27FC}"),  // ⟼
        ("\\hookrightarrow",  "\u{21AA}"),  // ↪
        ("\\hookleftarrow",   "\u{21A9}"),  // ↩
    ]
    for (cmd, ch) in arrows {
        table[cmd] = SymbolEntry(unicode: ch, atomType: .rel)
    }

    // ── Arrow aliases ────────────────────────────────────────────────
    let arrowAliases: [(String, String)] = [
        ("\\to",              "\u{2192}"),  // →
        ("\\gets",            "\u{2190}"),  // ←
        ("\\iff",             "\u{27FA}"),  // ⟺
        ("\\implies",         "\u{27F9}"),  // ⟹
        ("\\impliedby",       "\u{27F8}"),  // ⟸
        ("\\imply",           "\u{27F9}"),  // ⟹
    ]
    for (cmd, ch) in arrowAliases {
        table[cmd] = SymbolEntry(unicode: ch, atomType: .rel)
    }

    // ── Binary Operators ─────────────────────────────────────────────
    let binaryOps: [(String, String)] = [
        ("\\times",      "\u{00D7}"),  // ×
        ("\\div",        "\u{00F7}"),  // ÷
        ("\\pm",         "\u{00B1}"),  // ±
        ("\\dagger",     "\u{2020}"),  // †
        ("\\ddagger",    "\u{2021}"),  // ‡
        ("\\mp",         "\u{2213}"),  // ∓
        ("\\setminus",   "\u{2216}"),  // ∖
        ("\\ast",        "\u{2217}"),  // ∗
        ("\\circ",       "\u{2218}"),  // ∘
        ("\\bullet",     "\u{2219}"),  // ∙
        ("\\wedge",      "\u{2227}"),  // ∧
        ("\\vee",        "\u{2228}"),  // ∨
        ("\\cap",        "\u{2229}"),  // ∩
        ("\\cup",        "\u{222A}"),  // ∪
        ("\\wr",         "\u{2240}"),  // ≀
        ("\\uplus",      "\u{228E}"),  // ⊎
        ("\\sqcap",      "\u{2293}"),  // ⊓
        ("\\sqcup",      "\u{2294}"),  // ⊔
        ("\\oplus",      "\u{2295}"),  // ⊕
        ("\\ominus",     "\u{2296}"),  // ⊖
        ("\\otimes",     "\u{2297}"),  // ⊗
        ("\\oslash",     "\u{2298}"),  // ⊘
        ("\\odot",       "\u{2299}"),  // ⊙
        ("\\star",       "\u{22C6}"),  // ⋆
        ("\\cdot",       "\u{22C5}"),  // ⋅
        ("\\diamond",    "\u{22C4}"),  // ⋄
        ("\\amalg",      "\u{2A3F}"),  // ⨿
        // Additional binary ops (amssymb)
        ("\\ltimes",         "\u{22C9}"),  // ⋉
        ("\\rtimes",         "\u{22CA}"),  // ⋊
        ("\\circledast",     "\u{229B}"),  // ⊛
        ("\\circledcirc",    "\u{229A}"),  // ⊚
        ("\\circleddash",    "\u{229D}"),  // ⊝
        ("\\boxdot",         "\u{22A1}"),  // ⊡
        ("\\boxminus",       "\u{229F}"),  // ⊟
        ("\\boxplus",        "\u{229E}"),  // ⊞
        ("\\boxtimes",       "\u{22A0}"),  // ⊠
        ("\\divideontimes",  "\u{22C7}"),  // ⋇
        ("\\dotplus",        "\u{2214}"),  // ∔
        ("\\lhd",            "\u{22B2}"),  // ⊲
        ("\\rhd",            "\u{22B3}"),  // ⊳
        ("\\unlhd",          "\u{22B4}"),  // ⊴
        ("\\unrhd",          "\u{22B5}"),  // ⊵
        ("\\intercal",       "\u{22BA}"),  // ⊺
        ("\\barwedge",       "\u{22BC}"),  // ⊼
        ("\\veebar",         "\u{22BB}"),  // ⊻
        ("\\curlywedge",     "\u{22CF}"),  // ⋏
        ("\\curlyvee",       "\u{22CE}"),  // ⋎
        ("\\doublebarwedge", "\u{2A5E}"),  // ⩞
        ("\\centerdot",      "\u{22C5}"),  // ⋅ (alias for cdot)
        ("\\land",           "\u{2227}"),  // ∧ (alias for wedge)
        ("\\lor",            "\u{2228}"),  // ∨ (alias for vee)
    ]
    for (cmd, ch) in binaryOps {
        table[cmd] = SymbolEntry(unicode: ch, atomType: .bin)
    }

    // ── Relations ────────────────────────────────────────────────────
    let relations: [(String, String)] = [
        ("\\leq",        "\u{2264}"),  // ≤
        ("\\geq",        "\u{2265}"),  // ≥
        ("\\leqslant",   "\u{2A7D}"),  // ⩽
        ("\\geqslant",   "\u{2A7E}"),  // ⩾
        ("\\neq",        "\u{2260}"),  // ≠
        ("\\in",         "\u{2208}"),  // ∈
        ("\\notin",      "\u{2209}"),  // ∉
        ("\\ni",         "\u{220B}"),  // ∋
        ("\\propto",     "\u{221D}"),  // ∝
        ("\\mid",        "\u{2223}"),  // ∣
        ("\\parallel",   "\u{2225}"),  // ∥
        ("\\sim",        "\u{223C}"),  // ∼
        ("\\simeq",      "\u{2243}"),  // ≃
        ("\\cong",       "\u{2245}"),  // ≅
        ("\\approx",     "\u{2248}"),  // ≈
        ("\\asymp",      "\u{224D}"),  // ≍
        ("\\doteq",      "\u{2250}"),  // ≐
        ("\\equiv",      "\u{2261}"),  // ≡
        ("\\gg",         "\u{226B}"),  // ≫
        ("\\ll",         "\u{226A}"),  // ≪
        ("\\prec",       "\u{227A}"),  // ≺
        ("\\succ",       "\u{227B}"),  // ≻
        ("\\preceq",     "\u{2AAF}"),  // ⪯
        ("\\succeq",     "\u{2AB0}"),  // ⪰
        ("\\subset",     "\u{2282}"),  // ⊂
        ("\\supset",     "\u{2283}"),  // ⊃
        ("\\subseteq",   "\u{2286}"),  // ⊆
        ("\\supseteq",   "\u{2287}"),  // ⊇
        ("\\sqsubset",   "\u{228F}"),  // ⊏
        ("\\sqsupset",   "\u{2290}"),  // ⊐
        ("\\sqsubseteq", "\u{2291}"),  // ⊑
        ("\\sqsupseteq", "\u{2292}"),  // ⊒
        ("\\models",     "\u{22A7}"),  // ⊧
        ("\\vdash",      "\u{22A2}"),  // ⊢
        ("\\dashv",      "\u{22A3}"),  // ⊣
        ("\\bowtie",     "\u{22C8}"),  // ⋈
        ("\\perp",       "\u{27C2}"),  // ⟂
        ("\\smile",      "\u{2323}"),  // ⌣
        ("\\frown",      "\u{2322}"),  // ⌢
        // Negated relations (amssymb)
        ("\\nless",          "\u{226E}"),  // ≮
        ("\\ngtr",           "\u{226F}"),  // ≯
        ("\\nleq",           "\u{2270}"),  // ≰
        ("\\ngeq",           "\u{2271}"),  // ≱
        ("\\nleqslant",      "\u{2A87}"),  // ⪇
        ("\\ngeqslant",      "\u{2A88}"),  // ⪈
        ("\\lneq",           "\u{2A87}"),  // ⪇
        ("\\gneq",           "\u{2A88}"),  // ⪈
        ("\\lneqq",          "\u{2268}"),  // ≨
        ("\\gneqq",          "\u{2269}"),  // ≩
        ("\\lnsim",          "\u{22E6}"),  // ⋦
        ("\\gnsim",          "\u{22E7}"),  // ⋧
        ("\\lnapprox",       "\u{2A89}"),  // ⪉
        ("\\gnapprox",       "\u{2A8A}"),  // ⪊
        ("\\nprec",          "\u{2280}"),  // ⊀
        ("\\nsucc",          "\u{2281}"),  // ⊁
        ("\\npreceq",        "\u{22E0}"),  // ⋠
        ("\\nsucceq",        "\u{22E1}"),  // ⋡
        ("\\precneqq",       "\u{2AB5}"),  // ⪵
        ("\\succneqq",       "\u{2AB6}"),  // ⪶
        ("\\precnsim",       "\u{22E8}"),  // ⋨
        ("\\succnsim",       "\u{22E9}"),  // ⋩
        ("\\precnapprox",    "\u{2AB9}"),  // ⪹
        ("\\succnapprox",    "\u{2ABA}"),  // ⪺
        ("\\nsim",           "\u{2241}"),  // ≁
        ("\\ncong",          "\u{2247}"),  // ≇
        ("\\nmid",           "\u{2224}"),  // ∤
        ("\\nshortmid",      "\u{2224}"),  // ∤
        ("\\nparallel",      "\u{2226}"),  // ∦
        ("\\nshortparallel", "\u{2226}"),  // ∦
        ("\\nsubseteq",      "\u{2288}"),  // ⊈
        ("\\nsupseteq",      "\u{2289}"),  // ⊉
        ("\\subsetneq",      "\u{228A}"),  // ⊊
        ("\\supsetneq",      "\u{228B}"),  // ⊋
        ("\\subsetneqq",     "\u{2ACB}"),  // ⫋
        ("\\supsetneqq",     "\u{2ACC}"),  // ⫌
        ("\\varsubsetneq",   "\u{228A}"),  // ⊊
        ("\\varsupsetneq",   "\u{228B}"),  // ⊋
        ("\\varsubsetneqq",  "\u{2ACB}"),  // ⫋
        ("\\varsupsetneqq",  "\u{2ACC}"),  // ⫌
        ("\\notni",          "\u{220C}"),  // ∌
        ("\\nni",            "\u{220C}"),  // ∌
        ("\\ntriangleleft",  "\u{22EA}"),  // ⋪
        ("\\ntriangleright", "\u{22EB}"),  // ⋫
        ("\\ntrianglelefteq","\u{22EC}"),  // ⋬
        ("\\ntrianglerighteq","\u{22ED}"), // ⋭
        ("\\nvdash",         "\u{22AC}"),  // ⊬
        ("\\nvDash",         "\u{22AD}"),  // ⊭
        ("\\nVdash",         "\u{22AE}"),  // ⊮
        ("\\nVDash",         "\u{22AF}"),  // ⊯
        ("\\nsqsubseteq",    "\u{22E2}"),  // ⋢
        ("\\nsqsupseteq",    "\u{22E3}"),  // ⋣
    ]
    for (cmd, ch) in relations {
        table[cmd] = SymbolEntry(unicode: ch, atomType: .rel)
    }

    // ── Miscellaneous Symbols (.ordinary) ────────────────────────────
    // These match SwiftMath's atom types exactly.
    // Note: partial uses math-italic codepoint (U+1D715), marked .ord
    // so mathItalicize won't double-process it.
    let misc: [(String, String)] = [
        ("\\infty",      "\u{221E}"),  // ∞
        ("\\partial",    "\u{1D715}"), // 𝜕 (math-italic, SwiftMath style)
        ("\\nabla",      "\u{2207}"),  // ∇
        ("\\forall",     "\u{2200}"),  // ∀
        ("\\exists",     "\u{2203}"),  // ∃
        ("\\nexists",    "\u{2204}"),  // ∄
        ("\\neg",        "\u{00AC}"),  // ¬
        ("\\lnot",       "\u{00AC}"),  // ¬
        ("\\emptyset",   "\u{2205}"),  // ∅
        ("\\varnothing", "\u{2205}"),  // ∅
        ("\\angle",      "\u{2220}"),  // ∠
        ("\\measuredangle","\u{2221}"), // ∡
        ("\\triangle",   "\u{25B3}"),  // △
        ("\\square",     "\u{25A1}"),  // □
        ("\\Box",        "\u{25A1}"),  // □
        ("\\Diamond",    "\u{25C7}"),  // ◇
        ("\\mho",        "\u{2127}"),  // ℧
        ("\\hbar",       "\u{210F}"),  // ℏ
        ("\\ell",        "\u{2113}"),  // ℓ
        ("\\wp",         "\u{2118}"),  // ℘
        ("\\Re",         "\u{211C}"),  // ℜ
        ("\\Im",         "\u{2111}"),  // ℑ
        ("\\aleph",      "\u{2135}"),  // ℵ
        ("\\beth",       "\u{2136}"),  // ℶ
        ("\\gimel",      "\u{2137}"),  // ℷ
        ("\\daleth",     "\u{2138}"),  // ℸ
        ("\\top",        "\u{22A4}"),  // ⊤
        ("\\bot",        "\u{22A5}"),  // ⊥
        ("\\flat",       "\u{266D}"),  // ♭
        ("\\natural",    "\u{266E}"),  // ♮
        ("\\sharp",      "\u{266F}"),  // ♯
        ("\\clubsuit",   "\u{2663}"),  // ♣
        ("\\diamondsuit","\u{2662}"),  // ♢
        ("\\heartsuit",  "\u{2661}"),  // ♡
        ("\\spadesuit",  "\u{2660}"),  // ♠
        ("\\ldots",      "\u{2026}"),  // …
        ("\\cdots",      "\u{22EF}"),  // ⋯
        ("\\vdots",      "\u{22EE}"),  // ⋮
        ("\\ddots",      "\u{22F1}"),  // ⋱
        ("\\dots",       "\u{2026}"),  // … (synonym for \ldots)
        ("\\prime",      "\u{2032}"),  // ′
        ("\\backprime",  "\u{2035}"),  // ‵
        ("\\surd",       "\u{221A}"),  // √
        ("\\checkmark",  "\u{2713}"),  // ✓
        ("\\maltese",    "\u{2720}"),  // ✠
        ("\\Bbbk",       "\u{1D55C}"), // 𝕜
        ("\\imath",      "\u{0131}"),  // ı
        ("\\jmath",      "\u{0237}"),  // ȷ
        ("\\pounds",     "\u{00A3}"),  // £
        ("\\yen",        "\u{00A5}"),  // ¥
        ("\\circledR",   "\u{00AE}"),  // ®
        ("\\S",          "\u{00A7}"),  // §
        ("\\P",          "\u{00B6}"),  // ¶
        ("\\copyright",  "\u{00A9}"),  // ©
        ("\\degree",     "\u{00B0}"),  // °
        ("\\angstrom",   "\u{00C5}"),  // Å
        ("\\lbar",       "\u{019B}"),  // ƛ
        ("\\colon",      "\u{003A}"),  // :  (punctuation colon)
        ("\\cdotp",      "\u{00B7}"),  // ·  (punctuation centered dot)
        ("\\vert",       "\u{007C}"),  // |
        ("\\upquote",    "\u{0027}"),  // '
    ]
    for (cmd, ch) in misc {
        table[cmd] = SymbolEntry(unicode: ch, atomType: .ord)
    }

    // ── Punctuation ─────────────────────────────────────────────────
    table["\\colon"] = SymbolEntry(unicode: "\u{003A}", atomType: .punct)
    table["\\cdotp"] = SymbolEntry(unicode: "\u{00B7}", atomType: .punct)

    // ── Special characters ──────────────────────────────────────────
    let specials: [(String, String, AtomType)] = [
        ("\\{",     "{",  .open),
        ("\\}",     "}",  .close),
        ("\\$",     "$",  .ord),
        ("\\&",     "&",  .ord),
        ("\\#",     "#",  .ord),
        ("\\%",     "%",  .ord),
        ("\\_",     "_",  .ord),
        ("\\backslash", "\\", .ord),
    ]
    for (cmd, ch, at) in specials {
        table[cmd] = SymbolEntry(unicode: ch, atomType: at)
    }

    return table
}()

// MARK: - Command List

public let allSymbolCommands: [String] = Array(symbolTable.keys)

// MARK: - Font Command Handler

/// Handles font style commands like \mathbf{F}, \mathrm{x}, \mathbb{R}, etc.
/// Currently passes through the braced content (font styles not yet implemented).
func handleFontCommand(tokens: ArraySlice<Token>, index: inout Int) -> ASTNode? {
    guard tokens.count >= 2, tokens[tokens.startIndex + 1].kind == .leftBrace else {
        // No argument — skip the command token
        index = 1
        return nil
    }
    // Find matching right brace
    var depth = 1
    var braceTokens: [Token] = []
    var i = tokens.startIndex + 2
    while i < tokens.endIndex, depth > 0 {
        let t = tokens[i]
        if t.kind == .leftBrace { depth += 1 }
        else if t.kind == .rightBrace { depth -= 1 }
        if depth > 0 { braceTokens.append(t) }
        i += 1
    }
    // Parse the content inside braces
    let parser = LatexParser()
    let content = parser.parse(tokens: braceTokens)
    // Return as a group node (font style metadata is lost for now)
    index = i - tokens.startIndex
    if content.count == 1 {
        return content[0]
    }
    return ASTNode(type: .ordgroup, text: nil, childNodes: content.isEmpty ? nil : content)
}

// MARK: - Spacing Command Handler

func handleSpacingCommand(tokens: ArraySlice<Token>, index: inout Int) -> ASTNode? {
    guard let token = tokens.first else { return nil }
    let cmd = token.text
    let spaceText: String
    switch cmd {
    case "\\quad":   spaceText = "quad"
    case "\\qquad":  spaceText = "qquad"
    case "\\,":      spaceText = "thin"
    case "\\;":      spaceText = "thick"
    case "\\!":      spaceText = "negative"
    default:         return nil
    }
    index = 1
    return ASTNode(type: .spacing, text: spaceText, location: token.sourceLocation, originalText: cmd)
}

// MARK: - Symbol Command Handler

func handleSymbolCommand(tokens: ArraySlice<Token>, index: inout Int) -> ASTNode? {
    guard let token = tokens.first else { return nil }
    let cmd = token.text
    guard let entry = symbolTable[cmd] else { return nil }

    let nodeType: ASTNodeType
    switch entry.atomType {
    case .ord:   nodeType = .mathord
    case .bin:   nodeType = .bin
    case .rel:   nodeType = .rel
    case .op:    nodeType = .op
    case .open:  nodeType = .open
    case .close: nodeType = .close
    case .punct: nodeType = .punct
    case .inner: nodeType = .mathord
    }

    index = 1
    return ASTNode(type: nodeType, text: entry.unicode, location: token.sourceLocation,
                   originalText: cmd)
}
