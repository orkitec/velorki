---
title: Boucles
description: "Demandez à Velorki un aller-retour d’une distance donnée qui se termine là où il a commencé, puis parcourez les candidats jusqu’à ce que l’un vous convienne."
order: 3
---

Une boucle est une sortie qui revient à son point de départ, et Velorki les génère à partir d’une distance plutôt que de points que vous touchez. Utilisez le bouton **Boucle** quand vous savez combien de kilomètres vous voulez rouler mais pas où, et pour fermer un itinéraire que vous avez déjà tracé.

Le générateur de boucles est un simple algorithme qui tourne sur votre téléphone. Il est gratuit, il n’a besoin d’aucun serveur en dehors du calcul d’itinéraire lui-même, et aucun modèle d’IA n’intervient.

## L’ouvrir

Touchez **Boucle** dans la barre d’outils de la feuille d’itinéraire, sur l’onglet **Planifier**. La feuille s’intitule **Créer une boucle**, et ce qu’elle propose dépend de ce que le planificateur contient déjà.

## Fermer un itinéraire que vous avez tracé

Si le planificateur contient déjà deux points ou plus, la feuille propose de ramener l’itinéraire à son départ.

1. Elle indique « Revenir au point de départ. »
2. Sous **VÉLO**, choisissez le profil. C’est le même réglage que les pastilles du planificateur : le changer ici le change là-bas.
3. **Autre chemin au retour** est activé par défaut, avec la note « Évite les routes déjà parcourues. » Désactivez-le et le trajet retour pourra reprendre le chemin de l’aller.
4. Touchez **Fermer la boucle**. Velorki ajoute une copie de votre premier point, calcule le chemin du retour et affiche le résultat sous la forme `48,2 km · 720 m de montée`.
5. **Autre retour** conserve l’aller exactement tel quel et ne demande qu’un retour différent. Appuyez-y autant que vous voulez ; chaque appui compte pour une étape d’annulation. Le bouton est grisé tant que **Autre chemin au retour** est désactivé.
6. **OK** ferme la feuille. La boucle est sur la carte du planificateur comme un itinéraire ordinaire que vous pouvez modifier et enregistrer.

## Créer une boucle de zéro

Si le planificateur est vide, ou ne contient qu’un seul point, la feuille demande plutôt une distance.

1. **Où elle commence.** Si un point est déjà sur la carte, c’est lui le départ. Sinon la ligne indique **Depuis votre position**, et Velorki demande la localisation la première fois. Si aucune position n’est disponible, il se rabat sur le centre de la carte et la ligne devient **Depuis le centre de la carte**.
2. **DISTANCE.** Faites glisser le curseur. En métrique, il va de 5 à 200 km par pas de 5 km, en impérial de 3 à 125 miles par pas de 1 mile, et la valeur choisie s’affiche en grand au-dessus. Il s’ouvre sur la dernière valeur demandée, 30 km la première fois.
3. **VÉLO.** Les mêmes cinq profils que dans le planificateur.
4. **Autre chemin au retour.** Activé, vous obtenez un vrai cercle ; désactivé, vous allez jusqu’à un point éloigné et revenez par le même chemin.
5. Touchez **Créer une boucle**.

## Pendant la recherche

Velorki lance la requête dans huit directions et calcule chacune sur le téléphone, ce qui prend de quelques secondes à plus d’une minute, selon la distance et le téléphone. Une barre de progression avance à mesure que les directions sont terminées, avec une ligne dessous : « 8 directions essayées · 3 vérifiées jusqu’ici ».

La meilleure boucle du moment est sur la carte dès qu’il y en a une, avec son résumé, **Une autre** et **OK** à côté de la barre, tandis que la ligne indique que la recherche continue pour une boucle plus calme et plus fluide. À la fin, la ligne dit parmi combien de boucles celle affichée a été choisie, « La meilleure de 6 boucles ». **Arrêter** met fin à la recherche plus tôt et conserve ce qui a été trouvé ; **OK** garde la boucle affichée et laisse la recherche se terminer en arrière-plan sans la remplacer.

## Choisir parmi les candidats

On ne vous donne pas de liste à lire. Chaque candidat est noté selon sa proximité avec la distance demandée, son dénivelé par kilomètre, la part de revêtement non goudronné, la part qui passe par des pistes cyclables et des réseaux cyclables, la part qui répète les mêmes routes et la part qui emprunte de grands axes. Le meilleur est transmis directement au planificateur et tracé sur la carte, et la feuille n’affiche que sa ligne de résumé, `48,2 km · 720 m de montée`.

Pour voir le suivant, touchez **Une autre**. Cela descend d’un cran dans le classement sans aucun nouveau calcul d’itinéraire, donc c’est instantané. Quand le classement est épuisé, Velorki relance une recherche avec les huit directions décalées d’un demi-pas, de sorte que les nouveaux essais tombent entre les anciens.

Chaque candidat que vous regardez est un véritable itinéraire dans le planificateur : déplacez-vous autour, faites glisser un point, consultez son profil altimétrique et **Enregistrez**-le quand l’un convient.

Si le curseur ou le profil de vélo change après une recherche, le résultat est périmé et le bouton redevient **Créer une boucle**.

## Demander une boucle qui passe par un lieu précis

La feuille de boucle n’a aucun champ pour un lieu à longer, ni préférence de relief ou de revêtement. Cela passe par l’[assistant](./assistant) : une phrase comme« une boucle vallonnée de 60 km depuis ici qui passe près du lac » devient une requête avec un point de passage et des préférences, et le générateur de boucles fait le travail. L’assistant fait partie de Velorki Plus ; la feuille de boucle elle-même est gratuite.

## Quand il ne trouve rien

- **« Aucune boucle trouvée ici, essayez une autre distance. »** Certains endroits, une île ou une vallée en cul-de-sac, n’ont simplement pas de réseau routier pour un cercle de cette longueur. Augmentez ou réduisez nettement la distance, ou partez d’ailleurs.
- **« Activez la localisation ou touchez la carte pour placer le départ. »** Aucun point de départ n’a pu être déterminé. Autorisez la localisation, ou touchez d’abord la carte.
- **« La recherche de boucle a pris trop de temps sur ce téléphone. Essayez une distance plus courte. »** La recherche a abandonné au bout de 30 minutes.
- **« Échec de la recherche de boucle : »** suivi d’une raison signifie que le calcul d’itinéraire lui-même a échoué. Consultez le [dépannage](./troubleshooting).

Fermer la feuille annule une recherche en cours mais conserve ce qu’elle avait déjà trouvé.

## Voir aussi

- [Planifier un itinéraire](./planning-a-route)
- [Assistant](./assistant)
- [Cartes et routage hors ligne](./offline-maps-and-routing)
- [Bibliothèque](./library)
