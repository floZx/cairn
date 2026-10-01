import Foundation

/// Ce qu'une plage choisie à la souris sur le profil d'altitude dit du
/// terrain : sa longueur, ce qu'elle monte et descend, et sa pente moyenne.
///
/// Calculé sur les points du graphique — six cents au plus, un tous les vingt
/// mètres sur une sortie de douze kilomètres —, interpolés aux deux bornes
/// pour que la plage commence et finisse là où on l'a tirée, pas au point le
/// plus proche.
struct ProfileSelection: Equatable, Sendable {
    let distanceKm: Double
    let gain: Double
    let loss: Double
    /// En pour cent, signée : négative en descente.
    let grade: Double

    /// Nil quand la plage ne couvre rien de mesurable.
    static func compute(points: [StreamPoint], from a: Double, to b: Double) -> ProfileSelection? {
        let start = min(a, b), end = max(a, b)
        guard end - start > 0.001, points.count > 1 else { return nil }
        guard let startAlt = altitude(at: start, in: points),
              let endAlt = altitude(at: end, in: points) else { return nil }

        // Le profil dans la plage : la borne de départ, les points mesurés
        // entre les deux, la borne d'arrivée.
        var profile = [startAlt]
        profile += points.filter { $0.distanceKm > start && $0.distanceKm < end }.map(\.value)
        profile.append(endAlt)

        var gain = 0.0, loss = 0.0
        for (before, after) in zip(profile, profile.dropFirst()) {
            let delta = after - before
            if delta > 0 { gain += delta } else { loss -= delta }
        }
        let metres = (end - start) * 1000
        return ProfileSelection(
            distanceKm: end - start, gain: gain, loss: loss,
            grade: (endAlt - startAlt) / metres * 100
        )
    }

    /// L'altitude à une distance, interpolée entre les deux points qui
    /// l'encadrent ; celle du bout le plus proche au-delà du tracé.
    static func altitude(at distanceKm: Double, in points: [StreamPoint]) -> Double? {
        guard let first = points.first, let last = points.last else { return nil }
        if distanceKm <= first.distanceKm { return first.value }
        if distanceKm >= last.distanceKm { return last.value }
        guard let upper = points.firstIndex(where: { $0.distanceKm >= distanceKm }), upper > 0
        else { return nil }
        let a = points[upper - 1], b = points[upper]
        let span = b.distanceKm - a.distanceKm
        guard span > 0 else { return b.value }
        return a.value + (b.value - a.value) * (distanceKm - a.distanceKm) / span
    }
}
