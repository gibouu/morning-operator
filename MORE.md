# MORE — Référence produit


Version du 16 octobre 2026, issue des décisions du fondateur. Ce document fixe la valeur et l'expérience à construire. Il est la référence pour les décisions produit, les parcours, l'architecture et les critères d'acceptation. Une évolution de cette direction doit faire l'objet d'une décision explicite, puis être reportée ici.


**MORE comprend ta routine matinale, te permet de la transformer si tu le souhaites, puis la fait pour toi. Le résultat attendu est un matin hands-free, avec presque aucun besoin de toucher son téléphone.**

Cette promesse est la cible produit. Les capacités déjà réalisées et leurs preuves restent décrites dans les documents techniques et les comptes rendus de tests. Une limite du prototype constitue du travail à résoudre ; elle ne redéfinit pas la valeur de MORE.

## 1. La valeur de MORE

Les gens répètent des habitudes le matin : consulter Instagram ou TikTok, lire X, regarder leurs mails et leurs messages Slack, vérifier leur calendrier, la météo ou leurs données de sommeil. Ils n'ont pas toujours conscience de l'ordre de ces actions ni du temps qu'elles occupent.

MORE leur apporte trois choses :

1. **Prendre conscience de leur routine.** Voir ce qu'ils font réellement, dans quel ordre et pendant combien de temps.
2. **Pouvoir la transformer.** Garder ce qui leur plaît, déplacer des étapes, ajuster les durées, ajouter un moment ou retirer une habitude. La personnalisation reste facultative.
3. **La confier à MORE.** Une fois la routine validée, MORE la déroule, présente les contenus et réalise les actions prévues pendant que la personne se prépare, se brosse les dents ou fait autre chose.

La personne garde ses plaisirs et ses choix. MORE ne lui impose aucune définition d'un matin productif. La valeur vient du temps et de l'attention libérés, de la maîtrise de ses habitudes et de la réalisation effective de la routine.

## 2. Comprendre la routine avec trois sources complémentaires

MORE doit réunir les informations disponibles dans une même compréhension de la routine. Les sources se renforcent et se complètent ; elles ne produisent pas trois parcours indépendants à reconstruire manuellement.

| Source | Ce qu'elle apporte | Expérience attendue |
| --- | --- | --- |
| Screen Time | Les applications utilisées, les durées et les périodes d'usage disponibles | La personne autorise la lecture. MORE exploite la couverture réellement obtenue pour proposer une première structure. |
| Une ou plusieurs vidéos des routines matinales | Une séquence visible, les contenus et les usages permettant de compléter les données agrégées | La personne enregistre elle-même son écran pendant sa routine, puis dépose les vidéos dans MORE. Elle peut en apporter plusieurs, sur plusieurs matins. |
| L'usage du navigateur intégré | Des parcours et actions observables directement : pages, défilements, stories, interactions, rythme et durée | Les premiers jours, la personne utilise ses services dans MORE. L'apprentissage est explicite et visible ; MORE s'en sert pour préciser les habitudes et les actions à automatiser. |

### Les vidéos sont une entrée centrale

L'utilisateur doit pouvoir déposer une vidéo ou plusieurs vidéos de ses routines. MORE ne suppose pas pouvoir récupérer directement les enregistrements sur l'iPhone à sa place.

La chaîne d'analyse derrière l'interface traite ces vidéos pour extraire les étapes et leur chronologie, rapprocher plusieurs observations et enrichir les durées et usages connus. Elle conserve la distinction entre ce qui est visible, ce qui est déduit et ce qui demeure inconnu. La vidéo complète Screen Time, notamment là où ses données agrégées n'expliquent pas ce que la personne fait dans une application.

Le mot « back » désigne ici cette chaîne de traitement. Il ne décide pas d'un hébergement distant : l'analyse et les médias restent locaux par défaut selon les règles du dépôt. Un éventuel traitement distant doit être choisi et consenti explicitement.

### L'apprentissage dans le navigateur précise les gestes

