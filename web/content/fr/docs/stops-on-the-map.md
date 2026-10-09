---
title: Haltes sur la carte
description: Affichez l’eau potable, les cafés, les toilettes, la réparation de vélos et d’autres haltes sur la carte, dans la zone que vous regardez ou le long de l’itinéraire à venir, et activez la carte vélo.
order: 5
---

Velorki peut dessiner sur la carte les lieux où l’on s’arrête en sortie : eau potable, cafés, boulangeries, toilettes, stations de réparation vélo et plus. Ils viennent de l’index des lieux des données de routage sur le téléphone ; il faut donc avoir téléchargé la zone (voir [cartes et routage hors ligne](./offline-maps-and-routing)), cela marche sans réseau et n’envoie rien nulle part.

## Le bouton Calques

**Calques** se trouve dans la colonne de boutons à droite de la carte, dans l’onglet Planifier comme dans l’onglet Rouler. Sa feuille contient :

- **Carte vélo** : « Pistes, bandes et itinéraires cyclables de vos zones téléchargées · fonctionne hors ligne · visible en zoomant ». Dessinée par l’app à partir des données de routage du téléphone, donc sans connexion, et seulement là où une zone est téléchargée. Ses parties se déplient sous l’interrupteur, voir [la carte vélo](#la-carte-vélo).
- **Carte vélo en ligne** : « La carte de CyclOSM avec magasins et parkings vélo · nécessite une connexion ». La surcouche de CyclOSM, récupérée en ligne. Les deux cartes vélo alternent : en activer une désactive l’autre.
- **Haltes**, un interrupteur, désactivé tant que vous ne l’activez pas. Dessous, les types à afficher, par groupe : **Haltes à vélo**, **Hébergement** et **Points d’intérêt**. Touchez un type pour l’afficher ou le masquer. La première fois, l’eau potable, les cafés, les boulangeries, les toilettes et les stations de réparation vélo sont choisis. Interrupteur désactivé, les types se replient ; votre choix est conservé pour la fois suivante.

Le bouton est mis en évidence tant que la carte vélo, la carte vélo en ligne ou les haltes sont activées.

## La carte vélo

La carte vélo apparaît en fondu entre le zoom 12 et 13, et disparaît de même en dézoomant. Elle dessine ce que les données de routage savent de la pratique du vélo. Activée, elle déplie sous l’interrupteur une puce par partie, chacune avec un échantillon de son trait en guise de légende. Touchez une puce pour afficher ou masquer la partie ; le choix est conservé. Les flèches et points affichés à partir du zoom 15 apparaissent en fondu pendant le palier de zoom précédent.

| Partie | Dessinée comme |
| --- | --- |
| **Pistes & bandes** | Pistes cyclables en bleu plein, rues cyclables avec une bande pâle ; pistes en trait plein et bandes en tirets, au bord de la route, plus loin sur les grandes routes. Voies partagées (couloirs de bus ouverts aux vélos, bandes marquées seulement de symboles vélo, accotements, trottoirs ouverts aux vélos) en tirets espacés bleu clair le long de la route. Les pistes cyclables à double sens et les pistes et bandes à double sens sont tracées plus larges que celles à sens unique |
| **Flèches de sens unique** | Des chevrons du bleu propre à la voie indiquent le sens à suivre : sur les pistes cyclables et chemins parcourus dans un seul sens à partir du zoom 15, et sur les pistes et bandes à sens unique le long de la route à partir d’environ le zoom 15,5 |
| **Voies partagées** | Chemins partagés avec les piétons en tirets turquoise, trottoirs ouverts aux vélos en pointillés gris-bleu |
| **Rues à sens unique** | Un chevron gris au milieu des rues à sens unique aussi pour les vélos, dans le sens de la circulation, à partir du zoom 15. Les rues à sens unique que les vélos peuvent emprunter dans les deux sens montrent à la place le signe bicolore de **Double sens cyclable**. Là où une bande ou une piste le long de la rue montre son propre sens, la rue n’a pas de chevron à elle |
| **Double sens cyclable** | Sur les rues à sens unique que les vélos peuvent emprunter dans les deux sens, à partir du zoom 15, un chevron gris montre le sens de la circulation et un bleu celui des vélos à contresens |
| **Itinéraires nationaux**, **Itinéraires régionaux**, **Itinéraires locaux** | Itinéraires cyclables balisés en halo violet, plus marqué quand l’itinéraire porte loin |
| **Non revêtu & cahoteux** | Gravier en tirets ocre, terrain accidenté pour VTT en tirets bruns, pavage cahoteux en petits traits rouges |
| **Obstacles & escaliers** | Barrières, bornes et échaliers en points à partir du zoom 15 ; en rouge là où il faut porter le vélo. Escaliers en barreaux bruns à partir du zoom 15, avec une bande bleue à côté là où une rampe pour vélos existe |
| **Rues calmes** | Rues teintées selon leur calme : cyan pour 30 km/h (20 mph) ou moins, vert pour 20 km/h ou zones de rencontre, vert pâle pour l’allure du pas, vert vif sans trafic motorisé ; routes interdites aux vélos en gris |
| **VTT** | Petits traits de difficulté sur les sentiers à partir du zoom 14 : bleu pour facile (S0–S1), rouge pour S2, noir pour S3 et plus difficile (blanc sur la carte de nuit) ; itinéraires VTT en halo orange |

Au départ, toutes les parties sont actives sauf **Non revêtu & cahoteux**, **Rues à sens unique**, **Rues calmes** et **VTT**. Une partie ajoutée dans une version ultérieure démarre avec sa valeur par défaut ; les choix faits avant sont conservés.

Dans l’onglet Planifier, avec la carte vélo activée sur une zone non téléchargée, une puce indique **Pas de carte vélo ici – zone non téléchargée**, avec **Télécharger** ; un toucher ouvre le téléchargement de la zone visible. Si la puce des haltes s’applique aussi, elle passe en premier.

## Dans la zone que vous regardez

Avec **Haltes** activé, les haltes de la partie visible de la carte apparaissent à partir du zoom 11. De loin, les haltes proches sont regroupées en bulles avec un nombre ; à partir du zoom 15, elles se séparent en haltes isolées avec leurs icônes. Touchez une bulle pour zoomer là où elle se sépare.

Plus loin que cela, une pastille indique **Zoomez pour voir les haltes** ; touchez-la et la carte zoome là où elles s’affichent.

Quand la zone n’est pas téléchargée, la pastille indique à la place **Pas de haltes ici – zone non téléchargée**, avec **Télécharger** ; un toucher ouvre le téléchargement de la zone visible.

## Le long de l’itinéraire à venir

Avec un itinéraire choisi sous **Itinéraire suivi** dans l’onglet Rouler, les haltes sont celles situées à moins de 300 m de la partie de l’itinéraire encore devant vous, jusqu’à 50 km, à tout zoom. Une ligne au-dessus de la carte liste la prochaine de chaque type avec sa distance le long de l’itinéraire, « Eau potable · 2,4 km » ; touchez une entrée pour voir la halte sur la carte. Tant que la carte vous suit pendant une sortie, elle reste avec vous et la halte est seulement mise en évidence.

Quand rien des 50 prochains km de l’itinéraire n’est téléchargé, la même pastille prend la place de cette ligne.

**Le long du parcours** et **Dans cette zone** dans la feuille Calques basculent entre les deux.

## Toucher une halte

Une halte ouvre sa fiche du lieu, la même que celle d’un résultat de recherche : nom, type, ville, distance par rapport à vous et, avec un itinéraire, distance par rapport à celui-ci. Dans l’onglet Planifier, elle propose quoi faire du lieu, **Itinéraire jusqu’ici**, **Partir d’ici**, **Ajouter comme étape** ou **Arrivée** ; dans l’onglet Rouler, elle ne fait qu’informer. **Détails** et **Ouvrir dans…** sont dans les deux. Voir [la fiche du lieu](./search#la-fiche-du-lieu).

## Voir aussi

- [Recherche](./search)
- [Planifier un itinéraire](./planning-a-route)
- [Navigation guidée](./navigation)
- [Cartes et routage hors ligne](./offline-maps-and-routing)
