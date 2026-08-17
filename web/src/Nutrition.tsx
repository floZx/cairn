import { useState } from "react"
import { useQuery } from "@tanstack/react-query"
import { supabase } from "./supabase"
import { dateLongue } from "./format"
import { jourCourant } from "./NoteEditor"
import {
  arrondi,
  dansLeMille,
  depassement,
  macrosDe,
  objectifsAdaptatifs,
  objectifsDuJour,
  somme,
  type EtatRepas,
  type Macros,
} from "./macros"

type Creneau = { uuid: string; name: string; sort_order: number; target_pct: number }
type TypeDeJour = { uuid: string; name: string; kcal_target: number }
type Aliment = {
  uuid: string
  meal_slot_uuid: string | null
  food_name: string
  kcal100: number
  protein100: number
  carbs100: number
  fat100: number
  grams: number
  sort_order: number
}
type NoteDeRepas = { uuid: string; meal_slot_uuid: string | null; note: string }

/// Les créneaux et les types de jour : une poignée de lignes, les mêmes tous
/// les jours. Interrogés une fois pour la session plutôt qu'à chaque
/// changement de date.
function useReglages() {
  return useQuery({
    queryKey: ["nutrition-reglages"],
    staleTime: Infinity,
    queryFn: async () => {
      const [creneaux, types, cibles] = await Promise.all([
        supabase
          .from("meal_slot")
          .select("uuid, name, sort_order, target_pct")
          .is("deleted_at", null)
          .order("sort_order"),
        supabase.from("day_type").select("uuid, name, kcal_target").is("deleted_at", null),
        // Une seule ligne, celle de la personne connectée. Écrite par le Mac
        // à chaque synchronisation, jamais d'ici.
        supabase
          .from("nutrition_target")
          .select("protein_g, fat_g")
          .is("deleted_at", null)
          .maybeSingle(),
      ])
      if (creneaux.error) throw creneaux.error
      if (types.error) throw types.error
      if (cibles.error) throw cibles.error
      return {
        creneaux: creneaux.data as Creneau[],
        types: new Map((types.data as TypeDeJour[]).map((t) => [t.uuid, t])),
        cibles: cibles.data as { protein_g: number; fat_g: number } | null,
      }
    },
  })
}

function useJournee(dateKey: string) {
  return useQuery({
    queryKey: ["nutrition-jour", dateKey],
    queryFn: async () => {
      const [jour, aliments, notes] = await Promise.all([
        supabase
          .from("nutrition_day")
          .select("day_type_uuid")
          .eq("date_key_raw", dateKey)
          .is("deleted_at", null)
          .maybeSingle(),
        supabase
          .from("food_entry")
          .select(
            "uuid, meal_slot_uuid, food_name, kcal100, protein100, carbs100, fat100, grams, sort_order",
          )
          .eq("date_key_raw", dateKey)
          .is("deleted_at", null)
          .order("sort_order"),
        supabase
          .from("meal_note")
          .select("uuid, meal_slot_uuid, note")
          .eq("date_key_raw", dateKey)
          .is("deleted_at", null),
      ])
      if (jour.error) throw jour.error
      if (aliments.error) throw aliments.error
      if (notes.error) throw notes.error
      return {
        typeDeJourUUID: (jour.data?.day_type_uuid as string | null) ?? null,
        aliments: aliments.data as Aliment[],
        notes: notes.data as NoteDeRepas[],
      }
    },
  })
}

function decale(dateKey: string, jours: number): string {
  const [a, m, j] = dateKey.split("-").map(Number)
  const d = new Date(a, m - 1, j + jours)
  const deux = (n: number) => String(n).padStart(2, "0")
  return `${d.getFullYear()}-${deux(d.getMonth() + 1)}-${deux(d.getDate())}`
}

/// Un chiffre et sa couleur. Vert quand le repas atterrit sur son plan, orange
/// puis rouge au-delà — jamais l'inverse : un journal qui ne colore que pour
/// gronder est un journal qu'on cesse de lire.
function classeDe(consomme: number, objectif: number | null): string {
  if (objectif === null) return ""
  const d = depassement(consomme, objectif)
  if (d === "franc") return " franc"
  if (d === "modere") return " modere"
  return dansLeMille(consomme, objectif) ? " atteint" : ""
}

/// `objectif` à `null` quand il n'y en a pas : le chiffre s'affiche seul,
/// sans couleur. Un nombre coloré sans repère ne veut rien dire.
function LigneMacros({
  m,
  objectif,
  sansUnite,
}: {
  m: Macros
  objectif?: Macros | null
  sansUnite?: boolean
}) {
  const a = arrondi(m)
  const part = (valeur: number, cible: number | undefined, lettre: string) => (
    <span className={classeDe(valeur, cible ?? null)}>
      {valeur} {lettre}
    </span>
  )
  return (
    <span className="macros">
      {part(a.proteines, objectif?.proteines, "P")} ·{" "}
      {part(a.glucides, objectif?.glucides, "G")} ·{" "}
      {part(a.lipides, objectif?.lipides, "L")}
      {sansUnite ? "" : " (g)"}
    </span>
  )
}

