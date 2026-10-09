---
title: Assistant
description: "Décrivez la sortie que vous voulez en une phrase et Velorki en fait un itinéraire, avec votre consentement, une position arrondie au plus, et aucun historique d'itinéraires envoyé."
order: 14
---

L'assistant transforme une phrase comme« une boucle gravel d’environ 80 km sur routes calmes » en itinéraire dans le planificateur. C'est la seule partie de Velorki qui envoie ce que vous avez tapé à un serveur : il demande donc d'abord votre consentement et vous dit exactement ce qui part.

L'assistant fait partie de [Velorki Plus](./velorki-plus).

## L'ouvrir

Touchez **Demander** dans la barre d'outils de la fiche d'itinéraire de l'onglet **Planifier**. La carte de l'assistant prend la place de la fiche d'itinéraire, intitulée **Demander un itinéraire** : « Décrivez la sortie que vous avez en tête. Velorki en fait une demande et calcule l’itinéraire sur votre téléphone. » La carte au-dessus reste la carte : déplacez-la, zoomez et touchez-la comme avec la fiche d'itinéraire affichée. Faites glisser la carte de l'assistant vers le bas, ou revenez en arrière, et la fiche d'itinéraire est là, comme vous l'avez laissée ; ce que vous avez tapé et les réponses restent pour la fois suivante.

Quand un itinéraire est sur la carte, la fiche s'ouvre plutôt sur **Cet itinéraire**, une question à propos de cet itinéraire (voir [Poser une question sur cet itinéraire](#poser-une-question-sur-cet-itinéraire)) ; **Nouvel itinéraire** au-dessus permet de revenir en arrière.

Si le bouton **Demander** est absent, cette version de Velorki n'a aucune adresse de serveur, ce qui est le cas d'une copie compilée par vos soins sans relais propre.

## Consentement, et ce qui quitte le téléphone

La première fois que vous envoyez quelque chose, Velorki affiche **Avant que l’assistant ne demande** :

> Ce que vous saisissez, ainsi que l’itinéraire sur lequel vous posez une question, est envoyé au serveur Velorki, qui le transmet à notre fournisseur d’IA. Rien d’autre ne l’accompagne : ni nom, ni compte, ni historique d’itinéraires.
>
> Si vous l’autorisez, votre position est également envoyée, arrondie à environ un kilomètre. Sans elle, l’assistant ne sait pas où vous êtes et ses suggestions seront moins précises.

Trois réponses :

- **Autoriser, avec ma position approximative** envoie votre texte et une position arrondie à environ un kilomètre.
- **Autoriser, texte seulement** envoie votre texte et rien d'autre.
- **Plus tard** n’envoie rien et désactive l'assistant.

Ce qui voyage réellement : votre texte, éventuellement la position arrondie, votre langue et vos unités pour que la réponse convienne, et, pour une description d'itinéraire ou une question sur un itinéraire, un condensé de l'itinéraire (voir plus bas). Aucun identifiant de vous ni de votre téléphone n'est mis dans la requête.

Changez d'avis à tout moment sous **Réglages → Assistant IA → Ce qui est envoyé**, dont le sous-titre indique toujours dans lequel des quatre états vous êtes, avec un bouton **Modifier** à côté.

## Demander quelque chose

Tapez une phrase et touchez **Demander**. Trois exemples sont là à toucher :

- **Une boucle plate de 30 km d’ici**
- **Une boucle de 50 km sur routes calmes**
- **Une boucle gravel d’environ 80 km**

Dès que vous tapez, des pastilles sous **Ajouter** proposent les souhaits que le planificateur prend en compte : **plat**, **vallonné**, **sur gravier**, **sur routes calmes** et **retour au départ**, chacune jusqu’à ce qu’elle soit dite.

Autres choses qui marchent bien : une distance et une direction, un endroit où passer, un revêtement, la quantité de dénivelé voulue, un départ qui n'est pas là où vous êtes.

La fiche affiche **Réflexion…** pendant que le modèle répond, puis **Recherche des lieux…** pendant que les noms de lieux sont convertis en coordonnées. Puis elle résume ce qu'elle a compris : « Boucle d'environ 80 km », « Départ depuis votre position » ou « Départ à Fribourg », et une pastille par lieu où passer.

Si un nom correspond à plusieurs lieux éloignés les uns des autres, Velorki demande **Quel lieu « Fribourg » ?** avec jusqu'à trois choix. En toucher un le résout sur le téléphone, sans second aller-retour avec le modèle.

## Ce qui se passe avec la réponse

La fiche se ferme d'elle-même et le planificateur prend le relais :

- **Une boucle sans lieu particulier où passer** ouvre la [fiche de boucle](./loops) avec la recherche déjà lancée. Une fois la recherche terminée, la fiche de boucle se ferme et l'assistant revient sur **Cet itinéraire**, avec ce que vous avez demandé au-dessus de la question, pour que vous puissiez l'interroger aussitôt sur la boucle. Si la recherche n'a trouvé aucune boucle, il revient sur **Nouvel itinéraire** et le dit. Fermez la fiche de boucle ou faites quoi que ce soit dedans pendant la recherche, et la recherche est à vous : l'assistant reste à l'écart.
- **Une boucle passant par des lieux nommés** devient des points de passage avec la boucle fermée, et Velorki dit « L'itinéraire est sur la carte. »
- **Un itinéraire d'un point à un autre** devient des points de passage avec le profil de vélo réglé, et de nouveau « L'itinéraire est sur la carte. »

