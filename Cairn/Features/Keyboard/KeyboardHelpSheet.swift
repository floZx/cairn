import SwiftUI

/// The key map, on `?`.
///
/// A modal editor is only usable if its vocabulary is discoverable, and these
/// keys appear in no menu — a menu item would need a ⌘, which is the whole point
/// of not using one here.
struct KeyboardHelpSheet: View {
    let onClose: () -> Void

    private struct Group: Identifiable {
        let id = UUID()
        let title: String
        let rows: [(keys: String, what: String)]
    }

    private let groups: [Group] = [
        Group(title: "Se déplacer", rows: [
            ("j / k", "activité suivante / précédente"),
            ("5j", "cinq activités plus bas — tout mouvement prend un compte"),
            ("gg / G", "première / dernière activité"),
            ("⌃d / ⌃u", "une demi-page vers le bas / vers le haut"),
        ]),
        Group(title: "Changer de vue", rows: [
            ("ga", "mes activités"),
            ("gm", "carte globale"),
            ("gs", "statistiques"),
            ("gn", "alimentation"),
            ("gp", "poids"),
            ("t", "basculer tableau / fiches (⌥⌘L depuis partout)"),
        ]),
        Group(title: "Agir sur la sélection", rows: [
            ("e", "modifier"),
            ("n", "écrire les notes — l'éditeur s'ouvre dans le champ"),
            ("f", "favori"),
            ("x", "supprimer"),
            ("o", "ouvrir la carte en grand"),
            ("h", "fermer le volet de droite"),
        ]),
        Group(title: "Journal alimentaire", rows: [
            ("j / k", "ligne ou repas suivant / précédent"),
            ("a", "ajouter un aliment au repas sélectionné (pesée sur Poids)"),
            ("e / ⏎", "éditer l'aliment sélectionné"),
            ("x", "supprimer l'aliment sélectionné"),
            ("f", "étoile favori"),
            ("K / J", "remonter / descendre l'aliment"),
            ("n", "note du repas sélectionné"),
            ("c / s", "charger une recette / enregistrer le repas en recette"),
            ("t", "cycler le jour-type"),
            ("w", "nouvelle pesée"),
            ("← / →", "jour précédent / suivant — échap : aujourd'hui"),
        ]),
        Group(title: "Chercher", rows: [
            ("/", "aller au champ de recherche"),
            ("échap", "revenir à aujourd'hui (journal), vider la recherche, sinon la sélection"),
            ("⌥⌘I", "fermer le volet — depuis n'importe quelle vue"),
            ("?", "cet aide-mémoire"),
        ]),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Raccourcis clavier")
                .font(.title2.bold())
                .padding([.top, .horizontal])
                .padding(.bottom, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(groups) { group in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(group.title)
                                .font(.headline)
                            ForEach(group.rows, id: \.keys) { row in
                                HStack(alignment: .firstTextBaseline, spacing: 12) {
                                    Text(row.keys)
                                        .font(.system(.body, design: .monospaced))
                                        // A fixed gutter, for the same reason the
                                        // sport icons have one: ragged keys are
                                        // harder to scan than ragged prose.
                                        .frame(width: 76, alignment: .leading)
                                    Text(row.what)
                                        .foregroundStyle(.secondary)
                                    Spacer(minLength: 0)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom)
            }

            Divider()
            HStack {
                Text("Les raccourcis avec ⌘ restent dans les menus.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Fermer", action: onClose)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(12)
        }
        .frame(width: 480, height: 640)
    }
}
