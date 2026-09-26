import { useState } from "react"
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query"
import { supabase } from "./supabase"
import { POIDS_MASQUE } from "./masquees"
import { dateLongue } from "./format"
import { jourCourant } from "./NoteEditor"
import { AjoutAliment } from "./AjoutAliment"
import { ModifAliment, type AlimentAModifier } from "./ModifAliment"
import { Feuille, Chargement } from "./Chrome"
import { ListeGlissable } from "./ListeGlissable"
import { Symbole } from "./IconeSport"
import { NoteRepas, Pesee, TypeDeJournee } from "./SaisieJour"
import { BilanDuJour, etatDe } from "./JaugeMacro"
import { jourRelatif } from "./Journal"
import {
  arrondi,
  macrosDe,
  objectifsAdaptatifs,
  objectifsDuJour,
  somme,
  type EtatRepas,
  type Macros,
} from "./macros"

type Creneau = { uuid: string; name: string; sort_order: number; target_pct: number }
type TypeDeJour = { uuid: string; name: string; kcal_target: number; sort_order: number }
type Aliment = {
  uuid: string
  meal_slot_uuid: string | null
  food_name: string
  kcal100: number
  protein100: number
  carbs100: number
  fat100: number
  /// Nulles quand la source ne les connaît pas. Plus affichées : trop peu
  /// renseignées pour servir, mais gardées avec l'aliment.
  fiber100: number | null
  grams: number
  sort_order: number
}
type NoteDeRepas = { uuid: string; meal_slot_uuid: string | null; note: string }
type PeseeDuJour = { uuid: string; weight_kg: number; note: string | null }

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
        supabase
          .from("day_type")
          .select("uuid, name, kcal_target, sort_order")
          .is("deleted_at", null)
          .order("sort_order"),
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
        // La liste ordonnée en plus de la table : la feuille les propose du
        // plus calme au plus chargé, ce qu'une `Map` ne garantit pas.
        typesOrdonnes: types.data as TypeDeJour[],
        cibles: cibles.error
          ? null
          : (cibles.data as {
              protein_g: number
              fat_g: number
            } | null),
      }
    },
  })
}

