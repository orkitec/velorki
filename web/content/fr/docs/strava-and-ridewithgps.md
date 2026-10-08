---
title: Strava et Ride with GPS
description: Connectez votre compte Strava ou Ride with GPS pour téléverser vos sorties enregistrées et importer des itinéraires, et comprenez pourquoi l’envoi d’un itinéraire vers Strava passe par un fichier.
order: 12
---

Velorki peut dialoguer avec Strava et Ride with GPS en votre nom : téléverser une sortie que vous avez enregistrée et rapatrier dans votre bibliothèque les itinéraires de ces comptes. La connexion à l’un ou l’autre service fait partie de [Velorki Plus](./velorki-plus) ; les fichiers GPX, FIT et TCX restent gratuits et font le même travail à la main.

Rien n’est envoyé à l’un ou l’autre service tant que vous n’avez pas connecté le compte vous-même, puis demandé quelque chose.

## Connecter un compte

1. Ouvrez **Réglages** et trouvez la section **Connexions**.
2. Touchez **Se connecter avec Strava** ou **Se connecter à Ride with GPS**.
3. La page de connexion du service s’ouvre dans un navigateur. Connectez-vous-y et autorisez l’accès.
4. Vous revenez dans Velorki, et la ligne affiche votre nom au lieu de **Non connecté**.

Votre téléphone conserve le jeton d’accès dans son stockage sécurisé, sous une forme que seul le serveur Velorki peut ouvrir. Dès lors, chaque téléversement et chaque import transite par ce serveur, qui vérifie votre abonnement, ouvre le jeton pour cette seule requête et le transmet. Il ne conserve ni le fichier ni le jeton, et ne peut pas utiliser le jeton de lui-même.

Si une tentative de connexion échoue, Velorki affiche « Connexion impossible : » suivi de la raison. Si vous annulez la page de connexion, rien n’est affiché.

Une ligne indiquant **Non disponible dans cette version** signifie que cette version de Velorki a été compilée sans les clés de ce service, ce qui est le cas d’une version compilée par vos soins tant que vous n’avez pas fourni les vôtres.

## Se déconnecter

Touchez **Déconnecter** sur la ligne connectée. Velorki demande « Déconnecter Strava ? » et explique : « Velorki oublie le jeton d’accès. Les itinéraires et sorties déjà dans la bibliothèque restent. »

La déconnexion demande aussi au service de révoquer l’accès de Velorki, lorsque le serveur est joignable. Elle ne supprime rien sur Strava ou Ride with GPS, et rien dans votre bibliothèque.

## Téléverser une sortie

1. Ouvrez la sortie dans **Bibliothèque → Sorties**.
2. Touchez le bouton nuage en haut à droite, intitulé **Envoyer**.
3. Choisissez **Envoyer à Strava** ou **Envoyer à Ride with GPS**.

Velorki affiche « Envoi à Strava… », puis « Envoyée à Strava » avec une action **Voir sur Strava** qui l’ouvre. Une sortie déjà présente là-bas n’est jamais téléversée deux fois : l’entrée du menu devient **Voir sur Strava** ou **Ouvrir sur Ride with GPS**.

Un téléversement vers Strava peut prendre un moment, car Strava traite le fichier avant qu’il n’existe en tant qu’activité ; Velorki attend et renvoie vers le résultat.

## Importer des itinéraires

1. Ouvrez l’onglet **Bibliothèque**.
2. Touchez le bouton nuage en haut à droite et choisissez **Importer depuis Strava** ou **Importer depuis Ride with GPS**.
3. La liste s’intitule **Itinéraires Strava** ou **Itinéraires Ride with GPS**. Chaque ligne indique le nom, la distance, la montée et la date.
4. Touchez **Importer** sur celui que vous voulez. Il arrive dans votre bibliothèque comme un itinéraire ordinaire, et Velorki affiche « Tour des Alpes importé ».

Le pied de page indique **Lu le 16 sept. 2026**, c’est-à-dire le moment où la liste a été récupérée. Velorki la garde en cache jusqu’à sept jours, comme l’exigent les conditions de Strava, et **Actualiser** en haut à droite la récupère de nouveau.

Si le compte n’est pas connecté, l’écran indique « Connectez d’abord Strava dans Réglages → Connexions. »

## Envoyer un itinéraire vers Ride with GPS

Ouvrez l’itinéraire, touchez **Envoyer**, choisissez **Envoyer à Ride with GPS**. Il est téléversé sur votre compte et Velorki propose **Ouvrir** pour le voir là-bas.

## Envoyer un itinéraire vers Strava

L’API de Strava peut lire les itinéraires mais pas en créer, il n’y a donc rien que Velorki puisse y téléverser. Choisir **Envoyer à Strava** ouvre donc une explication :

> **Strava ne peut pas recevoir d’itinéraires.** L’API de Strava peut lire les itinéraires mais pas en créer. Velorki exporte donc un fichier GPX : partagez-le, puis importez-le sur strava.com.

Touchez **Exporter en GPX**, enregistrez ou envoyez le fichier, puis téléversez-le comme itinéraire sur strava.com. Cette voie est gratuite et ne demande aucune connexion.

## Ce qui est gratuit, et ce qui demande Plus

| | Nécessite Plus |
|---|---|
| Connecter Strava ou Ride with GPS | oui |
| Téléverser une sortie vers l’un ou l’autre | oui |
| Importer des itinéraires depuis l’un ou l’autre | oui |
| Envoyer un itinéraire vers Ride with GPS | oui |
| Exporter en GPX, FIT ou TCX et le téléverser soi-même | non |
| Importer un fichier GPX, FIT ou TCX issu de l’un ou l’autre service | non |

## Une remarque sur l’assistant et Strava

**Décrire cet itinéraire** n’est pas proposé pour un itinéraire issu de Strava. Les conditions de l’API de Strava n’autorisent pas l’envoi de leurs données à un fournisseur d’IA ; Velorki masque donc le bouton plutôt que de les enfreindre.

## Voir aussi

- [Velorki Plus](./velorki-plus)
- [Import et export](./import-and-export)
- [Bibliothèque](./library)
- [Assistant](./assistant)
- [Confidentialité sur le téléphone](./privacy-on-the-phone)
