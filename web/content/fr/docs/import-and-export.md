---
title: Importer et exporter
description: "Ouvrir des fichiers GPX, FIT et TCX depuis n’importe où sur le téléphone, les enregistrer comme itinéraires ou sorties, et exporter les vôtres vers Komoot, Garmin ou tout autre outil."
order: 10
---

Velorki lit et écrit des fichiers GPX, FIT et TCX, et c’est ainsi que les itinéraires et les sorties circulent entre lui et le reste du monde. Tout cela est gratuit, sans compte ni connexion, et fonctionne avec Komoot, Garmin Connect, Strava, un compteur de vélo ou un simple fichier sur le téléphone.

## Faire entrer un fichier

Il y a trois façons, et toutes mènent au même écran d’import.

**Ouvrir avec.** Touchez un fichier GPX, FIT ou TCX dans votre appli de fichiers, dans un e-mail ou dans les téléchargements du navigateur, et choisissez Velorki. Sur iPhone, c’est « Ouvrir dans Velorki » depuis Fichiers, Mail ou Safari.

**Feuille de partage.** Dans une autre appli, partagez le fichier et choisissez Velorki. C’est ainsi qu’un itinéraire arrive depuis Komoot ou depuis le message d’un ami.

**Le sélecteur.** Dans l’onglet **Bibliothèque**, touchez **Importer un fichier** en haut à droite et choisissez le fichier vous-même.

**Un lien Ride with GPS.** Partagez le lien d’un itinéraire depuis l’appli Ride with GPS ou un navigateur et choisissez Velorki : l’itinéraire arrive sur l’écran d’import. Un itinéraire public n’exige rien d’autre ; un itinéraire privé est récupéré via votre compte Ride with GPS connecté, et sans compte l’écran dit « Cet itinéraire Ride with GPS est privé. Connectez Ride with GPS dans les Réglages pour l’ouvrir. »

Un fichier qui ne peut pas être importé ouvre le même écran avec la raison : ce n’est pas un fichier GPX, FIT ou TCX, il est illisible, vide, ou c’est un lien qui n’a pas pu être récupéré.

Velorki détermine ce qu’est le fichier en lisant ses premiers octets, sans se fier à son nom ni à son type : un `.gpx` qui est en réalité un fichier FIT s’importe donc quand même. Un fichier TCX est reconnu à son élément racine.

## Un lieu depuis une autre appli

