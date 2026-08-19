import { useMemo, useState } from "react"
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query"
import { supabase } from "./supabase"
import { IconeSport, couleurDuSport } from "./IconeSport"
import { nomDuSport, SPORTS } from "./sports"
import { dateLongue } from "./format"
import { distance as formatDistance, duree as formatDuree } from "./format"
import { Feuille } from "./Chrome"
import { apparie, objectifResume, semainesDuMois } from "./plan"

/// Le plan d'entraînement, mois par mois.
///
/// Une grille et non une liste, comme sur le Mac : un plan se lit par
/// semaines — trois séances et deux jours de repos — et une liste verticale de
/// dates cache précisément ce rythme-là.
///
/// La grille reste compacte sur un téléphone : une case n'y porte que des
/// icônes, et le détail du jour choisi se lit sous la grille, là où il y a la
/// place de l'écrire.

type Seance = {
  uuid: string
  date_key_raw: string
  sport_type_raw: string
  title: string
  planned_distance: number | null
  planned_duration: number | null
  planned_elevation: number | null
  notes: string
  day_type_uuid: string | null
  sort_order: number
}

type Sortie = {
  uuid: string
  name: string
  sport_type_raw: string
  start_local_date: string
  distance: number | null
  moving_time: number | null
}

async function identifiant(): Promise<string> {
  const { data } = await supabase.auth.getUser()
  const id = data.user?.id
  if (!id) throw new Error("Session expirée, reconnecte-toi.")
  return id
}

const deux = (n: number) => String(n).padStart(2, "0")

function cleDuJour(d: Date): string {
  return `${d.getFullYear()}-${deux(d.getMonth() + 1)}-${deux(d.getDate())}`
}

/// Le mois d'un jour, et ses bornes — les deux dates que les requêtes
/// encadrent.
function bornes(annee: number, mois: number) {
  const debut = `${annee}-${deux(mois + 1)}-01`
  const dernier = new Date(annee, mois + 1, 0).getDate()
  return { debut, fin: `${annee}-${deux(mois + 1)}-${deux(dernier)}` }
}

/// Deux requêtes et non une, séparées exprès.
///
/// Une seule les aurait perdues ensemble : une colonne — ou ici une table —
/// absente fait échouer la requête **entière**, et le plan n'existe pas tant
/// que la migration 007 n'est pas passée. Groupées, l'absence du plan aurait
/// aussi effacé les sorties, c'est-à-dire tout l'écran. La leçon vient des
/// fibres, qui avaient fait disparaître la feuille d'ajout d'un aliment.
function usePlan(annee: number, mois: number) {
  const { debut, fin } = bornes(annee, mois)
  return useQuery({
    queryKey: ["plan-mois", debut],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("planned_session")
        .select(
          "uuid, date_key_raw, sport_type_raw, title, planned_distance, planned_duration, planned_elevation, notes, day_type_uuid, sort_order",
        )
        .is("deleted_at", null)
        .gte("date_key_raw", debut)
        .lte("date_key_raw", fin)
        .order("date_key_raw")
        .order("sort_order")
      if (error) throw error
      return data as Seance[]
    },
  })
}

function useSorties(annee: number, mois: number) {
  const { debut, fin } = bornes(annee, mois)
  return useQuery({
    queryKey: ["plan-sorties", debut],
    queryFn: async () => {
      // `start_local_date` porte l'heure murale estampillée `+00:00` — d'où
      // les bornes en texte, qui décaleraient d'un jour en passant par une
      // date.
      const { data, error } = await supabase
        .from("activity")
        .select("uuid, name, sport_type_raw, start_local_date, distance, moving_time")
        .is("deleted_at", null)
        .gte("start_local_date", `${debut}T00:00:00`)
        .lte("start_local_date", `${fin}T23:59:59`)
        .order("start_local_date")
      if (error) throw error
      return data as Sortie[]
    },
  })
}

