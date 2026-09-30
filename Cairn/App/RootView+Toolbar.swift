import SwiftUI
import SwiftData

// The window's two toolbars: the list's actions, and the pane's.
extension RootView {
    @ToolbarContentBuilder
    var syncToolbar: some ToolbarContent {
            ToolbarItem(placement: .status) {
                if app.progress.isRunning {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text(app.progress.toolbarText)
                            .font(.caption)
                            .monospacedDigit()
                            .lineLimit(1)
                            // Reserved on the text alone, so the pill keeps a
                            // steady width as the counter ticks over without
                            // pinning its contents against one edge.
                            .frame(width: 96, alignment: .leading)
                    }
                    .help(app.progress.statusText)
                }
            }
            // Un `ControlGroup` en style `.navigation`, et non des
            // `ToolbarItem` côte à côte : macOS 26 coule tous les boutons
            // voisins dans une seule capsule, et `ToolbarSpacer` n'y change
            // rien dans cette fenêtre (essayé, fixe comme flexible).
            //
            // Plus de bouton de synchronisation : elle part seule au
            // lancement, et le menu comme ⌘R la relancent. Le « + » a rejoint
            // les actions sur les sorties — ajouter, modifier, favori,
            // supprimer, la destructive en dernier comme partout sur le Mac.
            if showsActivityActions {
                ToolbarItem {
                    ControlGroup {
                        Button {
                            editor = .create
                        } label: {
                            Label("Nouvelle activité", systemImage: "plus")
                        }
                        .help("Ajouter une activité saisie à la main")

                        Button {
                            if let selected { editor = .edit(selected) }
                        } label: {
                            Label("Modifier", systemImage: "pencil")
                        }
                        .disabled(selected == nil)
                        .help("Modifier l'activité sélectionnée")

                        Button {
                            toggleFavorite()
                        } label: {
                            // Filled when every selected activity is already a favourite,
                            // so the icon says what the button is about to do.
                            Label(
                                "Favori",
                                systemImage: selection.allSatisfy(\.isFavorite) && !selection.isEmpty
                                    ? "star.fill" : "star"
                            )
                        }
                        .disabled(selection.isEmpty)
                        .help("Marquer ou retirer des favoris")

                        Button {
                            pendingDeletion = selected
                        } label: {
                            Label("Supprimer", systemImage: "trash")
                        }
                        .disabled(selected == nil)
                        .help("Supprimer l'activité sélectionnée")
                    }
                    .controlGroupStyle(.navigation)
                }
            }
            if showsJournalSection {
                ToolbarItemGroup {
                    // Le même segmenté que la présentation des activités : le
                    // choix porte sur la façon de ranger ce qu'on a sous les
                    // yeux, pas sur l'endroit où l'on va.
                    Picker("Vue du journal", selection: $vueJournal) {
                        ForEach(VueJournal.allCases) { vue in
                            Label(vue.displayName, systemImage: vue.symbolName)
                                .tag(vue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelStyle(.iconOnly)
                    .help("Basculer entre les journées et les gens qui y sont cités")

                    // Écrire et supprimer, ce sont des gestes sur une note :
                    // devant la liste des gens ils n'ont rien à viser.
                    if showsJournal {
                        Button {
                            openTodaysNote()
                        } label: {
                            Label("Note du jour", systemImage: "square.and.pencil")
                        }
                        .help("Ouvrir la note d'aujourd'hui (⌘N)")

                        Button {
                            journalPendingDeletion = journalSelection
                        } label: {
                            Label("Supprimer", systemImage: "trash")
                        }
                        .disabled(!journalSelectionHasNote)
                        .help("Supprimer la note sélectionnée")
                    }
                }
            }
    }

    /// Le bouton du volet, à part du reste de la barre : posé sur la colonne
    /// de détail, il passe après le tri et la présentation que la liste
    /// déclare, et vient donc juste avant la recherche — la place du bouton
    /// d'inspecteur dans Xcode ou le Finder. Sur la colonne du milieu, il
    /// restait devant le tri : la barre d'une vue englobante passe avant
    /// celles qu'elle contient. Il reste affiché quand la colonne est
    /// refermée à zéro (Alimentation, volet masqué), essayé : sans quoi on
    /// ne pourrait plus la rouvrir. Plus à droite encore, après la
    /// recherche, n'est pas possible : `.searchable` se range toujours en
    /// dernier (essayé : `.primaryAction`, `.confirmationAction`, la colonne
    /// de détail, `.inspector`).
    @ToolbarContentBuilder
    var panelToolbar: some ToolbarContent {
            // Kept in place and merely disabled rather than appearing with the
            // selection: a toolbar whose buttons come and go is unsettling, and
            // this way the affordance is visible before it is needed.
            ToolbarItem {
                Button {
                    // In the food journal the pane is not driven by a
                    // selection, so the same button toggles the side panel
                    // instead of clearing a selection it doesn't have.
                    if showsNutrition {
                        nutritionPanelVisible.toggle()
                    } else if showsPeople {
                        // Le volet des gens suit la personne choisie, comme
                        // celui du journal suit la note.
                        selectedPerson = nil
                    } else if showsJournal {
                        // Le volet du journal reste ouvert : le bouton y est
                        // grisé, et rien ne se fait si ⌥⌘I passe quand même.
                    } else if showsStatistics {
                        // Vider la sélection ne fermait rien ici : le volet
                        // suit le drapeau, et la sélection appartient à la
                        // liste d'activités — voir `sortieOuverteDepuisLEcran`.
                        sortieOuverteDepuisLEcran = false
                    } else {
                        selectedActivities = []
                    }
                } label: {
                    Label("Fermer le panneau", systemImage: "sidebar.trailing")
                }
                // A letter, not a digit: on an AZERTY keyboard the top row
                // needs shift for its numbers, so ⌥⌘0 is really ⇧⌥⌘0 and half
                // unreachable. ⌥⌘I is the Finder's inspector shortcut, and this
                // is the same pane on the same side.
                .keyboardShortcut("i", modifiers: [.option, .command])
                // The button needs something to act on — a selected note in
                // the journal, a selected activity anywhere else.
                .disabled(
                    // Le journal et les gens gardent toujours leur volet
                    // ouvert, sur une journée ou sur quelqu'un.
                    showsJournal
                        || showsPeople
                        || (showsStatistics && !sortieOuverteDepuisLEcran)
                        || (!showsNutrition && !showsJournal && !showsPeople
                            && !showsStatistics
                            && (selection.isEmpty || listStyle == .cards))
                )
                .help(
                    showsNutrition
                        ? (nutritionPanelVisible
                            ? "Fermer le panneau de droite (⌥⌘I)"
                            : "Rouvrir le panneau de droite (⌥⌘I)")
                        : "Fermer le panneau de droite et désélectionner (⌥⌘I)"
                )
            }
    }
}
