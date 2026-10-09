---
title: Confidentialité sur le téléphone
description: "En termes de cycliste : ce qui reste sur votre téléphone, ce qui en sort, quand et vers qui. Il n’y a pas de compte et rien n’est téléversé sans que vous le demandiez."
order: 17
---

Velorki n’a pas de compte : il n’y a donc rien à quoi se connecter et rien sur vous sur un serveur. Cette page est la version en langage clair de ce que cela signifie en pratique ; la [politique de confidentialité](/privacy) est la version formelle.

## Ce qui reste sur le téléphone

Tout ce que vous créez et tout ce que vous téléchargez :

- les itinéraires planifiés, les sorties enregistrées et leurs traces GPS,
- vos réglages, y compris les unités et la voix que vous avez choisies, ainsi que le poids, l’année de naissance, le sexe, la fréquence cardiaque maximale, le poids du vélo, le type de vélo et la puissance seuil que vous pouvez saisir dans Réglages → Cycliste : ce sont des réglages du téléphone, qui ne sont jamais envoyés nulle part,
- les zones de carte hors ligne téléchargées,
- les tuiles de routage téléchargées et les index de recherche de lieux qui les accompagnent,
- les jetons d’accès à Strava et Ride with GPS si vous les connectez, qui vont dans le stockage sécurisé du téléphone sous une forme que seul le relais Velorki peut ouvrir.

Rien de tout cela n’est téléversé où que ce soit sans que vous le demandiez.

Sur Android, Velorki est volontairement exclu de la sauvegarde cloud de Google et du transfert d’appareil à appareil : vos sorties ne sont donc pas non plus copiées hors du téléphone par le système. Pour passer à un nouveau téléphone, exportez ce que vous voulez garder en fichiers GPX, FIT ou TCX, voir [import et export](./import-and-export).

## Ce qui quitte le téléphone, et quand

### Quand vous regardez la carte

Les tuiles de carte sont récupérées auprès d’OpenFreeMap, et de CyclOSM si vous activez **Carte vélo en ligne** sous **Calques**. La **Carte vélo** est dessinée sur le téléphone et ne demande rien à aucun serveur. Demander une tuile indique au serveur de tuiles quel carré du monde vous regardez, et fait intervenir votre adresse IP, comme toute requête. Une zone que vous avez téléchargée est servie depuis le téléphone et ne demande rien.

### Quand vous planifiez

Le routage s’effectue sur votre téléphone partout où vous avez les tuiles de routage. Pour une zone que vous n’avez pas téléchargée, les points de passage sont envoyés à un serveur de routage, qui renvoie l’itinéraire. Il reçoit les points de passage, rien d’autre : pas d’identité, pas d’autres itinéraires, pas de sorties.

**Réglages → Avancé → Routage → Sur l’appareil uniquement** désactive entièrement le serveur ; Velorki propose alors le téléchargement au lieu de calculer l’itinéraire.

### Quand vous cherchez

La recherche est traitée sur le téléphone sur une zone téléchargée, et rien de ce que vous tapez ne quitte l’appareil.

Elle ne passe jamais en ligne d’elle-même : rien n’est envoyé tant que vous ne touchez pas **Rechercher « … » en ligne**. Quand rien n’est téléchargé ou que la carte est sur une zone non téléchargée, rien n’est cherché avant ce choix ; **Chercher dans les zones téléchargées** reste sur le téléphone. Ce que vous avez tapé est alors envoyé à Photon, avec une position approximative pour que les résultats proches arrivent en premier.

Les [haltes sur la carte](./stops-on-the-map) sont lues dans l’index sur le téléphone et ne demandent rien.

Toucher **Détails** sur la fiche d’un lieu récupère ses détails (horaires d’ouverture, site web, etc.) auprès d’OpenStreetMap.

Un lien de carte court que vous partagez vers Velorki (`maps.app.goo.gl`, `maps.apple/p`, `osm.org/go`) est ouvert une fois auprès du service qui l’a créé, pour savoir vers où il pointe ; ce service voit le lien et votre adresse IP, comme il le ferait dans un navigateur.

### Quand vous enregistrez

