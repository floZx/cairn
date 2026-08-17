import { useState } from "react"
import { useQuery } from "@tanstack/react-query"
import { supabase } from "./supabase"
import { dateLongue } from "./format"
import { jourCourant } from "./NoteEditor"
import { AjoutAliment } from "./AjoutAliment"
import { ModifAliment, type AlimentAModifier } from "./ModifAliment"
import { Feuille } from "./Chrome"
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
      // L'erreur des cibles est avalée, à la différence des deux autres, et
      // c'est délibéré : elles sont un supplément, pas la journée. Un Mac qui
      // n'a pas encore synchronisé — ou un projet Supabase où la migration
      // n'est pas passée — rendait ici « Could not find the table
      // public.nutrition_target », et l'écran des repas entier disparaissait
      // derrière ce message pour une ligne d'objectifs manquante. Sans elles,
      // les macros s'affichent sans couleur ; c'est exactement ce qu'il faut.
      return {
        creneaux: creneaux.data as Creneau[],
        types: new Map((types.data as TypeDeJour[]).map((t) => [t.uuid, t])),
        cibles: cibles.error
          ? null
          : (cibles.data as { protein_g: number; fat_g: number } | null),
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
  // La cible écrite, pas seulement suggérée par une couleur. Sans elle, une
  // journée sous l'objectif — le cas courant en milieu de journée — s'affiche
  // sans la moindre marque, et rien ne distingue « pas encore d'objectif » de
  // « objectif pas encore atteint ».
  const part = (valeur: number, cible: number | undefined, lettre: string) => (
    <span className={classeDe(valeur, cible ?? null)}>
      {valeur}
      {cible !== undefined && <span className="attenue">/{Math.round(cible)}</span>}
      {" "}
      {lettre}
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
  const [ajoutDans, setAjoutDans] = useState<{ uuid: string; nom: string } | null>(null)
  const [enModification, setEnModification] = useState<AlimentAModifier | null>(null)
  const reglages = useReglages()
  const journee = useJournee(dateKey)

  const enTete = (
    <div className="barre-jour">
      <button className="lien" onClick={() => setDateKey(decale(dateKey, -1))}>
        ‹
      </button>
      {/* Un champ de date natif plutôt qu'un calendrier maison : sur un
          téléphone il ouvre le sélecteur du système, et remonter à juin
          coûtait cinquante clics sur la flèche. La date en toutes lettres
          reste au-dessus — `input[type=date]` affiche « 26/06/2026 », ce qui
          ne dit pas quel jour de la semaine c'était. */}
      <label className="choix-jour">
        <span className="jour">{dateLongue(dateKey)}</span>
        <input
          type="date"
          value={dateKey}
          max={jourCourant()}
          onChange={(e) => e.target.value && setDateKey(e.target.value)}
        />
      </label>
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
      {enModification && (
        <Feuille titre="Modifier l'aliment" onFerme={() => setEnModification(null)}>
          <ModifAliment
            aliment={enModification}
            dateKey={dateKey}
            onFerme={() => setEnModification(null)}
          />
        </Feuille>
      )}
      {ajoutDans && (
        <Feuille titre={`Ajouter à ${ajoutDans.nom}`} onFerme={() => setAjoutDans(null)}>
          <AjoutAliment
            dateKey={dateKey}
            slotUUID={ajoutDans.uuid}
            slotNom={ajoutDans.nom}
            onFerme={() => setAjoutDans(null)}
          />
        </Feuille>
      )}
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
                <span>
                  {objectif && (
                    <span className="attenue">{Math.round(objectif.kcal)} kcal prévues</span>
                  )}
                  <button
                    className="ajouter"
                    onClick={() => setAjoutDans({ uuid: creneau.uuid, nom: creneau.name })}
                    aria-label={`Ajouter à ${creneau.name}`}
                  >
                    +
                  </button>
                </span>
              </h3>
            </section>
          )
        }
        return (
          <section className="repas" key={creneau.uuid}>
            <h3>
              {creneau.name}
              <span>
                <span className={"kcal-repas" + classeDe(consomme.kcal, objectif?.kcal ?? null)}>
                  {Math.round(consomme.kcal)}
                  {objectif && <span className="attenue"> / {Math.round(objectif.kcal)}</span>}
                </span>
                <button
                  className="ajouter"
                  onClick={() => setAjoutDans({ uuid: creneau.uuid, nom: creneau.name })}
                  aria-label={`Ajouter à ${creneau.name}`}
                >
                  +
                </button>
              </span>
            </h3>
            {note && <p className="note-repas">{note}</p>}
            <ul className="aliments">
              {lignes.map((ligne) => {
                const m = arrondi(macrosDe(ligne))
                return (
                  <li key={ligne.uuid}>
                    {/* Toute la ligne est le bouton : sur un téléphone, viser
                        un nom de trois lettres pour corriger une quantité est
                        une cible qu'on rate. */}
                    <button
                      className="ligne-aliment"
                      onClick={() =>
                        setEnModification({
                          uuid: ligne.uuid,
                          nom: ligne.food_name,
                          grammes: ligne.grams,
                          kcal100: ligne.kcal100,
                          protein100: ligne.protein100,
                          carbs100: ligne.carbs100,
                          fat100: ligne.fat100,
                        })
                      }
                    >
                      <span className="nom">{ligne.food_name}</span>
                      <span className="attenue petit">{Math.round(ligne.grams)} g</span>
                      <span className="kcal">{m.kcal}</span>
                    </button>
                  </li>
                )
              })}
            </ul>
            {/* Les macros du repas contre celles que son objectif adaptatif
                lui alloue — la même question que les calories juste au-dessus,
                posée pour les trois autres. Affichée dès qu'il y a un aliment,
                même un seul : savoir si ce qu'on vient de manger tient dans le
                repas ne dépend pas du nombre de lignes. */}
            {lignes.length > 0 && (
              <div className="sous-total">
                <LigneMacros
                  m={consomme}
                  objectif={cibles ? objectif : null}
                  sansUnite
                />
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
