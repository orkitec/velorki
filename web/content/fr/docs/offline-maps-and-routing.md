---
title: Cartes hors ligne et routage
description: Téléchargez la carte que vous regardez et les données de routage qui servent à calculer vos itinéraires, pour que la planification, la recherche et la navigation fonctionnent sans réseau.
order: 6
---

Deux téléchargements distincts permettent à Velorki de fonctionner sans connexion : la **carte**, ce que vous voyez, et les **données de routage**, à partir desquelles sont calculés les itinéraires et la recherche hors ligne. Téléchargez les deux pour la zone où vous roulez avant une sortie qui quitte la couverture réseau.

## Les deux types de données

| | Carte | Données de routage |
|---|---|---|
| Affiché comme | **Carte** | **Données de routage** |
| De quoi s’agit-il | des tuiles de carte vectorielles d’OpenFreeMap, dessinées d’après OpenStreetMap | des tuiles BRouter du miroir Velorki, construites d’après OpenStreetMap |
| Couverture | exactement le rectangle affiché à l’écran | un carré fixe de 5° × 5° du globe |
| Taille | quelques dizaines de mégaoctets pour une ville | souvent de 125 à 250 Mo par tuile |
| Sans elles | des tuiles grises là où la carte n’est pas en cache | ni routage ni recherche hors ligne dans cette zone |

Les données de routage contiennent aussi l’index des lieux : une zone téléchargée permet donc aussi de rechercher hors ligne et affiche ses [haltes sur la carte](./stops-on-the-map). C’est pourquoi l’écran des tuiles de routage indique « Une région téléchargée permet aussi de rechercher des lieux sans réseau. » La même région téléchargée permet également d’obtenir la répartition des revêtements d’une sortie enregistrée, voir [la bibliothèque](./library).

## Télécharger une zone

1. Dans l’onglet **Planifier**, déplacez la carte pour que la zone voulue remplisse l’écran. Ne dézoomez pas plus que nécessaire : le téléchargement de la carte suit exactement ce qui est affiché.
2. Touchez le bouton **Données hors ligne** dans la colonne à droite de la carte. Sur un petit écran comme celui de l’iPhone SE, la colonne n’a pas la place de l’afficher : touchez alors **Télécharger** dans l’avis en haut des résultats de recherche ou dans la pastille sur la carte, ou le bouton de téléchargement sous un itinéraire qui a besoin de tuiles, et gérez ce que vous avez dans **Réglages → Données hors ligne**.
3. Lisez les deux cartes, puis touchez **Télécharger la zone visible** en bas.
4. La boîte de dialogue **Télécharger la zone visible** liste ce que vous allez récupérer : « Carte de la zone visible · taille connue après le téléchargement » pour la carte, puis une ligne par tuile de routage avec sa taille, par exemple `E5_N45 · 187 Mo`, ou « Les données de routage de cette zone sont déjà sur l’appareil ».
5. Touchez **Télécharger**.

À partir du zoom 11, dès que le centre de la carte de l’onglet Planifier se trouve sur une zone non téléchargée, une pastille sur la carte affiche **Cette zone n’est pas téléchargée** avec **Télécharger**. Un toucher n’importe où sur la pastille ouvre l’écran hors ligne pour la zone visible. Avec les [haltes](./stops-on-the-map) affichées, elle dit « Pas de haltes ici – zone non téléchargée », avec la carte vélo « Pas de carte vélo ici – zone non téléchargée ». Elle disparaît une fois la zone téléchargée.

Les deux téléchargements se déroulent tant que l’app est ouverte. Les cartes affichent **Téléchargement de la carte…** et **Téléchargement de E5_N45…** avec des barres de progression.

L’écran vous prévient pour une bonne raison : « Les tuiles sont volumineuses, souvent 125–250 Mo chacune, et Velorki ne sait pas distinguer le Wi-Fi des données mobiles. Lancez plutôt un téléchargement en Wi-Fi. »

Vous pouvez aussi atteindre cet écran depuis **Réglages → Données hors ligne**, mais ouvert ainsi, il n’y a pas de carte derrière : le bouton de téléchargement est désactivé et la note indique « Ouvrez cet écran depuis la carte pour télécharger la zone que vous regardez. »

## Gérer les zones de carte

**Gérer** sur la carte **Carte** ouvre **Cartes hors ligne**, avec une ligne par zone téléchargée :

