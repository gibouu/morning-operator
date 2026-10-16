# MORE : cause du blocage ElevenLabs et correction

Guillaume · Recherche technique du 16 octobre 2026 · Dernier contrôle serveur : 10:54:19, heure de Paris.

## Réponse directe

Une cause bloquante est confirmée pour la dernière identité mesurée dans MORE 0.1.0 (2026101622) : **notre serveur ne l'autorise pas à utiliser ElevenLabs**. Le code d'assistance effectivement affiché sur l'iPhone correspond à une seule installation dans la base. Cette installation est absente de la liste d'autorisations active ; l'ancienne identité, elle, est toujours autorisée. Une exécution locale de la garde de production avec cette identité et la liste réellement déployée retourne **503 / voice_not_configured**, avec **zéro appel à ElevenLabs**. Ce résultat établit un blocage d'autorisation dans MORE ; ce n'est pas une nouvelle capture HTTP provenant de l'iPhone. [S1, S2]

Le défaut client favorisant cette rupture est également établi dans le code : l'ancienne version cherchait son identifiant secret dans le Trousseau à partir du **chemin absolu du conteneur iOS**. Si ce chemin change, la recherche manque l'ancien identifiant et l'app peut s'enregistrer comme une nouvelle installation. Apple documente explicitement que ce chemin change lors d'une mise à jour. La transition exacte sur cet appareil, entre remplacement du conteneur et changement d'alias de chemin, n'a pas été enregistrée. [S3, S4]

## Ce qui a été vérifié

| Vérification | Résultat et portée |
| --- | --- |
| Identité réellement affichée | Code du contrôle physique test12 rapproché, par requête SELECT paramétrée, d'une seule ligne D1 ; correspondance unique confirmée. Aucune valeur privée publiée. |
| Configuration active | Version serveur 35e47ab2 ; configuration canonique et active identiques ; deux installations autorisées ; anciennes clés de configuration conservées. |
| Autorisation | Identité test12 absente, identité précédemment activée présente. La clé ElevenLabs et la configuration d'agent existent côté serveur. Leur valeur n'a pas été extraite. |
| Reproduction du refus | Même fonction morningSpeech que la version déployée, identité rapprochée et liste active ; valeurs non secrètes représentant la présence des deux réglages. Résultat 503 voice_not_configured, aucun appel fournisseur. |
| Lectures historiques | Les quatre exemples français/anglais et Homme/Femme ont terminé via le secours Apple. L'utilisateur a confirmé leur audibilité et refusé leur qualité. Les préférences persistent après relance. |
| Trace serveur historique | Une troisième identité non autorisée a une demande d'activation au 16 octobre à 08:20:33 UTC, pendant la fenêtre des lectures. Elle diffère de l'identité test12 mesurée plus tard. Une date seule ne prouve pas l'origine de cette demande. |

La base conserve une demande d'activation uniquement lorsque le courtier retourne 503 avec sa configuration fournisseur présente. La fonction de synthèse retourne ce refus avant son appel réseau fournisseur. Les erreurs obtenues ensuite auprès du fournisseur sont converties en 502 speech_unavailable. Une panne de décodage ou de lecture intervient encore plus tard, dans l'app. Ce sont trois étapes distinctes. [S1]

## Pourquoi les voix entendues étaient mauvaises

Le secours Apple permet de terminer la lecture après un échec du chemin principal. Les captures des quatre exemples montrent ce secours ; l'inventaire public ne contenait que des voix Standard dans les quatre combinaisons. Le succès de la lecture Apple efface la cause terminale dans l'app. Le message de secours, seul, ne permet donc pas de reconstruire l'erreur HTTP originale. [S5]

Les contrôles précédents ont obtenu de vrais fichiers audio ElevenLabs pour les quatre combinaisons. Cela établit que le fournisseur répondait à ces contrôles, mais ne certifie pas chaque demande de l'iPhone ni la santé permanente du fournisseur. La documentation ElevenLabs distingue notamment authentification, crédits, limitation de débit et indisponibilité. Aucun code fournisseur de ce type n'a été capturé pour les quatre lectures physiques. [S6, S7]

## Correction et état de livraison

