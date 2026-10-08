---
title: Premiers pas
description: "Installez Velorki, découvrez les quatre onglets, voyez quelles autorisations l’app demande et pourquoi, et réglez vos unités. Aucun compte n’est nécessaire."
order: 1
---

Velorki est un planificateur d’itinéraires et un enregistreur de sorties à vélo, gratuit et open source, pour iPhone et Android, fondé sur les données d’OpenStreetMap. Cette page couvre les dix premières minutes : l’installation, ce que l’app demande, l’organisation de l’écran et le seul réglage que la plupart des cyclistes veulent changer tout de suite.

## Ce qu’il vous faut

- Un iPhone sous iOS 15 ou plus récent, ou un téléphone Android sous Android 8.0 ou plus récent.
- Aucun compte. Velorki n’a ni inscription, ni identifiant, ni mot de passe. Rien à votre sujet n’est conservé sur un serveur.
- Aucune connexion, une fois une zone téléchargée. La planification, le calcul d’itinéraire, la recherche de lieux, la navigation et l’enregistrement fonctionnent tous sur le téléphone.

## L’installer

1. Installez Velorki depuis l’App Store ou Google Play, comme n’importe quelle autre app.
2. Ouvrez-la. Il n’y a pas d’écran d’inscription ni de visite guidée à parcourir : l’app s’ouvre sur la carte.

