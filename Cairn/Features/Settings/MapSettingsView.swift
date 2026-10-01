import SwiftUI

/// Everything about how the maps look and what they store locally.
struct MapSettingsView: View {
    @AppStorage(TrackColor.storageKey) private var trackColor: TrackColor = .accent
    @AppStorage(MapStyle.darkLevelKey) private var darkLevel = MapStyle.defaultDarkLevel
    @AppStorage(MapNightTint.storageKey) private var nightTint: MapNightTint = .green
    /// Ce que le curseur montre pendant qu'on le tire. Le réglage n'est écrit
    /// qu'au lâcher : chaque valeur refait toutes les tuiles des cartes
    /// ouvertes, et les refaire à chaque pixel de glissé les faisait clignoter.
    @State private var darkDraft: Double?
    /// Read when the pane appears rather than on every redraw: walking the
    /// cache directory is cheap but not free.
    @State private var cacheSize = MapSettingsView.formattedCacheSize()

    var body: some View {
        Form {
            Section {
                Picker("Couleur des traces", selection: $trackColor) {
                    ForEach(TrackColor.allCases) { choice in
                        Label {
                            Text(choice.displayName)
                        } icon: {
                            Image(nsImage: choice.swatch)
                        }
                        .tag(choice)
                    }
                }
            } header: {
                Text("Traces")
            } footer: {
                // Said outright, because this setting no longer reaches every map:
                // the other two assign their own colours, and a preference that
                // silently applies to one place out of three is a puzzle.
                Text(
                    "S'applique à la carte d'une activité. La carte globale alterne "
                        + "les couleurs pour distinguer les tracés qui se "
                        + "superposent, et la carte de comparaison en attribue une "
                        + "par activité sélectionnée."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Assombrissement") {
                    HStack {
                        Slider(
                            value: Binding(
                                get: { darkDraft ?? darkLevel },
                                set: { darkDraft = $0 }
                            ),
                            in: 0...1, step: 0.05
                        ) {
                            Text("Assombrissement")
                        } minimumValueLabel: {
                            Text("Aucun")
                        } maximumValueLabel: {
                            Text("Fort")
                        } onEditingChanged: { editing in
                            guard !editing, let draft = darkDraft else { return }
                            darkLevel = draft
                            darkDraft = nil
                        }
                        .labelsHidden()
                        let shown = darkDraft ?? darkLevel
                        Text(shown == 0 ? "—" : "\(Int((shown * 100).rounded())) %")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 40, alignment: .trailing)
                    }
                }
                Picker("Teinte", selection: $nightTint) {
                    ForEach(MapNightTint.allCases) { tint in
                        Text(tint.displayName).tag(tint)
                    }
                }
                .disabled(darkLevel == 0)
            } header: {
                Text("Cartes topographiques en mode sombre")
            } footer: {
                Text("""
                    L'IGN et OpenTopoMap n'ont pas de carte de nuit : en mode \
                    sombre, Cairn passe leurs tuiles en négatif en gardant leurs \
                    couleurs, puis les assombrit d'autant et les teinte. « Aucun » \
                    les laisse claires.
                    """)
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Tuiles en cache", value: cacheSize)
                Button("Vider le cache des cartes") {
                    TileCache.clear()
                    cacheSize = Self.formattedCacheSize()
                }
                .disabled(TileCache.diskUsage == 0)
            } header: {
                Text("Fonds de carte")
            } footer: {
                Text("""
                    Les tuiles des fonds topographiques sont conservées sur le \
                    disque : une zone déjà consultée ne se retélécharge pas, même \
                    après un redémarrage. Les fonds d'Apple ont leur propre cache, \
                    géré par le système.
                    """)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { cacheSize = Self.formattedCacheSize() }
    }

    private static func formattedCacheSize() -> String {
        let bytes = TileCache.diskUsage
        guard bytes > 0 else { return "aucune" }
        return ByteCountFormatter.string(
            fromByteCount: Int64(bytes), countStyle: .file
        )
    }
}
