---
title: Politique de confidentialité
description: "Ce que Velorki fait de vos données : aucun compte, vos itinéraires et vos sorties restent sur votre téléphone, et la liste exacte de ce qui quitte l'appareil et à quel moment."
draft: true
---

> **Note sur la traduction.** Ceci est une traduction de la version anglaise.
> En cas de divergence, la version anglaise prévaut.

Date d'entrée en vigueur : 16 octobre 2026.

Velorki est une application de planification d'itinéraires vélo et
d'enregistrement de sorties, développée par Orkitec. Cette page explique ce
qu'il advient de vos données.

**Qui est responsable.** Le responsable du traitement pour tout ce qui est
décrit ici est Steffen Roemer, exerçant sous le nom « Orkitec », Straße der
Pariser Kommune 27, 10243 Berlin, Allemagne, ride@velorki.com. Aucun délégué à
la protection des données n'est désigné : les traitements décrits ci-dessous
n'en exigent pas au titre de l'article 37 du RGPD. Les informations complètes
sur le prestataire figurent dans les [mentions légales](./imprint).

## En bref

- Il n'y a **aucun compte**. Vous ne vous inscrivez pas, et nous ne savons pas
  qui vous êtes.
- Vos itinéraires, vos sorties et vos réglages restent **sur votre téléphone**.
  Sur un iPhone ou un iPad, ils sont aussi synchronisés entre vos propres
  appareils par votre iCloud, et non par nous.
- Certaines choses nécessitent un serveur : les tuiles de carte, le routage en
  dehors des zones que vous avez téléchargées, la recherche lorsque vous la
  demandez et, si vous les utilisez, l'assistant IA, les connexions à Strava et
  à RideWithGPS (gratuites), et les liens de partage. Chacun est décrit ci-dessous.
- Ce **site web** n'a ni outil d'analyse d'audience, ni publicité, ni pistage :
  le court avis affiché en bas de page ne vous demande donc rien.
- Nous ne vendons pas vos données et ne les utilisons ni à des fins
  publicitaires ni pour du profilage.

## Ce qui reste sur votre appareil

Les itinéraires planifiés, les sorties enregistrées, leurs traces GPS, vos
réglages, les régions de cartes hors ligne téléchargées, les tuiles de routage
téléchargées et les index de recherche de lieux qui les accompagnent sont
conservés dans le stockage propre de l'application, sur votre téléphone. Ils ne
sont envoyés nulle part, sauf si vous le demandez ; la seule exception est la
synchronisation iCloud sur un iPhone ou un iPad, décrite plus bas, qui va vers
votre propre iCloud et non vers nous.

La fréquence cardiaque, la cadence et la puissance provenant d'une Apple Watch,
d'un capteur Bluetooth ou de votre application de santé sont enregistrées avec
la sortie, sur le téléphone, comme la trace elle-même. Lorsque l'interrupteur
Santé est activé dans les Réglages, l'application lit la fréquence cardiaque
depuis Apple Health ou Health Connect et y inscrit vos sorties terminées en tant
qu'entraînements de cyclisme ; cet échange a lieu sur votre téléphone et rien
ne nous en parvient. Les valeurs des capteurs ne voyagent avec une sortie que
là où la sortie elle-même va : dans un fichier GPX, FIT ou TCX que vous
exportez, ou dans un envoi vers Strava ou RideWithGPS que vous lancez.

Si vous connectez Strava ou RideWithGPS, les jetons d'accès à ces comptes sont
conservés dans le stockage sécurisé du téléphone (Keychain sur iOS, Keystore
sur Android), sous une forme chiffrée que seul notre relais peut ouvrir, et ce que vous
récupérez de Strava est conservé sur le téléphone ; voir la section consacrée à
Strava et à RideWithGPS ci-dessous.

Sur Android, l'application est exclue de la sauvegarde dans le cloud de Google
et du transfert d'appareil à appareil : vos sorties et vos jetons d'accès ne
sont donc pas non plus copiés hors du téléphone par le système. Pour passer à
un nouveau téléphone, exportez ce que vous souhaitez conserver sous forme de
fichiers GPX, FIT ou TCX.

## Ce qui quitte votre appareil, et quand

### Routage

Le routage se fait normalement entièrement sur votre téléphone, à partir des
tuiles de routage que vous avez téléchargées, et rien n'est envoyé nulle part.
Pour une zone dont vous n'avez pas les tuiles, l'application envoie les
coordonnées de vos points de passage à un serveur de routage (BRouter, exploité
par nous), qui renvoie l'itinéraire. Il a besoin des points de passage pour
calculer l'itinéraire ; il ne reçoit ni votre identité, ni vos autres
itinéraires, ni vos sorties.

### Recherche