Velorki est open source. Si vous préférez la compiler vous-même, ou faire tourner vos propres serveurs pour les parties qui en utilisent, le code et les instructions se trouvent sur [github.com/orkitec/velorki](https://github.com/orkitec/velorki).

## Premier lancement

Velorki s’ouvre sur l’onglet **Planifier**, avec une carte du monde. Rien n’est encore téléchargé et aucune autorisation n’a encore été demandée.

Une bonne première séance :

1. Déplacez la carte là où vous roulez et pincez pour zoomer.
2. Touchez la carte pour fixer un départ, touchez à nouveau pour ajouter une arrivée. Un itinéraire apparaît en un instant.
3. Touchez le bouton de téléchargement à droite de la carte (**Données hors ligne**) et téléchargez la zone, pour que la carte et le calcul d’itinéraire continuent de fonctionner quand le réseau fait défaut. Voir [cartes et routage hors ligne](./offline-maps-and-routing) pour savoir ce que sont les deux téléchargements et leur taille.
4. Réglez vos unités dans **Réglages → Apparence → Unités** si l’app s’est trompée.

## Les autorisations demandées, et pourquoi

Velorki ne demande rien au lancement. Chaque autorisation est demandée au moment où elle devient nécessaire pour la première fois, et chacune est expliquée avant l’apparition de la boîte de dialogue du système.

### Position

Demandée la première fois que vous touchez **Afficher ma position**, que vous démarrez une sortie ou que vous demandez une boucle depuis votre position.

Velorki affiche d’abord sa propre boîte de dialogue, intitulée **Afficher votre position ?** : « Velorki utilise votre position pour centrer la carte sur vous et enregistrer vos sorties. La position reste sur cet appareil ; elle n’est jamais envoyée. » Vous pouvez répondre **Plus tard** et continuer à utiliser l’app ; seules les fonctions qui ont besoin de savoir où vous êtes cessent de fonctionner.

Une fois l’autorisation accordée, la carte s’ouvre là où vous l’aviez laissée, puis glisse jusqu’à votre position : aussitôt vers le dernier endroit connu du téléphone si celui-ci date de moins d’une heure, et vers la première position récente sinon, ou lorsque cette position vous place à plus de 300 m environ de là, aussi bien au démarrage de l’app qu’à votre retour dans l’app après une demi-heure ou plus. Elle ne bouge pas tant qu’un plan est sur l’onglet Planifier, qu’une fiche d’itinéraire ou de sortie est ouverte, qu’une sortie est en cours d’enregistrement, que vous êtes déjà à l’écran ou que vous avez vous-même déplacé la carte.

« Pendant l’utilisation de l’app » suffit. Sur Android, Velorki ne demande volontairement **pas** la position en arrière-plan : l’enregistrement d’une sortie tourne plutôt comme service au premier plan, avec une notification. Sur iOS, « Lorsque l’app est active » combiné au mode de position en arrière-plan couvre une sortie enregistrée écran éteint.

### Notifications (Android)

Demandées la première fois que vous démarrez une sortie. L’enregistrement s’exécute dans une notification qui affiche votre distance et votre temps, et Android arrête l’enregistrement si cette notification ne peut pas être publiée. Si vous refusez, Velorki le dit : « Sans l’autorisation des notifications, Android arrête l’enregistrement dès que vous quittez l’app. »

### Optimisation de la batterie (Android)

Demandée une seule fois, la première fois que vous démarrez une sortie : **Continuer l’enregistrement en arrière-plan** :« Android peut arrêter l’enregistrement pendant la mise en veille du téléphone. Dans les réglages de batterie qui s’ouvrent, choisissez Velorki et autorisez une utilisation sans restriction de la batterie (sur certains téléphones : non optimisée), et la trace restera complète. La question n’est posée qu’une fois. » Répondez **Ouvrir les réglages** ou **Plus tard** ; elle n’est plus jamais reposée.

### Fichiers

Aucune autorisation permanente. Lorsque vous importez un fichier GPX, FIT ou TCX, le sélecteur de fichiers du système remet ce seul fichier à l’app ; lorsque vous exportez, la feuille de partage du système l’emporte.

Velorki ne demande rien d’autre. Il n’y a aucun accès aux contacts, aux photos, au micro, à la santé ou à la publicité dans toute l’app.

## Les quatre onglets

La barre en bas comporte quatre onglets.

| Onglet | Ce qu’on y trouve |
|---|---|
| **Planifier** | La carte, la recherche de lieux, le planificateur d’itinéraires, les boucles intelligentes et l’assistant. |
| **Rouler** | Démarrer, mettre en pause et terminer une sortie, les chiffres en direct et vos sorties récentes. |
| **Bibliothèque** | Tout ce que vous avez enregistré : **Itinéraires** et **Sorties**, avec import et export. |
| **Réglages** | Apparence, unités et langue, options de navigation et d’enregistrement, données hors ligne, recherche, connexions, abonnement et pages légales. |

La barre flotte au-dessus du contenu, si bien que les listes défilent dessous.

## Unités

Velorki affiche les distances en kilomètres et en mètres, ou en miles et en pieds, et applique votre choix partout : les statistiques, les curseurs, les axes des graphiques, la bannière de virage et les indications vocales.

1. Ouvrez **Réglages**.
2. Sous **Apparence**, repérez **Unités**.
3. Choisissez **Métrique** ou **Impérial**.

Tant que vous n’avez pas choisi, Velorki suit le pays du téléphone : impérial uniquement là où le pays l’utilise, métrique partout ailleurs.

## Où trouver quoi

- **Les commandes de la carte** forment une colonne à droite de la carte : **Afficher ma position**, **Calques** (la carte vélo et les [haltes sur la carte](./stops-on-the-map)), **Données hors ligne** (absentes sur un petit écran comme celui d’un iPhone SE), **Zoom avant** et **Zoom arrière**. Dans l’onglet Rouler, un bouton boussole s’y ajoute et bascule entre **Nord en haut** et **La carte tourne avec vous**.
- **Le champ de recherche** se trouve en haut de l’onglet Planifier.
- **Le profil de vélo** (Rando, Route, Gravel, VTT, Direct) est la rangée de pastilles sous le champ de recherche.
- **La feuille d’itinéraire** est le panneau en bas de l’onglet Planifier. Tirez-la vers le haut pour le profil altimétrique et la répartition des revêtements, vers le bas pour voir plus de carte.
- **Une feuille par-dessus la carte**, comme Calques, la fiche d’un lieu, la feuille d’un point ou la feuille de boucle, fait descendre la fiche de l’onglet à sa hauteur minimale tant qu’elle est ouverte ; elle remonte quand la feuille se ferme.

## Voir aussi

- [Planifier un itinéraire](./planning-a-route)
- [Cartes et routage hors ligne](./offline-maps-and-routing)
- [Enregistrer une sortie](./recording-a-ride)
- [Réglages et apparence](./settings-and-appearance)
- [Confidentialité sur le téléphone](./privacy-on-the-phone)