Velorki accepte aussi un lieu isolé où aller à vélo, et l’ouvre dans l’onglet **Planifier** comme s’ouvre un résultat de recherche : épinglé sur la carte, sur sa [fiche du lieu](./search#la-fiche-du-lieu).

- **Feuille de partage.** Partagez un lieu depuis Google Maps, Plans d’Apple, OpenStreetMap, un navigateur ou une messagerie et choisissez Velorki. Un lien de carte, des coordonnées comme `52.5200, 13.4050` ou `52°31'12"N 13°24'18"E`, ou une adresse fonctionnent tous ; une adresse va dans le champ de recherche, qui la trouve.
- **Ouvrir avec** (Android). Un lieu qu’une autre appli ouvre (un lien `geo:`) propose Velorki dans le sélecteur.
- **Liens courts** comme `maps.app.goo.gl/…`, `maps.apple/p/…` ou `osm.org/go/…` n’indiquent où ils mènent qu’une fois ouverts. En ligne, Velorki les ouvre (une requête vers ce service, rien d’autre n’est envoyé) et arrive sur le lieu ; hors ligne, il le dit : ouvrez d’abord le lien dans un navigateur, puis partagez le lieu depuis là.

**Pour les développeurs d’applis**, Velorki ouvre ces liens :

| Lien | Ouvre |
|---|---|
| `velorki://navigate?lat=52.52&lon=13.405&name=Brandenburger%20Tor` | le lieu à ces coordonnées, nommé d’après `name` (facultatif) |
| `velorki://navigate?q=Pariser%20Platz%201%2C%20Berlin` | une recherche de l’adresse ou du nom du lieu |

Les coordonnées sont en degrés décimaux (WGS 84) ; toutes les valeurs sont encodées pour les URL. Sur Android, une intention `geo:` (`geo:LAT,LON`, `geo:0,0?q=LAT,LON(Label)`, `geo:0,0?q=address`) fonctionne aussi.

## L’écran d’import

Intitulé **Importer**, il montre :

- un aperçu de la trace sur la carte, avec les points de repère du fichier sous forme de petits repères nommés : les points d’intérêt fournis avec un itinéraire, une zone où mettre pied à terre, une fontaine, un passage difficile, dans la couleur de leur type,
- un champ **Nom**, prérempli d’après le nom du fichier,
- le format et la taille, « GPX · 4 812 points »,
- la période, « 16 sept. 2026, 09:12 – 16 sept. 2026, 13:40 », ou « Le fichier ne contient aucun horodatage. »,
- la distance, la montée, la descente et la durée,
- **ENREGISTRER COMME**, un sélecteur entre **Itinéraire** et **Sortie**.

La carte reste en haut pendant que les pages en dessous défilent, avec des points sous la carte indiquant quelle page est affichée. Un balayage vers la gauche donne le profil altimétrique. Quand le fichier comporte des virages ou des points d’intérêt, un balayage de plus donne la **FEUILLE DE ROUTE**, chaque virage et chaque point d’intérêt avec sa distance depuis le départ, repliée à huit lignes avec **Tout afficher**. Touchez une ligne et la carte glisse jusque-là au zoom que vous avez, avec le repère épinglé et son nom ; touchez un repère sur la carte et la feuille de route remonte avec sa ligne sélectionnée et amenée dans la vue. Une ligne sélectionnée s’ouvre avec ce qu’il y a à savoir : la note d’un danger, ou la manœuvre simple sous les mots de l’auteur.

Un itinéraire GPX avec feuille de route, l’export d’itinéraire de Ride with GPS ou un parcours Garmin, apporte ses virages : chaque indication devient une instruction de virage avec les mots de l’auteur, affichée dans la bannière de virage, sur la page de la feuille de route et énoncée par la voix. Une trace GPX ne porte pas de feuille de route ; la bannière de virage propre à Velorki fonctionne quand même dessus, d’après la forme de l’itinéraire.

Velorki devine **Itinéraire** ou **Sortie** selon que les points portent des heures : un enregistrement en a, un itinéraire planifié non. Un parcours FIT est reconnu comme un parcours et deviné comme un itinéraire, quelle que soit sa base de temps synthétique, et il en va de même d’un parcours TCX ; ses points de parcours deviennent la feuille de route de l’itinéraire (virages) et ses points d’intérêt (eau, nourriture, dangers, lieux nommés). Rien n’est écrit tant que vous ne touchez pas **Enregistrer**.

Un itinéraire s’ouvre avec le vélo que nomme son fichier : un `<type>` GPX comme `road_biking` ou `mountain_biking`, ou le sous-sport d’un parcours ou d’une activité FIT (route, VTT, gravel), devient **Route**, **VTT**, **Gravel** ou **Rando**. Un fichier qui n’en nomme aucun s’ouvre avec le vélo que vous avez utilisé en dernier. Un itinéraire exporté réécrit son vélo de la même façon ; un fichier TCX n’a pas de mot pour cela.

Une activité FIT d’un compteur apporte plus que sa trace : les tours découpés par l’appareil remplacent les tronçons fixes sur la page de la sortie, les totaux écrits par l’appareil (distance, temps en mouvement, montée, calories) sont affichés sous **Tel qu’enregistré par l’appareil** là où ils diffèrent de ce que Velorki calcule à partir des positions, et une température, quand l’appareil en a enregistré une, a son propre graphique. Une sortie GPX apporte de la même façon fréquence cardiaque, cadence, puissance et température depuis ses extensions. Un fichier GPX avec plusieurs traces, un voyage de plusieurs jours par exemple, les liste avec une case à cocher chacune, et enregistre une sortie (ou un itinéraire) par trace cochée.

Ensuite vous obtenez « Tour des Alpes ajouté à la bibliothèque » ou « Tour des Alpes ajouté à vos sorties », et vous arrivez sur la fiche du nouvel élément dans l’onglet Bibliothèque.

Si le fichier ne s’ouvre pas, Velorki dit de quel problème il s’agit : « Ce n’est pas un fichier GPX, FIT ou TCX. », « Impossible de lire ce fichier. », « Ce fichier ne contient aucun point de trace. » ou « Impossible d’ouvrir ce fichier. »

## Faire sortir un fichier

**Depuis un itinéraire** (Bibliothèque → Itinéraires → ouvrez-le → **Exporter**) :

| Format | À utiliser pour |
|---|---|
| **Itinéraire GPX** | un itinéraire planifié pour un autre planificateur, une appli de téléphone ou un compteur de vélo. Un itinéraire avec feuille de route sort comme l’écrit Ride with GPS : une `<rte>` des virages, chacun avec sa direction et ses mots, et une `<trk>` de toute la ligne à côté ; un itinéraire sans feuille de route garde tous ses points sur la `<rte>`. |
| **Parcours FIT** | un compteur Garmin, Wahoo ou similaire qui attend un parcours ; la feuille de route et les points d’intérêt suivent sous forme de points de parcours, pour que l’appareil affiche le prochain virage |
| **Parcours TCX** | un ancien appareil Garmin ou un site d’entraînement qui lit le Training Center XML ; la feuille de route et les points d’intérêt suivent sous forme de points de parcours, avec des noms coupés aux dix caractères que permet le format |

**Depuis une sortie** (Bibliothèque → Sorties → ouvrez-la, ou la fiche de la sortie après l’avoir terminée) :

| Format | À utiliser pour |
|---|---|
| **Exporter la trace GPX** | la trace enregistrée avec ses horodatages ; fréquence cardiaque, cadence, puissance et température suivent. |
| **Exporter l’activité FIT** | un fichier d’activité pour une plateforme d’entraînement |
| **Exporter l’activité TCX** | la même chose en Training Center XML, un tour par tour de la sortie, fréquence cardiaque, cadence et puissance sur chaque point |

Dans les deux cas, Velorki écrit le fichier et le remet à la feuille de partage du système : vous pouvez le ranger dans vos fichiers, l’envoyer par e-mail ou le passer à une autre appli.

## Komoot, Garmin et les autres

Velorki n’a pas d’intégration Komoot ni Garmin, et n’en a pas besoin : tous parlent GPX et FIT, et la plupart lisent encore le TCX.

- **De Komoot vers Velorki** : exportez la sortie en GPX dans Komoot, puis partagez-la vers Velorki, ou enregistrez-la et ouvrez-la avec le bouton **Importer un fichier**.
- **De Velorki vers Komoot** : exportez l’itinéraire en **Itinéraire GPX** et partagez-le vers l’import de Komoot.
- **Vers un compteur Garmin** : exportez l’itinéraire en **Parcours FIT**, ou en **Itinéraire GPX** si votre appareil le préfère, et mettez-le sur l’appareil comme d’habitude, via Garmin Connect ou en copiant le fichier.
- **Depuis un Garmin** : l’activité `.fit` de l’appareil s’importe comme une sortie.

L’envoi d’un itinéraire **vers Strava** passe aussi par un fichier, car l’API de Strava ne peut pas créer d’itinéraires. Voir [Strava et Ride with GPS](./strava-and-ridewithgps).

## Voir aussi

- [Bibliothèque](./library)
- [Strava et Ride with GPS](./strava-and-ridewithgps)
- [Partage](./sharing)
- [Enregistrer une sortie](./recording-a-ride)