Les lieux sont recherchés sur votre téléphone, dans les index de recherche qui
accompagnent les tuiles de routage que vous avez téléchargées. Rien de ce que
vous y saisissez ne quitte l'appareil.

Si vous touchez « Rechercher “…” en ligne » en bas des résultats (ou si vous
n'avez téléchargé aucune tuile de routage, auquel cas le champ de recherche
interroge directement le service en ligne), ce que vous avez saisi est envoyé à
Photon, un service de géocodage, accompagné d'une position approximative afin
que les résultats proches apparaissent en premier. Photon renvoie des
suggestions de lieux.

Toucher « Détails » sur la fiche d'un lieu récupère ses informations détaillées
(horaires d'ouverture, site web, etc.) auprès d'OpenStreetMap.

### Tuiles de carte

La carte est dessinée à partir de tuiles récupérées auprès d'OpenFreeMap, et
auprès de CyclOSM si vous activez la surcouche vélo. Récupérer une tuile indique
au fournisseur de tuiles quelle partie de la carte vous regardez et implique
votre adresse IP, comme toute requête web. Données cartographiques
© contributeurs d'OpenStreetMap.

### Météo

**La carte météo et les prévisions gratuites de l'itinéraire.** Lorsque vous
activez la pluie, les nuages ou le vent sur la carte, ou que vous colorez un
itinéraire selon le vent ou la pluie sans Velorki Plus, l'application récupère
des images et des données de prévision directement auprès de services
météorologiques publics : le Deutscher Wetterdienst (Allemagne), la National
Oceanic and Atmospheric Administration américaine et l'Iowa State University
(États-Unis), la NASA, EUMETSAT, le KNMI (Pays-Bas) et l'Institut météorologique
finlandais. Chaque requête indique une partie de la carte, ou un cadre autour de
votre itinéraire, et une heure, et implique votre adresse IP, comme toute
requête web. Votre itinéraire lui-même, vos sorties et votre identité ne sont
pas transmis.

**Une météo plus fine le long de l'itinéraire (Velorki Plus).** L'application
envoie à notre relais les points le long de l'itinéraire arrondis à une grille
d'environ 2,5 km, chacun avec son altitude arrondie à 50 m, et les heures
auxquelles vous y passerez — pas l'itinéraire, ni son nom, ni vos sorties. Le
relais vérifie que votre abonnement est actif et interroge le National Weather
Service américain, Bright Sky (pour les prévisions du Deutscher Wetterdienst) et
MET Norway sur ces points de grille. Ceux-ci voient notre serveur, pas votre
téléphone. Chaque réponse est conservée jusqu'à deux heures par point de grille
et partagée avec tous ceux qui demandent le même point.

**Radar de pluie sur toute l'Europe (Velorki Plus).** L'application demande à
notre relais la partie de la carte que vous regardez et une heure. Le relais
récupère le radar une seule fois pour tout le monde dans l'archive ouverte
d'EUMETNET OPERA et, pour l'Italie, auprès du Dipartimento della Protezione
Civile, le conserve jusqu'à deux heures et demie et renvoie une image de cette
partie de la carte. Les fournisseurs du radar voient notre serveur, pas votre
téléphone, et le relais ne garde aucune trace de la partie de la carte que vous
avez demandée.

### Strava et RideWithGPS

Les deux connexions sont gratuites. Rien n'est envoyé à Strava ou à RideWithGPS
tant que vous ne connectez pas vous-même le compte et ne déclenchez pas ensuite
une action : envoyer une sortie, importer un itinéraire.

Lorsque vous vous connectez, l'application remet un code à usage unique à notre
serveur relais (api.velorki.com), qui l'échange contre un jeton d'accès en y
ajoutant le secret de notre application, chiffre le jeton avec une clé que seul
le relais détient, et le renvoie à l'application sous cette forme. Votre
téléphone conserve le jeton chiffré dans son stockage sécurisé (Keychain sur
iOS, Keystore sur Android), exclu des sauvegardes ; il ne peut pas l'utiliser
seul, et nous ne le conservons pas du tout.

Ensuite, chaque envoi, transfert d'itinéraire, import et déconnexion que vous
déclenchez passe par le relais : il déchiffre le jeton pour cette seule requête,
transmet la requête à Strava ou à RideWithGPS et renvoie la réponse à
l'application. Il ne conserve ni le fichier, ni le jeton, ni rien de la réponse,
ni aucune trace de l'appel. Aucun abonnement n'est vérifié pour ces appels ; pour
empêcher les abus, le relais ne garde que des compteurs de limitation de débit
de courte durée, associés à l'identifiant anonyme de votre installation et à
l'adresse IP (voir Journaux des serveurs ci-dessous). Ses journaux ne
contiennent jamais le jeton, le corps de la requête ni cet identifiant.

#### Strava

**Ce que Velorki demande.** Deux autorisations : `read`, votre profil Strava
public (votre identifiant d'athlète et votre nom), et `activity:write`, pour
téléverser les sorties que vous choisissez de téléverser. Velorki ne lit pas vos
activités.

**Ce qu'il lit et conserve, uniquement sur votre téléphone :**

- votre identifiant d'athlète et votre nom, affichés dans Réglages →
  Connexions, jusqu'à ce que vous vous déconnectiez ;
- votre liste d'itinéraires Strava (nom, distance, dénivelé positif,
  description et date), récupérée lorsque vous ouvrez l'écran d'import et
  conservée sur le téléphone **48 heures** au plus ;
- le fichier GPX d'un itinéraire, lorsque vous importez cet itinéraire ; il est
  conservé comme itinéraire dans la bibliothèque de l'application, de même que
  tout itinéraire que vous modifiez à partir de lui, uniquement tant que
  l'itinéraire existe encore sur Strava : tant que l'application est ouverte,
  en ligne et connectée, elle le revérifie auprès de Strava toutes les 48
  heures, et le supprime s'il a été supprimé sur Strava ou n'a pas pu être
  vérifié pendant 7 jours, et vous le signale. Il est aussi supprimé lorsque
  vous le supprimez ou que vous vous déconnectez ;
- après un envoi, l'identifiant de l'activité Strava et son lien, conservés avec
  la sortie pour que l'application puisse afficher « View on Strava », jusqu'à
  ce que vous vous déconnectiez.

Une sortie que vous envoyez est transmise à Strava, qui la traite comme décrit
dans la [politique de confidentialité de Strava](https://www.strava.com/legal/privacy).
Strava et Orkitec sont chacun responsables de leur propre traitement.

**Les données Strava restent chez vous.** Les données Strava ne servent qu'à
vous être montrées, dans l'application. Elles ne sont jamais envoyées à
l'assistant IA, jamais mises dans un lien de partage et jamais envoyées à
RideWithGPS ni à aucun autre service. Nous ne détenons aucune donnée Strava sur
nos serveurs.

**Suppression.** La déconnexion de Strava dans Réglages → Connexions révoque
l'autorisation de Velorki chez Strava, supprime les jetons et supprime du
téléphone tout élément venant de Strava : les itinéraires Strava importés et
ceux modifiés à partir d'eux, la liste d'itinéraires en cache et les liens
d'activité conservés. L'application le confirme alors : « Vos données Strava ont
été supprimées de ce téléphone. » Si vous révoquez plutôt l'accès de Velorki sur
strava.com, l'application le remarque à son prochain appel à Strava, supprime
les mêmes données et vous le dit. Désinstaller l'application les supprime aussi.
Comme tout est sur votre téléphone, ce sont les moyens de les supprimer ; pour
toute question ou demande de suppression, écrivez à ride@velorki.com.

**Données d'utilisation chez Strava.** Strava peut surveiller et collecter des
données sur la manière dont Velorki utilise l'API de Strava (données
d'utilisation) et peut les utiliser à toute fin commerciale, interne ou externe,
y compris pour apporter des améliorations à l'API de Strava ou à la plateforme
Strava, fournir une assistance aux développeurs ou aux utilisateurs, et veiller
au respect de son contrat d'API.

#### RideWithGPS

Ce que RideWithGPS fait des données que vous lui envoyez est régi par sa propre
politique de confidentialité.

### L'assistant IA (Velorki Plus)

L'assistant est désactivé tant que vous ne l'activez pas, et votre consentement
vous est demandé la première fois que vous l'ouvrez. Vous pouvez choisir
d'envoyer uniquement votre texte, ou votre texte accompagné d'une position de
départ approximative, ou de refuser. Vous pouvez retirer votre consentement à
tout moment dans les réglages.

Lorsque vous l'utilisez, les éléments suivants sont envoyés, via notre serveur
relais, à notre fournisseur d'IA :

- le texte que vous avez saisi,
- facultativement, une position de départ **arrondie à environ un kilomètre**,
- les réglages de langue et d'unités, pour que la réponse soit adaptée,
- si vous demandez une description d'itinéraire, un résumé de l'itinéraire
  établi sur votre téléphone : distance, montée, répartition des revêtements,
  les tronçons qu'il emprunte avec leur route, leur revêtement et leur pente,
  ses montées, les localités qu'il traverse et les haltes situées à proximité,
  chacun avec sa distance le long de l'itinéraire et sa position (à environ
  10 m près). Le fournisseur d'IA les reçoit également ; un itinéraire qui part
  de votre domicile révèle donc où se trouve votre domicile.

Aucun identifiant vous concernant, vous ou votre téléphone, n'est inséré dans la
requête. Le modèle renvoie une demande structurée : une distance, une forme, des
noms de lieux, des préférences. Le routage proprement dit a ensuite lieu dans
l'application ; le modèle ne voit jamais votre itinéraire.

Notre relais transmet la requête à **OpenRouter, Inc.** (États-Unis), un
service qui donne accès à des modèles de langage de plusieurs fournisseurs, et
OpenRouter la transmet au fournisseur qui sert le modèle que nous utilisons.
Nous avons configuré OpenRouter pour n'envoyer les requêtes qu'à des
fournisseurs qui ne s'en servent pas pour entraîner des modèles et ne les
conservent pas. Le transfert vers les États-Unis repose sur les clauses
contractuelles types de la Commission européenne. OpenRouter et le fournisseur
du modèle reçoivent la requête de notre relais, et non de votre téléphone : ils
voient donc l'adresse de notre serveur, et non la vôtre.

L'assistant accède au modèle via une interface compatible OpenAI : toute
personne qui héberge elle-même Velorki peut donc diriger son relais vers
n'importe quel fournisseur ou vers son propre modèle ; c'est alors la politique
de cet exploitant qui s'applique, et non la présente.

Les données provenant de Strava ne sont jamais envoyées au fournisseur d'IA.

### Liens de partage (Velorki Plus)

Si vous créez un lien de partage pour un itinéraire ou une sortie, cet
itinéraire ou cette sortie, avec sa trace, son nom et ses statistiques, est
envoyé sur notre serveur et y est conservé afin que toute personne disposant du
lien puisse l'ouvrir. La fréquence cardiaque, la cadence et la puissance en
sont exclues : une sortie partagée comporte sa trace et ses temps, pas ce qu'un
capteur a mesuré. Le lien est public : toute personne qui le possède peut voir
le contenu, y compris les points de départ et d'arrivée de la trace. Pensez-y
avant de partager une sortie qui part de votre domicile.

Un élément partagé est conservé **un an**, puis supprimé automatiquement. Pour
le faire supprimer plus tôt, envoyez le lien à l'adresse de contact ci-dessous
et nous le supprimons. Consulter un lien partagé ne nécessite aucun compte.

### Synchronisation iCloud (iPhone et iPad)

Sur un iPhone ou un iPad sous iOS 17 ou plus récent, vos itinéraires enregistrés
et vos sorties enregistrées, avec la trace, les notes et les statistiques de
chaque sortie, sont synchronisés entre vos propres appareils Apple connectés au
même compte Apple. Quelques réglages le sont aussi : thème, couleur d'accent,
aspect de la carte, style de la barre, côté de la colonne, unités, ainsi que les
réglages des annonces de virage et des annonces vocales. Elle est activée par
défaut, et l'interrupteur **Synchroniser avec iCloud** dans les Réglages la
désactive sur cet appareil.

Les données passent par CloudKit d'Apple et sont conservées dans votre propre
base de données privée iCloud. Apple les stocke et les transfère, et elles
comptent dans votre stockage iCloud. Orkitec n'exploite aucun serveur pour cela
et ne peut ni les lire, ni y accéder, ni les supprimer ; il n'y a pas de compte
Velorki. Apple chiffre les données en transit et sur ses serveurs ; avec la
protection avancée des données activée, elles sont chiffrées de bout en bout,
comme le décrit l'[aperçu de la sécurité des données iCloud d'Apple](https://support.apple.com/en-us/102651).

Certaines choses ne sont jamais synchronisées. Les itinéraires lus depuis Strava
et les itinéraires modifiés à partir d'eux, ainsi que les liens Strava des
sorties que vous avez envoyées vers Strava, restent sur ce seul téléphone,
comme décrit plus haut à la section Strava. Les liens des envois vers Ride with
GPS ne sont pas synchronisés non plus ; un itinéraire que vous importez depuis
Ride with GPS est synchronisé comme votre propre itinéraire, sans son
identifiant Ride with GPS. Les régions de carte téléchargées et les tuiles de
routage, les autorisations, les capteurs associés, les comptes connectés et
l'état de l'abonnement n'en font pas partie. L'application Android ne
synchronise pas.

Désactiver l'interrupteur arrête la synchronisation sur cet appareil. Ce qui est
déjà dans iCloud y reste jusqu'à ce que vous le supprimiez, dans les réglages
iCloud de l'appareil.

### Abonnements

Velorki Plus est vendu via l'App Store et Google Play, et géré pour notre
compte par RevenueCat. RevenueCat attribue à votre installation un
**identifiant d'utilisateur anonyme de l'application**, une chaîne aléatoire qui
n'est liée ni à un nom, ni à une adresse e-mail, ni à un identifiant
d'appareil. RevenueCat reçoit également le reçu d'achat de la boutique. Notre
relais envoie cet identifiant anonyme à RevenueCat pour vérifier si votre
abonnement est actif, et à rien d'autre.

Nous ne voyons jamais vos données de paiement ; elles restent chez Apple ou
Google.

### Rapports de plantage et analyse d'audience

Il n'y en a pas. L'application ne contient aucun SDK de rapport de plantage,
d'analyse d'audience ou de publicité, et elle n'envoie aucune statistique
d'utilisation ; chaque requête réseau qu'elle effectue est l'une de celles
décrites ci-dessus. Les plantages sont signalés de manière agrégée par les
boutiques d'applications au compte développeur, sans rien qui vous identifie,
et uniquement si vous l'avez activé dans les réglages de votre téléphone. Si un
outil de rapport de plantage est un jour ajouté, cette section le nommera et
indiquera ce qu'il collecte avant la sortie de la version concernée.

### Journaux des serveurs

Notre relais et notre serveur de routage tiennent des journaux d'exploitation
(heure de la requête, point d'accès, statut, adresse IP et un en-tête indiquant
la version du client) pour faire fonctionner le service, détecter les pannes et
appliquer les limitations de débit. Ils ne servent pas à établir des profils
d'utilisateurs et ne contiennent jamais de jeton d'accès, de corps de requête
ni d'identifiant d'abonné.

- Les journaux d'accès du serveur web sont conservés sur la machine pendant
  **14 jours**, puis supprimés par la rotation des journaux.
- Les lignes de journal propres à l'application sont collectées par Orkify, le
  tableau de bord de déploiement que l'exploitant fait tourner sur la même
  infrastructure Hetzner, et y sont purgées au plus tard après **90 jours**.

## Ce site web

velorki.com est un site web simple : aucun compte, aucune publicité, aucun outil
d'analyse d'audience, aucun pistage. Rien de ce que vous faites ici n'est
mesuré : l'avis que vous avez peut-être vu en bas de la page n'est donc
exactement que cela, un avis ; il n'y a aucun consentement à donner ou à
refuser, car rien n'est stocké sur votre appareil tant que vous ne le demandez
pas. L'entrée 🍪 Cookies du pied de page le fait réapparaître.

- **Journaux des serveurs.** Chaque requête est journalisée comme décrit
  ci-dessus sous Journaux des serveurs : heure, chemin, statut, taille, votre
  adresse IP et l'agent utilisateur de votre navigateur, conservés 14 jours.
- **Rapports d'erreur.** Si une page de ce site échoue dans votre navigateur,
  elle envoie l'erreur, l'adresse de la page et l'agent utilisateur de votre
  navigateur à notre serveur, uniquement pour que nous puissions corriger le
  bogue.
- **Cloudflare.** Le site est servi via Cloudflare, qui termine la connexion,
  filtre les attaques et transmet la requête à notre serveur. Cloudflare traite
  donc votre adresse IP et la requête elle-même. Cloudflare est établi aux
  États-Unis ; le transfert repose sur les clauses contractuelles types de l'UE.
- **Un cookie de langue.** Choisir une langue dans l'en-tête dépose un cookie
  appelé `NEXT_LOCALE` (valeur `en` ou `de`, durée d'un an). Il sert à ce que
  le site s'ouvre dans la langue que vous avez choisie. Rien d'autre n'y est
  stocké, et il n'est déposé que lorsque vous faites ce choix — il est
  strictement nécessaire à une fonction que vous avez demandée et ne requiert
  aucun consentement au titre de l'article 25, paragraphe 2, du TTDSG.
- **Une préférence de thème.** Choisir le mode clair, le mode sombre ou une
  couleur d'accentuation inscrit `velorki.theme` dans le stockage local de
  votre navigateur. Cette valeur ne quitte jamais le navigateur et nous ne
  pouvons pas la lire. Fermer l'avis mentionné ci-dessus inscrit une clé
  supplémentaire, `velorki.cookie-notice`, afin qu'il ne s'affiche plus.
- **Pages de partage.** Ouvrir un lien `velorki.com/s/…` charge l'itinéraire
  partagé depuis notre serveur et les tuiles de carte depuis OpenFreeMap, qui
  voit votre adresse IP comme pour toute requête web. La page ne contient aucun
  autre contenu tiers.
- **Le chat d'assistance.** Le bouton de chat dans le coin est le widget
  d'Orkify. Orkitec exploite également Orkify : il s'agit donc de notre propre
  infrastructure, mais d'un site différent ; le script est chargé depuis
  orkify.com et demande ses paramètres à orkify.com à l'ouverture de la page, ce
  qui signifie que votre adresse IP lui parvient, comme elle parvient à tout
  serveur auquel vous adressez une requête. Rien d'autre ne se passe tant que
  vous n'ouvrez pas le chat.

  Lorsque vous nous écrivez, votre message — ainsi que le nom et l'adresse
  e-mail que vous saisissez dans son formulaire — est transmis à un canal
  Discord privé où nous répondons, et la conversation y reste jusqu'à ce que
  nous la supprimions. Demandez-le à ride@velorki.com et nous supprimons la
  vôtre. Le widget conserve l'identifiant de la conversation ainsi que le nom et
  l'adresse e-mail que vous avez indiqués dans le stockage local de votre
  navigateur, afin qu'une réponse vous parvienne encore lorsque vous revenez, et
  les efface lorsque vous mettez fin au chat. Si vous ouvrez le sélecteur
  d'autocollants, votre recherche est envoyée à Klipy, qui renvoie les images.
  Ne mettez dans le chat rien que vous ne voudriez pas voir figurer dans un
  ticket d'assistance ; pour signaler un problème de sécurité, utilisez plutôt
  l'adresse indiquée dans
  [SECURITY.md](https://github.com/orkitec/velorki/blob/main/SECURITY.md).
- **Les polices et les images** proviennent toutes de ce serveur et, en dehors
  du chat d'assistance, il n'y a aucun script tiers, aucun CDN pour nos propres
  ressources et aucun service de polices.

## Conservation et suppression

| Données | Conservation | Comment les supprimer |
|---|---|---|
| Itinéraires, sorties, réglages, données hors ligne | sur votre téléphone, jusqu'à ce que vous les supprimiez | supprimez-les dans l'application, ou désinstallez l'application |
| Jetons Strava / RideWithGPS | sur votre téléphone, chiffrés de sorte que seul notre relais puisse les ouvrir, jusqu'à ce que vous vous déconnectiez ; jamais conservés de notre côté | déconnectez-vous dans l'application, ou désinstallez-la |
| Données Strava : votre nom, les liens d'activité | sur votre téléphone, jusqu'à ce que vous vous déconnectiez ; jamais conservées de notre côté | déconnectez Strava dans l'application, ou désinstallez-la ; questions à ride@velorki.com |
| Itinéraires importés depuis Strava, et itinéraires modifiés à partir d'eux | sur votre téléphone, uniquement tant que l'itinéraire existe encore sur Strava : revérifié toutes les 48 heures, supprimé s'il y a été supprimé ou n'a pas pu être vérifié pendant 7 jours ; jamais conservés de notre côté | supprimez-le dans l'application, déconnectez Strava, ou désinstallez l'application |
| La liste en cache de vos itinéraires Strava | sur votre téléphone, 48 heures au plus | déconnectez Strava, ou désinstallez l'application |
| Compteurs de limitation de débit (identifiant d'installation anonyme, adresse IP) | sur notre serveur, pendant la fenêtre de comptage, un jour au plus | sans objet |
| Liens de partage | un an, puis supprimés automatiquement | supprimez-les depuis l'application |
| Itinéraires, sorties et réglages synchronisés par iCloud (iPhone et iPad) | dans votre propre iCloud, jusqu'à ce que vous les y supprimiez ; jamais conservés de notre côté | supprimez-les dans les réglages iCloud de l'appareil |
| Requêtes à l'IA | non conservées par nous au-delà de ce que contiennent les journaux ci-dessus | sans objet |
| Données RevenueCat | selon la politique propre de RevenueCat | contactez-nous et nous transmettrons la demande |
| Conversations du chat d'assistance | dans notre canal Discord jusqu'à ce que nous les supprimions | demandez-le à ride@velorki.com |

La désinstallation de l'application supprime tout ce que l'application a stocké
sur l'appareil. Ce que la synchronisation iCloud a placé dans votre iCloud y
reste ; voir la synchronisation iCloud plus haut. Elle ne supprime pas les liens de partage que vous avez créés
(ils expirent au bout d'un an, ou sur demande), ni rien de ce que vous avez
envoyé vers Strava ou RideWithGPS.

## Bases juridiques

Pour les lecteurs situés dans l'UE et au Royaume-Uni, les bases juridiques au
sens de l'article 6, paragraphe 1, du RGPD sont les suivantes :

| Quoi | Base juridique |
|---|---|
| Servir le site web et les pages de partage, maintenir les serveurs en fonctionnement, détecter les pannes, limiter le débit, se défendre contre les attaques | f) intérêt légitime à exploiter un service qui fonctionne et dont il n'est pas fait un usage abusif |
| Routage en ligne et recherche en ligne, lorsque vous les demandez | b) exécution du service que vous avez demandé, et f) pour les coordonnées strictement nécessaires pour répondre |
| Velorki Plus : vérification auprès de RevenueCat qu'un abonnement est actif | b) exécution du contrat |
| Velorki Plus : la météo plus fine le long de l'itinéraire et le radar de pluie | b) exécution du contrat |
| Strava et RideWithGPS : connexion d'un compte, chaque transfert que vous déclenchez et les données Strava conservées sur votre téléphone | b) exécution du service que vous avez demandé, ainsi que a) consentement, donné en connectant le compte et retiré en le déconnectant |
| Liens de partage que vous créez | b) exécution du contrat |
| Synchronisation iCloud (iPhone et iPad), tant que l'interrupteur est activé | b) exécution du service que vous avez demandé ; Apple agit en vertu de votre propre contrat iCloud avec Apple |
| L'assistant IA | a) consentement, demandé séparément dans l'application et révocable dans les réglages |
| Vous répondre dans le chat d'assistance | b) lorsque cela concerne un abonnement, sinon f) intérêt légitime à répondre à la personne qui nous a écrit |
| Conservation des pièces fiscalement pertinentes relatives à un abonnement | c) obligation légale — et ce sont Apple et Google, et non nous, qui détiennent les données de facturation |