La personne retrouve ses services et se connecte sur leurs pages. MORE observe les parcours et les actions utiles à la routine : passer du fil aux stories, regarder plusieurs publications, faire défiler, aimer un contenu, lire une conversation ou revenir à une rubrique.

Cette compréhension doit aller au-delà d'un compteur de scrolls. Elle doit permettre de relier une intention — par exemple « regarder mes stories puis mon fil » — aux opérations que l'agent pourra réaliser. Les mots de passe, codes et saisies d'authentification ne deviennent pas des données d'apprentissage.

Il n'y a pas de durée arbitraire imposée avant de proposer une routine. MORE utilise les éléments disponibles, indique les incertitudes utiles et laisse corriger sa compréhension dans l'interface.

## 3. Proposer une routine et la valider dans l'interface

MORE présente une routine lisible : ses étapes, leur ordre, les services concernés et les durées proposées. La personne peut :

- accepter la proposition telle quelle ;
- réordonner les étapes ;
- changer leur durée ;
- supprimer une habitude de sa routine ;
- ajouter ou modifier une étape ;
- préciser ce que MORE fera pour elle dans chaque étape.

Les choix personnels priment sur les nouvelles déductions. Une habitude retirée ne doit pas réapparaître silencieusement après une nouvelle analyse. Une routine en cours garde la version qui a été validée pour cette session.

**Valider la routine signifie en confier l'exécution à MORE.** L'interface explique avant validation que MORE prendra en charge les étapes et les actions présentées. Il n'existe pas de deuxième parcours de « proposition de délégation », ni de demande vocale pour déléguer une routine déjà validée.

L'apprentissage, la revue et la validation se font dans l'interface, avec des éléments à lire et des boutons. La personne n'a pas besoin de mener une conversation pour configurer son matin. La validation confie les prochaines exécutions à MORE ; le démarrage d'une session suit le déclenchement prévu dans le produit.

Après le paywall, une seule page facultative prépare la voix : micro et reconnaissance vocale sont expliqués ensemble, puis l'iPhone présente les autorisations nécessaires successivement. Accepter ou passer mène directement à l'accueil. Les autres accès et connexions se proposent au moment où ils deviennent utiles, ou depuis les réglages, sans imposer un parcours de huit pages. Une météo déjà configurée reste disponible et n'est pas redemandée comme une nouvelle connexion. Revoir les accès dans les réglages ouvre une liste de choix indépendants.

### Wording à travailler à partir de cette intention

| Moment | Proposition de texte à tester |
| --- | --- |
| Présentation | « Voici à quoi ressemble votre matin. » |
| Personnalisation | « Gardez ce qui vous plaît. Ajustez le reste. » |
| Explication avant validation | « MORE s'occupe de ces étapes pour vous. Vous pourrez l'interrompre à tout moment. » |
| Validation | « Confier mon matin à MORE » |
| Démarrage | « Commencer mon matin » |

Ces formulations sont des propositions, pas une copie figée. Leur sens doit rester clair : la personne valide ce que MORE fera pour elle. Les mots « agent », « sandbox », « parsing », « workflow », les noms d'outils API et le JSON appartiennent à l'implémentation, pas au parcours utilisateur.

## 4. Exécuter réellement la routine

Chaque étape validée doit correspondre à un comportement réalisable : obtenir une information, la restituer, naviguer dans un contenu, effectuer une action ou combiner ces opérations. La session suit l'ordre et les durées retenus, puis passe à la suite selon le comportement de l'étape et les demandes de la personne.

MORE prépare et présente les informations pertinentes, ouvre les pages nécessaires, réalise les interactions prévues et gère les transitions. Une page ouverte, un compte connecté ou un minuteur affiché ne suffisent pas à établir que la routine est exécutée.

### L’accueil reste la scène du matin


