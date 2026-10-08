---
title: Bibliothèque
description: "Où se trouvent vos itinéraires enregistrés et vos sorties, ce que montre une fiche d’itinéraire ou de sortie, et comment renommer ou supprimer l’un ou l’autre."
order: 9
---

L’onglet Bibliothèque contient tout ce que vous avez gardé : les itinéraires que vous avez planifiés et les sorties que vous avez enregistrées. C’est une fiche posée sur la carte, comme les onglets Planifier et Enregistrer : son contenu défile à n’importe quelle hauteur et la poignée en haut la déplace ; quand il n’y a rien à faire défiler, c’est toute la fiche qui bouge. Tirez-la vers le haut pour plus de place, tirez-la tout en bas et elle se replie dans la barre de navigation en laissant la carte. C’est ici que vous rouvrez un itinéraire, lisez les graphiques et les tronçons d’une sortie, et faites entrer et sortir des fichiers.

Tout ce qui est dans la bibliothèque est sur le téléphone. Il n’y a pas de compte et rien n’est synchronisé nulle part.

## Itinéraires et Sorties

Un sélecteur sous le titre de la fiche choisit la liste : **Itinéraires** ou **Sorties**. Velorki se souvient de celle que vous regardiez en dernier.

- Une ligne d’**itinéraire** montre son nom et, en dessous, la date, la distance et la montée.
- Une ligne de **sortie** montre son nom et, en dessous, la date, la distance et le temps en mouvement. Au-dessus de la liste figure un décompte, « 12 sorties ».

Touchez une ligne pour l’ouvrir dans la fiche, avec l’itinéraire ou la sortie tracé sur la carte au-dessus. La flèche en haut à gauche de la fiche, ou le retour du système, ramène la liste.

Les listes vides s’expliquent d’elles-mêmes : « Aucun itinéraire enregistré pour l’instant. Planifiez un itinéraire dans l’onglet Planifier et enregistrez-le. » et « Aucune sortie pour l’instant. »

## Renommer et supprimer

**Itinéraires** : le menu à droite de la ligne propose **Renommer** et **Supprimer**. Balayer une ligne vers la gauche la supprime aussi. Dans les deux cas, le message qui suit comporte **Annuler**.

**Sorties** : balayez la ligne vers la gauche pour la supprimer, là aussi avec **Annuler**. Pour renommer une sortie, ou la supprimer avec une confirmation, passez par sa fiche, dans le menu à droite de son en-tête.

Les deux boîtes de dialogue de renommage sont identiques : un champ, **Nom**, puis **Annuler** ou **Enregistrer**.

## Une fiche d’itinéraire

Ouvrir un itinéraire le trace sur la carte, cadré dans la partie de l’écran au-dessus de la fiche, avec ses points d’intérêt sous forme de petits repères nommés quand il en a été importé. La fiche montre, depuis le haut :

- la date, le profil de vélo et la montée,
- la description, si l’itinéraire en a une,
- **Distance**, **Montée**, **Descente** et **Durée est.**,
- la fiche elle-même s’ouvre tout en haut quand la liste à l’écran compte plus de deux entrées, et reste à mi-hauteur sinon ; une fois que vous l’avez déplacée, elle revient où vous l’avez laissée jusqu’au redémarrage de l’appli,
- sous le nom, l’origine d’un itinéraire importé : le format du fichier et son auteur, par exemple « Importé depuis GPX · Garmin Connect » ; un itinéraire planifié ici n’affiche rien à cet endroit,
- les actions ci-dessous, **Ouvrir dans le planificateur** en premier pour qu’elle soit visible à la hauteur de repos de la fiche,
- une ligne **Description** et une ligne **Lien**, chacune avec un crayon : la description est celle du fichier, de l’assistant ou la vôtre, le lien est le `<link>` du fichier ou un lien que vous saisissez, et le toucher ouvre la page,
- la répartition des revêtements : les chiffres du routeur lui-même pour un itinéraire planifié ici, et pour un itinéraire lu depuis un fichier le même rapprochement que pour une sortie, voir plus bas,
- le profil altimétrique,
- **Points d’intérêt** : les points de l’itinéraire qui ne sont pas sur sa trace, chacun avec l’icône de son type, son nom et sa note — ceux que fournissait un fichier en dehors du parcours, et les lieux que vous avez marqués à côté de l’itinéraire dans le planificateur ; ceux qui sont sur la trace sont des lignes de la feuille de route à la place,
- pour un itinéraire importé avec des virages ou des points d’intérêt, ou avec des points que vous avez nommés ou annotés dans le planificateur, la feuille de route : chaque virage et chaque point avec sa distance depuis le départ ; toucher une ligne fait glisser la carte jusque-là à votre niveau de zoom, et toucher un repère fait défiler la fiche jusqu’à cette ligne.