Nous ne faisons pas de profilage, ne prenons aucune décision automatisée vous
concernant et n'utilisons aucune de ces données à des fins de prospection
directe.

## Qui d'autre reçoit des données

Nous ne vendons, ne louons ni n'échangeons de données personnelles. Elles
parviennent aux parties suivantes, et à aucune autre :

**Sous-traitants, agissant pour notre compte en vertu d'un contrat de
sous-traitance**

- **Hetzner Cloud GmbH**, Gunzenhausen, Allemagne — le serveur qui fait tourner
  le relais, les liens de partage et ce site web. Les données restent en
  Allemagne.
- **Cloudflare, Inc.**, San Francisco, États-Unis — DNS, CDN et protection
  contre les attaques pour velorki.com et api.velorki.com. Adresses IP et
  métadonnées des requêtes.
- **RevenueCat, Inc.**, San Francisco, États-Unis — la vérification de
  l'abonnement. L'identifiant d'utilisateur anonyme de l'application et le reçu
  de la boutique, sans nom ni adresse e-mail.
- **Orkify**, exploité par le même exploitant sur l'infrastructure Hetzner
  mentionnée ci-dessus — le tableau de bord de déploiement qui collecte les
  journaux de l'application et les métriques des processus décrits sous
  Journaux des serveurs ainsi que les rapports d'erreur de ce site web, et le
  widget du chat d'assistance.