La routine se déroule sur le paysage existant de l’accueil de MORE. Seul le court passage en cours de lecture ou de transcription apparaît sur ce fond, puis laisse sa place au suivant. Les paroles de la personne apparaissent au fil des mots reconnus dans la même zone, avec leurs corrections, puis laissent la place à la réponse de MORE. L’historique ne s’accumule pas. Aucun titre d’étape, minuteur, panneau, fiche, formulaire ou bouton permanent ne recouvre le paysage. Les passages changent doucement ; la réduction des animations conserve une transition discrète sans mouvement.

Un tap révèle seulement deux symboles flottants en Liquid Glass : Play au centre et Paramètres en haut à droite. Le verre épouse directement le triangle ou la roue dentée, sans disque, contour de bouton ni plaque derrière. Pendant la lecture, Play devient Pause. Ces commandes disparaissent après cinq secondes sans interaction ; une nouvelle interaction relance ce délai. VoiceOver les conserve pour permettre leur exploration. La routine, l’apprentissage, l’historique, les connexions, les pensées et les commandes supplémentaires (suivant, prolonger, interagir, arrêter) se retrouvent dans Paramètres. Aucun menu ni panneau de raccourcis ne s’ouvre sur l’accueil.

Les Paramètres et leurs sous-écrans ont une direction distincte du paysage : réglages groupés compacts, typographie système et surfaces neutres, sans cartes crème ni texture de papier. Le mode jour ou nuit suit le même cycle solaire que l’accueil, y compris après une navigation ou l’ouverture d’une feuille. Entrer dans les Paramètres la nuit ne force jamais une interface claire.

Le navigateur s’ouvre pour les moments interactifs, puis rend la place à l’accueil. Les formulaires de réponse et les détails restent accessibles sur demande. Pour une activité dans une autre app, MORE laisse le temps prévu ; quand la personne revient dans MORE pendant le déroulement automatique, la routine continue sans bouton « c’est fait ». Ce retour ne prouve aucune action dans l’autre app, et MORE ne suppose pas pouvoir ramener iOS de force au premier plan.


La durée règle le temps alloué à un moment. Sa fin permet à MORE d'annoncer ou d'engager la transition prévue. Elle ne prouve pas qu'une action distante a réussi. Une pause, une prolongation ou un changement demandé à la voix doit se répercuter sur la même session et la même étape.

### Un agent dans le navigateur de MORE

MORE doit disposer d'un agent de phone use contenu dans son propre navigateur. L'agent ouvre les pages dans MORE et agit dans ces pages : naviguer, scroller, ouvrir des contenus, regarder les stories, passer d'une vidéo à l'autre et réaliser les interactions autorisées, notamment les likes.

Instagram, TikTok, X, Reddit, Facebook et les autres services interactifs doivent avoir cette expérience navigateur. Une connexion API seule ne remplace pas la consultation de leurs contenus dans MORE. Un même service peut utiliser le navigateur pour l'expérience interactive et une API pour une opération précise.

L'agent comprend le contexte de la page et vérifie l'effet de ses actions. Il doit pouvoir composer avec les chargements, une session expirée, un contenu absent ou une mise en page différente. Son périmètre reste le navigateur de MORE ; le contrôle universel des autres applications iOS n'est pas présumé.

La faisabilité est un chantier à prouver sur les vrais services et comptes. Il faut observer l'agent ouvrir la bonne page, réaliser l'action, vérifier son résultat, s'arrêter et reprendre. Une démonstration avec des taps pilotés par un Mac ou des pages factices ne valide pas cette promesse.

### Les connexions servent des usages complets

Les API et les intégrations natives permettent à MORE d'obtenir les données et de réaliser les opérations adaptées à chaque service. Le produit présente un résultat compréhensible et exploitable à la voix. L'utilisateur ne doit pas assembler lui-même des appels techniques.

**Toutes les connexions actuellement présentes dans l'app font partie du périmètre produit.** Le scénario mail ci-dessous illustre une capacité générale ; il ne limite pas MORE à Gmail, à un briefing ou à quelques destinations de démonstration.

## 5. La voix pendant le matin

MORE conduit le déroulement et parle quand cela sert la routine. Une discussion permanente n'est pas nécessaire. La personne peut l'interrompre à tout moment pour poser une question, demander une action, corriger son intention, passer une étape, prolonger un moment, mettre en pause ou arrêter.

