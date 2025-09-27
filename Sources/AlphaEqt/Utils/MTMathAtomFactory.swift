//
//  MTMathAtomFactory.swift
//  AlphaEqt
//
//  Created by Alpha Ng on 28/9/2025.
//

import Foundation

actor SupportedAccentedCharactersActor {
    private let _supportedAccentedCharacters: [Character: (String, String)] = [
        // Acute accents
        "á": ("acute", "a"), "é": ("acute", "e"), "í": ("acute", "i"),
        "ó": ("acute", "o"), "ú": ("acute", "u"), "ý": ("acute", "y"),
        // Grave accents
        "à": ("grave", "a"), "è": ("grave", "e"), "ì": ("grave", "i"),
        "ò": ("grave", "o"), "ù": ("grave", "u"),
        // Circumflex
        "â": ("hat", "a"), "ê": ("hat", "e"), "î": ("hat", "i"),
        "ô": ("hat", "o"), "û": ("hat", "u"),
        // Umlaut/dieresis
        "ä": ("ddot", "a"), "ë": ("ddot", "e"), "ï": ("ddot", "i"),
        "ö": ("ddot", "o"), "ü": ("ddot", "u"), "ÿ": ("ddot", "y"),
        // Tilde
        "ã": ("tilde", "a"), "ñ": ("tilde", "n"), "õ": ("tilde", "o"),
        // Special characters
        "ç": ("cc", ""), "ø": ("o", ""), "å": ("aa", ""), "æ": ("ae", ""),
        "œ": ("oe", ""), "ß": ("ss", ""),
        "'": ("upquote", ""),
        // Upper case variants
        "Á": ("acute", "A"), "É": ("acute", "E"), "Í": ("acute", "I"),
        "Ó": ("acute", "O"), "Ú": ("acute", "U"), "Ý": ("acute", "Y"),
        "À": ("grave", "A"), "È": ("grave", "E"), "Ì": ("grave", "I"),
        "Ò": ("grave", "O"), "Ù": ("grave", "U"),
        "Â": ("hat", "A"), "Ê": ("hat", "E"), "Î": ("hat", "I"),
        "Ô": ("hat", "O"), "Û": ("hat", "U"),
        "Ä": ("ddot", "A"), "Ë": ("ddot", "E"), "Ï": ("ddot", "I"),
        "Ö": ("ddot", "O"), "Ü": ("ddot", "U"),
        "Ã": ("tilde", "A"), "Ñ": ("tilde", "N"), "Õ": ("tilde", "O"),
        "Ç": ("CC", ""),
        "Ø": ("O", ""),
        "Å": ("AA", ""),
        "Æ": ("AE", ""),
        "Œ": ("OE", "")
    ]

    func get() -> [Character: (String, String)] {
        return _supportedAccentedCharacters
    }

    func getValue(for key: Character) -> (String, String)? {
        return _supportedAccentedCharacters[key]
    }
}


/** A factory to create commonly used MTMathAtoms. */
public class MTMathAtomFactory {
    
    public static let aliases = [
        "lnot" : "neg",
        "land" : "wedge",
        "lor" : "vee",
        "ne" : "neq",
        "le" : "leq",
        "ge" : "geq",
        "lbrace" : "{",
        "rbrace" : "}",
        "Vert" : "|",
        "gets" : "leftarrow",
        "to" : "rightarrow",
        "iff" : "Longleftrightarrow",
        "AA" : "angstrom"
    ]
    
    public static let delimiters = [
        "." : "", // . means no delimiter
        "(" : "(",
        ")" : ")",
        "[" : "[",
        "]" : "]",
        "<" : "\u{2329}",
        ">" : "\u{232A}",
        "/" : "/",
        "\\" : "\\",
        "|" : "|",
        "lgroup" : "\u{27EE}",
        "rgroup" : "\u{27EF}",
        "||" : "\u{2016}",
        "Vert" : "\u{2016}",
        "vert" : "|",
        "uparrow" : "\u{2191}",
        "downarrow" : "\u{2193}",
        "updownarrow" : "\u{2195}",
        "Uparrow" : "\u{21D1}",
        "Downarrow" : "\u{21D3}",
        "Updownarrow" : "\u{21D5}",
        "backslash" : "\\",
        "rangle" : "\u{232A}",
        "langle" : "\u{2329}",
        "rbrace" : "}",
        "}" : "}",
        "{" : "{",
        "lbrace" : "{",
        "lceil" : "\u{2308}",
        "rceil" : "\u{2309}",
        "lfloor" : "\u{230A}",
        "rfloor" : "\u{230B}"
    ]
    
    actor DelimValueToNameActor {
        private var _delimValueToName = [String: String]()

        func get(delimiters: [String: String]) -> [String: String] {
            if _delimValueToName.isEmpty {
                var output = [String: String]()
                for (key, value) in delimiters {
                    if let existingValue = output[value] {
                        if key.count > existingValue.count {
                            continue
                        } else if key.count == existingValue.count {
                            if key.compare(existingValue) == .orderedDescending {
                                continue
                            }
                        }
                    }
                    output[value] = key
                }
                _delimValueToName = output
            }
            return _delimValueToName
        }
    }
    
    private static let delimActor = DelimValueToNameActor()
    public static func getDelimValueToName() async -> [String: String] {
        await delimActor.get(delimiters: Self.delimiters)
    }
    
    public static let accents = [
        "grave" :  "\u{0300}",
        "acute" :  "\u{0301}",
        "hat" :  "\u{0302}",  // In our implementation hat and widehat behave the same.
        "tilde" :  "\u{0303}", // In our implementation tilde and widetilde behave the same.
        "bar" :  "\u{0304}",
        "breve" :  "\u{0306}",
        "dot" :  "\u{0307}",
        "ddot" :  "\u{0308}",
        "check" :  "\u{030C}",
        "vec" :  "\u{20D7}",
        "overrightarrow" : "\u{20D7}", //By Alpha
        "widehat" :  "\u{0302}",
        "widetilde" :  "\u{0303}",
        "arc" : "\u{23DC}" //By Alpha
    ]
    
    actor AccentValueToNameActor {
        private var _accentValueToName: [String: String]? = nil

        func getAccentValueToName(accents: [String: String]) -> [String: String] {
            if _accentValueToName == nil {
                var output = [String: String]()

                for (key, value) in accents {
                    if let existingValue = output[value] {
                        if key.count > existingValue.count {
                            continue
                        } else if key.count == existingValue.count {
                            if key.compare(existingValue) == .orderedDescending {
                                continue
                            }
                        }
                    }
                    output[value] = key
                }
                _accentValueToName = output
            }
            return _accentValueToName!
        }
    }
    
    private static let accentValueActor = AccentValueToNameActor()

    public static func accentValueToName() async -> [String: String] {
        await accentValueActor.getAccentValueToName(accents: accents)
    }
    
}