- **Discord Netherlands B.V.** (pour les utilisateurs en Europe ; Discord Inc.,
  San Francisco, États-Unis, pour le service sous-jacent) — où une conversation
  du chat d'assistance est transmise et conservée.
- **Klipy** — la recherche d'autocollants et de GIF dans le chat d'assistance,
  et uniquement pendant que ce sélecteur est ouvert.
- **OpenRouter, Inc.**, États-Unis, et le fournisseur de modèle auquel il
  transmet les requêtes — l'assistant IA, uniquement après votre consentement,
  limité aux fournisseurs qui n'entraînent pas de modèles sur les requêtes et
  ne les conservent pas.

**Services que votre téléphone ou votre navigateur contacte directement, chacun
étant responsable de ses propres traitements**

- **OpenFreeMap** (tuiles de carte) et **OpenStreetMap France** (la surcouche
  CyclOSM, uniquement lorsque vous l'activez) — les tuiles de la partie de la
  carte que vous regardez, et votre adresse IP.
- **komoot GmbH**, Potsdam, Allemagne — le géocodeur Photon à l'adresse
  `photon.komoot.io`, et uniquement pour une recherche en ligne que vous avez
  demandée.
- **OpenStreetMap** (`api.openstreetmap.org`) — les détails d'un lieu, lorsque
  vous touchez « Détails » sur sa fiche.
- **Services météorologiques publics** — le Deutscher Wetterdienst, la NOAA,
  l'Iowa State University, la NASA, EUMETSAT, le KNMI et l'Institut
  météorologique finlandais — la partie de la carte ou le cadre autour de votre
  itinéraire que vous avez demandé, une heure et votre adresse IP, uniquement
  lorsqu'une couche météo ou les prévisions gratuites de l'itinéraire sont
  activées.
- **Apple Inc.** (iCloud) — les itinéraires, sorties et réglages de la
  synchronisation iCloud, dans votre propre iCloud et uniquement tant que
  l'interrupteur est activé. Nous ne les recevons pas ; Apple agit en vertu de
  votre propre contrat iCloud avec Apple.
- **Apple Inc.** et **Google Ireland Ltd** — la vente de Velorki Plus. Ce sont
  eux les vendeurs ; nous ne voyons jamais vos données de paiement.
- **Strava, Inc.** et **Ride with GPS** — uniquement après que vous avez
  connecté le compte et uniquement pour un transfert que vous déclenchez. Ce
  qu'ils en font est régi par leurs propres politiques.

Nous communiquerons également des données à une juridiction ou à une autorité
lorsque la loi l'exige.

## Transferts hors de l'UE

Cloudflare, RevenueCat, OpenRouter et le fournisseur de modèle auquel il fait
appel, Discord, Klipy, Strava, Ride with GPS, Apple et Google sont établis aux
États-Unis ou y transfèrent des données. Ces transferts reposent sur les
clauses contractuelles types de la Commission européenne ou, lorsque le
fournisseur en dispose, sur sa certification au titre du cadre de protection
des données UE–États-Unis (EU–US Data Privacy Framework), complétées par les
garanties techniques propres au fournisseur. Hetzner, komoot et les services de
tuiles de carte auxquels nous faisons appel sont établis dans l'UE,
OpenStreetMap au Royaume-Uni. Tout ce que l'application stocke pour vous reste
sur votre téléphone et n'est transféré nulle part.

## Sécurité

Chaque connexion à nos serveurs et aux services ci-dessus est chiffrée par TLS.
Les jetons Strava et RideWithGPS ne se trouvent jamais nulle part en clair :
votre téléphone les conserve dans le stockage sécurisé de la plateforme,
enveloppés avec une clé que seul le relais possède, et le relais n'en déchiffre
un que pour la seule requête qui le nécessite, sans rien conserver. La base de
données des partages se trouve sur le disque du serveur, en dehors du
répertoire de publication, et n'est lisible que par l'utilisateur du service.
Les journaux sont expurgés : aucun en-tête `Authorization`, aucun corps de
requête, aucun identifiant d'abonné. L'accès au serveur nécessite une clé, et
non un mot de passe, et est réservé à l'exploitant. Si une violation de
données devait mettre vos droits en danger, nous la notifierons à l'autorité de
contrôle dans un délai de 72 heures (article 33 du RGPD) et, lorsque la loi
l'exige, à vous.

## Vos droits

Si vous vous trouvez dans l'UE ou au Royaume-Uni, vous disposez d'un droit
d'accès (article 15 du RGPD), de rectification (16), d'effacement (17), à la
limitation du traitement (18), à la portabilité des données (20) et d'un droit
d'opposition aux traitements fondés sur un intérêt légitime (21) ; et lorsque
nous nous fondons sur votre consentement — l'assistant —, vous pouvez le
retirer à tout moment, sans que cela remette en cause la licéité du traitement
effectué avant ce retrait (article 7, paragraphe 3). Vous pouvez exercer
vous-même la plupart de ces droits, car les données se trouvent sur votre
téléphone et peuvent être exportées sous forme de fichiers GPX, FIT ou TCX
quand vous le souhaitez.

Pour tout ce qui est détenu de notre côté (liens de partage, entrées de
journal, enregistrement RevenueCat), écrivez à **ride@velorki.com**. Nous
répondons dans un délai de 30 jours. Nous aurons besoin de suffisamment
d'informations pour identifier les données, ce qui, pour un lien de partage,
signifie le lien lui-même, puisqu'il n'existe aucun compte grâce auquel nous
pourrions vous retrouver.

Vous pouvez également introduire une réclamation auprès d'une autorité de
contrôle. La nôtre est la
[Berliner Beauftragte für Datenschutz und Informationsfreiheit](https://www.datenschutz-berlin.de)
(commissaire de Berlin à la protection des données et à la liberté
d'information), et vous pouvez tout aussi bien vous adresser à l'autorité de
votre lieu de résidence.

Le responsable du traitement est Steffen Roemer, exerçant sous le nom
« Orkitec », Straße der Pariser Kommune 27, 10243 Berlin, Allemagne.

## Enfants

Velorki ne s'adresse pas aux enfants et ne collecte pas sciemment de données
les concernant. L'application n'a aucune fonction sociale, aucune messagerie
entre utilisateurs et aucune publicité.

## Modifications

Si la présente politique change d'une manière qui affecte ce qui quitte votre
appareil, l'application vous en informera la prochaine fois que vous l'ouvrirez,
et la date indiquée en haut de cette page changera. Les anciennes versions
restent disponibles dans l'historique git du dépôt.

## Contact

Orkitec, ride@velorki.com ; adresse postale dans les
[mentions légales](./imprint). Pour signaler un problème de sécurité, consultez
[SECURITY.md](https://github.com/orkitec/velorki/blob/main/SECURITY.md) dans le
dépôt du code source.
