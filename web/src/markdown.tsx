import type { ReactNode } from "react"

/// Un rendu Markdown minimal, écrit à la main plutôt qu'emprunté.
///
/// Ce que le journal et les descriptions d'activité contiennent réellement :
/// des paragraphes, du gras, de l'italique, des titres, des listes, des liens,
/// et des images. Une bibliothèque complète ferait cent fois ça pour deux cents
/// kilo-octets, et surtout il faut de toute façon détourner la résolution des
/// images — elles ne sont pas à une URL, elles sont dans Storage.
///
/// L'avant-propos YAML entre `---` est retiré : c'est de la métadonnée
/// qu'Obsidian écrit et que personne n'a demandé à lire. Le Mac fait pareil.

type Bloc =
  | { sorte: "titre"; niveau: number; texte: string }
  | { sorte: "paragraphe"; texte: string }
  | { sorte: "liste"; items: string[] }
  | { sorte: "image"; chemin: string; alt: string }

const imageSeule = /^!\[([^\]]*)\]\(([^)]+)\)$/

export function enBlocs(markdown: string): Bloc[] {
  const sansAvantPropos = markdown.replace(/^---\n[\s\S]*?\n---\n?/, "")
  const blocs: Bloc[] = []
  let liste: string[] = []

  const viderListe = () => {
    if (liste.length) {
      blocs.push({ sorte: "liste", items: liste })
      liste = []
    }
  }

  for (const ligne of sansAvantPropos.split("\n")) {
    const nette = ligne.trim()
    if (!nette) {
      viderListe()
      continue
    }
    const image = nette.match(imageSeule)
    if (image) {
      viderListe()
      blocs.push({ sorte: "image", alt: image[1], chemin: image[2] })
      continue
    }
    const titre = nette.match(/^(#{1,6})\s+(.*)$/)
    if (titre) {
      viderListe()
      blocs.push({ sorte: "titre", niveau: titre[1].length, texte: titre[2] })
      continue
    }
    const puce = nette.match(/^[-*]\s+(.*)$/)
    if (puce) {
      liste.push(puce[1])
      continue
    }
    viderListe()
    // Les lignes consécutives se rejoignent, comme en Markdown : un retour
    // simple n'est pas un paragraphe.
    const dernier = blocs[blocs.length - 1]
    if (dernier?.sorte === "paragraphe") dernier.texte += " " + nette
    else blocs.push({ sorte: "paragraphe", texte: nette })
  }
  viderListe()
  return blocs
}

/// Gras, italique et liens dans une ligne. Volontairement naïf : ces textes
/// sont écrits à la main dans un journal, pas produits par une machine.
export function enLigne(texte: string): ReactNode[] {
  const morceaux: ReactNode[] = []
  const motif = /(\*\*[^*]+\*\*)|(\*[^*]+\*)|(\[[^\]]+\]\([^)]+\))/g
  let dernierIndex = 0
  let m: RegExpExecArray | null
  let cle = 0

  while ((m = motif.exec(texte)) !== null) {
    if (m.index > dernierIndex) morceaux.push(texte.slice(dernierIndex, m.index))
    const brut = m[0]
    if (brut.startsWith("**")) {
      morceaux.push(<strong key={cle++}>{brut.slice(2, -2)}</strong>)
    } else if (brut.startsWith("*")) {
      morceaux.push(<em key={cle++}>{brut.slice(1, -1)}</em>)
    } else {
      const lien = brut.match(/^\[([^\]]+)\]\(([^)]+)\)$/)!
      morceaux.push(
        <a key={cle++} href={lien[2]} target="_blank" rel="noreferrer">
          {lien[1]}
        </a>,
      )
    }
    dernierIndex = m.index + brut.length
  }
  if (dernierIndex < texte.length) morceaux.push(texte.slice(dernierIndex))
  return morceaux
}

export function Markdown({
  texte,
  imageURL,
}: {
  texte: string
  /// Résout `pieces-jointes/x.jpg` en URL affichable. Rendue séparément parce
  /// que ces octets vivent dans Storage, derrière une URL signée, et qu'aucun
  /// chemin relatif ne pourrait les atteindre.
  imageURL?: (chemin: string) => string | undefined
}) {
  return (
    <>
      {enBlocs(texte).map((bloc, i) => {
        switch (bloc.sorte) {
          case "titre": {
            const Balise = `h${Math.min(bloc.niveau + 2, 6)}` as "h3"
            return <Balise key={i}>{enLigne(bloc.texte)}</Balise>
          }
          case "liste":
            return (
              <ul key={i}>
                {bloc.items.map((item, j) => (
                  <li key={j}>{enLigne(item)}</li>
                ))}
              </ul>
            )
          case "image": {
            const url = imageURL?.(bloc.chemin)
            if (!url) return null
            return <img key={i} className="image-note" src={url} alt={bloc.alt} />
          }
          default:
            return <p key={i}>{enLigne(bloc.texte)}</p>
        }
      })}
    </>
  )
}
