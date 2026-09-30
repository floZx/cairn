import { useEffect, useRef, useState } from "react"

/// Les codes d'un emballage alimentaire : EAN en Europe, UPC pour l'import.
const FORMATS = ["ean_13", "ean_8", "upc_a", "upc_e"]

type Detecteur = { detect(source: HTMLVideoElement): Promise<{ rawValue: string }[]> }

/// Le détecteur du navigateur quand il en a un, sinon ZXing en WebAssembly.
///
/// Safari iOS n'a pas `BarcodeDetector` : c'est la bibliothèque qui lit, et
/// elle n'est chargée qu'ici, à la première ouverture du scanner — un
/// mégaoctet que l'application n'a pas à porter au démarrage. Son moteur est
/// servi depuis notre domaine et non depuis le CDN où elle irait le chercher
/// d'elle-même.
async function detecteur(): Promise<Detecteur> {
  const natif = (globalThis as { BarcodeDetector?: new (o: object) => Detecteur })
    .BarcodeDetector
  if (natif) return new natif({ formats: FORMATS })
  const [{ BarcodeDetector, prepareZXingModule }, { default: wasm }] = await Promise.all([
    import("barcode-detector/ponyfill"),
    import("zxing-wasm/reader/zxing_reader.wasm?url"),
  ])
  prepareZXingModule({
    overrides: {
      locateFile: (chemin: string, prefixe: string) =>
        chemin.endsWith(".wasm") ? wasm : prefixe + chemin,
    },
  })
  return new BarcodeDetector({ formats: FORMATS as never })
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
  const [erreur, setErreur] = useState<string | null>(null)

  useEffect(() => {
    let fini = false
    let flux: MediaStream | null = null
    let minuteur: ReturnType<typeof setTimeout> | undefined

    ;(async () => {
      try {
        const [lecteur, camera] = await Promise.all([
          detecteur(),
          navigator.mediaDevices.getUserMedia({
            video: { facingMode: "environment" },
            audio: false,
          }),
        ])
        flux = camera
        if (fini || !video.current) return
        video.current.srcObject = camera
        await video.current.play()

        // Cinq lectures par seconde : assez pour que le code soit pris dès
        // qu'il est net, assez peu pour ne pas chauffer le téléphone.
        const lire = async () => {
          if (fini || !video.current) return
          try {
            const trouves = await lecteur.detect(video.current)
            const code = trouves[0]?.rawValue
            if (code && !fini) {
              fini = true
              navigator.vibrate?.(40)
              onCode(code)
              return
            }
          } catch {
            // Une image illisible n'est pas une erreur : la suivante le sera peut-être moins.
          }
          minuteur = setTimeout(lire, 200)
        }
        lire()
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
      clearTimeout(minuteur)
      flux?.getTracks().forEach((piste) => piste.stop())
    }
  }, [onCode])

  return (
    <div className="scanner">
      <video ref={video} playsInline muted />
      <div className="scanner-viseur" />
      {erreur && <p className="scanner-erreur">{erreur}</p>}
      <button className="scanner-annuler" onClick={onFerme}>
        Annuler
      </button>
    </div>
  )
}