function useJournee(dateKey: string) {
  return useQuery({
    queryKey: ["nutrition-jour", dateKey],
    queryFn: async () => {
      const [jour, aliments, notes, pesee] = await Promise.all([
        supabase
          .from("nutrition_day")
          .select("uuid, day_type_uuid")
          .eq("date_key_raw", dateKey)
          .is("deleted_at", null)
          .maybeSingle(),
        supabase
          .from("food_entry")
          .select(
            "uuid, meal_slot_uuid, food_name, kcal100, protein100, carbs100, fat100, fiber100, grams, sort_order",
          )
          .eq("date_key_raw", dateKey)
          .is("deleted_at", null)
          .order("sort_order"),
        supabase
          .from("meal_note")
          .select("uuid, meal_slot_uuid, note")
          .eq("date_key_raw", dateKey)
          .is("deleted_at", null),
        supabase
          .from("weight_entry")
          .select("uuid, weight_kg, note")
          .eq("date_key_raw", dateKey)
          .is("deleted_at", null)
          .maybeSingle(),
      ])
      if (jour.error) throw jour.error
      if (aliments.error) throw aliments.error
      if (notes.error) throw notes.error
      if (pesee.error) throw pesee.error
      return {
        jourUUID: (jour.data?.uuid as string | undefined) ?? null,
        typeDeJourUUID: (jour.data?.day_type_uuid as string | null) ?? null,
        aliments: aliments.data as Aliment[],
        notes: notes.data as NoteDeRepas[],
        pesee: pesee.data as PeseeDuJour | null,
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
  const etat = etatDe(consomme, objectif)
  return etat ? " " + etat : ""
}

const dateSansAnnee = new Intl.DateTimeFormat("fr-FR", { weekday: "long", day: "numeric", month: "long" })
const dateCourteDuJour = new Intl.DateTimeFormat("fr-FR", { day: "numeric", month: "short" })

/// « Aujourd'hui · 26 sept. », « Hier · 25 sept. », « Jeudi · 24 sept. »
/// dans la semaine, puis « jeudi 18 septembre » — l'année seulement quand ce
/// n'est pas celle-ci. La date entière tenait une ligne à elle seule.
function libelleDuJour(dateKey: string): string {
  const aujourdhui = jourCourant()
  const [a, m, j] = dateKey.split("-").map(Number)
  const date = new Date(a, m - 1, j)
  const ecart = Math.round((new Date(aujourdhui + "T00:00").getTime() - date.getTime()) / 86_400_000)
  if (ecart >= 0 && ecart <= 6) {
    return `${jourRelatif(dateKey, aujourdhui)} · ${dateCourteDuJour.format(date)}`
  }
  if (String(a) !== aujourdhui.slice(0, 4)) return dateLongue(dateKey)
  const texte = dateSansAnnee.format(date)
  return texte.charAt(0).toUpperCase() + texte.slice(1)
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
    // La lettre d'abord, puis le chiffre : « P 40/42 » se lit comme une
    // étiquette, là où « 40/42 P » laissait chercher à quoi le chiffre
    // correspondait.
    <span className={"macro-repas" + classeDe(valeur, cible ?? null)}>
      <span className="lettre">{lettre}</span> {valeur}
      {cible !== undefined && <span className="attenue">/{Math.round(cible)}</span>}
    </span>
  )
  return (
    <span className="macros">
      {part(a.proteines, objectif?.proteines, "P")}
      {part(a.glucides, objectif?.glucides, "G")}
      {part(a.lipides, objectif?.lipides, "L")}
      {sansUnite ? "" : " (g)"}
    </span>
  )
}

export function Nutrition({
  /// Le jour sur lequel s'ouvrir, quand on arrive d'ailleurs — une citation du
  /// journal, par exemple. Aujourd'hui sinon.
  ///
  /// Lu une seule fois, à la construction : ensuite c'est la barre du jour qui
  /// commande. L'appelant force un remontage s'il veut en changer.
  jourInitial,
}: {
  jourInitial?: string
} = {}) {
  const [dateKey, setDateKey] = useState(() => jourInitial ?? jourCourant())
  const [ajoutDans, setAjoutDans] = useState<{ uuid: string; nom: string } | null>(null)
  const [enModification, setEnModification] = useState<AlimentAModifier | null>(null)
  const [noteDe, setNoteDe] = useState<{ uuid: string; nom: string } | null>(null)
  const [peseeOuverte, setPeseeOuverte] = useState(false)
  const [typeOuvert, setTypeOuvert] = useState(false)
  const reglages = useReglages()
  const journee = useJournee(dateKey)
  const client = useQueryClient()

  /// Pose un nouvel ordre des aliments d'un repas — celui que le glisser vient
  /// de donner (`ListeGlissable`).
  ///
  /// Les rangs du repas redistribués dans l'ordre voulu, plutôt que deux rangs
  /// échangés : le Mac peut laisser deux aliments au même rang, et un échange
  /// entre égaux ne déplace rien. Les valeurs déjà prises par ce repas sont
  /// reprises, rendues strictement croissantes, si bien qu'aucun autre repas
  /// du jour ne voit ses rangs bouger. Seules les lignes qui changent sont
  /// écrites ; le Mac relit `sort_order` avec le reste de la ligne.
  const deplacement = useMutation({
    mutationFn: async ({
      lignes,
      nouvelOrdre,
    }: {
      lignes: { uuid: string; sort_order: number }[]
      nouvelOrdre: string[]
    }) => {
      const ordre = nouvelOrdre
        .map((u) => lignes.find((l) => l.uuid === u))
        .filter((l): l is { uuid: string; sort_order: number } => !!l)
      const rangs: number[] = []
      for (const r of lignes.map((l) => l.sort_order).sort((a, b) => a - b)) {
        rangs.push(rangs.length ? Math.max(r, rangs[rangs.length - 1] + 1) : r)
      }
      const maintenant = new Date().toISOString()
      const changements = ordre
        .map((l, i) => ({ uuid: l.uuid, avant: l.sort_order, apres: rangs[i] }))
        .filter((c) => c.avant !== c.apres)
      for (const c of changements) {
        const { error } = await supabase
          .from("food_entry")
          .update({ sort_order: c.apres, edited_at: maintenant })
          .eq("uuid", c.uuid)
        if (error) throw error
      }
    },
    onSuccess: () => client.invalidateQueries({ queryKey: ["nutrition-jour", dateKey] }),
  })

  const enTete = (
    <div className="barre-jour">
      <button
        className="lien"
        onClick={() => setDateKey(decale(dateKey, -1))}
        aria-label="Jour précédent"
      >
        <Chevron sens="gauche" />
      </button>
      {/* Un champ de date natif plutôt qu'un calendrier maison : sur un
          téléphone il ouvre le sélecteur du système, et remonter à juin
          coûtait cinquante clics sur la flèche. La date en toutes lettres
          reste au-dessus — `input[type=date]` affiche « 26/06/2026 », ce qui
          ne dit pas quel jour de la semaine c'était. */}
      <label className="choix-jour">
        <span className="jour">{libelleDuJour(dateKey)}</span>
        <input
          type="date"
          value={dateKey}
          onChange={(e) => e.target.value && setDateKey(e.target.value)}
        />
      </label>
      <button
        className="lien"
        onClick={() => setDateKey(decale(dateKey, 1))}
        aria-label="Jour suivant"
      >
        <Chevron sens="droite" />
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
        <Chargement />
      </>
    )
  }

  const { creneaux, types, typesOrdonnes, cibles } = donneesReglages
  const { jourUUID, typeDeJourUUID, aliments, notes, pesee } = donneesJournee
  const typeDuJour = typeDeJourUUID ? types.get(typeDeJourUUID) : undefined

  const parCreneau = (uuid: string) => aliments.filter((a) => a.meal_slot_uuid === uuid)

  // Chaque ligne arrondie **avant** d'être sommée, jamais après : c'est la
  // règle de `Macros.rounded()`, et son commentaire dit ce qu'elle répare —
  // « sept lignes d'un repas lues 24, 1, 5, 3, 19, 13, 0, soit soixante-cinq,
  // sous un titre disant 64 ». Sommer les décimales donnait ici 41 g de
  // protéines là où le Mac en affiche 40, et un total de glucides vert là où
  // le sien est orange. Le total du jour est celui des repas, eux-mêmes déjà
  // arrondis — `NutritionDayModel` procède exactement ainsi.
  const consommeDu = (uuid: string) =>
    somme(...parCreneau(uuid).map((a) => arrondi(macrosDe(a))))
  const totalJour = somme(...creneaux.map((c) => consommeDu(c.uuid)))

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
      {noteDe && (
        <Feuille titre={`Note du ${noteDe.nom}`} onFerme={() => setNoteDe(null)}>
          <NoteRepas
            dateKey={dateKey}
            slotUUID={noteDe.uuid}
            slotNom={noteDe.nom}
            noteUUID={notes.find((n) => n.meal_slot_uuid === noteDe.uuid)?.uuid ?? null}
            texte={notes.find((n) => n.meal_slot_uuid === noteDe.uuid)?.note ?? ""}
            onFerme={() => setNoteDe(null)}
          />
        </Feuille>
      )}
      {typeOuvert && (
        <Feuille titre="Type de journée" onFerme={() => setTypeOuvert(false)}>
          <TypeDeJournee
            dateKey={dateKey}
            jourUUID={jourUUID}
            typeChoisi={typeDeJourUUID}
            types={typesOrdonnes}
            onFerme={() => setTypeOuvert(false)}
          />
        </Feuille>
      )}
      {peseeOuverte && (
        <Feuille titre="Pesée" onFerme={() => setPeseeOuverte(false)}>
          <Pesee
            dateKey={dateKey}
            peseeUUID={pesee?.uuid ?? null}
            kilos={pesee?.weight_kg ?? null}
            commentaire={pesee?.note ?? ""}
            onFerme={() => setPeseeOuverte(false)}
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

      <BilanDuJour
        typeDuJour={typeDuJour?.name ?? null}
        onType={() => setTypeOuvert(true)}
        kcal={{ consomme: totalJour.kcal, objectif: journeeVisee?.kcal ?? null }}
        proteines={{ consomme: totalJour.proteines, objectif: cibles ? (journeeVisee?.proteines ?? null) : null }}
        glucides={{ consomme: totalJour.glucides, objectif: cibles ? (journeeVisee?.glucides ?? null) : null }}
        lipides={{ consomme: totalJour.lipides, objectif: cibles ? (journeeVisee?.lipides ?? null) : null }}
      />

      {/* Le type de journée est passé en tête du bilan, qu'il règle ; il ne
          reste ici que la pesée, tant que le poids a un écran. */}
      {!POIDS_MASQUE && (
        <ul className="liste reglages-jour">
          <li className="ligne" onClick={() => setPeseeOuverte(true)}>
            <div className="ligne-tete">
              <span className="titre">Poids</span>
              <span className={pesee ? "" : "attenue"}>
                {pesee ? `${pesee.weight_kg.toLocaleString("fr-FR")} kg` : "Noter"}
              </span>
            </div>
          </li>
        </ul>
      )}

      {creneaux.map((creneau, i) => {
        const lignes = parCreneau(creneau.uuid)
        const note = notes.find((n) => n.meal_slot_uuid === creneau.uuid)?.note
        const consomme = consommeDu(creneau.uuid)
        const objectif = objectifs[i]
        const vide = lignes.length === 0 && !note
        const ecrireNote = () => setNoteDe({ uuid: creneau.uuid, nom: creneau.name })
        const ajouter = () => setAjoutDans({ uuid: creneau.uuid, nom: creneau.name })
        return (
          // Le titre, le total et les boutons dans la carte, et plus au-dessus :
          // un repas se lit comme un tout, et le chiffre reste collé au « + »
          // — « il me reste tant, j'ajoute ». Un créneau vide tient sur une
          // ligne, en retrait, sans carte à remplir.
          <section className={vide ? "repas-carte vide" : "repas-carte"} key={creneau.uuid}>
            <div className="tete-repas">
              <h3>{creneau.name}</h3>
              {vide ? (
                objectif && (
                  <span className="attenue petit">{Math.round(objectif.kcal)} kcal prévues</span>
                )
              ) : (
                <span className={"kcal-repas" + classeDe(consomme.kcal, objectif?.kcal ?? null)}>
                  {Math.round(consomme.kcal)}
                  {objectif && <span className="attenue"> / {Math.round(objectif.kcal)}</span>}
                </span>
              )}
              {/* Seulement tant qu'il n'y a pas de note : sinon on la touche
                  elle-même pour l'écrire, juste en dessous. */}
              {!note && (
                <button className="icone-repas" onClick={ecrireNote} aria-label={`Noter ${creneau.name}`}>
                  <Symbole nom="note.text" taille={17} />
                </button>
              )}
              <button className="ajouter" onClick={ajouter} aria-label={`Ajouter à ${creneau.name}`}>
                <svg
                  width="16"
                  height="16"
                  viewBox="0 0 24 24"
                  fill="none"
                  stroke="currentColor"
                  strokeWidth="2.2"
                  strokeLinecap="round"
                  aria-hidden
                >
                  <path d="M12 5v14M5 12h14" />
                </svg>
              </button>
            </div>
            {note && (
              <button className="note-du-repas" onClick={ecrireNote}>
                {note}
              </button>
            )}
            {lignes.length > 0 && (
              <>
                {/* Un appui long sur un aliment le soulève, et on le glisse à
                    sa place — voir `ListeGlissable`. Un appui bref l'ouvre. */}
                <ListeGlissable
                  elements={lignes}
                  onOrdre={(nouvelOrdre) => deplacement.mutate({ lignes, nouvelOrdre })}
                  ligne={(ligne) => {
                    const m = arrondi(macrosDe(ligne))
                    return (
                      // Toute la ligne est le bouton : sur un téléphone, viser
                      // un nom de trois lettres pour corriger une quantité est
                      // une cible qu'on rate.
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
                    )
                  }}
                />
                {deplacement.error && (
                  <p className="erreur">{(deplacement.error as Error).message}</p>
                )}
                {/* Les macros du repas contre celles que son objectif
                    adaptatif lui alloue — la même question que les calories
                    de l'en-tête, posée pour les trois autres. */}
                <div className="sous-total">
                  <LigneMacros m={consomme} objectif={cibles ? objectif : null} sansUnite />
                </div>
              </>
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

/// Un chevron dessiné, pour les flèches des jours et de l'ordre des aliments.
///
/// Un tracé plutôt que « ‹ » : un caractère apporte ses métriques de police et
/// ne se centre jamais tout à fait dans un rond.
function Chevron({ sens }: { sens: "gauche" | "droite" | "haut" | "bas" }) {
  const trace = {
    gauche: "M15 5l-7 7 7 7",
    droite: "M9 5l7 7-7 7",
    haut: "M5 15l7-7 7 7",
    bas: "M5 9l7 7 7-7",
  }[sens]
  return (
    <svg
      width="16"
      height="16"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="2.4"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden
    >
      <path d={trace} />
    </svg>
  )
}