Absolument rien ne quitte le téléphone. L’enregistrement, les statistiques, les graphiques et les tronçons sont tous calculés sur l’appareil. Il en va de même pour la fréquence cardiaque, la cadence et la puissance provenant d’une montre, d’un capteur Bluetooth ou de votre app de santé : elles sont stockées avec la sortie et, si vous avez activé Santé, échangées avec Apple Santé ou Health Connect sur le téléphone lui-même.

### Quand vous interrogez l’assistant

Seulement avec votre consentement, et seulement ce que vous avez autorisé : votre texte, éventuellement une position arrondie à un kilomètre environ, votre langue et vos réglages d’unités. Pas de nom, pas de compte, pas d’historique d’itinéraires, et jamais votre trace. Voir [assistant](./assistant).

### Quand vous connectez Strava ou Ride with GPS

Rien n’est envoyé à l’un ou l’autre tant que vous n’avez pas connecté le compte puis demandé quelque chose, un téléversement ou un import.

La connexion transmet un code à usage unique au relais Velorki, qui le transforme en jeton d’accès en y ajoutant le secret de notre application, et remet le jeton à votre téléphone sous forme enveloppée, de sorte que seul le relais puisse l’ouvrir. Nous ne conservons pas le jeton. Ensuite, chaque téléversement et chaque import transite par le relais : il vérifie votre abonnement, ouvre le jeton pour cette seule requête et le transmet à Strava ou Ride with GPS. Il ne conserve ni le fichier ni le jeton, et ne peut pas utiliser le jeton de lui-même.

### Quand vous créez un lien de partage

Cet itinéraire ou cette sortie, avec sa trace, son nom et ses chiffres, est copié sur notre serveur pour que le lien puisse être ouvert. Le lien est public pour toute personne qui l’a, il montre où la trace commence et finit, et il est supprimé automatiquement au bout d’un an. Voir [partage](./sharing).

### Quand vous achetez Velorki Plus

Le store gère le paiement et nous ne voyons jamais votre carte. L’abonnement est vérifié à l’aide d’un identifiant aléatoire anonyme qui n’est lié ni à un nom, ni à une adresse e-mail, ni à un identifiant d’appareil.

## Ce que Velorki ne fait jamais

- Pas de compte, pas d’inscription, pas d’adresse e-mail.
- Pas de publicité, pas de SDK publicitaire, pas de profilage.
- Pas de SDK d’analyse ni de rapport de plantage dans l’app au moment de la rédaction. Si l’un d’eux était un jour ajouté, la politique de confidentialité le nommerait et dirait ce qu’il collecte avant sa mise en service.
- Aucune vente de données, à personne, jamais.
- Pas de fonctions sociales ni de messagerie entre utilisateurs.

## Effacer des données

| Quoi | Comment |
|---|---|
| Un itinéraire ou une sortie | supprimez-le dans la [bibliothèque](./library) |
| Zones de carte hors ligne et tuiles de routage | supprimez-les dans les [données hors ligne](./offline-maps-and-routing) |
| Un jeton Strava ou Ride with GPS | **Déconnecter** dans Réglages → Connexions |
| Tout ce que l’app a stocké | désinstallez l’app |
| Un lien de partage | il expire au bout d’un an ; écrivez à [hello@orkitec.com](mailto:hello@orkitec.com) avec le lien pour le faire retirer plus tôt |

Désinstaller ne supprime pas les liens de partage que vous avez créés, ni rien de ce que vous avez téléversé sur Strava ou Ride with GPS.

## Vos droits

Si vous êtes dans l’UE ou au Royaume-Uni, le RGPD vous donne des droits sur vos données personnelles. Vous pouvez en exercer la plupart vous-même, car les données sont sur votre téléphone et s’exportent à tout moment en GPX, FIT ou TCX. Pour tout ce qui se trouve de notre côté, c’est-à-dire les liens de partage, les entrées de journal et l’enregistrement d’abonnement, écrivez à [hello@orkitec.com](mailto:hello@orkitec.com). La déclaration complète, avec la base juridique et l’autorité auprès de qui déposer une réclamation, se trouve dans la [politique de confidentialité](/privacy).

## Voir aussi

- [Politique de confidentialité](/privacy)
- [Partage](./sharing)
- [Assistant](./assistant)
- [Strava et Ride with GPS](./strava-and-ridewithgps)
- [Cartes hors ligne et routage](./offline-maps-and-routing)
