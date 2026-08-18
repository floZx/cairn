import { useEffect, useState } from "react"
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query"
import { supabase } from "./supabase"
import { assemble, chercherDansOFF, type Aliment } from "./off"
import { macrosDe } from "./macros"

type Recette = { uuid: string; name: string; meal_slot_uuid: string | null }

/// Les favoris et les aliments déjà consignés — ce qu'on mange vraiment,
/// devant le catalogue entier.
///
/// Les récents sont reconstruits depuis `food_entry` plutôt que stockés : le
/// Mac fait pareil, et une seconde table à tenir à jour dériverait du jour au
/// lendemain. Dédoublonnés par (nom, code) en gardant le plus récent, qui
/// porte la quantité la plus probable.
function useGardeManger() {
  return useQuery({
    queryKey: ["garde-manger"],
    staleTime: 5 * 60 * 1000,
    queryFn: async () => {
      const [favoris, recents, recettes] = await Promise.all([
        supabase
          .from("favorite_food")
          .select(
            "food_name, product_code, kcal100, protein100, carbs100, fat100, fiber100, grams",
          )
          .is("deleted_at", null),
        supabase
          .from("food_entry")
          .select(
            "food_name, product_code, kcal100, protein100, carbs100, fat100, fiber100, grams, date_key_raw",
          )
          .is("deleted_at", null)
          .order("date_key_raw", { ascending: false })
          .limit(400),
        supabase
          .from("recipe")
          .select("uuid, name, meal_slot_uuid")
          .is("deleted_at", null)
          .order("name"),
      ])
      if (favoris.error) throw favoris.error
      if (recents.error) throw recents.error
      if (recettes.error) throw recettes.error

      type Ligne = {
        food_name: string
        product_code: string | null
        kcal100: number
        protein100: number
        carbs100: number
        fat100: number
        fiber100: number | null
        grams: number
      }
      const enAliment = (l: Ligne, favori: boolean): Aliment => ({
        id: l.product_code ?? l.food_name,
        nom: l.food_name,
        marque: "",
        kcal100: l.kcal100,
        protein100: l.protein100,
        carbs100: l.carbs100,
        fat100: l.fat100,
        fiber100: l.fiber100,
        productCode: l.product_code,
        grammesFavori: favori ? l.grams : null,
      })

      const listeFavoris = (favoris.data as Ligne[]).map((l) => enAliment(l, true))
      const vus = new Set(listeFavoris.map((a) => `${a.nom}|${a.productCode ?? ""}`))
      const listeRecents: Aliment[] = []
      for (const ligne of recents.data as Ligne[]) {
        const cle = `${ligne.food_name}|${ligne.product_code ?? ""}`
        if (vus.has(cle)) continue
        vus.add(cle)
        // La quantité du dernier passage sert de proposition : on remange le
        // plus souvent la même portion.
        listeRecents.push({ ...enAliment(ligne, false), grammesFavori: ligne.grams })
      }
      return {
        favoris: listeFavoris,
        recents: listeRecents,
        recettes: recettes.data as Recette[],
      }
    },
  })
}

/// Le rang du prochain aliment de ce repas — `NutritionJournal`'s own rule:
/// le plus grand déjà posé, plus un.
async function prochainRang(dateKey: string, slotUUID: string): Promise<number> {
  const { data, error } = await supabase
    .from("food_entry")
    .select("sort_order")
    .eq("date_key_raw", dateKey)
    .eq("meal_slot_uuid", slotUUID)
    .is("deleted_at", null)
    .order("sort_order", { ascending: false })
    .limit(1)
  if (error) throw error
  return ((data?.[0]?.sort_order as number | undefined) ?? 0) + 1
}

async function identifiant(): Promise<string> {
  const { data } = await supabase.auth.getUser()
  const id = data.user?.id
  if (!id) throw new Error("Session expirée, reconnecte-toi.")
  return id
}

