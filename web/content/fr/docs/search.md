---
title: Recherche
description: "Trouvez des lieux, des rues, des numéros de rue et des choses comme l’eau potable ou les toilettes, sur le téléphone dans les zones téléchargées et en ligne quand vous le choisissez."
order: 4
---

Le champ de recherche en haut de l’onglet Planifier trouve des villes, des rues, des numéros de rue et des points d’intérêt comme les cafés, l’eau potable et les magasins de vélos. Sur une zone téléchargée, il répond depuis le téléphone, instantanément et sans réseau ; sur une zone non téléchargée, vous choisissez entre un géocodeur en ligne et les zones que vous avez téléchargées.

## Comment chercher

1. Ouvrez l’onglet **Planifier** et touchez le champ en haut, qui affiche **Rechercher un lieu**.
2. Saisissez au moins trois caractères. Les résultats apparaissent dans une fiche sous le champ à mesure que vous tapez.
3. Touchez un résultat. La carte se déplace vers le lieu, l’épingle et ouvre sa fiche.

Des coordonnées saisies ou collées dans le champ, `40.71747, -73.94840` ou `40,71747° N, 73,94840° W` comme les copient les apps de cartes, sont le lieu lui-même : un seul résultat à cet endroit, sans rien chercher ni rien envoyer. Un lieu partagé depuis une autre app s’ouvre de la même façon, voir [importer et exporter](./import-and-export#un-lieu-depuis-une-autre-appli).

## La fiche du lieu

Un résultat de recherche, une [halte sur la carte](./stops-on-the-map) ou un lieu partagé depuis une autre app ouvre une fiche avec le nom du lieu, sa nature, sa ville, sa distance par rapport à vous et, avec un itinéraire, sa distance par rapport à l’itinéraire. Rien ne change tant que vous ne choisissez pas une action, qui dépend du plan :

- **Rien de planifié** : **Itinéraire jusqu’ici** part de votre position jusqu’au lieu ; **Partir d’ici** en fait le premier point de l’itinéraire.
- **Un départ seulement** : **Arrivée** en fait la fin de l’itinéraire.
- **Un itinéraire** : **Ajouter comme étape** l’insère dans l’itinéraire à l’endroit où il se trouve sur le trajet ; **Arrivée** l’ajoute à la fin.

Dans l’onglet Rouler, la fiche ne fait qu’informer, sans actions.

En dessous :

- **Détails** récupère le lieu auprès d’OpenStreetMap, uniquement lorsque vous le touchez : horaires d’ouverture avec l’indication s’il est ouvert maintenant, site web, numéro de téléphone, cuisine, accès en fauteuil roulant, places en terrasse et article Wikipédia, pour autant qu’ils soient renseignés. Les détails sont gardés une semaine sur le téléphone : le lieu les affiche aussitôt la fois suivante. Le bouton est absent pour les rues et les lieux sans identifiant OpenStreetMap.
- **Ouvrir dans…** montre le lieu dans Apple Plans, dans Google Maps s’il est installé (iPhone), dans une app de cartes de votre choix (Android) ou sur OpenStreetMap dans le navigateur, ou le remet à **Partager…**.

Fermer la fiche (le **X**, un balayage vers le bas ou un toucher sur la carte) ne change rien et efface la recherche.

## Hors ligne ou en ligne

Velorki décide d’après le **centre de la carte**, et non d’après votre connexion. Chaque tuile de routage téléchargée apporte avec elle un index de recherche de sa zone.

- **Centre de la carte sur une zone téléchargée** : la requête est traitée sur le téléphone. La dernière ligne de la fiche de résultats, **Rechercher « … » en ligne**, relance le même texte en ligne.
- **Centre de la carte sur une zone non téléchargée, alors que d’autres le sont** : rien n’est cherché et rien ne quitte le téléphone avant que vous ne choisissiez. La liste affiche un avis, **Cette zone n’est pas téléchargée**, une ligne qui en dit la raison et un bouton **Télécharger** qui ouvre l’écran hors ligne pour la zone visible, avec deux choix : **Rechercher « … » en ligne** et **Chercher dans les zones téléchargées**, qui parcourt toutes les zones téléchargées, la plus proche de la carte d’abord. Votre choix vaut pour les frappes suivantes, jusqu’à ce que vous effaciez la recherche. Les résultats en ligne viennent sous l’intitulé **Résultats en ligne**, et la dernière ligne, **Afficher les résultats hors ligne**, bascule vers les zones téléchargées ; les résultats du téléphone se terminent par **Rechercher « … » en ligne**.
- **Rien de téléchargé du tout** : la recherche part tout de suite en ligne, avec l’avis en haut.
- **Aucune recherche en ligne configurée** : les zones téléchargées répondent.
- **Pas de centre de carte** : en ligne.

L’avis reste visible pendant que vous faites défiler la liste et, si la recherche a échoué, il se place au-dessus du message d’erreur, ce qui est là où il compte le plus.

## Ce qu’elle trouve

- **Lieux** : villes, bourgs, villages, hameaux, faubourgs, quartiers, lieux-dits et îles.
- **Rues**, avec numéros.
- **Points d’intérêt**, chacun avec sa propre icône et son libellé : Café, Restaurant, Restauration rapide, Glacier, Station-service, Pompe à vélo, Eau potable, Toilettes, Station de réparation vélo, Magasin de vélos, Location de vélos, Parking vélos, Recharge VAE, Abri, Camping, Hôtel, Auberge de jeunesse, Refuge, Supermarché, Boulangerie, Pharmacie, Aire de pique-nique, Gare, Terminal de ferry, Aéroport, Point de vue, Sommet, Col, Parc, Plage, Plan d’eau, Réserve naturelle, Curiosité, Musée, Site historique, Lieu de culte, Hôpital, Université, Équipement sportif, Centre commercial, Tour, Phare, Bâtiment.
- **Lieux connus dans votre langue** : « Parigi » trouve Paris, et un monument célèbre passe avant ses homonymes.

Hors ligne, les lignes affichent sous le nom le type, la distance et la ville, pour autant que chacun soit connu : « Eau potable · 350 m », « Rue · Manhattan ». Un robinet, des toilettes, un abri ou un support à vélos sans nom propre figure sous son type.

## Chercher par type

Saisissez le nom d’un type plutôt que celui d’un lieu. « eau potable », « boulangerie », « toilettes » et les autres fonctionnent tous, dans la langue dans laquelle l’app s’exécute.

La liste s’ouvre alors sur les cinq éléments de ce type les plus proches du centre de la carte, chacun avec sa distance, suivis en dessous des correspondances de nom ordinaires. Velorki cherche dans un carré qui s’agrandit de 5 à 50 km autour du centre de la carte jusqu’à en avoir assez. C’est le moyen rapide de répondre à « où est le robinet le plus proche » en pleine sortie.

Une recherche par type ignore les interrupteurs de groupes décrits plus bas.

## Numéros de rue

Saisissez le numéro là où votre pays le met : « Hauptstrasse 12 », « 400 W 42nd », « Via Roma 12/A », « Budapest, Fő utca 12 ». Velorki trouve la rue et répond à la position propre du numéro le long de celle-ci ; la ligne est l’adresse telle que vous l’avez saisie, « 400 West 42nd Street ». Une ville avant la rue, avec une virgule, ou après elle indique de quel lieu vous voulez la rue. Un code postal est ignoré, et un numéro qui fait partie du nom d’une rue, « Route 66 », reste dans le nom.

Lorsque le numéro tombe entre deux numéros que l’index connaît, Velorki estime sa position et la ligne indique **≈ 400** pour que vous voyiez qu’il s’agit d’une estimation.

## Fautes de frappe, formes abrégées et autres alphabets

La recherche hors ligne pardonne une lettre ou deux fausses, un mot écrit en un seul ou en plusieurs, et les formes abrégées comme « St » ou « Str. ». Les noms en cyrillique ou en grec peuvent être saisis en lettres latines, « aleksandar nevski » ou « Nafplio ». Quand rien ne répond bien, Velorki essaie à la place les mots les plus probables de l’index et la fiche affiche **Résultats pour « … »** au-dessus de la liste, avec ce qui a réellement été cherché.

## Ordonner les groupes

Les résultats hors ligne sont regroupés, et vous décidez quels groupes apparaissent et dans quel ordre.

1. Ouvrez **Réglages**.
2. Touchez **Recherche**, au sous-titre « Ce que la recherche hors ligne affiche, et dans quel ordre. Faites glisser pour changer la priorité. »
3. Faites glisser une ligne par sa poignée pour la monter ou la descendre. Utilisez l’interrupteur à droite pour désactiver un groupe.

Les huit groupes, dans leur ordre par défaut : **Lieux**, **Rues et adresses**, **Points d’intérêt**, **Haltes à vélo**, **Hébergement**, **Nature**, **Transports**, **Services**.

Il n’y a pas de bouton d’enregistrement ; les changements prennent effet à la frappe suivante. Un groupe désactivé disparaît des correspondances de nom, et l’ordre départage les résultats qui correspondent aussi bien au texte.

## Quand la recherche ne fonctionne pas

- **« Aucun résultat. »** Le texte n’a rien donné, hors ligne comme en ligne. Essayez la dernière ligne pour changer de source, ou moins de mots.
- **« La recherche a échoué. »** suivi d’une raison signifie que le géocodeur en ligne n’a pas pu être joint. La recherche hors ligne continue de fonctionner là où vous avez téléchargé une zone.
- **« Aucun serveur de recherche configuré, définissez-en un dans Réglages → Avancé. »** signifie que cette version n’a ni adresse de géocodeur ni index téléchargé. Le champ est désactivé tant qu’il n’en existe pas.

## Voir aussi

- [Haltes sur la carte](./stops-on-the-map)
- [Cartes et routage hors ligne](./offline-maps-and-routing)
- [Planifier un itinéraire](./planning-a-route)
- [Réglages et apparence](./settings-and-appearance)
- [Confidentialité sur le téléphone](./privacy-on-the-phone)