Une IA doit recevoir le contexte utile de la session et les informations des services, comprendre les demandes et préparer les actions. La voix doit permettre une interaction au cours du déroulement, y compris lorsque MORE parlait déjà. Ouvrir un écran et appuyer sur un bouton pour chaque prise de parole ne satisfait pas l'objectif hands-free.

Le contexte doit suivre la conversation : « oui », « non », « réponds-lui », « change la dernière phrase » et « envoie » se rapportent au bon contenu et à l'action préparée. Les faits prononcés doivent venir des sources disponibles ; les informations importantes et les raisons de leur sélection doivent pouvoir être comprises et corrigées.

Le modèle prépare et propose les opérations ; le moteur d'exécution applique les autorisations, la routine validée et les instructions de la personne. Les contenus d'un mail ou d'une page ne constituent pas des ordres de l'utilisateur.

Décision du 16 octobre 2026 : les réglages de voix proposent seulement **Homme** et **Femme**, avec un exemple à écouter. ElevenLabs assure la voix naturelle après l'accord sur les textes transmis ; le fournisseur ne constitue pas un choix de réglage. En cas d'indisponibilité, MORE libère l'audio distant puis continue avec la meilleure voix Apple installée dans la langue choisie, en privilégiant Premium, puis Enhanced, puis Standard. MORE ne promet pas une voix Premium absente de l'iPhone. L'exemple fixe ne nécessite ni micro ni données personnelles.

Le modèle et la reconnaissance restent des décisions distinctes de la synthèse vocale. Le secours audio ne change pas le modèle d'inférence, ne transmet pas de nouvelles données et ne rejoue aucune action. Le principe d'inférence locale par défaut et l'accord préalable pour les routes distantes restent applicables.

### Modèle et mémoire personnelle

Décision du 16 octobre 2026 : une route OpenAI est autorisée pour ce prototype lorsqu’elle est explicitement activée. Le modèle doit servir la compréhension des observations, la conversation contextualisée, la préparation des actions et les conseils utiles. Le choix local reste le défaut ; une indisponibilité ne déclenche jamais d’envoi distant silencieux. Les vidéos et l’audio bruts restent locaux. L’activation explique les extraits de texte et le contexte transmis.

MORE doit retenir les faits personnels et préférences explicitement indiqués par la personne, respecter leurs négations et remplacer une information corrigée lors des prochains échanges et matins. Ces faits doivent rester consultables et effaçables dans les réglages. Un conseil ne crée pas un fait personnel : proposer des gants ne prouve pas que la personne possède une trottinette. Les données d’un mail ou d’une page ne deviennent jamais des déclarations de la personne.

À partir d’une météo réelle disponible, MORE peut proposer un conseil bref et contextualisé sans commande supplémentaire. Il adapte ce conseil aux faits connus, signale ce qui manque et n’invente ni équipement, ni moyen de transport, ni prévisions. Le branchement d’un modèle ne vaut pas preuve d’exécution d’une action externe.

## 6. Exemple complet avec les mails

Cet exemple décrit le niveau d'interaction attendu pour l'ensemble du produit.

1. MORE récupère les mails autorisés et identifie ceux qui méritent l'attention de la personne selon ses préférences et leur contenu.
2. Il présente un bilan concis : « Vous avez reçu plusieurs mails. Voici les trois qui semblent importants et auxquels vous pourriez répondre. » Il les cite et les résume.
3. Il demande si la personne souhaite répondre. Si elle dit non, le matin continue.
4. Si elle dit oui, elle exprime son intention en quelques mots.
5. MORE rédige une réponse soignée, permet de la connaître et de la corriger à la voix.
6. Quand la personne dit « envoyer », MORE envoie réellement le message préparé au destinataire identifié, puis annonce le résultat confirmé.

La validation de la routine autorise son déroulement ; elle ne remplace pas l'ordre vocal d'envoi dans cet exemple. Les actions répétitives comme les likes peuvent faire partie du comportement explicitement présenté et validé de la routine, sans exiger une confirmation identique à chaque interaction.

