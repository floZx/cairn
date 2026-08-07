import SwiftUI

/// Everything about how the maps look and what they store locally.
struct MapSettingsView: View {
    @AppStorage(TrackColor.storageKey) private var trackColor: TrackColor = .accent
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
