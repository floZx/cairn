import { useState } from "react"
import { NOMS as NOMS_ETIQUETTES, type Etiquette } from "./etiquettes"
import { SPORTS, nomDuSport } from "./sports"
import { AUCUN, PERIODES, criteres, type Filtre, type Periode } from "./criteres"

/// Les mêmes critères que sur le Mac, dans une feuille.
///
/// Appliqué en direct plutôt que derrière un bouton « Valider » : on tâtonne,
/// on coche un sport, on voit le compte bouger. Un formulaire qu'il faut
/// valider pour savoir ce qu'il donne se remplit à l'aveugle.
function Nombre({
  valeur,
  onChange,
  suffixe,
  libelle,
}: {
  valeur: number | null
  onChange: (v: number | null) => void
  suffixe: string
  libelle: string
}) {
  return (
    <label className="critere-nombre">
      <span>{libelle}</span>
      <span className="saisie-nombre">
        <input
          type="number"
          inputMode="decimal"
          value={valeur ?? ""}
          placeholder="—"
          onChange={(e) => {
            const v = e.target.value.trim()
            onChange(v === "" ? null : Number(v.replace(",", ".")))
          }}
        />
        <span className="attenue">{suffixe}</span>
      </span>
    </label>
  )
}

export function Filtres({
  filtre,
  onChange,
  onFerme,
  compte,
}: {
  filtre: Filtre
  onChange: (f: Filtre) => void
  onFerme: () => void
  /// Combien d'activités le filtre laisse passer, tel qu'il est.
  compte: number | null
}) {
  const [local, setLocal] = useState(filtre)
  /// Les étiquettes et le dénivelé par kilomètre se règlent après la requête ;
  /// le compte ne les connaît donc pas et n'est qu'un majorant. Le dire plutôt
  /// que d'afficher un nombre qui ne bouge pas quand on coche une étiquette —
  /// ce qui se lit comme un filtre qui ne marche pas.
  const majorant = local.etiquettes.length > 0 || local.denivelleParKmMin != null

  const poser = (modif: Partial<Filtre>) => {
    const suivant = { ...local, ...modif }
    setLocal(suivant)
    onChange(suivant)
  }

  const bascule = <T,>(liste: T[], valeur: T): T[] =>
    liste.includes(valeur) ? liste.filter((x) => x !== valeur) : [...liste, valeur]

  return (
    <>
      <div className="barre-editeur">
        <button
          className="lien"
          onClick={() => {
            setLocal(AUCUN)
            onChange(AUCUN)
          }}
          disabled={criteres(local).length === 0}
        >
          Tout effacer
        </button>
        <span className="jour">
          {compte === null
            ? "Filtres"
            : `${compte} activité${compte > 1 ? "s" : ""}${majorant ? " au plus" : ""}`}
        </span>
        <button className="lien fort" onClick={onFerme}>
          Terminé
        </button>
      </div>

      <h4 className="titre-section">Sports</h4>
      <div className="pastilles">
        {SPORTS.map((s) => (
          <button
            key={s}
            className={local.sports.includes(s) ? "pastille-choix active" : "pastille-choix"}
            onClick={() => poser({ sports: bascule(local.sports, s) })}
          >
            {nomDuSport(s)}
          </button>
        ))}
      </div>

      <h4 className="titre-section">Période</h4>
      <div className="pastilles">
        {PERIODES.map((p) => (
          <button
            key={p.clef}
            className={local.periode === p.clef ? "pastille-choix active" : "pastille-choix"}
            onClick={() => poser({ periode: p.clef as Periode })}
          >
            {p.nom}
          </button>
        ))}
      </div>

      <h4 className="titre-section">Distance et dénivelé</h4>
      <div className="criteres">
        <Nombre
          libelle="Distance min."
          suffixe="km"
          valeur={local.distanceMin}
          onChange={(v) => poser({ distanceMin: v })}
        />
        <Nombre
          libelle="Distance max."
          suffixe="km"
          valeur={local.distanceMax}
          onChange={(v) => poser({ distanceMax: v })}
        />
        <Nombre
          libelle="D+ min."
          suffixe="m"
          valeur={local.deniveleMin}
          onChange={(v) => poser({ deniveleMin: v })}
        />
        <Nombre
          libelle="D+ max."
          suffixe="m"
          valeur={local.deniveleMax}
          onChange={(v) => poser({ deniveleMax: v })}
        />
        <Nombre
          libelle="D+ par km min."
          suffixe="m"
          valeur={local.denivelleParKmMin}
          onChange={(v) => poser({ denivelleParKmMin: v })}
        />
      </div>

      <h4 className="titre-section">Étiquettes</h4>
      <div className="pastilles">
        {(Object.keys(NOMS_ETIQUETTES) as Etiquette[]).map((e) => (
          <button
            key={e}
            className={
              local.etiquettes.includes(e) ? "pastille-choix active" : "pastille-choix"
            }
            onClick={() => poser({ etiquettes: bascule(local.etiquettes, e) })}
          >
            {NOMS_ETIQUETTES[e]}
          </button>
        ))}
      </div>
    </>
  )
}