Ce mécanisme doit se décliner sur les autres connexions : comprendre une information, la présenter utilement, recueillir une intention si nécessaire, préparer un résultat et effectuer l'action demandée. Si une action externe a un résultat incertain, MORE le réconcilie avant de la répéter.

## 7. Périmètre des services

L'inventaire ci-dessous fixe la couverture à poursuivre à partir de l'app au 15 octobre 2026. Il ne certifie pas que chaque action fonctionne déjà. Les opérations de chaque service doivent respecter les droits du compte et les possibilités réelles du fournisseur.

| Famille | Services dans le périmètre | Expérience à rendre possible |
| --- | --- | --- |
| Réseaux et contenus interactifs | Instagram, TikTok, X, Reddit, Facebook, Threads, YouTube Shorts | Usage et apprentissage dans le navigateur de MORE, puis navigation et interactions par l'agent selon la routine validée. Les API restent complémentaires. |
| Communications | Gmail, Outlook, Slack, WhatsApp, Discord et les usages de communication disponibles dans les autres connexions | Retrouver les contenus autorisés, les restituer, préparer et réaliser les actions pertinentes. L'accès à un compte ne garantit pas l'accès à toutes ses conversations. |
| Agenda et organisation | Calendrier Apple, Google Calendar, Calendly, Rappels | Présenter les informations utiles et accomplir les opérations demandées dans la routine. |
| Informations du jour | Météo, actualités et sites choisis, dont Le Monde | Présenter des informations à jour, lire ou parcourir les contenus retenus. |
| Santé et sommeil | Santé Apple et les sources de sommeil ou trackers à intégrer | Restituer la durée, la qualité de sommeil, la récupération et les autres indicateurs effectivement fournis. Un pourcentage de récupération doit provenir d'une source qui le mesure ou le calcule, et être attribué. |
| Documents et travail | Google Drive, Google Docs, Google Sheets, Notion, LinkedIn | Réaliser les usages pertinents de la routine à partir des contenus et actions autorisés. |
| Autres usages iPhone | Messages, Mail, Notes, Horloge, Plans et les raccourcis proposés dans l'app | Intégrer les actions réalisables par les routes prises en charge, avec un résultat vérifiable. |

Un compte professionnel et un compte personnel peuvent offrir des capacités différentes. Une API de publication ou de gestion de Page ne vaut pas accès au fil personnel. Une fonction absente d'une API doit conduire à étudier la route navigateur ou native adaptée, puis à en vérifier la faisabilité.

L'interface décrit précisément ce qui est disponible pour la personne. Une capacité restant à construire garde son statut visible dans le suivi du projet ; elle n'est pas remplacée par une promesse de connexion générique.

## 8. Fiabilité et contrôle personnel


### Préparer les accès après l’abonnement

Les choix d’accès font partie de l’onboarding, après la confirmation de l’abonnement, essai compris. Ils reprennent le paysage fixe, les polices et la palette solaire de la découverte de MORE : clairs le jour, sombres la nuit. Chaque écran présente un titre et une phrase utile ; le détail reste disponible sur demande. Après les accès, la personne peut découvrir sa routine ou rejoindre l’accueil et apprendre plus tard. Avant chaque demande système, une étape statique explique l'accès demandé, son usage concret et le contrôle conservé par la personne. Les demandes sont séquentielles ; microphone et reconnaissance vocale ont chacun leur explication. Un refus n'empêche pas de préparer les autres accès ni d'entrer dans l'app. Les accès non disponibles dans le build sont annoncés fidèlement. Les connexions aux comptes et le partage d'une vidéo gardent leur parcours explicite.

### Un accueil qui reflète le temps qu'il fait ici

La météo utilise la position actuelle autorisée sur l'iPhone, sans obliger la personne à saisir une ville. Une ville choisie reste une solution de repli explicite. Les observations météo restent temporaires et ne deviennent pas des traces de déplacement ou des données d'apprentissage.