export function Entrainement() {
  const aujourdhui = cleDuJour(new Date())
  const [jour, setJour] = useState(aujourdhui)
  const [annee, mois] = useMemo(() => {
    const [a, m] = jour.split("-").map(Number)
    return [a, m - 1]
  }, [jour])
  const [aEditer, setAEditer] = useState<Seance | "nouvelle" | null>(null)

  const plan = usePlan(annee, mois)
  const sorties = useSorties(annee, mois)

  const parJour = useMemo(() => {
    const table = new Map<string, { seances: Seance[]; sorties: Sortie[] }>()
    for (const seance of plan.data ?? []) {
      const case_ = table.get(seance.date_key_raw) ?? { seances: [], sorties: [] }
      case_.seances.push(seance)
      table.set(seance.date_key_raw, case_)
    }
    for (const sortie of sorties.data ?? []) {
      const cle = sortie.start_local_date.slice(0, 10)
      const case_ = table.get(cle) ?? { seances: [], sorties: [] }
      case_.sorties.push(sortie)
      table.set(cle, case_)
    }
    return table
  }, [plan.data, sorties.data])

  const rapprochement = (cle: string) => {
    const case_ = parJour.get(cle) ?? { seances: [], sorties: [] }
    return apparie(
      case_.seances,
      case_.sorties,
      (s) => s.sport_type_raw,
      (a) => a.sport_type_raw,
    )
  }

  const semaines = semainesDuMois(annee, mois)
  const duJour = rapprochement(jour)

  const glisser = (pas: number) => {
    const d = new Date(annee, mois + pas, 1)
    setJour(cleDuJour(d))
  }

  return (
    <>
      <div className="barre-jour">
        <button className="lien" onClick={() => glisser(-1)} aria-label="Mois précédent">
          ‹
        </button>
        <span className="jour">
          {new Date(annee, mois, 1)
            .toLocaleDateString("fr-FR", { month: "long", year: "numeric" })
            .replace(/^./, (c) => c.toUpperCase())}
        </span>
        <button className="lien" onClick={() => glisser(1)} aria-label="Mois suivant">
          ›
        </button>
      </div>

      {plan.error && <p className="erreur">{(plan.error as Error).message}</p>}
      {sorties.error && <p className="erreur">{(sorties.error as Error).message}</p>}

      <div className="grille-plan">
        {["L", "M", "M", "J", "V", "S", "D"].map((nom, index) => (
          <span className="entete-jour" key={index}>
            {nom}
          </span>
        ))}
        {semaines.flat().map((cle, index) =>
          cle === null ? (
            <span className="case-plan vide" key={`vide-${index}`} />
          ) : (
            <button
              key={cle}
              className={[
                "case-plan",
                cle === jour ? "choisie" : "",
                cle === aujourdhui ? "aujourdhui" : "",
              ]
                .filter(Boolean)
                .join(" ")}
              onClick={() => setJour(cle)}
            >
              <span className="numero">{Number(cle.slice(8))}</span>
              <span className="points">
                {rapprochement(cle).paires.map((paire, rang) => (
                  <span
                    key={rang}
                    className={paire.sortie ? "point-plan fait" : "point-plan"}
                    style={{ background: couleurDuSport(paire.seance.sport_type_raw) }}
                  />
                ))}
                {rapprochement(cle).enPlus.map((sortie) => (
                  <span
                    key={sortie.uuid}
                    className="point-plan libre"
                    style={{ borderColor: couleurDuSport(sortie.sport_type_raw) }}
                  />
                ))}
              </span>
            </button>
          ),
        )}
      </div>

      <h2 className="titre-jour-plan">{dateLongue(jour)}</h2>

      {plan.isPending && sorties.isPending ? (
        <p className="attenue petit">…</p>
      ) : (
        <>
          {duJour.paires.map(({ seance, sortie }) => (
            <button
              key={seance.uuid}
              className="seance"
              onClick={() => setAEditer(seance)}
            >
              <span className="tete-seance">
                <IconeSport sport={seance.sport_type_raw} taille={22} />
                <span className="intitule">
                  {seance.title || nomDuSport(seance.sport_type_raw)}
                </span>
                {sortie && <span className="fait">✓</span>}
              </span>
              {objectifResume(
                seance.planned_distance,
                seance.planned_duration,
                seance.planned_elevation,
              ) && (
                <span className="attenue petit">
                  {objectifResume(
                    seance.planned_distance,
                    seance.planned_duration,
                    seance.planned_elevation,
                  )}
                </span>
              )}
              {seance.notes && <span className="notes-seance">{seance.notes}</span>}
              {sortie && (
                <span className="attenue petit accompli">
                  {sortie.name}
                  {sortie.distance ? ` · ${formatDistance(sortie.distance)}` : ""}
                  {sortie.moving_time ? ` · ${formatDuree(sortie.moving_time)}` : ""}
                </span>
              )}
            </button>
          ))}

          {duJour.enPlus.map((sortie) => (
            <div className="seance hors-plan" key={sortie.uuid}>
              <span className="tete-seance">
                <IconeSport sport={sortie.sport_type_raw} taille={22} />
                <span className="intitule">{sortie.name}</span>
              </span>
              <span className="attenue petit">Hors du plan</span>
            </div>
          ))}

          {duJour.paires.length === 0 && duJour.enPlus.length === 0 && (
            <p className="attenue petit">Rien de prévu ce jour-là.</p>
          )}

          <button className="bouton" onClick={() => setAEditer("nouvelle")}>
            Ajouter une séance
          </button>
        </>
      )}

      {aEditer && (
        <Feuille
          titre={aEditer === "nouvelle" ? "Nouvelle séance" : "Modifier la séance"}
          onFerme={() => setAEditer(null)}
        >
          <SaisieSeance
            dateKey={jour}
            seance={aEditer === "nouvelle" ? null : aEditer}
            rangSuivant={duJour.paires.length}
            onFerme={() => setAEditer(null)}
          />
        </Feuille>
      )}
    </>
  )
}

