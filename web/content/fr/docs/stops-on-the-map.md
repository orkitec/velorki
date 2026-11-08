---
title: Haltes sur la carte
description: Affichez l’eau potable, les cafés, les toilettes, la réparation de vélos et d’autres haltes sur la carte, dans la zone que vous regardez ou le long de l’itinéraire à venir.
order: 5
---

Velorki peut dessiner sur la carte les lieux où l’on s’arrête en sortie : eau potable, cafés, boulangeries, toilettes, stations de réparation vélo, gares et arrêts de bus, pharmacies et plus. Ils viennent de l’index des lieux des données de routage sur le téléphone ; il faut donc avoir téléchargé la zone (voir [cartes et routage hors ligne](./offline-maps-and-routing)), cela marche sans réseau et n’envoie rien nulle part.

## Le bouton Calques

**Calques** se trouve dans la colonne de boutons à droite de la carte, dans l’onglet Planifier comme dans l’onglet Rouler. Sa feuille contient :

- **Haltes**, un interrupteur, activé tant que vous ne le désactivez pas. Dessous, les types à afficher, par groupe : **Haltes à vélo**, **Hébergement**, **Nature**, **Transports**, **Services** et **Points d’intérêt**. Touchez un type pour l’afficher ou le masquer. La première fois, l’eau potable, les cafés, les boulangeries, les toilettes et les stations de réparation vélo sont choisis ; les autres types sont désactivés. **Haltes à vélo** comprend le distributeur de chambres à air, **Nature** l’aire de pique-nique, le point de vue et la plage, **Transports** les gares (haltes ferroviaires comprises), les arrêts de bus et de tram, les terminaux de ferry et les aéroports, et **Services** la pharmacie et l’hôpital. Interrupteur désactivé, les types se replient ; votre choix est conservé pour la fois suivante.
- **Le long du parcours** et **Dans cette zone**, sous **Haltes**, dès qu’il y a un itinéraire : un itinéraire planifié dans l’onglet Planifier, ou celui que vous suivez dans l’onglet Rouler. Chaque choix dit ce qu’il montre ; il vaut pour les deux onglets.
- **Prochaines haltes en roulant**, sous **Haltes** dans l’onglet Rouler seulement, désactivé tant que vous ne l’activez pas : la ligne des prochaines haltes au-dessus de la carte, voir plus bas.

## Dans la zone que vous regardez

Avec **Haltes** activé, les haltes de la partie visible de la carte apparaissent à partir du zoom 11. De loin, les haltes proches sont regroupées en bulles avec un nombre ; à partir du zoom 15, elles se séparent en haltes isolées avec leurs icônes. Touchez une bulle pour zoomer là où elle se sépare. Toutes les haltes des types choisis dans la vue sont chargées, aucune n’est laissée de côté. Plus loin que le zoom 11, aucune n’est dessinée.

Quand la zone n’est pas téléchargée, une pastille indique **Pas de haltes ici – zone non téléchargée**, avec **Télécharger**. Un toucher demande ce qui sera récupéré, puis télécharge la zone sur place ; la pastille affiche la progression, et son **X** devient **Annuler le téléchargement** (avec demande de confirmation avant l’arrêt). Hors téléchargement, le **X** masque la pastille pour cette zone jusqu’au redémarrage de l’app.

## Le long de l’itinéraire à venir

Dans l’onglet Planifier, avec un itinéraire planifié et **Le long du parcours** choisi, les haltes sont celles situées à moins de 300 m de tout l’itinéraire, du départ à l’arrivée, à tout zoom.

Dans l’onglet Rouler, avec un itinéraire choisi sous **Itinéraire suivi**, ce sont celles à moins de 300 m de la partie de l’itinéraire encore devant vous, jusqu’à 50 km, à tout zoom. Quand rien des 50 prochains km de l’itinéraire n’est téléchargé, la même pastille le dit.

Choisissez **Dans cette zone** pour voir plutôt les haltes à l’écran.

## La ligne des prochaines haltes

Avec **Prochaines haltes en roulant** activé, une ligne au-dessus de la carte dans l’onglet Rouler liste la prochaine halte de chaque type, la plus proche d’abord. Touchez une entrée pour voir la halte sur la carte. Tant que la carte vous suit pendant une sortie, elle reste avec vous et la halte est seulement mise en évidence.

- Le long d’un itinéraire suivi, chaque entrée a sa distance le long de l’itinéraire, « Eau potable · 2,4 km ».
- Sans itinéraire, ou avec **Dans cette zone** choisi, chacune a sa distance à vol d’oiseau depuis l’endroit où vous êtes, « Eau potable · à 2,4 km ». Il faut une sortie en cours, d’où vient votre position, et la ligne liste les haltes chargées autour de la carte, donc à partir du zoom 11.

Quand la zone n’est pas téléchargée, la pastille qui le dit se tient à la place de la ligne.

## Toucher une halte

Une halte ouvre sa fiche du lieu, la même que celle d’un résultat de recherche : nom, type, ville, distance par rapport à vous et, avec un itinéraire, distance par rapport à celui-ci. Dans l’onglet Planifier, elle propose quoi faire du lieu, **Itinéraire jusqu’ici**, **Partir d’ici**, **Ajouter comme étape** ou **Arrivée** ; dans l’onglet Rouler, elle ne fait qu’informer, sauf pendant une sortie qui suit un itinéraire : là, **Ajouter comme étape** insère la halte dans la partie de l’itinéraire devant vous, après une question et avec un recalcul, et le guidage continue sur l’ancien itinéraire jusqu’à ce que le nouveau soit prêt. **Détails** et **Ouvrir dans…** sont dans les deux. Voir [la fiche du lieu](./search#la-fiche-du-lieu).

## Voir aussi

- [Calques de la carte](./map-layers)
- [Recherche](./search)
- [Planifier un itinéraire](./planning-a-route)
- [Navigation guidée](./navigation)
- [Cartes et routage hors ligne](./offline-maps-and-routing)