Le paysage de l'accueil doit être reconnaissable et mémorable : sa lumière, ses nuages, sa visibilité, ses précipitations et son vent suivent les données réellement disponibles. De petits souffles espacés accompagnent une brise ; leur fréquence, leur taille et leur intensité augmentent avec le vent et les rafales mesurés. La direction du vent relie les mouvements du ciel, des précipitations et des arbres. L'absence de données reste une absence, sans conditions inventées. La réduction des animations conserve une scène lisible et immobile.


La routine validée fixe ce que MORE doit faire et avec quels services. La personne peut arrêter l'exécution, changer ses choix et retirer un accès. Une nouvelle déduction ne modifie pas silencieusement ses décisions.

L'apprentissage utilise les sources choisies, avec un état visible et une possibilité d'arrêt. Les vidéos et les médias bruts ont une durée de conservation distincte de la compréhension de la routine. Les identifiants, contenus privés et médias ne sont pas copiés dans Git ou dans les rapports partagés.

Pendant l'exécution, MORE distingue une source vide, absente, périmée ou inaccessible. Il ne transforme pas une information inconnue en zéro ni un échec en réussite. Une interruption, une fermeture ou une réponse réseau tardive ne doivent pas entraîner un double envoi, un like répété involontairement ou une progression incohérente.

Les permissions et les connexions se préparent dans l'interface. Une difficulté rencontrée pendant le matin appelle une explication courte, un choix vocal utile et une reprise cohérente. L'objectif reste de réduire les gestes, pas de multiplier les confirmations routinières.

### Découvrir MORE et s’abonner

Au premier lancement, MORE utilise automatiquement la langue principale de l’iPhone : le français si cette langue est le français, l’anglais dans tous les autres cas, même si le français figure ensuite dans les langues préférées. La région de l’iPhone ne choisit pas la langue de l’interface. Aucun questionnaire ni choix de langue ne précède la découverte.

Le parcours d’entrée présente d’abord la valeur de MORE : comprendre ses habitudes, ajuster sa routine, puis la confier à MORE pour un matin mains libres. Il présente ensuite un abonnement mensuel à **4,99 € avec une semaine d’essai gratuit**, selon l’éligibilité confirmée par l’App Store. Le prix localisé et les conditions réellement disponibles viennent de la boutique Apple.

Les demandes d’accès commencent seulement après la confirmation de l’abonnement, essai compris. Chaque demande explique son utilité avant d’ouvrir l’autorisation correspondante. Le paysage, les polices, les couleurs et le cycle jour/nuit accompagnent toute cette découverte, sans dépendre du paiement ni d’une autorisation de localisation. La restauration des achats et les contrôles de confidentialité restent accessibles sans abonnement actif. Les surfaces givrées et les commandes Liquid Glass restent sobres ; la réduction de la transparence et le contraste renforcé gardent des surfaces pleines et lisibles. Le monogramme original de MORE reprend deux arches continues, sans points ni rayons décoratifs.

Exception de développement acceptée : un build Debug affiche une croix « Accès développeur » sur l’introduction et l’offre. Un appui ouvre la suite du parcours sans achat et mémorise ce choix sur cet iPhone entre lancements et mises à jour du build. Cette préférence locale reste distincte des droits StoreKit, ne crée aucune transaction et n’est ni lue ni exposée dans un build Release, qui conserve l’abonnement obligatoire. Les tests UI isolent cette préférence par espace de travail. Cet accès ne valide aucune autorisation système à la place de la personne.

## 9. Ce qui doit encore être construit et prouvé

Le dépôt contient déjà des briques de lecture Screen Time, d'import et d'analyse vidéo, de propositions éditables, de sessions, de navigateur, de connexions, de voix et de minuteries. Leur présence n'établit pas l'exécution autonome décrite ici.

Les principaux chantiers qui découlent de cette direction sont :

