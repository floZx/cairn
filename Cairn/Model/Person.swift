import Foundation
import SwiftData

/// La fiche d'une personne citée dans les notes.
///
/// **Elle n'existe que pour porter sa note.** La liste des gens, elle, se
/// déduit des textes — comme les tags, et pour la même raison : une citation
/// est un fait sur le texte, et une copie en base est une copie qui se périme.
/// Effacer « @sam » de la dernière note où il figurait le fait disparaître de
/// la liste sans qu'aucune ligne n'ait à être supprimée.
///
/// Une ligne naît donc au moment où l'on écrit quelque chose **sur** la
/// personne, jamais au moment où on la cite.
@Model
final class Person {
    #Unique<Person>([\.key])

    /// Identité locale stable, indépendante de tout service.
    var uuid: String = UUID().uuidString

    /// Le pseudo replié — sans casse ni accents. C'est lui qui identifie.
    var key: String = ""

    /// Le pseudo tel qu'il a été écrit : c'est ce qui s'affiche.
    var name: String = ""

    /// Ce qu'on a à dire d'elle, en markdown comme les autres notes.
    var note: String = ""

    /// Les autres noms sous lesquels on la cite — « Chris », « Chérie » pour
    /// Christèle —, tels qu'écrits.
    ///
    /// Dans un sens seulement : ce sont les alias de **cette** fiche, dont le
    /// nom reste le principal. Une mention `@Chris` est ramenée à elle partout
    /// où l'on compte et où l'on ouvre — voir `PeopleIndex.Annuaire` —, mais
    /// le texte garde le mot écrit.
    ///
    /// Porter des alias suffit à faire exister la fiche, note vide ou non.
    var aliases: [String] = []

    init(handle: PersonHandle, note: String = "") {
        self.key = handle.key
        self.name = handle.name
        self.note = note
    }

    var handle: PersonHandle? { PersonHandle(name: name) }
}