1. **Stabiliser l'identité : intégré.** Le correctif 66fb098, fusionné par la PR #221, conserve le namespace initial dans composio-keychain-namespace.json. Le secret et le journal des actions incertaines continuent d'utiliser les mêmes comptes du Trousseau ; aucun secret n'est déplacé. Les workspaces de test restent isolés et un marqueur illisible ou contradictoire bloque l'accès plutôt que de recréer silencieusement une identité. Cette correction a été examinée dans le code ; sa validation après mise à jour réelle n'est pas acquise par cette recherche. [S8]
2. **Activer l'installation finale : à effectuer.** Après installation de la version finale, relever son code d'assistance, le rapprocher d'une seule identité serveur, puis autoriser uniquement celle-ci en conservant les autorisations existantes. Ne pas réutiliser aveuglément l'identité test12 : une nouvelle installation a pu changer l'identité avant le premier lancement corrigé. Le marqueur ne récupère pas un ancien secret déjà devenu introuvable. La première migration reste suivie dans #220. [S2, S8]
3. **Vérifier le résultat ciblé : restant.** Une lecture fixe doit obtenir audio/mpeg, terminer sur le chemin principal sans message de secours et rester satisfaisante à l'écoute. Une réponse technique seule ne valide pas la qualité perçue. L'installation finale et les actions appareil appartiennent au coordinateur de livraison ; cette recherche n'a lancé aucun essai sur le téléphone. [S5]
4. **Conserver la cause lors d'un secours : recommandé.** Enregistrer seulement l'étape, le statut HTTP et un code d'erreur contrôlé, séparément du succès Apple. Exclure texte lu, audio, en-têtes, clés et identifiants. Cela permettra de distinguer immédiatement refus du courtier, panne fournisseur et problème audio natif. [S1, S5, S7]

## Limites et méthode

Le blocage de l'identité test12 est confirmé par une lecture fraîche de la configuration et de la base, puis une reproduction déterministe du contrôle d'autorisation. **Le statut HTTP des quatre demandes physiques originales n'a pas été conservé.** Il n'est donc pas affirmé que chacune est une 503 observée. Le chemin ou UUID iOS avant/après n'a pas été capturé. La nouvelle version finale ne bénéficie pas automatiquement de l'activation d'une identité antérieure.

Recherche : source exacte du build 1622 et artefact signé figé ; revue indépendante du correctif ; rapprochement code UI / D1 ; lecture de la version et des autorisations déployées ; exécution de la garde sans réseau fournisseur ; documentation officielle Apple et ElevenLabs. Aucun accès micro, lecture personnelle, installation, compte fournisseur modifié, activation, écriture en base ou génération audio. Arrêt des recherches après validation de la cause suffisante et identification des deux limites historiques ; d'autres recherches web ne peuvent pas reconstituer une trace physique absente.

## Sources

- **S1 - Code du courtier MORE**, source du build 786f1dd, identique pour les trois fichiers runtime à la version examinée : [garde avant fournisseur](https://github.com/gibouu/morning-operator/blob/786f1dd/Services/Composio/morning-voice.mjs#L8), [enregistrement du refus](https://github.com/gibouu/morning-operator/blob/786f1dd/Services/Composio/server.mjs#L403), [stockage D1](https://github.com/gibouu/morning-operator/blob/786f1dd/Services/Composio/cloudflare/storage.mjs#L17). Accès source local et serveur le 16 octobre 2026.
- **S2 - Vérification opérateur du 16 octobre à 08:54:19 UTC**, current-gate-verified-sanitized.json, conservée localement. Lecture de configuration, rapprochement SELECT et reproduction locale ; aucun identifiant secret publié. Résultats principaux repris intégralement dans ce rapport.
- **S3 - Client MORE 786f1dd**, [compte du Trousseau](https://github.com/gibouu/morning-operator/blob/786f1dd/Sources/MorningApple/ComposioService.swift#L229), [réinscription en l'absence d'identifiant](https://github.com/gibouu/morning-operator/blob/786f1dd/Sources/MorningApple/ComposioService.swift#L514).
- **S4 - Apple, Technical Note TN2285 : Testing iOS App Updates**, section Managing Data Across Updates, document archivé : [contrat de déplacement du conteneur](https://developer.apple.com/library/archive/technotes/tn2285/index.html). Corroboration : [attributs composant la clé d'un élément du Trousseau](https://developer.apple.com/documentation/security/ksecclassgenericpassword). Consultés le 16 octobre 2026.
- **S5 - Preuve physique MORE**, [rapport du 16 octobre](https://github.com/gibouu/morning-operator/blob/main/docs/LANGUAGE-VOICE-IPHONE-2026-10-16.md) ; [récupération Apple](https://github.com/gibouu/morning-operator/blob/786f1dd/Sources/MorningApple/SpeechCoordinator.swift#L314). Les résultats bruts restent locaux.
- **S6 - MORE, résultats fournisseur et limites**, [acceptation de la voix](https://github.com/gibouu/morning-operator/blob/main/docs/VOICE-CHOICE-ACCEPTANCE-2026-10-16.md) ; ElevenLabs, [Create speech](https://elevenlabs.io/docs/api-reference/text-to-speech/convert). Consultés le 16 octobre 2026.
- **S7 - ElevenLabs, documentation officielle**, [authentification](https://elevenlabs.io/docs/api-reference/authentication), [erreurs API](https://elevenlabs.io/docs/eleven-api/resources/errors). Consultées le 16 octobre 2026. L'authentification serveur et l'activation locale MORE sont deux contrôles distincts.
- **S8 - Correctif MORE 66fb098**, [namespace persistant](https://github.com/gibouu/morning-operator/blob/66fb098/Sources/MorningApple/ComposioService.swift#L196), [PR #221](https://github.com/gibouu/morning-operator/pull/221), [limite de première migration #220](https://github.com/gibouu/morning-operator/issues/220).
