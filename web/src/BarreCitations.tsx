import { useEffect, useState, type RefObject } from "react"
import { useQuery } from "@tanstack/react-query"
import { supabase } from "./supabase"
import { citations, enCoursDe, propositions, type Personne } from "./citations"

/// La barre de propositions qui se pose au-dessus d'un champ quand on tape `@`.
///
/// L'annuaire est demandé une fois par session : relire les notes à chaque
/// lettre pour proposer six noms serait payer très cher un service très
/// simple. Quelqu'un cité pour la première fois dans la note qu'on écrit n'y
/// figure donc pas encore, ce qui est sans conséquence — on est justement en
/// train de taper son nom en entier.
function useAnnuaire() {
  return useQuery({
    queryKey: ["annuaire-citations"],
    staleTime: 5 * 60 * 1000,
    queryFn: async () => {
      const [fiches, notes, sorties] = await Promise.all([
        supabase.from("person").select("name").is("deleted_at", null),
        supabase.from("journal_note").select("text").is("deleted_at", null),
        supabase
          .from("activity")
          .select("activity_description")
          .is("deleted_at", null)
          .not("activity_description", "is", null),
      ])
      const table = new Map<string, Personne>()
      const ajoute = (texte: string) => {
        for (const qui of citations(texte)) table.set(qui.cle, qui)
      }
      for (const f of (fiches.data ?? []) as { name: string }[]) ajoute(`@${f.name}`)
      for (const n of (notes.data ?? []) as { text: string }[]) ajoute(n.text)
      for (const a of (sorties.data ?? []) as { activity_description: string }[]) {
        ajoute(a.activity_description)
      }
      return [...table.values()]
    },
  })
}

export function BarreCitations({
  aire,
  texte,
  onTexte,
}: {
  /// Le champ surveillé. Une référence plutôt qu'une valeur : c'est lui qui
  /// sait où est le curseur, et c'est toute la question.
  aire: RefObject<HTMLTextAreaElement | null>
  texte: string
  onTexte: (valeur: string) => void
}) {
  const annuaire = useAnnuaire()
  const [enCours, setEnCours] = useState<{ fragment: string; debut: number } | null>(null)

  useEffect(() => {
    const champ = aire.current
    if (!champ) return
    const relire = () => setEnCours(enCoursDe(champ.value, champ.selectionStart ?? 0))
    // Les trois moments où le curseur peut bouger : la frappe, les flèches, le
    // doigt posé ailleurs dans le texte.
    champ.addEventListener("input", relire)
    champ.addEventListener("keyup", relire)
    champ.addEventListener("click", relire)
    champ.addEventListener("blur", () => setEnCours(null))
    return () => {
      champ.removeEventListener("input", relire)
      champ.removeEventListener("keyup", relire)
      champ.removeEventListener("click", relire)
    }
  }, [aire])

  const choix = enCours ? propositions(enCours.fragment, annuaire.data ?? []) : []
  if (!enCours || choix.length === 0) return null

  const choisir = (qui: Personne) => {
    const champ = aire.current
    const curseur = champ?.selectionStart ?? texte.length
    const avant = texte.slice(0, enCours.debut)
    const apres = texte.slice(curseur)
    const insere = `@${qui.nom} `
    onTexte(avant + insere + apres)
    setEnCours(null)
    // Le curseur derrière ce qu'on vient d'insérer, et le champ qui garde la
    // main : sans ça, choisir un nom renvoie le doigt en haut du texte.
    requestAnimationFrame(() => {
      if (!champ) return
      const position = avant.length + insere.length
      champ.focus()
      champ.setSelectionRange(position, position)
    })
  }

  return (
    <div className="barre-citations">
      {choix.map((qui) => (
        // `onMouseDown` et non `onClick` : le `blur` du champ part le premier
        // et referme la barre avant que le clic n'arrive.
        <button
          key={qui.cle}
          className="proposition"
          onMouseDown={(e) => {
            e.preventDefault()
            choisir(qui)
          }}
        >
          @{qui.nom}
        </button>
      ))}
    </div>
  )
}
