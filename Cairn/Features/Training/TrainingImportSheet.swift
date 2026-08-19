import EventKit
import SwiftUI
import SwiftData

/// La feuille de reprise : quel calendrier, sur quelle période.
///
/// Un aperçu avant d'écrire, parce que la lecture des titres est une
/// devinette : mieux vaut voir « SL 18 km → Course, 18 km » sur trois lignes
/// que de découvrir trois cents séances mal rangées dans la grille.
struct TrainingImportSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var store = EKEventStore()
    @State private var acces: Acces = .aDemander
    @State private var calendriers: [EKCalendar] = []
    @State private var choisi: String?
    @State private var debut = DateKey(Date()).monthStart.date()
    @State private var fin = Calendar.current.date(byAdding: .month, value: 6, to: Date()) ?? Date()
    @State private var apercu: [TrainingCalendarImport.Evenement] = []
    @State private var importees: Int?
    /// Ce que le système a répondu, mot pour mot.
    @State private var diagnostic = ""

    private enum Acces { case aDemander, accorde, refuse }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Importer un plan depuis un calendrier")
                .font(.headline)
            Text("""
                Les séances sont importées dans Cairn, une fois. \
                Le calendrier n'est jamais modifié, et il ne sera plus relu ensuite.
                """)
                .font(.callout)
                .foregroundStyle(.secondary)

            switch acces {
            case .aDemander:
                ProgressView().frame(maxWidth: .infinity)
            case .refuse:
                VStack(alignment: .leading, spacing: 6) {
                    Label(
                        "Cairn n'a pas accès aux calendriers. Réglages système → "
                            + "Confidentialité et sécurité → Calendriers.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .foregroundStyle(.orange)
                    Text(diagnostic)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            case .accorde:
                Form {
                    Picker("Calendrier", selection: $choisi) {
                        Text("Choisir…").tag(nil as String?)
                        ForEach(calendriers, id: \.calendarIdentifier) { calendrier in
                            Text(calendrier.title).tag(calendrier.calendarIdentifier as String?)
                        }
                    }
                    DatePicker("Du", selection: $debut, displayedComponents: .date)
                    DatePicker("Au", selection: $fin, displayedComponents: .date)
                }
                .formStyle(.grouped)

                if let importees {
                    Label(
                        importees == 0
                            ? "Rien à importer : ces séances sont déjà dans Cairn."
                            : "\(importees) séance\(importees > 1 ? "s" : "") importée\(importees > 1 ? "s" : "").",
                        systemImage: "checkmark.circle"
                    )
                    .foregroundStyle(.green)
                } else if !apercu.isEmpty {
                    Text("\(apercu.count) séance\(apercu.count > 1 ? "s" : "") à importer")
                        .font(.callout.weight(.medium))
                    List(apercu.prefix(60), id: \.self.debut) { evenement in
                        let lu = TrainingImport.lire(evenement.titre)
                        HStack(spacing: 6) {
                            Text(evenement.dateKey.raw)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Image(systemName: lu.sport.symbolName)
                                .foregroundStyle(lu.sport.color)
                            Text(evenement.titre).lineLimit(1)
                        }
                    }
                    .frame(height: 200)
                }
            }

            HStack {
                Spacer()
                Button("Fermer", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                if acces == .accorde, importees == nil {
                    Button(apercu.isEmpty ? "Aperçu" : "Importer") {
                        apercu.isEmpty ? preparer() : ecrire()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(choisi == nil)
                }
            }
        }
        .padding(20)
        .frame(width: 520)
        .task { await demander() }
        // Un changement de calendrier ou de période invalide l'aperçu : le
        // bouton doit redemander « Aperçu » plutôt que d'écrire l'ancien.
        .onChange(of: choisi) { _, _ in apercu = [] }
        .onChange(of: debut) { _, _ in apercu = [] }
        .onChange(of: fin) { _, _ in apercu = [] }
    }

    private func demander() async {
        let reponse = await TrainingCalendarImport.demanderAcces(store)
        diagnostic = reponse.pourquoi
        guard reponse.accorde else {
            acces = .refuse
            return
        }
        calendriers = TrainingCalendarImport.calendriers(store)
        // Le calendrier d'entraînement, s'il porte ce nom : c'est celui qu'on
        // vient chercher, et le désigner d'avance épargne un menu déroulant.
        choisi = calendriers.first {
            $0.title.folding(options: .diacriticInsensitive, locale: nil)
                .localizedCaseInsensitiveContains("entrainement")
        }?.calendarIdentifier
        acces = .accorde
    }

    private func preparer() {
        guard let identifiant = choisi,
              let calendrier = calendriers.first(where: { $0.calendarIdentifier == identifiant }),
              let du = DateKey(debut) as DateKey?, let au = DateKey(fin) as DateKey?
        else { return }
        let existantes = ((try? context.fetch(FetchDescriptor<PlannedSession>())) ?? [])
            .map { (jour: $0.dateKeyRaw, titre: $0.title) }
        apercu = TrainingCalendarImport.aCreer(
            TrainingCalendarImport.evenements(de: calendrier, du: du, au: au, dans: store),
            deja: existantes
        )
        if apercu.isEmpty { importees = 0 }
    }

    private func ecrire() {
        importees = (try? TrainingCalendarImport.ecrire(apercu, dans: context)) ?? 0
        apercu = []
    }
}
