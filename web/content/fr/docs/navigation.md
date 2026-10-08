---
title: Navigation guidée
description: "Suivez un itinéraire pendant l’enregistrement, avec une bannière de virage et des indications vocales, et découvrez ce que fait Velorki quand vous quittez l’itinéraire."
order: 7
---

Velorki vous guide le long d’un itinéraire pendant l’enregistrement d’une sortie : une bannière au-dessus de la carte montre le prochain virage, et une voix l’annonce à haute voix. Activez les interrupteurs de navigation, choisissez un itinéraire à suivre dans l’onglet Rouler, puis démarrez la sortie.

La navigation est gratuite, fonctionne hors ligne là où vous avez téléchargé les données de routage, et ne demande aucun compte.

## L’activer

Les réglages se trouvent à deux endroits à la fois, et c’est le même réglage dans les deux cas : dans **Réglages → Navigation**, et sur la feuille de l’onglet Rouler, sous **Garder l’écran allumé**.

1. **Indications de direction**, « Afficher la prochaine direction pendant l’enregistrement sur un itinéraire ». C’est l’interrupteur principal ; le reste est grisé tant qu’il est désactivé.
2. **Voix**, « Annoncer les directions à voix haute ».
3. **Hors itinéraire** : **Me guider pour revenir**, **Nouvel itinéraire vers l’arrivée** ou **Ne pas recalculer**. Voir [quand vous quittez l’itinéraire](#quand-vous-quittez-litinéraire).

Ensuite, dans l’onglet **Rouler**, choisissez quelque chose sous **Itinéraire suivi** : **L’itinéraire de l’onglet Planifier** si le planificateur contient un itinéraire, ou n’importe quel itinéraire de votre bibliothèque. Démarrez la sortie et la bannière apparaît.

## La bannière de virage

Une pastille en haut de la carte, au-dessus des commandes de la carte. De gauche à droite : une flèche pour le virage, la distance en gros chiffres, puis l’instruction.

Les instructions sont : **Tournez à gauche**, **Tournez à droite**, **Légèrement à gauche**, **Légèrement à droite**, **Virage serré à gauche**, **Virage serré à droite**, **Restez à gauche**, **Restez à droite**, **Faites demi-tour**, **Au rond-point, prenez la sortie 3**, **Prenez la sortie à gauche**, **Prenez la sortie à droite**, **Continuez tout droit** et **Vous arrivez**.

Quand un deuxième virage suit de près le premier, une petite flèche grise pour celui-ci se place au bout de la pastille.

Un itinéraire importé avec une feuille de route affiche à la place les mots de l’auteur pour un virage, « Tournez à gauche sur la rue Principale », et la voix les prononce aussi.

Un point d’intérêt sur l’itinéraire, une fontaine ou une zone où mettre pied à terre dans un fichier importé, prend la place de la bannière lorsqu’il est plus proche que le prochain virage et à moins de 300 m : son icône, la distance et son nom, un danger sous la forme « Attention : … » dans la couleur d’avertissement. La voix l’annonce une fois, avec la même avance qu’un virage, « Dans 100 mètres, attention : début de zone à pied ». Voir [capteurs et montre](./sensors-and-watch) pour ce qui parvient à la montre, et [import et export](./import-and-export) pour l’origine des points.

À la fin de l’itinéraire, la bannière devient verte et indique **Vous êtes arrivé**.

## La voix

Avec **Voix** activée, chaque virage est annoncé une fois à l’approche, puis une fois de plus au virage : « Dans 200 mètres, tournez à gauche », puis « Maintenant, tournez à gauche ». Deux virages rapprochés sont annoncés en une seule indication, « tournez à gauche, puis à droite ». Les unités impériales donnent « Dans 500 pieds », « Dans un quart de mile », « Dans un demi-mile », « Dans un mile ».

**Annonce des directions** dans Réglages → Navigation règle l’avance : le curseur est en secondes, et l’aide indique « 12 secondes avant le changement de direction à votre vitesse, jamais à moins de 50 mètres ». Comme il compte en secondes plutôt qu’en mètres, l’indication arrive au même moment que vous grimpiez une côte à la rame ou que vous la descendiez à toute allure.

La bannière porte aussi un bouton **Couper la voix pour cette sortie** tant que la voix est activée. Il coupe la voix **pour le reste de cette sortie seulement** et ne touche pas à votre réglage ; la sortie suivante recommence avec le son.

## Choisir une voix

1. **Réglages → Navigation → Voix de lecture**.
2. La première ligne est **Voix du système**, « La voix du téléphone pour votre langue ». En dessous figure chaque voix installée sur le téléphone, nommée par exemple « Voix féminine 2 (Royaume-Uni) ».
3. Touchez une ligne pour la choisir. Elle prononce un échantillon au moment où vous la choisissez.
4. Touchez **Écouter** sur n’importe quelle ligne pour l’entendre sans la choisir.

Deux choses à savoir :

- **Les voix qui ont besoin d’Internet.** Certains téléphones proposent des voix générées sur un serveur. Elles restent masquées tant que vous n’activez pas **Afficher les voix en ligne** en bas, et chacune est marquée **Nécessite Internet**. Velorki prévient : « Une voix marquée d’un nuage est générée en ligne. Sans réseau, l’annonce n’est pas prononcée ou arrive trop tard. Pour rouler, préférez une voix stockée sur le téléphone. »
- **Sur un iPhone qui n’a que la voix compacte**, Velorki affiche **De meilleures voix à télécharger** et vous guide : Réglages → Accessibilité → Contenu énoncé → Voix → votre langue → touchez le nuage à côté d’une voix Améliorée ou Premium. Ensuite, l’app choisit d’elle-même la meilleure voix du téléphone.

Si le téléphone n’a aucune voix pour votre langue : « Aucune voix n’est installée pour votre langue. Ajoutez-en une dans les réglages du téléphone, sous Synthèse vocale ou Contenu énoncé. »

## Quand vous quittez l’itinéraire

La plupart des erreurs de direction se rattrapent en un pâté de maisons, donc rien ne se passe à la seconde où vous vous écartez.

À environ **75 mètres** de l’itinéraire, pendant deux positions de suite ou environ huit secondes, la bannière devient orange : **Retour à l’itinéraire, sur votre gauche**, avec la distance jusqu’au point le plus proche de l’itinéraire encore devant vous. Cela se produit dans tous les modes et ne coûte aucun calcul d’itinéraire.

La suite dépend du choix sous **Hors itinéraire**. L’attente est la même pour les deux modes qui calculent : environ **trois quarts de minute hors itinéraire, ou 150 mètres depuis l’endroit où vous l’avez quitté**, et jamais avant 15 secondes, de sorte qu’une rafale de mauvaises positions ne coûte rien. **Touchez la bannière** pour passer l’attente.

### Me guider pour revenir

Le mode par défaut. Votre plan n’est jamais remplacé. Velorki calcule un chemin pour y revenir, vers un point **devant** vous : il essaie 300 mètres, 800 mètres puis 2 kilomètres plus loin sur le plan, comptés depuis l’endroit où vous êtes arrivé à côté de lui plutôt que depuis celui où vous l’avez quitté, et retient le premier qui n’est pas un détour absurde et qui ne vous fait pas prendre une rue à sens unique à contresens, longer un trottoir ou revenir sur vos pas. Le chemin de retour est tracé comme sa propre ligne, dans sa propre couleur, le plan restant sur la carte, et la bannière et la voix le suivent. Une fois de retour sur le plan, le chemin de retour disparaît sans un mot et les virages du plan reprennent.

Si vous roulez à votre façon, le chemin de retour est recalculé, mais seulement quand vous êtes à **300 mètres** de l’endroit où le dernier a été calculé, et jamais vers un point situé en deçà du précédent : il avance avec vous au lieu de vous rappeler, et une minute de route est le maximum qu’il demandera au calculateur. Il n’abandonne jamais le plan et ne planifie pas de lui-même un nouvel itinéraire.

### Nouvel itinéraire vers l’arrivée

Quand vous quittez l’itinéraire, Velorki replanifie depuis votre position jusqu’à l’arrivée, en passant par les étapes que vous n’avez pas encore atteintes, et cela devient l’itinéraire pour le reste de la sortie. L’ancien plan reste sur la carte, estompé. Si vous quittez aussi le nouvel itinéraire, il replanifie, une fois que vous êtes à 300 mètres de l’endroit où il l’a fait en dernier, afin de ne pas tourner en rond.

### Ne pas recalculer

Seulement la bannière orange, avec la distance à l’itinéraire et la direction pour y revenir. Velorki ne demande rien au calculateur, et toucher la bannière ne fait rien.

### Pendant que vous êtes hors itinéraire

La bannière indique **Recalcul…** pendant qu’un chemin de retour ou un nouvel itinéraire est calculé, et **Itinéraire recalculé** quand un nouvel itinéraire arrive. **Nouvel itinéraire d’ici**, un bouton à côté de la bannière orange, planifie aussitôt depuis l’endroit où vous vous trouvez jusqu’à l’arrivée, quel que soit le réglage.

Toutes les distances ci-dessus augmentent avec la mauvaise qualité de votre signal GPS, en gros elles doublent avec la précision annoncée, afin qu’un téléphone sous les arbres ne vous déclare pas perdu en permanence. Elles cessent d’augmenter à 100 mètres de précision, si bien qu’un téléphone qui a complètement perdu le ciel ne peut pas désactiver la détection de sortie d’itinéraire.

## La carte pendant la navigation

- Le bouton boussole sur la carte bascule entre **Nord en haut** et **La carte tourne avec vous**. Votre choix est mémorisé pour la sortie suivante.
- Votre position se place dans la partie de la carte au-dessus de la feuille : au milieu avec le nord en haut, plus bas quand la carte tourne avec vous, de sorte que l’essentiel de ce qu’on voit est la route devant vous.
- La carte garde le zoom que vous lui donnez en pinçant pendant qu’elle vous suit, de quelques kilomètres de large jusqu’à un seul pâté de maisons ; seul le fait de la faire glisser arrête le suivi.
- **Afficher ma position** reprend le suivi après que vous avez déplacé la carte, au zoom habituel au niveau de la rue.
- Tant que vous êtes sur l’itinéraire, le marqueur de position est dessiné sur l’itinéraire et orienté le long de celui-ci, plutôt que de flotter au gré du signal.
- Les points de l’itinéraire lui-même sont aussi sur la carte : le départ, l’arrivée avec son drapeau, chaque étape qui a un nom ou un type, et les lieux à côté de l’itinéraire. Un point qui ne fait que façonner la ligne est omis. Les étapes que vous avez dépassées s’estompent, et elles restent estompées si vous revenez en arrière. Après un nouvel itinéraire vers l’arrivée, les marqueurs sont toujours ceux de votre itinéraire.
- Avec **Haltes** activé sous **Calques**, les haltes à côté de l’itinéraire à venir sont sur la carte, et une ligne liste la prochaine de chaque type avec sa distance ; voir [haltes sur la carte](./stops-on-the-map#le-long-de-litinéraire-à-venir).

## Voir aussi

- [Enregistrer une sortie](./recording-a-ride)
- [Planifier un itinéraire](./planning-a-route)
- [Cartes et routage hors ligne](./offline-maps-and-routing)
- [Réglages et apparence](./settings-and-appearance)
- [Dépannage](./troubleshooting)
