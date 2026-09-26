import { forwardRef, useEffect, useImperativeHandle, useLayoutEffect, useRef } from "react"

/// Ce qu'un champ de note offre à qui le pilote — la barre des citations, le
/// curseur posé à l'ouverture : le sous-ensemble d'un `textarea` dont on se
/// sert, et rien de plus.
export type ChampNote = {
  readonly value: string
  readonly selectionStart: number
  setSelectionRange: (debut: number, fin: number) => void
  focus: () => void
  addEventListener: HTMLElement["addEventListener"]
  removeEventListener: HTMLElement["removeEventListener"]
}

/// Une zone de note : un bloc éditable en texte brut, et non un `textarea`.
///
/// Safari sur iPhone range toute zone de texte parmi les champs qu'il peut
/// préremplir, et posait « Préremplir le contact » au-dessus du clavier de
/// chaque note — signalé. `autocomplete="off"` et un `name` neutre n'y ont rien
/// changé, essayé : il n'écoute que ses propres heuristiques. Un bloc
/// `contenteditable` n'est pas un champ de formulaire, et il ne le propose
/// jamais.
///
/// `plaintext-only` et `white-space: pre-wrap` : un retour à la ligne s'y écrit
/// alors comme un « \n » dans le texte, sans balise, si bien que le texte du
/// bloc est exactement la note.
export const ZoneNote = forwardRef<
  ChampNote,
  {
    value: string
    onChange: (valeur: string) => void
    placeholder?: string
    className?: string
    autoFocus?: boolean
  }
>(function ZoneNote({ value, onChange, placeholder, className, autoFocus }, ref) {
  const bloc = useRef<HTMLDivElement>(null)

  // Le texte vient du bloc tant qu'on tape ; il n'y est réécrit que quand la
  // valeur change d'ailleurs — une citation choisie, une photo jointe. Le
  // réécrire à chaque frappe renverrait le curseur au début.
  //
  // Réécrire le bloc y perd le curseur, qui retombe au début : il est remis
  // aussitôt derrière ce qui a changé — après la citation insérée, après la
  // photo jointe. La barre des citations le replace aussi, mais une image plus
  // tard, et une lettre tapée entre-temps partait en tête de la note.
  useLayoutEffect(() => {
    const el = bloc.current
    const avant = el?.textContent ?? ""
    if (!el || avant === value) return
    const avaitLaMain = document.activeElement === el
    el.textContent = value
    if (!avaitLaMain) return
    let fin = 0
    while (
      fin < avant.length &&
      fin < value.length &&
      avant[avant.length - 1 - fin] === value[value.length - 1 - fin]
    ) {
      fin++
    }
    placer(el, value.length - fin)
  }, [value])

  useEffect(() => {
    if (autoFocus) bloc.current?.focus()
  }, [autoFocus])

  useImperativeHandle(
    ref,
    () => ({
      get value() {
        return bloc.current?.textContent ?? ""
      },
      get selectionStart() {
        const el = bloc.current
        const sel = getSelection()
        if (!el || !sel || sel.rangeCount === 0) return el?.textContent?.length ?? 0
        const plage = sel.getRangeAt(0)
        if (!el.contains(plage.startContainer)) return el.textContent?.length ?? 0
        return decalage(el, plage.startContainer, plage.startOffset)
      },
      setSelectionRange(debut: number) {
        if (bloc.current) placer(bloc.current, debut)
      },
      focus() {
        bloc.current?.focus()
      },
      addEventListener(...args: Parameters<HTMLElement["addEventListener"]>) {
        bloc.current?.addEventListener(...args)
      },
      removeEventListener(...args: Parameters<HTMLElement["removeEventListener"]>) {
        bloc.current?.removeEventListener(...args)
      },
    }),
    [],
  )

  return (
    <div
      ref={bloc}
      className={className ? `zone-note ${className}` : "zone-note"}
      contentEditable="plaintext-only"
      role="textbox"
      aria-multiline
      aria-label={placeholder}
      data-placeholder={placeholder}
      suppressContentEditableWarning
      // Le collage fait à la main : inséré par le navigateur, un texte de
      // plusieurs lignes y perdait ses retours à la ligne — mesuré, « x\ny »
      // arrivait « xy ».
      onPaste={(e) => {
        const el = e.currentTarget
        const colle = e.clipboardData.getData("text/plain")
        const sel = getSelection()
        if (!colle || !sel || sel.rangeCount === 0) return
        e.preventDefault()
        const plage = sel.getRangeAt(0)
        const debut = decalage(el, plage.startContainer, plage.startOffset)
        const fin = decalage(el, plage.endContainer, plage.endOffset)
        const texte = el.textContent ?? ""
        const suivant = texte.slice(0, debut) + colle.replace(/\r\n?/g, "\n") + texte.slice(fin)
        el.textContent = suivant
        placer(el, suivant.length - (texte.length - fin))
        onChange(suivant)
      }}
      onInput={(e) => {
        const el = e.currentTarget
        const texte = el.textContent ?? ""
        // Vidé, le bloc garde parfois un `<br>` de remplissage : il ne serait
        // plus `:empty`, et le texte indicatif ne reviendrait pas.
        if (texte === "" && el.firstChild) el.replaceChildren()
        onChange(texte)
      }}
    />
  )
})

/// Combien de caractères du bloc précèdent ce point.
function decalage(el: HTMLElement, noeud: Node, offset: number): number {
  const avant = document.createRange()
  avant.selectNodeContents(el)
  avant.setEnd(noeud, offset)
  return avant.toString().length
}

/// Le curseur à `index` caractères du début du bloc.
function placer(el: HTMLElement, index: number) {
  const [noeud, decalage] = position(el, index)
  const plage = document.createRange()
  plage.setStart(noeud, decalage)
  plage.collapse(true)
  const sel = getSelection()
  sel?.removeAllRanges()
  sel?.addRange(plage)
}

/// Le nœud de texte et le décalage qui tombent à `index` caractères du début.
function position(el: HTMLElement, index: number): [Node, number] {
  const marche = document.createTreeWalker(el, NodeFilter.SHOW_TEXT)
  let reste = index
  let noeud = marche.nextNode()
  let dernier: Node | null = null
  while (noeud) {
    const longueur = noeud.textContent?.length ?? 0
    if (reste <= longueur) return [noeud, reste]
    reste -= longueur
    dernier = noeud
    noeud = marche.nextNode()
  }
  return dernier ? [dernier, dernier.textContent?.length ?? 0] : [el, 0]
}
