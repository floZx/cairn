import { supabase } from "./supabase"

/// Ajouter une photo à une note, depuis le téléphone.
///
/// Un portage de `JournalAttachmentRules` du Mac, ses trois règles comprises :
/// la taille qu'une image garde, le nom qu'elle prend, et la ligne de Markdown
/// qui la désigne. Trois règles qui doivent coïncider des deux côtés — le nom
/// est la clé que le texte de la note cite, et une divergence donnerait une
/// note qui pointe sur un fichier que personne ne trouve.

/// Beside the notes, not among them — le dossier que le Markdown nomme.
export const DOSSIER = "pieces-jointes"

/// Le plus grand côté qu'une image garde.
///
/// Un téléphone photographie en 3024 × 4032, et un journal ne montre jamais
/// plus que la largeur d'un écran. La valeur est celle du Mac, au pixel près :
/// deux tailles différentes donneraient deux poids selon l'appareil qui a
/// ajouté la photo.
export const COTE_MAX = 2048

/// Réduit une image et la rend en JPEG.
///
/// Toujours ré-encodée, à la différence du Mac qui recopie tel quel ce qui est
/// déjà plus petit : un iPhone livre du HEIC, que Safari sait décoder mais que
/// rien d'autre ne lit — ni le Mac par cette voie, ni le navigateur d'un autre.
/// Le JPEG est le format que tout le monde ouvre.
///
/// `createImageBitmap` plutôt qu'un `<img>` : il décode hors du fil principal,
/// et une photo de douze mégapixels y bloquerait l'interface une seconde.
export async function reduire(fichier: File): Promise<Blob> {
  const source = await createImageBitmap(fichier)
  const facteur = Math.min(1, COTE_MAX / Math.max(source.width, source.height))
  const largeur = Math.round(source.width * facteur)
  const hauteur = Math.round(source.height * facteur)

  const toile = document.createElement("canvas")
  toile.width = largeur
  toile.height = hauteur
  const pinceau = toile.getContext("2d")
  if (!pinceau) throw new Error("Impossible de préparer l'image.")
  pinceau.drawImage(source, 0, 0, largeur, hauteur)
  source.close()

  const blob = await new Promise<Blob | null>((resoudre) =>
    // 0,82 : au-delà le poids grimpe sans que l'œil y gagne, en deçà les
    // aplats du ciel se marbrent.
    toile.toBlob(resoudre, "image/jpeg", 0.82),
  )
  if (!blob) throw new Error("Impossible d'encoder l'image.")
  return blob
}

/// `AAAA-MM-JJ-N.jpg`, N étant le premier numéro libre du jour.
///
/// Le numéro est pris sans égard à l'extension — deux fichiers qui ne
/// différeraient que par elle se liraient comme la même photo. Le nom
/// d'origine est abandonné exprès : il vient d'un appareil ou d'une capture,
/// il ne dit rien, et deux « IMG_4032.jpg » finiraient par se rencontrer.
export function nomDeFichier(dateKey: string, pris: string[]): string {
  const racines = new Set(pris.map((nom) => nom.replace(/\.[^.]*$/, "")))
  let numero = 1
  while (racines.has(`${dateKey}-${numero}`)) numero += 1
  return `${dateKey}-${numero}.jpg`
}

/// Du Markdown ordinaire, jamais le `![[…]]` d'Obsidian : Obsidian lit les
/// deux, et le rendu d'ici n'a pas à apprendre une syntaxe qu'une seule
/// application possède.
export function lien(nomFichier: string): string {
  return `![](${DOSSIER}/${nomFichier})`
}

/// Le lien ajouté à la fin de la note.
///
/// Une ligne vide avant lui quand il y a du texte dont se séparer, aucune
/// quand la note est vide ou finit déjà par une : une note qui s'ouvre sur une
/// ligne blanche a l'air d'avoir été commencée par accident.
export function enAjoutant(lignes: string[], texte: string): string {
  if (lignes.length === 0) return texte
  const corps = lignes.join("\n")
  if (!texte) return corps
  if (texte.endsWith("\n\n")) return texte + corps
  if (texte.endsWith("\n")) return texte + "\n" + corps
  return texte + "\n\n" + corps
}

/// Envoie une photo et rend le lien Markdown qui la désigne.
///
/// Les octets partent **avant** la ligne : une note qui citerait une image
/// non encore déposée s'afficherait cassée le temps que l'envoi finisse, et
/// définitivement s'il échouait.
export async function ajouterPhoto(fichier: File, dateKey: string): Promise<string> {
  const { data: session } = await supabase.auth.getUser()
  const userID = session.user?.id
  if (!userID) throw new Error("Session expirée, reconnecte-toi.")

  const { data: existants, error: erreurListe } = await supabase
    .from("journal_attachment")
    .select("file_name")
    .like("file_name", `${dateKey}-%`)
  if (erreurListe) throw erreurListe

  const nom = nomDeFichier(dateKey, (existants ?? []).map((r) => r.file_name as string))
  const blob = await reduire(fichier)

  const { error: erreurEnvoi } = await supabase.storage
    .from("photos")
    .upload(`${userID}/journal/${nom}`, blob, {
      contentType: "image/jpeg",
      upsert: true,
    })
  if (erreurEnvoi) throw erreurEnvoi

  const maintenant = new Date().toISOString()
  const { error: erreurLigne } = await supabase.from("journal_attachment").insert({
    uuid: crypto.randomUUID(),
    user_id: userID,
    file_name: nom,
    added_at: maintenant,
    storage_path: `${userID}/journal/${nom}`,
    edited_at: maintenant,
  })
  if (erreurLigne) throw erreurLigne

  return lien(nom)
}
