# Montage de la démo cinq minutes

Le montage v4 conserve les 300 secondes, les 9 000 images à 30 fps, l'ordre des scènes et les positions de la piste audio du MP4 v3 fourni. Il ajoute un habillage et des raccords ; il ne modifie pas le comportement de l'application. Les captures historiques ne constituent pas une nouvelle preuve des capacités du produit.

Les médias restent locaux et ne sont pas ajoutés à Git. Le script vérifie l'empreinte SHA-256 du fichier v3 pour éviter d'appliquer ses coordonnées à une autre vidéo : `07dde8b6e714352c2dadd85aac1b4086ef1f45992690579e0add3302210f5f55`.

## Changements

- Remplacement du titre extérieur « MORE » par le nouveau mot-symbole pointillé et la nouvelle icône. Les PNG du mot-symbole sont exportés directement depuis `MorningBrandArtwork`, avec les mêmes proportions et couleurs. Les icônes sont celles du catalogue iOS approuvé.
- Six raccords courts, limités à l'intérieur de l'écran : 00:46, 00:57, 01:16, 02:32, 02:37 et 02:55. Les alertes et transitions natives déjà animées ne reçoivent pas de fondu supplémentaire.
- De 04:00 à 04:07, le fond extérieur passe progressivement au bleu nuit. Les légendes originales gardent leur texte et leurs instants d'apparition ; le logo et l'icône passent à leur variante nuit.
- À 04:46, disparition du décor et du téléphone sur noir en conservant le croissant. Après un bref maintien, le croissant monte vers la gauche et grandit jusqu'à la position de la lune du Duo. Les points réels des deux images servent au raccord ; les étoiles isolées sont rejetées du détourage.
- Le Duo apparaît derrière la lune de 04:50 à 04:51, puis rejoint son plan d'origine. Une petite signature nuit occupe la marge noire, puis suit la disparition finale.

## Reproduire

Prérequis locaux : macOS, compilateur Swift des outils Xcode, `ffmpeg`, `ffprobe`, Python avec Pillow et numpy. Aucun service distant n'est utilisé. Le fichier de sortie doit être nouveau ; le script refuse d'écraser un fichier existant.

```sh
python3 scripts/media/polish-demo.py /chemin/MORE-five-minute-v3.mp4 /chemin/MORE-five-minute-v4.mp4
```

Pour vérifier un passage avant l'export complet :

```sh
python3 scripts/media/polish-demo.py /chemin/MORE-five-minute-v3.mp4 /chemin/apercu-fin.mp4 --start 284 --end 294
```

Les bornes sont des timecodes source alignés à 30 fps. Le mode aperçu peut inclure un dernier paquet AAC dépassant légèrement la durée vidéo ; l'export complet vérifie la durée totale exacte. La piste audio est copiée, sans filtre ni réencodage. Pour l'export complet, le script compare tous les paquets AAC : empreintes SHA-256, PTS, DTS, durées, tailles et informations de priming. Il refuse la livraison en cas de différence. Un fichier `.verification.json` accompagne la sortie.

## Vérifications

Les contrôles comprennent la compilation de l'exporteur Swift, la validation syntaxique Python, les vues de contrôle du jour, de la nuit et du transport de la lune, puis les assertions de durée, de nombre d'images et de conservation audio lors de l'export complet. Aucun test de l'application ou test sur iPhone n'est impliqué par ce travail de montage.

## Propositions pour une passe suivante

Ces ajouts ne sont pas inclus dans v4 :

1. **01:40–01:50 :** faire apparaître le titre « The next morning » en douceur pendant le mouvement du soleil déjà présent. Garder sa position et son timecode, avec un léger dévoilement plutôt qu'un changement de scène supplémentaire.
2. **Autour de 02:25 :** accompagner l'apparition de la liste de courses d'une mise en évidence très discrète du texte. La synchroniser à la parole existante après une écoute dédiée.
3. **03:00–03:40 :** exploiter ponctuellement la marge latérale pour un court message par chapitre « Market and competitors » et « First customers ». Le contenu doit venir du discours validé ; aucun chiffre ni bénéfice nouveau n'est inventé.

Éviter un zoom continu, les marqueurs de tap répétés et les effets sur chaque alerte : le texte du téléphone est déjà petit, et la calme animation du paysage porte l'identité.