1. Réunir Screen Time, plusieurs vidéos et les usages du navigateur dans une compréhension commune, tout en conservant les corrections de l'utilisateur.
2. Faire correspondre chaque étape proposée à un comportement exécutable et compréhensible avant validation.
3. Construire et prouver l'agent navigateur : navigation, progression, stories, interactions et adaptation au contexte réel des pages.
4. Relier toutes les connexions à des opérations utiles dans la session, avec une restitution adaptée et un résultat vérifié.
5. Intégrer le modèle et la voix interactive, notamment l'interruption et les demandes liées au contenu courant.
6. Orchestrer les durées, les transitions automatiques, les pauses et la reprise dans une seule session persistée.
7. Aller jusqu'aux actions réelles demandées, dont l'envoi d'un mail après instruction vocale.
8. Vérifier le parcours complet sur un iPhone ordinaire avec les vrais services.

Les restrictions actuelles — actions web surtout manuelles, rythme mesuré sans pilotage automatique, voix par tours ouverts manuellement, lecteur mail historiquement en lecture seule, santé partiellement intégrée — décrivent le travail restant. Elles ne constituent pas les limites définitives du produit.

Les références techniques se trouvent dans [l'architecture](docs/ARCHITECTURE.md), [les connexions](docs/CONNECTIONS.md), [le catalogue API](docs/COMPOSIO-SERVICES.md), [le navigateur](docs/IN-APP-BROWSER.md), [la voix](docs/VOICE.md), [la confidentialité](docs/PRIVACY.md) et [le plan des modèles Apple](docs/APPLE-MODEL-PLAN.md). Leurs états datés restent des descriptions de l'implémentation ; ils doivent évoluer pour servir cette direction.

## 10. Comment savoir que MORE tient sa promesse

La validation du produit doit suivre une routine personnelle complète :

1. La personne fournit les sources disponibles, dont une ou plusieurs vidéos, et utilise les services dans MORE pour enrichir l'apprentissage.
2. Elle comprend la proposition, peut la modifier ou l'accepter directement, puis la valide dans l'interface en sachant ce que MORE fera.
3. Lors du matin, MORE obtient les informations réelles, parle, ouvre les pages, réalise les interactions prévues et enchaîne les étapes.
4. La personne peut interrompre MORE pendant qu'il parle, poser une question, refuser une action, dicter une intention, demander l'exécution d'une action préparée, prolonger ou arrêter.
5. Une interruption technique ou une source indisponible permet une reprise compréhensible, sans perte des choix ni double effet externe.
6. La session se termine avec un résultat fidèle à ce qui a eu lieu et la routine reste disponible pour les matins suivants.

Il faut mesurer les gestes nécessaires après le démarrage, les étapes réellement réalisées, les erreurs et reprises, la qualité de l'apprentissage, la latence et la compréhension de la voix. La référence est la personne qui peut se préparer pendant que MORE s'occupe de sa routine.

Les tests de composants, les simulations et les builds servent à construire cette fiabilité. La preuve finale exige des parcours répétés dans l'app normale, sur iPhone, avec des comptes autorisés et des effets observés. Une simple succession de pages ouvertes et de boutons « Suivant » pressés par la personne reste un parcours assisté à compléter.

## 11. Garder cette direction dans le temps

Avant une nouvelle fonctionnalité ou un changement de parcours, vérifier sa contribution à la compréhension des habitudes, à la maîtrise personnelle ou à l'exécution hands-free. Les tâches et critères d'acceptation doivent décrire le comportement vécu et son résultat, au-delà du composant à brancher.

La direction produit de ce fichier prévaut sur les anciens scénarios de démonstration lorsqu'ils réduisent MORE à de la lecture, de la navigation manuelle ou un minuteur. Les comptes rendus historiques conservent leur valeur de preuve à leur date et à leur périmètre ; ils ne sont pas réécrits en capacités acquises.

Maintenir ici les décisions durables. Conserver les tâches, limites et preuves d'implémentation dans les issues GitHub et les documents techniques liés. Toute proposition qui change cette valeur centrale doit être discutée explicitement avec le fondateur avant de devenir la nouvelle direction.
