import SwiftUI
import SwiftData

/// Écrire ou modifier une séance.
///
/// La même feuille dans les deux cas : les champs sont les mêmes, et deux
/// vues jumelles auraient divergé au premier ajout de champ. `session` à
/// `nil` veut dire « nouvelle », et c'est la seule différence.
struct PlannedSessionSheet: View {
    let session: PlannedSession?
    let dateKey: DateKey

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    /// Le jour de la séance, modifiable.
    ///
    /// Un plan se déplace tout le temps — la séance de côte du mardi se fait le
    /// lundi soir — et sans ce champ il fallait supprimer puis réécrire.
    @State private var jour = Date()
    @State private var sport: SportType = .run
    @State private var title = ""
    @State private var distanceKm: Double?
    @State private var dureeMinutes: Double?
    @State private var denivele: Double?
    @State private var notes = ""
    @State private var dayType: DayType?
    /// Le clavier n'est pas demandé ici : la feuille s'ouvre sur le sport.
    @State private var notesFocus = false

    @Query(sort: \DayType.sortOrder) private var dayTypes: [DayType]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(session == nil ? "Nouvelle séance" : "Modifier la séance")
                .font(.headline)
            Form {
                DatePicker("Jour", selection: $jour, displayedComponents: .date)
                Picker("Sport", selection: $sport) {
                    ForEach(SportType.allCases) { type in
                        Label(type.displayName, systemImage: type.symbolName).tag(type)
                    }
                }
                TextField("Intitulé", text: $title, prompt: Text("6×45″ en côte"))

                // En kilomètres et en minutes, pas en unités de base : un plan
                // s'écrit « 18 km, 1 h 30 », jamais « 18000 m, 5400 s ». La
                // conversion se fait ici, une fois.
                OptionalNumberField(title: "Distance", unit: "km", value: $distanceKm)
                OptionalNumberField(title: "Durée", unit: "min", value: $dureeMinutes)
                OptionalNumberField(title: "Dénivelé", unit: "m", value: $denivele)

                Picker("Journée", selection: $dayType) {
                    Text("Aucune").tag(nil as DayType?)
                    ForEach(dayTypes) { type in
                        Text(type.name).tag(type as DayType?)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Notes").font(.caption).foregroundStyle(.secondary)
                    CompletingNoteEditor(
                        texte: $notes,
                        taille: NSFont.systemFontSize,
                        focus: $notesFocus
                    )
                        .frame(minHeight: 90)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(.quaternary)
                        )
                }
            }
            .formStyle(.grouped)

            HStack {
                if let session {
                    Button("Supprimer", role: .destructive) {
                        context.delete(session)
                        try? context.save()
                        dismiss()
                    }
                }
                Spacer()
                Button("Annuler", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Enregistrer") { enregistrer() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear(perform: charger)
    }

    private func charger() {
        jour = (session?.dateKey ?? dateKey).date()
        guard let session else { return }
        sport = session.sport
        title = session.title
        distanceKm = session.plannedDistance.map { $0 / 1000 }
        dureeMinutes = session.plannedDuration.map { $0 / 60 }
        denivele = session.plannedElevation
        notes = session.notes
        dayType = session.dayType
    }

    /// Le rang à donner à une séance qui arrive dans une journée : après
    /// celles qui y sont déjà, pour que l'ordre d'écriture soit l'ordre de
    /// lecture.
    private func rangSuivant(dans journee: String) -> Int {
        let voisines = (try? context.fetch(
            FetchDescriptor<PlannedSession>(
                // La chaîne sortie de la fermeture : un `#Predicate` ne sait
                // pas traverser une propriété d'une valeur capturée.
                predicate: #Predicate { $0.dateKeyRaw == journee }
            )
        )) ?? []
        return (voisines.map(\.sortOrder).max() ?? -1) + 1
    }

    private func enregistrer() {
        let destination = DateKey(jour)
        let cible = session ?? {
            let seance = PlannedSession(
                dateKey: destination, sportTypeRaw: sport.rawValue, title: title,
                sortOrder: rangSuivant(dans: destination.raw)
            )
            context.insert(seance)
            return seance
        }()

        // Déplacée : elle se range à la fin de sa nouvelle journée, sinon elle
        // y garderait le rang qu'elle avait dans l'ancienne et passerait
        // devant des séances écrites avant elle.
        if cible.dateKeyRaw != destination.raw {
            cible.sortOrder = rangSuivant(dans: destination.raw)
            cible.dateKeyRaw = destination.raw
        }
        cible.sportTypeRaw = sport.rawValue
        cible.title = title
        cible.plannedDistance = distanceKm.map { $0 * 1000 }
        cible.plannedDuration = dureeMinutes.map { $0 * 60 }
        cible.plannedElevation = denivele
        cible.notes = notes
        cible.dayType = dayType
        // Le budget calorique suit le plan, sans second geste — mais jamais
        // par-dessus un type déjà choisi pour ce jour-là. Voir
        // `TrainingNutrition.appliquer`.
        try? TrainingNutrition.appliquer(cible, dans: context)
        try? context.save()
        dismiss()
    }
}