/// Écrire ou modifier une séance, comme la feuille du Mac.
function SaisieSeance({
  dateKey,
  seance,
  rangSuivant,
  onFerme,
}: {
  dateKey: string
  seance: Seance | null
  rangSuivant: number
  onFerme: () => void
}) {
  const [sport, setSport] = useState(seance?.sport_type_raw ?? "run")
  const [titre, setTitre] = useState(seance?.title ?? "")
  // En kilomètres et en minutes, comme sur le Mac : un plan s'écrit
  // « 18 km, 1 h 30 », jamais « 18000 m, 5400 s ».
  const [km, setKm] = useState(
    seance?.planned_distance != null ? String(seance.planned_distance / 1000) : "",
  )
  const [minutes, setMinutes] = useState(
    seance?.planned_duration != null ? String(Math.round(seance.planned_duration / 60)) : "",
  )
  const [denivele, setDenivele] = useState(
    seance?.planned_elevation != null ? String(seance.planned_elevation) : "",
  )
  const [notes, setNotes] = useState(seance?.notes ?? "")
  const client = useQueryClient()

  const nombre = (texte: string): number | null => {
    const propre = texte.trim().replace(",", ".")
    if (propre === "") return null
    const valeur = Number(propre)
    return Number.isFinite(valeur) ? valeur : null
  }

  const rafraichir = () => {
    client.invalidateQueries({ queryKey: ["plan-mois"] })
    onFerme()
  }

  const enregistrement = useMutation({
    mutationFn: async () => {
      const maintenant = new Date().toISOString()
      const { error } = await supabase.from("planned_session").upsert({
        uuid: seance?.uuid ?? crypto.randomUUID(),
        user_id: await identifiant(),
        date_key_raw: dateKey,
        sport_type_raw: sport,
        title: titre,
        planned_distance: km.trim() === "" ? null : (nombre(km) ?? 0) * 1000,
        planned_duration: minutes.trim() === "" ? null : (nombre(minutes) ?? 0) * 60,
        planned_elevation: nombre(denivele),
        notes,
        day_type_uuid: seance?.day_type_uuid ?? null,
        sort_order: seance?.sort_order ?? rangSuivant,
        edited_at: maintenant,
        deleted_at: null,
      })
      if (error) throw error
    },
    onSuccess: rafraichir,
  })

  const suppression = useMutation({
    mutationFn: async () => {
      if (!seance) return
      const maintenant = new Date().toISOString()
      const { error } = await supabase
        .from("planned_session")
        .update({ deleted_at: maintenant, edited_at: maintenant })
        .eq("uuid", seance.uuid)
      if (error) throw error
    },
    onSuccess: rafraichir,
  })

  const occupe = enregistrement.isPending || suppression.isPending

  return (
    <>
      <div className="barre-editeur">
        <button className="lien" onClick={onFerme} disabled={occupe}>
          Annuler
        </button>
        <span className="jour">{dateLongue(dateKey)}</span>
        <button
          className="lien fort"
          onClick={() => enregistrement.mutate()}
          disabled={occupe}
        >
          {enregistrement.isPending ? "…" : "Enregistrer"}
        </button>
      </div>
      {(enregistrement.error || suppression.error) && (
        <p className="erreur">
          {((enregistrement.error ?? suppression.error) as Error).message}
        </p>
      )}

      <label className="ligne-champ">
        <span>Sport</span>
        <select value={sport} onChange={(e) => setSport(e.target.value)}>
          {SPORTS.map((brut) => (
            <option key={brut} value={brut}>
              {nomDuSport(brut)}
            </option>
          ))}
        </select>
      </label>

      <label className="ligne-champ">
        <span>Intitulé</span>
        <input
          value={titre}
          onChange={(e) => setTitre(e.target.value)}
          placeholder="6×45″ en côte"
        />
      </label>

      <div className="trois-champs">
        <label className="ligne-champ">
          <span>Distance</span>
          <input
            inputMode="decimal"
            value={km}
            onChange={(e) => setKm(e.target.value)}
            placeholder="km"
          />
        </label>
        <label className="ligne-champ">
          <span>Durée</span>
          <input
            inputMode="numeric"
            value={minutes}
            onChange={(e) => setMinutes(e.target.value)}
            placeholder="min"
          />
        </label>
        <label className="ligne-champ">
          <span>D+</span>
          <input
            inputMode="numeric"
            value={denivele}
            onChange={(e) => setDenivele(e.target.value)}
            placeholder="m"
          />
        </label>
      </div>

      <textarea
        className="saisie-note courte"
        value={notes}
        onChange={(e) => setNotes(e.target.value)}
        placeholder="Séries, allures, consignes…"
      />

      {seance && (
        <button
          className="lien danger"
          onClick={() => suppression.mutate()}
          disabled={occupe}
        >
          Supprimer la séance
        </button>
      )}
    </>
  )
}