Les actions :

- **Ouvrir dans le planificateur** le charge dans l’onglet Planifier avec tous ses points, points intermédiaires et leurs noms, types et notes compris, où vous pouvez le modifier et l’enregistrer de nouveau. Un itinéraire importé plutôt que planifié s’ouvre avec le tracé exact du fichier et des points seulement à ses extrémités et aux points propres du fichier qui se trouvent sur la trace, qui viennent avec leur type et leur note ; une modification ne recalcule que les tronçons voisins, et le tracé du fichier reste partout ailleurs. Le tracé du fichier est conservé avec l’itinéraire à travers chaque modification et chaque enregistrement, de sorte que **Rétablir** dans le planificateur peut le remettre. Les points hors trace arrivent comme des lieux à côté de l’itinéraire, où ils peuvent être nommés, recevoir un type, être déplacés sur l’itinéraire ou supprimés comme n’importe quel autre point. Le prochain enregistrement réécrit les deux ensembles, de sorte qu’un lieu que vous supprimez dans le planificateur disparaît aussi de la fiche.
- **Exporter** propose **Itinéraire GPX** et **Parcours FIT**, voir [importer et exporter](./import-and-export).
- **Envoyer** propose **Envoyer à Ride with GPS** et **Envoyer à Strava**, voir [Strava et Ride with GPS](./strava-and-ridewithgps).
- **Partager un lien** le transforme en lien, voir [partage](./sharing).
- **Décrire cet itinéraire** demande à l’assistant d’en écrire un paragraphe, voir [assistant](./assistant).

## Une fiche de sortie

