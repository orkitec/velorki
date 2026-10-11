---
title: Calques de la carte
description: La carte vélo hors ligne et ses parties, la carte vélo en ligne, le radar de pluie, les nuages et les haltes, tout dans la feuille Calques.
order: 6
---

**Calques** se trouve dans la colonne de boutons à droite de la carte, dans l’onglet Planifier comme dans l’onglet Rouler. Sa feuille contient la carte vélo, la carte vélo en ligne, le radar de pluie, les nuages et les haltes. Le bouton est mis en évidence tant que l’une d’elles est activée.

<!-- screenshot: layers -->

## Carte vélo

**Carte vélo** : « Pistes, bandes et itinéraires cyclables de vos zones téléchargées · fonctionne hors ligne · visible en zoomant ». Dessinée par l’app à partir des données de routage du téléphone, donc sans connexion, et seulement là où une zone est téléchargée.

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
| **Montées** | Tronçons raides des voies que le vélo peut emprunter, en bande : jaune à partir de 6 %, orange à partir de 10 %, rouge à partir de 15 % ; des chevrons indiquent la montée à partir du zoom 15. Les altitudes viennent du modèle de terrain des données de routage. Une montée ne compte que si elle dure au moins 150 m et 10 m de dénivelé, donc les courtes rampes sont ignorées ; dans les centres-villes aux immeubles hauts, elle peut quand même montrer une montée qui n’existe pas ou en manquer une. Ponts et tunnels sont exclus. Dans les centres denses des plus grandes villes, où les altitudes sont celles des bâtiments, aucune montée n’est dessinée. |

Au départ, toutes les parties sont actives sauf **Non revêtu & cahoteux**, **Rues à sens unique**, **Rues calmes**, **VTT** et **Montées**. Une partie ajoutée dans une version ultérieure démarre avec sa valeur par défaut ; les choix faits avant sont conservés.

Dans l’onglet Planifier, avec la carte vélo activée sur une zone non téléchargée, une puce indique **Pas de carte vélo ici – zone non téléchargée**, avec **Télécharger** ; un toucher ouvre le téléchargement de la zone visible. Si la puce des haltes s’applique aussi, elle passe en premier.

## Carte vélo en ligne

**Carte vélo en ligne** : « La carte de CyclOSM avec magasins et parkings vélo · nécessite une connexion ». La surcouche de CyclOSM, récupérée en ligne. Les deux cartes vélo alternent : en activer une désactive l’autre.

## Radar de pluie et nuages

**Radar de pluie** : "Radar en Allemagne et aux États-Unis, ailleurs en Europe et en Afrique une estimation par satellite · prévision jusqu'à 24 heures". **Nuages** : "Europe, Afrique et Amériques · mis à jour toutes les heures en Europe". Les deux sont gratuits, désactivés tant que vous ne les activez pas, et nécessitent une connexion.

La pluie vient de trois sortes de sources. Maintenant : le radar du service météorologique allemand (Deutscher Wetterdienst) au-dessus de l’Allemagne et de ses environs et du service météorologique américain (National Weather Service) au-dessus des États-Unis, et autour, sur le reste de l’Europe, l’Afrique et l’Atlantique, la pluie estimée à partir du satellite Meteosat par H SAF d’EUMETSAT, toutes les dix minutes. Une estimation par satellite est plus grossière que le radar et manque une partie de la pluie faible ; elle n’est jamais dessinée sur les zones des radars, si bien que les deux ne se contredisent jamais sur la carte. Les deux heures à venir : en Allemagne la prévision radar du Deutscher Wetterdienst, la pluie du radar déplacée par quarts d’heure ; partout ailleurs, et partout à partir de trois heures, la prévision de son modèle météorologique ICON, heure par heure sur l’Europe et par pas de six heures ailleurs. L’app cherche des images plus récentes toutes les cinq minutes.

Avec le radar de pluie activé, sa commande de temps se trouve en haut de la feuille de Planifier et sur la carte de Rouler, sous les chiffres pendant une sortie : un curseur de **Maintenant** par quarts d’heure jusqu’à deux heures en avant, puis par heures jusqu’à 24 heures. Son libellé indique le pas, l’heure de l’image au centre de la carte et, en avant, ce que c’est, par exemple **Maintenant · 20:25**, **+45 min · 21:30 · Prévision radar** ou **+3 h · 23:00 · Prévision**. Le pas est le même dans tous les onglets et revient à **Maintenant** quand l’app revient après plus d’une demi-heure d’absence. La Bibliothèque indique l’heure dans un petit libellé sur la carte.

Les nuages sont des images satellite dessinées en blanc sur la carte : Meteosat d’EUMETSAT au-dessus de l’Europe, de l’Afrique et des environs, une nouvelle image à chaque heure pile, et les satellites GOES via la NASA au-dessus des Amériques. Ils montrent toujours leur image la plus récente, quel que soit le curseur de la pluie, et un petit libellé sur la carte indique son heure. Les nuages les plus épais et les plus froids sont les plus clairs ; le brouillard et les nuages bas apparaissent à peine ou pas du tout.

Si un service ne répond pas, la carte affiche **Radar de pluie indisponible pour le moment**, **Pluie par satellite indisponible pour le moment**, **Prévision de pluie indisponible pour le moment** ou **Nuages indisponibles pour le moment**, pour qu’une carte vide ne passe pas pour une journée sèche et dégagée. L’app charge les images directement auprès du Deutscher Wetterdienst, de la NOAA, de la NASA et d’EUMETSAT, pas via Velorki : ces services voient donc la zone de carte demandée. Leurs crédits figurent dans la ligne au bas de la carte tant qu’un calque est dessiné.

## Haltes

**Haltes** est un interrupteur dans la même feuille, désactivé tant que vous ne l’activez pas. Il dessine l’eau potable, les cafés, les toilettes, les stations de réparation vélo et plus, d’après l’index des lieux sur le téléphone. Les types, la zone que vous regardez et l’itinéraire à venir sont décrits dans [haltes sur la carte](./stops-on-the-map).