- Le nom donné par Velorki, **Zone de carte 1**, **Zone de carte 2**, etc.
- Sa taille et sa date, « 12,3 Mo · Téléchargée le 14 sept. 2026 ».
- **Actualisation disponible** en orange dès que la zone a plus de deux mois, avec un bouton **Actualiser** à côté. Une actualisation est un nouveau téléchargement complet.
- Un bouton **Supprimer**, qui demande « Supprimer la zone hors ligne ? » avec « Les tuiles téléchargées sont retirées de cet appareil. »

La carte de l’écran des données hors ligne résume la même chose : « 3 zones, 48 Mo », et « 2 zones datent de plus de deux mois et peuvent être actualisées ».

## Gérer les tuiles de routage

**Gérer** sur la carte **Données de routage** ouvre **Données de routage hors ligne**. Chaque ligne est une tuile de 5° × 5° avec son nom, sa taille et son état :

| État | Signification |
|---|---|
| **Sur cet appareil** | prête, le routage et la recherche hors ligne fonctionnent ici |
| **Mise à jour disponible** | le miroir a reconstruit cette tuile ; **Mettre à jour** la télécharge à nouveau |
| **Mise à jour : nouvelle version requise** | la tuile reconstruite est dans un format de données que cette version de l’app ne sait pas lire |
| **Téléchargement…** | en cours |
| **Non téléchargée** | connue du miroir, absente du téléphone |

Également sur l’écran :

- **Nécessaires pour cet itinéraire** apparaît quand vous arrivez depuis la bannière de tuiles manquantes du planificateur, avec les tuiles dont cet itinéraire a besoin déjà sélectionnées et un bouton qui les compte, par exemple **Télécharger 1 tuile (187 Mo)**.
- **Télécharger pour la zone visible** en bas, avec le total de tout ce que vous possédez : « 3 tuiles, 540 Mo ».
- **Miroir du 1 sept. 2026** sous chaque ligne, c’est-à-dire la date à laquelle le miroir a produit cette tuile pour la dernière fois.
- Un bouton **Supprimer** sur chaque ligne, avec l’avertissement « La tuile est retirée de cet appareil. Les itinéraires dans cette zone auront de nouveau besoin du serveur de routage. »
- Un bouton **Annuler le téléchargement** dans l’en-tête de progression pendant qu’un téléchargement est en cours.

Velorki vérifie chaque semaine si le miroir a reconstruit une tuile que vous possédez. Si c’est le cas, la ligne **Données hors ligne** des Réglages passe à l’orange, affiche « 2 tuiles ont des mises à jour » et place un badge avec le nombre sur le chevron.

## Le gazetteer, ou index de recherche

Chaque tuile de routage publiée par le miroir a un petit index de recherche à côté d’elle, et Velorki télécharge les deux ensemble. Rien n’en est exposé comme réglage ou téléchargement séparé.

Si l’index ne se télécharge pas, la tuile elle-même reste valable : la zone reste utilisable pour le routage et sa recherche passe simplement en ligne. Il en va de même pour un index dans un format que cette version de l’app ne lit pas : il est ignoré, les autres zones continuent de répondre hors ligne, et cette zone cherche en ligne.

## Où tout est stocké, et comment s’en débarrasser

Tout se trouve dans le stockage propre à l’app sur le téléphone, pas dans vos documents ni votre photothèque, et rien n’est copié dans une sauvegarde cloud.

Pour libérer de la place :

- supprimez des zones de carte une à une dans **Cartes hors ligne**,
- supprimez des tuiles de routage une à une dans **Données de routage hors ligne**,
- ou désinstallez l’app, ce qui supprime tout, y compris vos itinéraires et vos sorties. Exportez d’abord ce que vous voulez garder, voir [import et export](./import-and-export).

## « Mettez d’abord Velorki à jour »

Les tuiles de routage changent parfois de format. Quand le miroir propose une tuile que cette version de l’app ne sait pas lire, Velorki le dit au lieu de télécharger des données inutilisables : **Mettez d’abord Velorki à jour**, « Ces tuiles sont au format de données 5, et cette version de Velorki lit jusqu’au format 4. Elles nécessitent une version plus récente ; téléchargez-les une fois la mise à jour faite. » Répondez **Plus tard**, ou **Ouvrir la boutique** pour aller faire la mise à jour.

Les tuiles que vous avez déjà continuent de fonctionner.

## Voir aussi

- [Recherche](./search)
- [Planifier un itinéraire](./planning-a-route)
- [Navigation guidée](./navigation)
- [Dépannage](./troubleshooting)
