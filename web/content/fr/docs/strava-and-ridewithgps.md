---
title: Strava et Ride with GPS
description: Velorki fonctionne avec Strava et Ride with GPS, gratuitement. Connectez un compte pour téléverser vos sorties enregistrées et importer des itinéraires, et comprenez pourquoi l’envoi d’un itinéraire vers Strava passe par un fichier.
order: 13
---

Velorki est compatible avec Strava et Ride with GPS : il peut téléverser une sortie que vous avez enregistrée et rapatrier dans votre bibliothèque les itinéraires de ces comptes. La connexion à l’un ou l’autre service est gratuite, avec ou sans [Velorki Plus](./velorki-plus). Velorki n’est ni créé, ni approuvé, ni parrainé par Strava ou Ride with GPS.

Rien n’est envoyé à l’un ou l’autre service tant que vous n’avez pas connecté le compte vous-même, puis demandé quelque chose.

## Connecter un compte

1. Ouvrez **Réglages** et trouvez la section **Connexions**.
2. Touchez **Se connecter avec Strava** ou **Se connecter à Ride with GPS**.
3. La page de connexion du service s’ouvre dans un navigateur. Connectez-vous-y et autorisez l’accès.
4. Vous revenez dans Velorki, et la ligne affiche votre nom au lieu de **Non connecté**.

Velorki ne demande à Strava que deux autorisations : **read**, votre profil public (votre identifiant et votre nom, affichés dans les Réglages), et **activity:write**, pour téléverser les sorties que vous choisissez de téléverser. Il ne lit pas vos activités.

Votre téléphone conserve le jeton d’accès dans son stockage sécurisé, sous une forme que seul le serveur Velorki peut ouvrir, et l’exclut des sauvegardes. Dès lors, chaque téléversement et chaque import transite par ce serveur, qui ouvre le jeton pour cette seule requête et le transmet. Il ne conserve ni le fichier ni le jeton, ni aucune trace de l’appel, et ne peut pas utiliser le jeton de lui-même.

Si une tentative de connexion échoue, Velorki affiche « Connexion impossible : » suivi de la raison. Si vous annulez la page de connexion, rien n’est affiché.

Une ligne indiquant **Non disponible dans cette version** signifie que cette version de Velorki a été compilée sans les clés de ce service, ce qui est le cas d’une version compilée par vos soins tant que vous n’avez pas fourni les vôtres.

## Se déconnecter

Touchez **Déconnecter** sur la ligne connectée et confirmez. La déconnexion demande aussi au service de révoquer l’accès de Velorki, lorsque le serveur est joignable. Elle ne supprime rien sur votre compte Strava ou Ride with GPS.

**Strava.** La déconnexion supprime du téléphone toutes les données Strava : le jeton d’accès, les itinéraires importés depuis Strava et ceux que vous avez modifiés à partir d’eux, la liste d’itinéraires en cache, et les liens entre vos sorties et leurs activités Strava. Vos sorties elles-mêmes restent. Velorki affiche alors « Vos données Strava ont été supprimées de ce téléphone. »

Si vous retirez plutôt Velorki de votre compte Strava sur strava.com, Velorki le remarque à son prochain appel à Strava, supprime les mêmes données et vous le dit.

**Ride with GPS.** Velorki oublie le jeton d’accès. Les itinéraires et sorties déjà dans la bibliothèque restent.

## Téléverser une sortie

1. Ouvrez la sortie dans **Bibliothèque → Sorties**.
2. Touchez **Partager** en bas de la fiche.
3. Sur la ligne **Strava** ou **Ride with GPS**, touchez **Envoyer**. Un service que vous n’avez pas connecté affiche **Connecter** à la place.

Velorki affiche « Envoi à Strava… », puis « Envoyée à Strava » avec une action **View on Strava** qui l’ouvre. Pour cela, Velorki garde le lien de l’activité avec la sortie, jusqu’à la déconnexion. Une sortie déjà présente là-bas n’est jamais téléversée deux fois : la ligne propose alors **View on Strava** ou **Ouvrir sur Ride with GPS**.