Ouvrir une sortie trace sur la carte **la trace colorée selon la vitesse**, du lent au rapide, cadrée au-dessus de la fiche, avec une légende **lent**/**rapide** en haut de la fiche. Les tranches sont les quantiles propres à cette sortie : les couleurs comparent donc la sortie à elle-même et non à une échelle fixe. Une sortie sans horodatage est tracée comme une simple ligne. La fiche montre, depuis le haut :

- la date,
- sept chiffres : **Distance**, **En mouvement**, **Temps**, **Moy.**, **Max**, **Montée**, **Descente**. **En mouvement** exclut le temps passé à l’arrêt ; **Temps** est la sortie entière, du début à la fin.
- le graphique **Profil altimétrique**, l’altitude selon la distance, tracé seulement quand la trace comportait des altitudes,
- le graphique **Vitesse**, dont l’axe commence toujours à zéro,
- le graphique **Fréq. cardiaque**, quand la sortie en comportait une ; là où la mesure a été perdue sur un tronçon, la ligne s’interrompt, et quand moins de la majeure partie de la sortie avait une mesure, la légende dit dans quelle proportion, « Fréquence cardiaque · 24 % de la sortie », pour qu’une moyenne sur ces minutes ne soit pas lue comme celle de la sortie,
- le tableau des **Tronçons**.

Touchez un graphique et faites glisser le doigt dessus pour une lecture de la forme `12,3 km · 340 m`. Pincez un graphique pour zoomer sur un passage, faites glisser pour vous déplacer pendant le zoom, et touchez-le deux fois ou touchez **Toute la sortie** pour revoir la sortie entière ; les trois graphiques zooment ensemble.

### Itinéraire et points d’intérêt

Une sortie qui suivait un itinéraire montre cet itinéraire sous la trace, dans la couleur plus discrète d’une variante du planificateur, et les points d’intérêt de l’itinéraire sous forme de repères sur la carte et de marques sur le graphique **Profil altimétrique** à l’endroit où vous les avez passés — seulement pour les points dont la sortie s’est approchée à moins de 60 m. Toucher un repère l’épingle avec son nom ; la lecture nomme une marque sur laquelle repose le doigt. Le bouton d’itinéraire en haut de la colonne de commandes de la carte masque tout cela, et le choix est mémorisé.

### Chiffres issus d’un capteur

Une sortie enregistrée avec une ceinture cardio, une Apple Watch ou un capteur de puissance comporte plus que les sept : **FC moy.**, **FC max**, **Cadence moy.**, **Cadence max**, **Puiss. moy.**, **Puiss. max** et **Puiss. norm.** s’ajoutent aux chiffres, chacun seulement si la sortie l’a, et le graphique **Fréq. cardiaque** est tracé sous le graphique de vitesse. **Puiss. norm.** est la mesure du capteur pondérée comme les jambes la ressentent : la puissance sur une grille d’une seconde, sa moyenne glissante sur 30 s, chaque moyenne élevée à la puissance quatre, ces valeurs moyennées puis la racine quatrième prise. Une sortie régulière donne sa moyenne ; une sortie faite d’accélérations et de repos donne plus. Il faut au moins une demi-minute de mesures d’un seul tenant, et un trou de plus de cinq secondes dans le capteur commence un nouveau morceau. Avec **Zones de puissance** activées et un seuil défini, **Intensité** se place à côté : la puissance normalisée divisée par votre puissance seuil, de sorte que 0,80 correspond à une sortie à quatre cinquièmes de ce que vous pouvez tenir pendant une heure. Une sortie enregistrée sans capteur n’en montre rien, et une sortie importée depuis un fichier GPX, FIT ou TCX montre ce que ce fichier contenait. Voir [capteurs et montre](./sensors-and-watch).

### Calories, zones de fréquence cardiaque, zones de puissance et puissance estimée

Les quatre sont désactivées jusqu’à ce que vous les activiez dans Réglages → Cycliste, et les quatre sont calculées sur le téléphone à partir des points de la sortie elle-même, de sorte que les anciennes sorties en bénéficient aussi.

**Calories** est une estimation, et la petite ligne sous le chiffre dit sur quoi elle repose. Avec un capteur de puissance sur la sortie, c’est le travail fourni, « d’après la puissance » : un kilojoule de pédalage correspond presque exactement à une kilocalorie brûlée. Sinon, avec une fréquence cardiaque sur la sortie et votre poids, votre année de naissance et votre sexe, c’est « d’après la FC ». Sinon, avec **Estimer la puissance** activé, c’est « d’après la puiss. est. », le travail estimé en kilojoules là encore. Sinon c’est « d’après la vitesse », à partir de votre poids et de votre allure. Il faut votre poids dans tous les cas.

**Puiss. est.** n’apparaît qu’avec l’interrupteur activé et seulement sur les sorties sans capteur de puissance ; une sortie avec capteur montre le capteur et rien d’autre. C’est la moyenne de ce que le modèle de puissance de Martin dit que vous avez dû fournir aux pédales pour vous déplacer avec votre vélo à la vitesse où vous avez roulé, sur la pente où vous avez roulé : d’après votre vitesse, la pente et le poids total du cycliste et du vélo, en supposant ni vent, ni abri derrière un autre cycliste, un cycliste mains sur les cocottes, une résistance au roulement fixe par type de vélo, une perte de transmission de 2,5 % et un air plus mince avec l’altitude. Les altitudes sont lissées sur 50 m parce que les altitudes GPS sautent, et le travail est additionné par tranches d’une demi-minute avant que tout ce qui est négatif soit écarté, de sorte qu’une altitude qui oscille ne coûte rien ; la roue libre et le freinage comptent pour zéro, et les accélérations sont évaluées à partir de vitesses moyennées sur dix secondes, ce qui en ville représente l’essentiel du travail. Attendez-vous à un résultat raisonnable dans les longues montées, où le poids domine ; trop élevé dans un groupe rapide et faux par vent, qu’il ne peut pas voir. C’est un chiffre pour comparer vos propres sorties, pas un capteur de puissance.

**Zones de FC** est une barre sous le graphique de fréquence cardiaque, découpée en cinq zones de votre fréquence cardiaque maximale, avec une ligne par zone : sa plage, le temps passé dedans et sa part du temps de fréquence cardiaque de la sortie. La zone 1 est tout ce qui est sous 60 %, la zone 5 tout ce qui est à partir de 90 %. La légende nomme le maximum utilisé : celui que vous avez saisi, ou 220 moins votre âge.

**Zones de puissance** est la même barre pour les sorties avec capteur de puissance, découpée en sept zones de votre puissance seuil : sous 55 %, 55–75, 75–90, 90–105, 105–120, 120–150 et à partir de 150 %. Chaque seconde de la sortie va à la zone de la mesure du capteur à ce moment ; le temps passé à l’arrêt ne compte nulle part. La légende nomme le seuil, « Zones de puissance · seuil 250 W ». Il faut l’interrupteur et votre puissance seuil dans Réglages → Cycliste, et cela place le chiffre **Intensité** parmi les tuiles.

### Tronçons

Une ligne par tronçon, avec quatre colonnes : **Tronçon**, **En mouvement**, **Moy.** et **Montée**. La légende indique la longueur d’un tronçon, « Tronçons, tous les 5 km ». Par défaut, la longueur suit la sortie : un kilomètre jusqu’à 30 km, cinq jusqu’à 150 km, dix au-delà, en miles avec les unités impériales, de sorte que le tableau reste court sur une longue sortie ; **Longueur des tronçons** dans Réglages → Enregistrement la fixe plutôt à 1, 5 ou 10. La dernière ligne est le reste, elle peut donc être plus courte que les autres. Derrière chaque ligne, une barre montre la vitesse moyenne de ce tronçon par rapport à votre tronçon le plus rapide, ce qui fait ressortir d’un coup d’œil les passages difficiles. Touchez une ligne pour voir ce tronçon ombré sur les graphiques et tracé sur la trace sur la carte, où une pastille le nomme, « Tronçon 3 · 2–3 km » ; touchez de nouveau la ligne ou la pastille pour l’effacer.

### Montées

Sous les tronçons, sur une sortie qui en comportait, un tableau **Montées** : une ligne par montée avec **Début** (où dans la sortie elle a commencé, « à 12,3 km »), **Longueur**, **Montée** et **Pente**, et une ligne plus discrète en dessous avec le temps en mouvement, la VAM et, quand la sortie les comportait, la fréquence cardiaque moyenne et la puissance moyenne sur la montée. La VAM est le nombre de mètres de dénivelé gagnés par heure de temps en mouvement, la mesure habituelle de la vitesse à laquelle une montée a été grimpée : 1 000 m/h, c’est cent mètres toutes les six minutes. Derrière chaque ligne, une barre montre la montée de cette côte par rapport à la plus grande. Touchez une ligne pour voir cette montée ombrée sur les graphiques et tracée sur la trace sur la carte, où une pastille la nomme, « Montée 1 · 0,5–2,5 km » ; touchez de nouveau la ligne ou la pastille pour l’effacer. Un seul passage est mis en évidence à la fois, qu’il s’agisse d’un tronçon ou d’une montée.

Une montée est repérée comme le fait le profil de la feuille d’enregistrement pour celle où vous êtes : elle commence là où les 100 m de route suivants montent d’au moins 3 %, et elle se termine à son point haut une fois que la route est redescendue de 10 m en dessous, de sorte qu’un replat dans une longue montée ne la coupe pas en deux. Les montées de moins de 300 m, gagnant moins de 20 m ou ayant une pente moyenne inférieure à 3 % du pied au sommet ne sont pas listées. Les altitudes sont d’abord lissées sur 50 m, comme pour la puissance estimée, et les pauses ne comptent ni dans le temps ni dans le dénivelé.

### Revêtement

Un itinéraire lu depuis un fichier obtient son **Revêtement** de la même façon et pour la même raison : personne ne l’a jamais calculé, donc rien n’a jamais dit de quoi il est revêtu. À la première ouverture d’un tel itinéraire, sa trace est posée sur les tuiles de routage hors ligne et les parts sont lues sur les routes où elle tombe, puis conservées avec l’itinéraire pour n’être calculées qu’une fois. Les mêmes réserves valent : la région de routage doit être téléchargée, et une trace que la carte ne peut pas suivre le dit ; un itinéraire planifié ici n’est pas touché, car le routeur a déjà répondu. Les itinéraires enregistrés depuis un fichier avant l’existence de cette fonction sont rapprochés à la première ouverture.

Sous les montées, une barre **Revêtement** comme sur une fiche d’itinéraire : quelle part de la sortie était revêtue, non revêtue ou inconnue, avec les parts de pistes cyclables et de routes fréquentées à côté. La sortie n’a jamais été planifiée, l’appli le découvre donc après coup : elle pose la trace enregistrée sur les tuiles de routage hors ligne du téléphone et lit le revêtement sur les routes où elle tombe. Aucune trace ne quitte le téléphone pour cela. Il faut que la région de routage de la zone soit téléchargée ; tant qu’elle ne l’est pas, la section le dit. Une trace que la carte ne peut pas suivre, à travers un parc, sur un ferry ou par un raccourci, affiche « Impossible de caler la trace sur la carte » à la place, et le résultat, dans les deux cas, est conservé avec la sortie, pour n’être calculé qu’une fois. Une nouvelle tuile de routage donne une nouvelle chance à une sortie non rapprochée.

### Actions sur une sortie

- Le bouton nuage à droite de l’en-tête de la fiche envoie la sortie vers un service connecté.
- Le menu à côté : **Exporter la trace GPX**, **Exporter l’activité FIT**, **Poursuivre cette sortie**, **Renommer**, **Supprimer**.
- En bas : les deux mêmes exports et **Partager un lien**.

## Faire entrer des fichiers et des itinéraires

Les deux boutons à droite de l’en-tête de la fiche :

- **Importer un fichier** ouvre le sélecteur de fichiers du téléphone pour un fichier GPX, FIT ou TCX.
- Le bouton nuage propose **Importer depuis Strava** et **Importer depuis Ride with GPS**, quand ces services sont configurés.

Les deux sont décrits dans [importer et exporter](./import-and-export) et [Strava et Ride with GPS](./strava-and-ridewithgps).

## Voir aussi

- [Enregistrer une sortie](./recording-a-ride)
- [Capteurs et montre](./sensors-and-watch)
- [Importer et exporter](./import-and-export)
- [Partage](./sharing)
- [Strava et Ride with GPS](./strava-and-ridewithgps)
- [Planifier un itinéraire](./planning-a-route)