export function Nutrition() {
  const [dateKey, setDateKey] = useState(jourCourant)
  const reglages = useReglages()
  const journee = useJournee(dateKey)

  const enTete = (
    <div className="barre-jour">
      <button className="lien" onClick={() => setDateKey(decale(dateKey, -1))}>
        ‹
      </button>
      <span className="jour">{dateLongue(dateKey)}</span>
      <button
        className="lien"
        onClick={() => setDateKey(decale(dateKey, 1))}
        // Rien après aujourd'hui : le journal se tient, il ne se prévoit pas.
        disabled={dateKey >= jourCourant()}
      >
        ›
      </button>
    </div>
  )

  const erreur = reglages.error ?? journee.error
  if (erreur) {
    return (
      <>
        {enTete}
        <p className="erreur">{(erreur as Error).message}</p>
      </>
    )
  }
  // Les deux valeurs nommées avant d'être testées : `isPending` sur deux
  // requêtes distinctes ne dit rien à TypeScript sur la présence de `data`
  // de l'autre, et une garde combinée le laissait croire les deux
  // éventuellement absentes plus bas.
  const donneesReglages = reglages.data
  const donneesJournee = journee.data
  if (!donneesReglages || !donneesJournee) {
    return (
      <>
        {enTete}
        <p className="attenue">Chargement…</p>
      </>
    )
  }

  const { creneaux, types, cibles } = donneesReglages
  const { typeDeJourUUID, aliments, notes } = donneesJournee
  const typeDuJour = typeDeJourUUID ? types.get(typeDeJourUUID) : undefined

  const parCreneau = (uuid: string) => aliments.filter((a) => a.meal_slot_uuid === uuid)
  const consommeDu = (uuid: string) => somme(...parCreneau(uuid).map(macrosDe))
  const totalJour = somme(...aliments.map(macrosDe))

  // Les glucides ne sont pas un réglage : ils se déduisent de ce que les
  // calories laissent une fois les protéines et lipides comptés. Sans la
  // ligne `nutrition_target` — un Mac qui n'a pas encore synchronisé depuis
  // cette version — les objectifs de macros restent absents plutôt
  // qu'inventés, et seules les calories gardent une cible.
  const journeeVisee: Macros | null = typeDuJour
    ? objectifsDuJour(typeDuJour.kcal_target, cibles?.protein_g ?? 0, cibles?.fat_g ?? 0)
    : null

  const etats: EtatRepas[] = creneaux.map((c) => ({
    pct: c.target_pct,
    commence: parCreneau(c.uuid).length > 0,
    consomme: consommeDu(c.uuid),
  }))
  const objectifs = objectifsAdaptatifs(journeeVisee, etats)

  return (
    <>
      {enTete}

      <div className="total-jour">
        <div className="chiffre-jour">
          <span className={"valeur" + classeDe(totalJour.kcal, journeeVisee?.kcal ?? null)}>
            {Math.round(totalJour.kcal)}
          </span>
          {journeeVisee && <span className="attenue"> / {journeeVisee.kcal} kcal</span>}
          {!journeeVisee && <span className="attenue"> kcal</span>}
        </div>
        <LigneMacros m={totalJour} objectif={cibles ? journeeVisee : null} />
        {typeDuJour && <div className="attenue petit">{typeDuJour.name}</div>}
      </div>

      {creneaux.map((creneau, i) => {
        const lignes = parCreneau(creneau.uuid)
        const note = notes.find((n) => n.meal_slot_uuid === creneau.uuid)?.note
        const consomme = consommeDu(creneau.uuid)
        const objectif = objectifs[i]
        if (lignes.length === 0 && !note) {
          return (
            <section className="repas vide" key={creneau.uuid}>
              <h3>
                {creneau.name}
                {objectif && (
                  <span className="attenue"> {Math.round(objectif.kcal)} kcal prévues</span>
                )}
              </h3>
            </section>
          )
        }
        return (
          <section className="repas" key={creneau.uuid}>
            <h3>
              {creneau.name}
              <span className={"kcal-repas" + classeDe(consomme.kcal, objectif?.kcal ?? null)}>
                {Math.round(consomme.kcal)}
                {objectif && <span className="attenue"> / {Math.round(objectif.kcal)}</span>}
              </span>
            </h3>
            {note && <p className="note-repas">{note}</p>}
            <ul className="aliments">
              {lignes.map((ligne) => {
                const m = arrondi(macrosDe(ligne))
                return (
                  <li key={ligne.uuid}>
                    <span className="nom">{ligne.food_name}</span>
                    <span className="attenue petit">
                      {Math.round(ligne.grams)} g
                    </span>
                    <span className="kcal">{m.kcal}</span>
                  </li>
                )
              })}
            </ul>
            {lignes.length > 1 && (
              <div className="sous-total">
                <LigneMacros m={consomme} sansUnite />
              </div>
            )}
          </section>
        )
      })}

      {aliments.length === 0 && (
        <p className="attenue">Rien de noté pour cette journée.</p>
      )}
    </>
  )
}
