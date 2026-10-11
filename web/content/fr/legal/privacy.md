---
title: Politique de confidentialité
description: "Ce que Velorki fait de vos données : aucun compte, vos itinéraires et vos sorties restent sur votre téléphone, et la liste exacte de ce qui quitte l'appareil et à quel moment."
draft: true
---

> **Note sur la traduction.** Ceci est une traduction de la version anglaise.
> En cas de divergence, la version anglaise prévaut.

Date d'entrée en vigueur : 30 septembre 2026.

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
- Certaines choses nécessitent un serveur : les tuiles de carte, le routage en
  dehors des zones que vous avez téléchargées, la recherche lorsque vous la
  demandez et, si vous les utilisez, l'assistant IA, les connexions à Strava et
  à RideWithGPS, et les liens de partage. Chacun est décrit ci-dessous.
- Ce **site web** n'a ni outil d'analyse d'audience, ni publicité, ni pistage :
  le court avis affiché en bas de page ne vous demande donc rien.
- Nous ne vendons pas vos données et ne les utilisons ni à des fins
  publicitaires ni pour du profilage.

## Ce qui reste sur votre appareil

Les itinéraires planifiés, les sorties enregistrées, leurs traces GPS, vos
réglages, les régions de cartes hors ligne téléchargées, les tuiles de routage
téléchargées et les index de recherche de lieux qui les accompagnent sont
conservés dans le stockage propre de l'application, sur votre téléphone. Ils ne
sont envoyés nulle part, sauf si vous le demandez.

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
sur Android), sous une forme chiffrée que seul notre relais peut ouvrir ; voir
la section consacrée à Strava et à RideWithGPS ci-dessous.

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

### Strava et RideWithGPS (Velorki Plus)

Rien n'est envoyé à Strava ou à RideWithGPS tant que vous ne connectez pas
vous-même le compte et ne déclenchez pas ensuite une action : envoyer une
sortie, importer un itinéraire.

Lorsque vous vous connectez, l'application remet un code à usage unique à notre
serveur relais, qui l'échange contre un jeton d'accès en y ajoutant le secret
de notre application, chiffre le jeton avec une clé que seul le relais détient,
et le renvoie à l'application sous cette forme. Votre téléphone conserve le
jeton chiffré ; il ne peut pas l'utiliser seul, et nous ne le conservons pas du
tout.

Ensuite, chaque envoi, transfert d'itinéraire, import et déconnexion que vous
déclenchez passe par le relais : il vérifie que votre abonnement est actif,
déchiffre le jeton pour cette seule requête, transmet la requête à Strava ou à
RideWithGPS et renvoie la réponse à l'application. Il ne conserve ni le
fichier, ni le jeton, ni rien de la réponse, et il applique la même limitation
de débit qu'à tout autre appel au relais (voir Journaux des serveurs
ci-dessous). Ses journaux ne contiennent jamais le jeton, le corps de la
requête ni l'identifiant d'abonné.

Ce que Strava ou RideWithGPS font ensuite des données que vous leur envoyez est
régi par leurs propres politiques de confidentialité.

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
| Liens de partage | un an, puis supprimés automatiquement | supprimez-les depuis l'application |
| Requêtes à l'IA | non conservées par nous au-delà de ce que contiennent les journaux ci-dessus | sans objet |
| Données RevenueCat | selon la politique propre de RevenueCat | contactez-nous et nous transmettrons la demande |
| Conversations du chat d'assistance | dans notre canal Discord jusqu'à ce que nous les supprimions | demandez-le à ride@velorki.com |

La désinstallation de l'application supprime tout ce que l'application a stocké
sur l'appareil. Elle ne supprime pas les liens de partage que vous avez créés
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
| Strava et RideWithGPS : connexion d'un compte et chaque transfert que vous déclenchez | b) exécution du contrat, ainsi que a) consentement, donné en connectant le compte |
| Liens de partage que vous créez | b) exécution du contrat |
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
