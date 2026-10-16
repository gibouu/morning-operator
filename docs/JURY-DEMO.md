# MORE Démo — passage devant le jury

La variante technique Démo est un doublon isolé dont le nom visible est **MORE**, comme l’app principale. Le parcours conserve l’accueil, le paysage et les commandes habituelles : aucun écran ni panneau de présentation supplémentaire, ni annonce de démonstration. Les identifiants de bundle et les journaux restent distincts.

Provenance interne : le sommeil, la météo et le message de départ sont préparés ; le message annoncé ne provient pas d’une lecture en direct de l’inbox. La rédaction et l’envoi utilisent de vrais services. Cette préparation reste dans le back et ce document ; MORE discute naturellement de la routine sans annoncer un scénario ou une démonstration.

## État vérifié au 16 octobre 2026

- **Services réels :** rédaction libre puis révision avec OpenAI, synthèse ElevenLabs, un seul mail envoyé au compte lui-même et relu avec label SENT, destinataire et contenu exacts. La reprise serveur retrouve le reçu sans nouvel envoi.
- **iPhone et Dynamic Island :** le dernier passage isolé valide les deux tests d’interface et les commandes pause, reprise au premier plan avec nouvelle lecture réelle, puis arrêt depuis la Dynamic Island (98,557 s, avec neuf secondes sur l’accueil iOS à chaque phase). Le résultat local `work/jury-demo-isolated-final-acceptance.xcresult` compte quatre tests : trois réussites et un échec de reconnaissance acoustique. L’ensemble ne valide donc pas la conversation. Un contrôle séparé arrête ensuite la répétition par les paramètres ordinaires et vérifie le retour au repos (20,925 s), sans démarrer de nouveau matin.
- **Logique partagée :** commande Swift réussie après intégration de `main` (`e01c964`), avec 1 961 tests rapportés dans 226 suites et 7 tests optionnels ignorés ; 36 tests du service réussis. Les changements du graphe audio conditionnel iOS restent distincts de cette couverture macOS.
- **Python :** le contrôle historique sur `463af5f` comptait 33 méthodes réussies et une en échec pour 133 traductions anglaises absentes (104 dans le catalogue principal, 29 dans MorningApple). La PR 207 et le correctif `aff97cb` ont corrigé ces catalogues ; les 34 méthodes passent après intégration de `main` (`43d1d04`) et [l’issue 208](https://github.com/gibouu/morning-operator/issues/208) est résolue.
- **Conversion audio numérique :** quatre cas Float32 à 44,1 kHz, mono/stéréo vers 48 kHz mono, passent sur des signaux d’une seconde et de 8,4 secondes : écart de durée nul et fin conservée. Cela ne valide pas la reconnaissance acoustique.
- **Microphone :** la parole réelle diffusée par le Mac pendant l’essai de 45 secondes ne produit aucun caractère reconnu. Un lancement autonome, hors XCTest, reproduit cette absence. Le diagnostic brut passe son cycle de vie en 81,97 s, mais capture uniquement des zéros sur environ 1,8 million de trames, même en mode `.measurement`, sans traitement vocal ni reconnaissance. Ce succès de harnais ne valide aucune voix.
- **Nouvel essai physique :** après confirmation du téléphone éveillé et hors Recopie, une première tentative est invalidée car le haut-parleur du Mac avait changé d’identifiant. Le harnais corrigé diffuse ensuite réellement la phrase ; l’essai échoue encore en 86,167 s, avec 2 683 200 trames et aucun échantillon non nul. La personne confirme séparément que sa voix est audible dans Dictaphone. Cela justifie de comparer les méthodes de capture de MORE ; cela ne démontre pas encore une cause.
- **Isolation des essais :** un premier lot de trois contrôles UI échoue pendant une autre exécution sur le même téléphone. Les trois contrôles passent ensuite sans autre lanceur concurrent ; la reconnaissance reste en échec. L’interférence n’explique donc pas à elle seule le silence microphone. Réserver le téléphone à un seul lanceur pendant chaque passage.
- **Encore non prouvés :** conversation acoustique interactive complète, création réelle d’un rappel — jamais atteinte —, connexion Instagram et vidéo suivante. La démo complète devant jury n’est pas déclarée validée ; suivi ouvert dans [l’issue 205](https://github.com/gibouu/morning-operator/issues/205).

Apple indique que [le microphone est indisponible avec iPhone Mirroring](https://support.apple.com/en-us/120421). Mirroring n’était pas actif lors du contrôle et la nouvelle répétition physique conserve le problème : cette limite ne démontre pas la cause du silence observé.

Le diagnostic brut est réservé aux builds DEBUG et s’active explicitement avec `--jury-raw-microphone-diagnostic`. Il désactive la reconnaissance et les tours externes, ne conserve aucun audio et ne fournit que des compteurs numériques. Il ne doit pas être activé pour le passage normal.

Le second diagnostic DEBUG, `--jury-recorder-microphone-diagnostic`, lance automatiquement un `AVAudioRecorder` indépendant quand l’app est au premier plan. Il exige le bundle Démo et la permission réelle du micro, sans dépendre de la routine, d’un lien ou de XCTest. Il n’appelle aucun fournisseur et conserve l’ancien identifiant backend pour sa réconciliation normale. Le fichier audio local, privé et protégé, est supprimé à l’arrêt ; un éventuel orphelin après terminaison brutale est supprimé au lancement suivant.

Le bilan numérique privé `tmp/jury-recorder-measurement.json` se récupère avec CoreDevice dans le conteneur `com.gibouu.morningoperator.demo`, y compris par le réseau. Il distingue durée murale, `recordedDuration`, `recordedFilePresent`, `recordedFrames`, nombre de relevés du niveau, état et nettoyage. `recordedFrames` n’apparaît qu’après lecture de la longueur du CAF ; un fichier absent après démarrage effectif est une erreur. Un arrêt répété conserve cette mesure prise avant suppression. Cinquante relevés ne prouvent pas cinquante buffers audio. Un état final `3`, sans `errorCode`, et `audioCleanup=true` établissent une fin normale ; les trames et la durée enregistrées doivent ensuite être évaluées séparément de la conversation.

Le bilan de `322a240` ci-dessous précédait cette distinction : son `recordedFrames=0` pouvait aussi être la valeur initiale si le CAF était absent. Il ne prouve donc pas qu’un fichier présent a été lu vide. Le correctif de mesure doit encore être exercé sur le téléphone ; l’audit des mutateurs audio n’établit aucune désactivation concurrente à l’origine du silence.

Le premier essai autonome (`9c1d67b`) a bien produit ce bilan, mais est resté en capture après 52,36375 secondes murales, avec 50 relevés, niveau maximal de −120 dB et nettoyage non terminé. La reconnexion USB et l’expiration de la seconde phrase côté Mac rendent toute attribution causale prématurée. L’ancienne instance a été terminée et relancée sans flag ; l’inventaire des dossiers `jury-mic-*` est ensuite vide et le haut-parleur du Mac restauré. Le correctif `322a240`, compilé et signé strictement, borne désormais la capture avec le temps réel, indépendamment de l’horloge audio, et relit le nombre de trames du CAF avant sa suppression. Son passage stable par USB confirme un arrêt normal après **30,4984 secondes**, 29 relevés, `recordedDuration=30,524375`, `recordedFrames=0`, niveau maximal −120 dB, `state=3`, sans code d’erreur et `audioCleanup=true`. La phrase du Mac est réellement diffusée après sélection du haut-parleur intégré, démutage et volume temporaire, puis restauration exacte. Le journal confirme la suppression ; l’inventaire est vide après retour au lancement normal. Cela valide la borne et le nettoyage, **pas la capture de parole**. Le nombre de trames nul reste à élucider, sans le confondre avec les 29 interrogations du niveau. Une comparaison avec un lancement et une phrase directement effectués par la personne dans MORE Démo est désormais la prochaine vérification utile, sur un créneau libre.

Les deux runners précédents ont expiré avant le premier test sur « Timed out while enabling automation mode ». Leur configuration ne présente pas d’écart significatif avec le fichier nouvellement généré. Un autre parcours ordinaire a ensuite fonctionné par le réseau : l’absence d’USB ne suffit donc pas à expliquer ces erreurs. Le câble est depuis détecté à nouveau dans le registre USB, par `idevice_id` et par CoreDevice (`wired`). La voie autonome évite le runner et le relais syslog. Le dernier contrôle ciblé après intégration de `main` compte **56 tests réussis dans quatre suites** (transport jury, extras et modèle). Les 34 contrôles Python passent. Ces résultats restent distincts de l’acceptation physique de la voix.

## Préparer la répétition

- Installer la variante isolée (nom visible **MORE**, bundle `com.gibouu.morningoperator.demo`), avec sa configuration privée, à côté de l’app principale.
- Garder le Mac allumé, éveillé et connecté à Internet ; le téléphone et le Mac utilisent le même Wi-Fi, sans isolation entre appareils.
- Depuis la racine du dépôt, lancer `./Services/JuryDemo/run-local.sh`. Le script charge le `.env` privé du service ; ne jamais le projeter ni en afficher le contenu.
- Vérifier l’origine locale configurée dans l’app : le nom Bonjour du Mac et le port doivent être joignables depuis l’iPhone. La variante iOS autorise cette communication locale via sa configuration réseau/ATS.
- Vérifier les accès microphone et reconnaissance vocale, la voix ElevenLabs, le compte Gmail et le destinataire **identique à ce compte** pour cette démo.
- Dans la préparation ordinaire de chaque matin, autoriser la voix en ligne pour le parcours parlé. Un refus garde cette variante en pause, sans démarrer son client de conversation ; arrêter puis recommencer permet de refaire ce choix. Le contrôle de ce refus sur iPhone reste à effectuer.
- Ouvrir Instagram dans le navigateur intégré, terminer la connexion et vérifier que des Reels sont accessibles avant le passage.
- Préparer Gmail pour retrouver rapidement les éléments envoyés. Chaque nouvelle session peut envoyer un nouveau vrai message ; arrêter les répétitions inutiles.
- Pour montrer un rappel créé, le passage doit précéder **14 h 40 aujourd’hui**, soit vingt minutes avant le rendez-vous préparé de 15 h. Préparer la permission Rappels dans le parcours normal.
- Arrêter la session de répétition avant de commencer le passage du jury.

Le service local sur le port 8791 fonctionne actuellement dans un processus détaché. Cette installation dépend du Mac éveillé et du même réseau local ; elle ne constitue pas un déploiement cloud ni une preuve de fonctionnement loin du Mac.

Le candidat corrigé ci-dessous porte le numéro **2** dans le bundle Démo uniquement, pour le distinguer du premier doublon installé (build 1). La signature, le build réellement installé et les contrôles physiques de ce candidat doivent rester des preuves séparées.

Sur le code combiné `7e2b4f1`, les **115 tests Swift ciblés dans huit suites** passent, y compris les nouvelles protections de lecture et de sous-titres. Le `build-for-testing` iPhone réussit ; la signature stricte du doublon est valide et son plist donne version `0.1.0`, build `2`. Le test UI bilingue de refus est compilé, mais pas encore exécuté. Le build 2 n’est pas encore installé : le téléphone reste réservé aux autres contrôles coordonnés. Ces résultats ne valident aucune nouvelle capture, aucun rappel ni navigation Instagram.

## Parcours visé de deux à trois minutes

Répéter d’abord les passages vocaux sur le téléphone. Garder les options Rappels et Instagram seulement après leur validation réelle ; les tests du serveur ne suffisent pas à les certifier.

**0:00 — Commencer son matin.** Lancer la routine sur le paysage normal. MORE évoque brièvement le sommeil et la météo préparés, puis propose de regarder le message. Répondre naturellement : « Oui, on regarde. »

**0:20 — Comprendre et répondre.** MORE explique la proposition de point produit à 15 h. Dire : « Oui, réponds que je serai disponible. » OpenAI prépare une réponse que MORE lit ; rien n’est encore envoyé.

**0:40 — Corriger librement.** Dire par exemple : « Fais plus court, et propose qu’on commence par les retours utilisateurs. » Écouter la nouvelle version. Une seule révision suffit à montrer que le dialogue accepte des formulations libres.

**1:00 — Produire un vrai résultat.** Dire « Envoie ». Attendre la confirmation vérifiée, puis ouvrir Gmail et montrer le message dans les éléments envoyés, avec son heure et son contenu. Le destinataire est le compte de démonstration lui-même.

**1:25 — Option Rappels, après validation et si l’heure le permet.** Revenir dans MORE et dire : « Rappelle-moi vingt minutes avant le point produit. » Le parcours prévu prépare un rappel natif à 14 h 40 et n’annonce sa création qu’après confirmation de l’iPhone. Si l’heure est passée ou l’accès refusé, conserver la réponse d’indisponibilité et continuer.

**1:45 — Option Instagram, après connexion et vérification du fil.** Demander de passer aux vidéos. Une fois un vrai Reel chargé dans le navigateur intégré, dire « La suivante » et vérifier le changement. Une page ouverte ou une connexion réussie ne vaut pas navigation vérifiée.

**2:10 — Garder le contrôle.** Montrer l’état et les commandes de la Dynamic Island : pause, reprise vers MORE avec lecture effective, puis arrêt. Ces commandes sont vérifiées sur téléphone ; leur déclenchement par une conversation acoustique reste non validé.

Le rythme dépend de la conversation et des fournisseurs. Mieux vaut montrer ces quelques effets lisibles que multiplier les étapes ou réciter un texte exact.

## Si quelque chose ne répond pas

- Un envoi incertain se vérifie dans Gmail ; ne pas recommencer une nouvelle session pour le renvoyer. Le service conserve le journal et peut rechercher le résultat sans répéter l’envoi.
- Un rappel incertain se vérifie dans Rappels ; ne pas demander une seconde création pour masquer l’incertitude.
- Une connexion Instagram expirée se prépare à nouveau dans le navigateur ; ne pas prétendre qu’une vidéo a été parcourue si la page n’est pas disponible.
- Une panne du Mac, du réseau ou d’un fournisseur appelle un arrêt clair du passage.

Les détails des services et les limites de leurs preuves figurent dans [le service jury](../Services/JuryDemo/README.md). Actualiser ce statut seulement après observation du résultat correspondant sur le téléphone.

Le build **3** naturalise les textes prononcés, le nom visible, la routine et la note de rappel. Il migre uniquement les anciens libellés seed exacts, sans modifier les choix personnels ni les identifiants de routine. Les références techniques restent internes ; les informations réellement indisponibles ne sont pas inventées. Ce changement de textes n’a pas été recompilé ni testé sur téléphone, conformément à la consigne de livraison rapide.
