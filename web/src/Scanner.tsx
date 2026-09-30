import { useEffect, useRef, useState } from "react"
import type { ReaderOptions } from "zxing-wasm/reader"

/// Les codes d'un emballage alimentaire : EAN en Europe, UPC pour l'import.
const FORMATS: ReaderOptions["formats"] = ["EAN13", "EAN8", "UPCA", "UPCE"]

/// Réglés pour la vitesse sur une image déjà cadrée : un seul code, jamais
/// retourné ni inversé — un emballage se présente à l'endroit dans le cadre.
const OPTIONS: ReaderOptions = {
  formats: FORMATS,
  maxNumberOfSymbols: 1,
  tryRotate: false,
  tryInvert: false,
}

/// La largeur à laquelle la zone du cadre est lue. Un EAN y tient avec de la
/// marge, et le moteur a dix fois moins de pixels qu'avec l'image entière.
const LARGEUR_LUE = 640

type Lecteur = (image: ImageData) => Promise<string | null>

let moteur: Promise<Lecteur> | null = null

/// ZXing en WebAssembly — Safari iOS n'a pas `BarcodeDetector`.
///
/// Chargé une fois, et appelé dès l'ouverture de la feuille d'ajout plutôt
/// qu'au toucher de l'icône : un mégaoctet à télécharger et compiler, c'était
/// l'essentiel de l'attente au premier scan. Servi depuis notre domaine, et
/// non depuis le CDN où il irait le chercher de lui-même.
export function prechargerLecteur(): Promise<Lecteur> {
  moteur ??= (async () => {
    const [{ prepareZXingModule, readBarcodes }, { default: wasm }] = await Promise.all([
      import("zxing-wasm/reader"),
      import("zxing-wasm/reader/zxing_reader.wasm?url"),
    ])
    await prepareZXingModule({
      overrides: {
        locateFile: (chemin: string, prefixe: string) =>
          chemin.endsWith(".wasm") ? wasm : prefixe + chemin,
      },
      fireImmediately: true,
    })
    return async (image: ImageData) => {
      const [trouve] = await readBarcodes(image, OPTIONS)
      return trouve?.isValid ? trouve.text : null
    }
  })()
  // Un échec de chargement ne doit pas rester en cache : la prochaine
  // ouverture réessaie.
  moteur.catch(() => {
    moteur = null
  })
  return moteur
}

/// La zone de l'image que le cadre recouvre à l'écran, un peu élargie.
///
/// La vidéo remplit l'écran en `object-fit: cover` : elle est agrandie et
/// rognée, et le cadre dessiné par-dessus ne correspond à rien de simple dans
/// l'image d'origine sans ce calcul.
function zoneDuCadre(video: HTMLVideoElement, cadre: DOMRect) {
  const ecran = video.getBoundingClientRect()
  const echelle = Math.max(ecran.width / video.videoWidth, ecran.height / video.videoHeight)
  const decalageX = (ecran.width - video.videoWidth * echelle) / 2
  const decalageY = (ecran.height - video.videoHeight * echelle) / 2
  // Un tiers de hauteur en plus : un code tenu un peu haut ou bas se lit quand même.
  const marge = cadre.height / 3
  const x = Math.max(0, (cadre.left - ecran.left - decalageX) / echelle)
  const y = Math.max(0, (cadre.top - marge - ecran.top - decalageY) / echelle)
  const largeur = Math.min(video.videoWidth - x, cadre.width / echelle)
  const hauteur = Math.min(video.videoHeight - y, (cadre.height + 2 * marge) / echelle)
  return { x, y, largeur, hauteur }
}

/// La caméra arrière en plein écran, jusqu'au premier code lu.
///
/// Rend le code tel quel : chercher le produit est l'affaire de la feuille
/// d'ajout, qui sait aussi regarder dans les favoris.
export function Scanner({
  onCode,
  onFerme,
}: {
  onCode: (code: string) => void
  onFerme: () => void
}) {
  const video = useRef<HTMLVideoElement>(null)
  const cadre = useRef<HTMLDivElement>(null)
  const [erreur, setErreur] = useState<string | null>(null)

  useEffect(() => {
    let fini = false
    let flux: MediaStream | null = null
    const toile = document.createElement("canvas")
    const contexte = toile.getContext("2d", { willReadFrequently: true })

    ;(async () => {
      try {
        const [lire, camera] = await Promise.all([
          prechargerLecteur(),
          navigator.mediaDevices.getUserMedia({
            // La définition d'une vidéo HD : de quoi lire un code tenu à
            // bout de bras, et la zone du cadre est réduite avant lecture.
            video: { facingMode: "environment", width: { ideal: 1920 }, height: { ideal: 1080 } },
            audio: false,
          }),
        ])
        flux = camera
        if (fini || !video.current) return
        video.current.srcObject = camera
        await video.current.play()

        // Une lecture après l'autre, sans pause : chacune ne porte que sur la
        // zone du cadre, réduite, et laisse la main entre deux images.
        while (!fini && video.current && contexte) {
          const v = video.current
          if (v.videoWidth && cadre.current) {
            const zone = zoneDuCadre(v, cadre.current.getBoundingClientRect())
            const reduction = Math.min(1, LARGEUR_LUE / zone.largeur)
            toile.width = Math.round(zone.largeur * reduction)
            toile.height = Math.round(zone.hauteur * reduction)
            contexte.drawImage(
              v, zone.x, zone.y, zone.largeur, zone.hauteur, 0, 0, toile.width, toile.height,
            )
            try {
              const code = await lire(contexte.getImageData(0, 0, toile.width, toile.height))
              if (code && !fini) {
                fini = true
                navigator.vibrate?.(40)
                onCode(code)
                return
              }
            } catch {
              // Une image illisible n'est pas une erreur : la suivante le sera peut-être moins.
            }
          }
          await new Promise((suite) => requestAnimationFrame(suite))
        }
      } catch (e) {
        const nom = (e as Error).name
        setErreur(
          nom === "NotAllowedError"
            ? "Cairn n'a pas accès à la caméra. Autorise-la dans les réglages de Safari."
            : `Caméra indisponible : ${(e as Error).message}`,
        )
      }
    })()

    return () => {
      fini = true
      flux?.getTracks().forEach((piste) => piste.stop())
    }
  }, [onCode])

  return (
    <div className="scanner">
      <video ref={video} playsInline muted />
      <div ref={cadre} className="scanner-viseur" />
      {erreur && <p className="scanner-erreur">{erreur}</p>}
      <button className="scanner-annuler" onClick={onFerme}>
        Annuler
      </button>
    </div>
  )
}
