import Foundation

/// Le pseudo d'une personne citée, sans son `@`.
///
/// Une valeur validée plutôt qu'une chaîne nue, pour la raison qui a valu
/// `JournalTag` : les deux règles qui décident de ce qui est un pseudo — les
/// caractères permis, et « pas que des chiffres » — appartiennent au type, pas
/// à chaque endroit qui en lit un.
///
/// La casse ne compte pas : `@Sam` et `@sam` sont la même personne, et c'est
/// la première orthographe rencontrée qui s'affiche. Deux entrées dans la
/// liste pour une majuscule seraient une punition pour avoir commencé une
/// phrase par un prénom.
struct PersonHandle: Hashable, Comparable, Sendable, Identifiable {
    /// Tel qu'il a été écrit la première fois — c'est ce qu'on affiche.
    let name: String

    /// Ce qui décide de l'identité : le pseudo replié, sans accents ni casse.
    ///
    /// Sans accents, et c'est un vrai choix : « @Hélène » tapé au clavier
    /// français et « @Helene » tapé à la hâte désignent la même personne, et
    /// rien ne serait plus agaçant que deux fiches pour elle.
    let key: String

    /// Les caractères qu'un pseudo accepte.
    ///
    /// Ni `.` ni `/` : le point clôt les phrases — « j'ai couru avec @sam. » —
    /// et une personne n'a pas de hiérarchie, contrairement à un tag.
    static func isAllowed(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_" || character == "-"
    }

    /// - Returns: nil quand ce n'en est pas un.
    init?(name: String) {
        let trimmed = name.trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
        guard !trimmed.isEmpty,
              trimmed.allSatisfy(Self.isAllowed),
              // La règle des tags, pour la même raison : `@2026` reste une
              // année.
              trimmed.contains(where: { !$0.isNumber })
        else { return nil }
        self.name = trimmed
        self.key = Self.replie(trimmed)
    }

    static func replie(_ texte: String) -> String {
        texte.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
    }

    var id: String { key }

    var displayName: String { "@\(name)" }

    static func == (lhs: PersonHandle, rhs: PersonHandle) -> Bool { lhs.key == rhs.key }
    func hash(into hasher: inout Hasher) { hasher.combine(key) }

    static func < (lhs: PersonHandle, rhs: PersonHandle) -> Bool {
        lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }
}

/// Tire les personnes citées d'un texte. Rien n'est stocké : une citation est
/// un fait sur le texte, et une copie en cache est une copie qui se périme —
/// la même raison qu'à `JournalTagScanner`, dont ceci est le jumeau.
enum PersonScanner {
    /// `@pseudo` dans le corps.
    ///
    /// Le `@` doit **ouvrir le mot** — début du texte, ou après une espace ou
    /// une ponctuation ouvrante. C'est cette seule règle qui écarte les
    /// adresses de courriel : dans `f.maisonnial@gmail.com`, le `@` suit un
    /// `l`, donc rien n'est cité. Sans elle, chaque adresse écrite dans une
    /// note aurait créé une personne nommée « gmail ».
    static func mentions(in text: String) -> Set<PersonHandle> {
        var trouves: Set<PersonHandle> = []
        var precedent: Character?
        var index = text.startIndex

        while index < text.endIndex {
            let caractere = text[index]
            defer {
                precedent = caractere
                index = text.index(after: index)
            }
            guard caractere == "@" else { continue }
            guard precedent == nil || precedent!.isWhitespace || Self.ouvrante(precedent!)
            else { continue }

            var fin = text.index(after: index)
            while fin < text.endIndex, PersonHandle.isAllowed(text[fin]) {
                fin = text.index(after: fin)
            }
            if let handle = PersonHandle(name: String(text[text.index(after: index)..<fin])) {
                trouves.insert(handle)
            }
        }
        return trouves
    }

    /// Ce qui peut précéder un `@` sans le disqualifier : une parenthèse
    /// ouvrante, un tiret de liste, un guillemet. « (@sam et moi) » cite bien
    /// Sam.
    private static func ouvrante(_ caractere: Character) -> Bool {
        "([{«\"'-–—*>".contains(caractere)
    }

    /// Les personnes citées dans plusieurs textes d'un coup.
    static func mentions(inAny textes: [String?]) -> Set<PersonHandle> {
        textes.compactMap { $0 }.reduce(into: Set<PersonHandle>()) {
            $0.formUnion(mentions(in: $1))
        }
    }
}