Un téléversement vers Strava peut prendre un moment, car Strava traite le fichier avant qu’il n’existe en tant qu’activité ; Velorki attend et renvoie vers le résultat.

## Importer des itinéraires

1. Ouvrez l’onglet **Bibliothèque**.
2. Touchez le bouton nuage en haut à droite et choisissez **Importer depuis Strava** ou **Importer depuis Ride with GPS**.
3. La liste s’intitule **Itinéraires Strava** ou **Itinéraires Ride with GPS**. Chaque ligne indique le nom, la distance, la montée et la date.
4. Touchez **Importer** sur celui que vous voulez. Il arrive dans votre bibliothèque, et Velorki affiche « Tour des Alpes importé ». Un itinéraire importé depuis Strava reste sur le téléphone : il n’est jamais envoyé à l’assistant, mis dans un lien de partage ni envoyé à Ride with GPS ou à un autre service, et la déconnexion de Strava le supprime.

Un itinéraire de Strava, et tout itinéraire que vous modifiez à partir de lui, ne reste que tant qu’il existe encore sur Strava. Tant que Velorki est ouvert, en ligne et connecté, il revérifie cet itinéraire auprès de Strava toutes les 48 heures ; vos modifications restent tant que l’itinéraire est toujours là. S’il a été supprimé sur Strava, ou n’a pas pu être vérifié pendant 7 jours (hors ligne, déconnecté, ou vérifications en échec), Velorki le supprime et affiche « Un itinéraire de Strava a été supprimé : il n’existe plus sur Strava, ou n’a pas pu être vérifié pendant 7 jours. »

Le pied de page indique **Lu le 16 sept. 2026**, c’est-à-dire le moment où la liste a été récupérée. Velorki garde la liste sur le téléphone 48 heures au plus, et **Actualiser** en haut à droite la récupère de nouveau.

Si le compte n’est pas connecté, l’écran indique « Connectez d’abord Strava dans Réglages → Connexions. »

## Envoyer un itinéraire vers Ride with GPS

Ouvrez l’itinéraire, touchez **Partager** et utilisez **Envoyer** sur la ligne **Ride with GPS**. Il est téléversé sur votre compte et Velorki propose **Ouvrir** pour le voir là-bas.

## Envoyer un itinéraire vers Strava

L’API de Strava peut lire les itinéraires mais pas en créer, il n’y a donc rien que Velorki puisse y téléverser. La ligne **Strava** d’un itinéraire ouvre donc une explication :

> **Strava ne peut pas recevoir d’itinéraires.** L’API de Strava peut lire les itinéraires mais pas en créer. Velorki exporte donc un fichier GPX : partagez-le, puis importez-le sur strava.com.

Touchez **Exporter en GPX**, enregistrez ou envoyez le fichier, puis téléversez-le comme itinéraire sur strava.com. Cette voie est gratuite et ne demande aucune connexion.

## Tout est gratuit

Connecter Strava ou Ride with GPS, téléverser une sortie, importer des itinéraires et envoyer un itinéraire vers Ride with GPS sont gratuits, tout comme les fichiers GPX, FIT et TCX, qui font le même travail à la main. Rien de tout cela ne demande Velorki Plus.

## Les données Strava restent sur le téléphone

Les données Strava ne servent qu’à vous être montrées. Les conditions de l’API de Strava n’autorisent pas que leurs données soient données à un fournisseur d’IA ou à d’autres services : Velorki n’envoie donc jamais à l’assistant un itinéraire issu de Strava, ne le met jamais dans un lien de partage et ne l’envoie jamais à Ride with GPS ni ailleurs. **Décrire cet itinéraire**, par exemple, n’est pas proposé pour lui.

Nous ne conservons aucune donnée Strava sur nos serveurs : tout est sur votre téléphone. Pour toute question, ou pour demander la suppression de données, écrivez à [ride@velorki.com](mailto:ride@velorki.com) ; voir la [politique de confidentialité](/privacy).

## Voir aussi

- [Velorki Plus](./velorki-plus)
- [Import et export](./import-and-export)
- [Bibliothèque](./library)
- [Assistant](./assistant)
- [Confidentialité sur le téléphone](./privacy-on-the-phone)
