# La fiche d'une activité, resserrée

> **Statut** : abandonné le 12 août 2026 — mis en œuvre, essayé, et annulé.
> Les libellés retirés, l'allure ajoutée, l'alignement à droite, un en-tête, des
> fiches sur fond propre : rien de tout cela n'a rendu la liste plus belle à
> l'usage. Le code est revenu à ce qu'il était. La spec reste pour ce qu'elle
> documente — les pistes essayées et pourquoi elles ne suffisent pas.

**Date** : 2026-08-12

## Objectif

La présentation « fiche » de la liste des activités est lisible mais bavarde :
elle répète vingt fois les mêmes libellés, écrit des zéros pour des mesures qui
n'existent pas, tait le chiffre qu'un coureur cherche en premier, et donne à
une marche de 25 minutes le même poids qu'à un trail de trois heures.

Quatre corrections, toutes dans `ActivityCard`.

## Décisions structurantes (validées avec l'utilisateur)

1. **Les libellés disparaissent.** Chaque valeur porte déjà son unité — *9,0 km*,
   *48 min*, *32 m*, *132 bpm*. « Distance » sous « 9,0 km » ne dit rien de plus
   et occupe la moitié de la hauteur de la fiche. L'œil descend une colonne de
   chiffres au lieu de relire quatre fois le même mot.

2. **L'allure entre**, en cinquième colonne, lue selon le sport comme partout
   ailleurs dans l'application : allure au kilomètre à pied, aux 100 m en
   natation, vitesse à vélo. C'est le chiffre qu'on cherche en premier, et la
   fiche obligeait à le calculer de tête depuis les deux colonnes voisines.

3. **Un blanc plutôt qu'un zéro.** Une séance de renforcement n'a pas de
   distance ; ce n'est pas la même chose que d'en avoir une nulle. La colonne
   garde sa place — les lignes restent alignées pour le balayage — mais reste
   vide.

4. **Les grosses sorties pèsent plus lourd, d'un cran.** Le premier chiffre de
   la ligne passe en demi-gras pour une sortie notable. Pas de taille plus
   grande, pas de couleur : sur une liste de vingt lignes, une différence de
   graisse suffit à faire ressortir les trois trails d'un mois, là où une
   différence de corps ferait sauter l'alignement et crierait.

   **Notable** veut dire : au moins 90 minutes en mouvement, ou au moins 20 km.
   Deux seuils, parce qu'un sport ne se mesure pas comme un autre — trois heures
   de vélo et 25 km de trail sont l'un et l'autre une sortie dont on se
   souvient, une heure de footing ne l'est pas. Les deux nombres vivent côte à
   côte dans le type, à un endroit où les changer prend une seconde.

## Ce que devient une ligne

```
[trace]  Course à pied le matin          9,0 km   48 min   32 m   5:21/km  132 bpm
         mercredi 12 août 2026 à 06:48
```

Une séance de renforcement, qui n'a ni distance, ni dénivelé, ni allure :

```
[glyphe] Entraînement aux poids en soirée          —   26 min      —     —    86 bpm
         lundi 10 août 2026 à 18:32  ⌂
```

Le premier chiffre écrit — la distance, ou la durée quand il n'y a pas de
distance — porte la graisse quand la sortie est notable.

La partie gauche ne bouge pas : trace, nom, date, marqueurs. La hauteur de la
fiche non plus : les deux lignes de gauche la fixent, et les chiffres se
centrent verticalement en face.

## L'architecture

Tout tient dans `Cairn/Features/ActivityList/ActivityCard.swift`, qui est déjà
la vue d'une ligne et rien d'autre.

Ce qui en sort pour être testé : **la liste des chiffres d'une activité**, une
fonction pure.

```swift
extension ActivityCard {
    struct Figure: Equatable {
        /// Nil quand la mesure n'existe pas — une colonne vide, pas un zéro.
        var value: String?
        /// Vrai sur le premier chiffre écrit d'une sortie notable.
        var isLeading: Bool
    }
    static func figures(for activity: Activity) -> [Figure]
    static func isNotable(_ activity: Activity) -> Bool
}
```

Cinq entrées, toujours dans le même ordre — distance, durée, dénivelé, allure,
fréquence cardiaque — pour que deux lignes voisines s'alignent quoi qu'elles
portent. Une mesure absente rend `nil`, et la vue écrit alors une colonne vide.

## Les règles, une par une

- **Distance** : absente quand elle vaut zéro (salle, home-trainer).
- **Durée** : toujours présente. C'est la seule mesure qu'une activité a
  forcément.
- **Dénivelé** : absent quand il vaut zéro. Une sortie parfaitement plate est
  rare ; une séance en salle, non.
- **Allure ou vitesse** : absente quand la vitesse moyenne est nulle —
  `Format.speed` rend déjà un tiret dans ce cas, et la règle est la même ici.
- **Fréquence cardiaque** : absente sans cardio, ce que la fiche fait déjà.
- **Le premier chiffre écrit** porte `isLeading` quand la sortie est notable.
  « Premier écrit » et non « premier de la liste » : une séance en salle sans
  distance met la graisse sur sa durée.

## Tests

- Une course porte cinq chiffres, allure comprise, dans l'ordre.
- Une séance de renforcement n'écrit ni distance, ni dénivelé, ni allure — et
  ses colonnes restent aux mêmes places.
- Une natation lit son allure aux 100 m, un vélo sa vitesse — par
  `Format.speed`, pas par une seconde règle.
- Un trail de 25 km et une sortie de deux heures sont notables ; un footing de
  48 minutes ne l'est pas.
- La graisse se pose sur la distance d'une sortie notable, et sur la durée
  quand elle n'a pas de distance.

## Hors périmètre

- La présentation en tableau, qui a ses propres colonnes et son propre réglage.
- La hauteur de la fiche et la taille de la vignette, réglées récemment.
- Toute couleur ou tout fond nouveau : la graisse est le seul appui ajouté.