export function AjoutAliment({
  dateKey,
  slotUUID,
  slotNom,
  onFerme,
}: {
  dateKey: string
  slotUUID: string
  slotNom: string
  onFerme: () => void
}) {
  const [query, setQuery] = useState("")
  const [choisi, setChoisi] = useState<Aliment | null>(null)
  const [grammes, setGrammes] = useState("100")
  const garde = useGardeManger()
  const client = useQueryClient()

  // Recherche différée : on tape « saumon » lettre par lettre, et sans ce
  // délai chaque frappe partirait chez Open Food Facts.
  const [terme, setTerme] = useState("")
  useEffect(() => {
    const t = setTimeout(() => setTerme(query), 350)
    return () => clearTimeout(t)
  }, [query])

  const catalogue = useQuery({
    queryKey: ["off", terme],
    enabled: terme.trim().length >= 3,
    staleTime: 60 * 60 * 1000,
    queryFn: ({ signal }) => chercherDansOFF(terme, signal),
  })

  const enregistrement = useMutation({
    mutationFn: async () => {
      if (!choisi) return
      const poids = Number(grammes.replace(",", "."))
      if (!Number.isFinite(poids) || poids <= 0) throw new Error("Quantité invalide.")
      const maintenant = new Date().toISOString()
      const { error } = await supabase.from("food_entry").insert({
        uuid: crypto.randomUUID(),
        user_id: await identifiant(),
        date_key_raw: dateKey,
        meal_slot_uuid: slotUUID,
        product_code: choisi.productCode,
        food_name: choisi.nom,
        kcal100: choisi.kcal100,
        protein100: choisi.protein100,
        carbs100: choisi.carbs100,
        fat100: choisi.fat100,
        // Nulles quand la source n'a rien dit : le zéro ferait passer une
        // journée trouée pour une journée complète.
        fiber100: choisi.fiber100,
        grams: poids,
        sort_order: await prochainRang(dateKey, slotUUID),
        edited_at: maintenant,
      })
      if (error) throw error
    },
    onSuccess: () => {
      client.invalidateQueries({ queryKey: ["nutrition-jour", dateKey] })
      client.invalidateQueries({ queryKey: ["garde-manger"] })
      onFerme()
    },
  })

  const recette = useMutation({
    mutationFn: async (recetteUUID: string) => {
      const { data, error } = await supabase
        .from("recipe_item")
        .select(
          "food_name, product_code, kcal100, protein100, carbs100, fat100, fiber100, grams, sort_order",
        )
        .eq("recipe_uuid", recetteUUID)
        .is("deleted_at", null)
        .order("sort_order")
      if (error) throw error
      if (!data.length) throw new Error("Cette recette est vide.")

      const userID = await identifiant()
      const maintenant = new Date().toISOString()
      let rang = await prochainRang(dateKey, slotUUID)
      // Une seule requête pour toute la recette : un échec à mi-chemin
      // laisserait la moitié d'un porridge dans le journal.
      const lignes = data.map((item) => ({
        uuid: crypto.randomUUID(),
        user_id: userID,
        date_key_raw: dateKey,
        meal_slot_uuid: slotUUID,
        product_code: item.product_code,
        food_name: item.food_name,
        kcal100: item.kcal100,
        protein100: item.protein100,
        carbs100: item.carbs100,
        fat100: item.fat100,
        fiber100: item.fiber100,
        grams: item.grams,
        sort_order: rang++,
        edited_at: maintenant,
      }))
      const insertion = await supabase.from("food_entry").insert(lignes)
      if (insertion.error) throw insertion.error
    },
    onSuccess: () => {
      client.invalidateQueries({ queryKey: ["nutrition-jour", dateKey] })
      onFerme()
    },
  })

  if (choisi) {
    const apercu = macrosDe({ ...choisi, grams: Number(grammes.replace(",", ".")) || 0 })
    return (
      <div className="feuille">
        <div className="barre-editeur">
          <button className="lien" onClick={() => setChoisi(null)}>
            ‹ Retour
          </button>
          <span className="jour">{slotNom}</span>
          <button
            className="lien fort"
            onClick={() => enregistrement.mutate()}
            disabled={enregistrement.isPending}
          >
            {enregistrement.isPending ? "…" : "Ajouter"}
          </button>
        </div>
        {enregistrement.error && (
          <p className="erreur">{(enregistrement.error as Error).message}</p>
        )}
        <h3 className="nom-choisi">{choisi.nom}</h3>
        {choisi.marque && <p className="attenue petit">{choisi.marque}</p>}
        <label className="champ-quantite">
          <input
            type="number"
            inputMode="decimal"
            value={grammes}
            min={1}
            onChange={(e) => setGrammes(e.target.value)}
            autoFocus
          />
          <span>g</span>
        </label>
        <p className="macros">
          {Math.round(apercu.kcal)} kcal · {Math.round(apercu.proteines)} P ·{" "}
          {Math.round(apercu.glucides)} G · {Math.round(apercu.lipides)} L
        </p>
      </div>
    )
  }

  const liste = assemble(
    query,
    garde.data?.favoris ?? [],
    garde.data?.recents ?? [],
    catalogue.data ?? [],
  )
  // Les recettes du créneau d'abord, puis celles qui n'en visent aucun : une
  // recette de petit-déjeuner n'a rien à proposer au dîner.
  const recettes = (garde.data?.recettes ?? []).filter(
    (r) => !r.meal_slot_uuid || r.meal_slot_uuid === slotUUID,
  )

  return (
    <div className="feuille">
      <div className="barre-editeur">
        <button className="lien" onClick={onFerme}>
          Annuler
        </button>
        <span className="jour">{slotNom}</span>
        <span />
      </div>
      {/* Le curseur y est d'emblée, et le clavier avec lui : on n'ouvre cette
          feuille que pour chercher quelque chose, et l'ouvrir sur un champ
          vide qu'il faut encore aller toucher fait un geste de plus pour rien.
          C'est déjà ce que font la quantité et la pesée. */}
      <input
        className="recherche"
        type="search"
        value={query}
        onChange={(e) => setQuery(e.target.value)}
        placeholder="Chercher un aliment…"
        autoFocus
      />
      {recette.error && <p className="erreur">{(recette.error as Error).message}</p>}

      {!query && recettes.length > 0 && (
        <>
          <h4 className="titre-section">Recettes</h4>
          <ul className="choix">
            {recettes.map((r) => (
              <li key={r.uuid}>
                <button onClick={() => recette.mutate(r.uuid)} disabled={recette.isPending}>
                  <span className="nom">{r.name}</span>
                  <span className="attenue petit">recette</span>
                </button>
              </li>
            ))}
          </ul>
          <h4 className="titre-section">Aliments</h4>
        </>
      )}

      {catalogue.isFetching && <p className="attenue petit">Recherche…</p>}
      {catalogue.error && <p className="erreur">{(catalogue.error as Error).message}</p>}
      {query.trim().length > 0 && query.trim().length < 3 && (
        <p className="attenue petit">Trois lettres au moins pour chercher au catalogue.</p>
      )}

      {liste.length > 0 && <p className="attenue petit unite-liste">pour 100 g</p>}
      <ul className="choix">
        {liste.map((a) => (
          <li key={`${a.id}-${a.nom}`}>
            <button
              onClick={() => {
                setChoisi(a)
                setGrammes(String(Math.round(a.grammesFavori ?? 100)))
              }}
            >
              <span className="nom">
                {a.grammesFavori !== null && a.marque === "" ? "★ " : ""}
                {a.nom}
              </span>
              {/* Les quatre macros et les fibres, dans la forme exacte du
                  Mac : c'est la même question qu'on pose à la même liste, et
                  n'afficher ici que les calories obligeait à choisir un
                  aliment pour découvrir ce qu'il apportait vraiment.

                  Le tiret des fibres est ce qui rend le choix possible : une
                  absence muette ne se distinguerait pas d'une colonne qu'on
                  aurait oublié d'afficher, alors qu'elle est justement le
                  critère — entre deux flocons équivalents, prendre celui dont
                  la fiche est complète.

                  « /100 g » est dit une fois au-dessus de la liste et non sur
                  chaque rang : répété, il faisait passer toutes les lignes à
                  deux sur un écran de téléphone, et coupait la liste de moitié
                  pour une mention qui ne change jamais. */}
              <span className="attenue petit">
                {a.marque && `${a.marque} · `}
                {Math.round(a.kcal100)} kcal · P {Math.round(a.protein100)} · G{" "}
                {Math.round(a.carbs100)} · L {Math.round(a.fat100)} ·{" "}
                {a.fiber100 === null ? "F —" : `F ${Math.round(a.fiber100)}`}
              </span>
            </button>
          </li>
        ))}
      </ul>
      {liste.length === 0 && !catalogue.isFetching && (
        <p className="attenue">Rien trouvé.</p>
      )}
    </div>
  )
}
