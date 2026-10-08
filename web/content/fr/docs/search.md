---
title: Recherche
description: "Trouvez des lieux, des rues, des numéros de rue et des choses comme l’eau potable ou les toilettes, sur le téléphone là où vous avez téléchargé une zone et en ligne partout ailleurs."
order: 4
---

Le champ de recherche en haut de l’onglet Planifier trouve des villes, des rues, des numéros de rue et des points d’intérêt comme les cafés, l’eau potable et les magasins de vélos. Là où vous avez téléchargé une zone, il répond depuis le téléphone, instantanément et sans réseau ; partout ailleurs, il interroge un géocodeur en ligne.

## Comment chercher

1. Ouvrez l’onglet **Planifier** et touchez le champ en haut, qui affiche **Rechercher un lieu**.
2. Saisissez au moins trois caractères. Les résultats apparaissent dans une fiche sous le champ à mesure que vous tapez.
3. Touchez un résultat.

Une fiche s’affiche avec le nom du lieu, sa nature, sa distance par rapport à vous et, avec un itinéraire, sa distance par rapport à l’itinéraire. La carte se déplace vers le lieu et l’épingle. Ce que la fiche propose dépend du plan :

- **Rien de planifié** : **Itinéraire jusqu’ici** part de votre position jusqu’au lieu ; **Partir d’ici** en fait le premier point de l’itinéraire.
- **Un départ seulement** : **Arrivée** en fait la fin de l’itinéraire.
- **Un itinéraire** : **Ajouter comme étape** l’insère dans l’itinéraire à l’endroit où il se trouve sur le trajet ; **Arrivée** l’ajoute à la fin.

En dessous, **Détails** récupère auprès d’OpenStreetMap les horaires d’ouverture du lieu (avec l’indication s’il est ouvert maintenant), son site web, son numéro de téléphone et le reste, uniquement lorsque vous le touchez ; il est absent pour les rues et les lieux sans identifiant OpenStreetMap. **Ouvrir dans…** montre le lieu dans une autre app de cartes ou sur openstreetmap.org, ou le partage.

Fermer la fiche (le **X**, un balayage vers le bas ou un toucher sur la carte) ne change rien et efface la recherche. Une halte touchée sur la carte ouvre la même fiche.

## Hors ligne ou en ligne

Velorki décide d’après le **centre de la carte**, et non d’après votre connexion. Chaque tuile de routage téléchargée apporte avec elle un index de recherche de sa zone, donc :

- si la tuile située sous le centre de la carte a son index sur le téléphone, la requête est traitée sur le téléphone ;
- sinon, la requête part en ligne vers Photon.

En bas de la fiche de résultats se trouve exactement une ligne, et celle qui s’affiche vous indique d’où viennent les résultats :

| Ligne | Signification | En la touchant |
|---|---|---|
| **Rechercher « … » en ligne** | vous voyez des résultats hors ligne | relance le même texte en ligne |
| **Afficher les résultats hors ligne** | vous voyez des résultats en ligne | relance le même texte sur le téléphone |
| **Téléchargez cette zone pour chercher hors ligne** | cette zone n’a pas d’index sur le téléphone | ouvre l’écran hors ligne pour la zone visible |

Cette ligne reste visible pendant que vous faites défiler la liste, et elle s’affiche aussi sous un message d’erreur, ce qui est là où elle compte le plus.

## Ce qu’elle trouve

- **Lieux** : villes, bourgs, villages, hameaux, faubourgs, quartiers, lieux-dits et îles.
- **Rues**, avec numéros.
- **Points d’intérêt**, chacun avec sa propre icône et son libellé : Café, Eau potable, Toilettes, Station de réparation vélo, Magasin de vélos, Location de vélos, Parking vélos, Recharge VAE, Abri, Camping, Hôtel, Auberge de jeunesse, Refuge, Supermarché, Boulangerie, Pharmacie, Aire de pique-nique, Gare, Terminal de ferry, Aéroport, Point de vue, Sommet, Col, Parc, Plage, Plan d’eau, Réserve naturelle, Curiosité, Musée, Site historique, Lieu de culte, Hôpital, Université, Équipement sportif, Centre commercial, Tour, Phare, Bâtiment.

Hors ligne, les lignes affichent sous le nom le type, la distance, le numéro de rue et la ville, dans cet ordre, pour autant que chacun soit connu : « Eau potable · 350 m », « Rue · 400 · Manhattan ». Un robinet, des toilettes, un abri ou un support à vélos sans nom propre figure sous son type.

## Chercher par type

Saisissez le nom d’un type plutôt que celui d’un lieu. « eau potable », « boulangerie », « toilettes » et les autres fonctionnent tous, dans la langue dans laquelle l’app s’exécute.

La liste s’ouvre alors sur les cinq éléments de ce type les plus proches du centre de la carte, chacun avec sa distance, suivis en dessous des correspondances de nom ordinaires. Velorki cherche dans un carré qui s’agrandit de 5 à 50 km autour du centre de la carte jusqu’à en avoir assez. C’est le moyen rapide de répondre à « où est le robinet le plus proche » en pleine sortie.

Une recherche par type ignore les interrupteurs de groupes décrits plus bas.

## Numéros de rue

Mettez le numéro au début ou à la fin : « Hauptstrasse 12 », « 400 W 42nd ». Velorki retire le numéro, fait correspondre la rue et répond à la position propre du numéro le long de celle-ci.

Lorsque l’index contient ce numéro exact, la position est exacte. Lorsque le numéro tombe entre deux numéros connus, Velorki interpole et marque la ligne **≈ 400** pour que vous voyiez qu’il s’agit d’une estimation. Un nombre au milieu d’une requête est traité comme faisant partie du nom, de même qu’un ordinal comme « 42nd ».

## Fautes de frappe

Si une requête ne donne absolument rien, Velorki prend les mots qu’il ne reconnaît pas, trouve dans l’index les mots les plus probables à une ou deux lettres de distance, puis relance la recherche. La fiche affiche alors **Résultats pour « … »** au-dessus de la liste, avec ce qui a réellement été cherché.

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

- [Cartes et routage hors ligne](./offline-maps-and-routing)
- [Planifier un itinéraire](./planning-a-route)
- [Réglages et apparence](./settings-and-appearance)
- [Confidentialité sur le téléphone](./privacy-on-the-phone)
