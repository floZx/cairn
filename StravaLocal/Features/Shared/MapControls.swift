import SwiftUI

extension View {
    /// Standard treatment for a control floating over a map: a plain button has
    /// no contrast against either a pale topographic tile or a dark satellite
    /// image, so every one of them carries the same translucent backing.
    func mapControl() -> some View {
        padding(6)
            .background(.regularMaterial, in: .rect(cornerRadius: 6))
    }
}

/// Compact background picker, shared by every map in the app.
struct MapStylePicker: View {
    @Binding var style: MapStyle

    var body: some View {
        Menu {
            Picker("Fond de carte", selection: $style) {
                ForEach(MapStyle.allCases) { style in
                    Label(style.displayName, systemImage: style.symbolName)
                        .tag(style)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Label(style.displayName, systemImage: style.symbolName)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .mapControl()
        .help("Choisir le fond de carte")
    }
}

/// Shown only where a licence requires it.
struct MapAttribution: View {
    let style: MapStyle

    var body: some View {
        if let source = style.tileSource {
            Text(source.attribution)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(4)
                .background(.regularMaterial, in: .rect(cornerRadius: 4))
        }
    }
}
