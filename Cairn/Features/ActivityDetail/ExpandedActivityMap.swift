import SwiftUI

/// La carte d'une sortie en plein volet, avec son profil d'altitude dessous.
///
/// Agrandie, la carte perdait le profil que la fiche pose juste sous elle :
/// on voyait où l'on était passé, plus ce que le terrain y faisait. Le profil
/// revient ici avec ce qu'il fait dans la fiche — le point qui suit la souris
/// sur la trace, et le tronçon tiré à la souris, avec sa pente et sa place
/// sur la carte. Demandé le 2 octobre 2026.
struct ExpandedActivityMap: View {
    let activity: Activity
    @Binding var style: MapStyle
    let trackColor: TrackColor

    @State private var hoverDistanceKm: Double?
    @State private var selection: ClosedRange<Double>?

    private var trackModel: ActivityTrackModel {
        ActivityTrackModelCache.model(for: activity)
    }

    var body: some View {
        let model = trackModel
        let profile = model.series.filter { $0.id == "altitude" }
        VStack(spacing: 0) {
            ActivityMapView(
                coordinates: model.coordinates,
                highlight: hoverDistanceKm.flatMap(model.coordinate(atKilometre:)),
                segment: selection.map {
                    model.coordinates(fromKilometre: $0.lowerBound, to: $0.upperBound)
                } ?? [],
                style: style,
                trackColor: trackColor
            )
            .mapChrome(style: $style)

            if !profile.isEmpty, activity.distance > 0 {
                StreamChartsView(
                    series: profile,
                    hoverDistanceKm: $hoverDistanceKm,
                    selection: $selection
                )
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.bar)
                .overlay(alignment: .top) { Divider() }
            }
        }
    }
}
