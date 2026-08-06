import SwiftUI

/// Everything about how the maps look and what they store locally.
struct MapSettingsView: View {
    @AppStorage(TrackColor.storageKey) private var trackColor: TrackColor = .accent
    /// Read when the pane appears rather than on every redraw: walking the
    /// cache directory is cheap but not free.
    @State private var cacheSize = MapSettingsView.formattedCacheSize()

    var body: some View {
        Form {
            Section("Traces") {
                Picker("Couleur des traces", selection: $trackColor) {
                    ForEach(TrackColor.allCases) { choice in
                        Label {
                            Text(choice.displayName)
                        } icon: {
                            Image(systemName: "circle.fill")
                                .foregroundStyle(choice.color)
                        }
                        .tag(choice)
                    }
                }
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