À partir de là, c'est une planification ordinaire : modifiez-la, demandez des variantes, enregistrez-la.

## Ce qu'il ne fait pas

Le modèle ne renvoie jamais de coordonnées et ne calcule jamais d'itinéraire. Il renvoie une requête structurée, une distance, une forme, quelques noms de lieux et une préférence ou deux, et tout le reste se passe sur votre téléphone. C'est pourquoi l'assistant sert à exprimer ce que vous voulez, et non de source de faits sur les routes.

Il peut aussi se tromper. S'il dit quelque chose que vous ne vouliez pas, reformulez avec une distance claire et un lieu clair.

## Poser une question sur cet itinéraire

Avec un itinéraire sur la carte du planificateur, **Demander** s'ouvre sur **Cet itinéraire** : « Posez n’importe quelle question sur l’itinéraire affiché. » Exemples à toucher : **Vérifie cet itinéraire**, **Où prendre un café vers la mi-parcours ?**, **Où remplir mon bidon ?**, **Évite la route principale**, **Ça passe en vélo de route ?**

Ce qui part : votre question et le condensé de l'itinéraire décrit sous [Décrire cet itinéraire](#décrire-cet-itinéraire), positions comprises. Votre propre position ne part pas dans ce mode.

La réponse tient en quelques phrases et jusqu'à six constats le long de l'itinéraire, chacun avec son emplacement. **Afficher** y amène la carte. Un constat sur lequel le planificateur peut agir a un bouton :

- **Ajouter comme étape** fait passer l'itinéraire par un café, un point d'eau ou un autre lieu du condensé, inséré là où l'itinéraire le croise.
- **Éviter** tient le routeur à l'écart de ce tronçon. Il est dessiné en pointillés sur la carte, et la pastille **1 tronçon évité** au-dessus de la carte a **Autoriser à nouveau**.
- **Passer en Gravel** (ou un autre vélo) replanifie l'itinéraire avec ce profil.

Chacun est une seule étape que **Annuler** reprend, et la fiche reste ouverte et l'indique comme **Appliqué**. Le modèle ne suggère que des lieux du condensé ; il n'invente jamais une étape ni une coordonnée.

**Cet itinéraire** n'est pas proposé pour un itinéraire importé de Strava.

## Décrire cet itinéraire

L'autre chose que fait l'assistant est d'écrire un paragraphe sur un itinéraire que vous avez déjà. Ouvrez un itinéraire dans la bibliothèque et touchez **Décrire cet itinéraire** ; la fiche commence à écrire aussitôt, et **Enregistrer comme description** conserve le texte avec l'itinéraire. **Réécrire** en demande un autre essai.

Avant de demander, le téléphone confronte l'itinéraire à ses tuiles de routage et à sa recherche de lieux hors ligne et construit un condensé : la distance, la montée, les parts de revêtement goudronné et non goudronné, les noms des points de passage, les tronçons de l'itinéraire avec leur type de route, leur revêtement et leur pente, ses montées, les villes et villages traversés, et les cafés, boulangeries, points d'eau, toilettes, points de vue et magasins de vélos à moins de 300 m, chacun avec sa distance le long de l'itinéraire et sa position. Sans tuiles téléchargées pour la zone, seuls les chiffres partent. Le modèle reçoit aussi les positions, à 10 m près, pour savoir où se situe la sortie ; un itinéraire qui part de votre porte montre où est votre porte. Chaque lieu que la description nomme vient du condensé : elle peut donc dire « le café de Caniço au km 9 » et parler d'un café qui existe. Elle écrit dans la langue et les unités de l'app.

Le bouton n'est pas proposé pour un itinéraire importé de Strava, car les conditions de Strava interdisent de donner leurs données à un fournisseur d'IA.

## Limites et erreurs

L'assistant est limité en fréquence : vingt requêtes par heure et cent par jour.

| Ce que dit la fiche | Ce que cela signifie |
|---|---|
| « Trop de demandes. Réessayez dans 90 secondes. » | vous avez atteint la limite |
| « L'assistant IA fait partie de Velorki Plus. » | pas d'abonnement |
| « L’assistant a besoin de votre accord avant de pouvoir envoyer quoi que ce soit. » | le consentement manque ou est refusé |
| « Je ne suis pas sûr d’avoir compris. Indiquez une distance et un lieu. » | le modèle n'était pas sûr |
| « Impossible de trouver « Fribourg ». Essayez une autre orthographe ou une ville proche. » | le nom du lieu n'a pas été résolu |
| « Il me faut un point de départ. Activez la localisation ou indiquez un lieu de départ. » | « d'ici » sans position |
| « L'assistant n'a pas pu répondre : » | le serveur ou le modèle a échoué |

**Réessayer** efface l'erreur et garde ce que vous avez tapé.

## Signaler une mauvaise réponse

**Réglages → Assistant IA → Signaler une réponse de l’IA** ouvre un e-mail qui nous est adressé : « Signalez-nous une réponse fausse ou inappropriée. » Merci de l'utiliser. Les réponses erronées et inappropriées sont la façon dont les requêtes sont corrigées.

## Voir aussi

- [Velorki Plus](./velorki-plus)
- [Boucles](./loops)
- [Planifier un itinéraire](./planning-a-route)
- [Confidentialité sur le téléphone](./privacy-on-the-phone)
