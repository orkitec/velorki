---
title: Capteurs et montre
description: "Fréquence cardiaque, cadence et puissance depuis un capteur Bluetooth, une Apple Watch ou l'app santé du téléphone : réglez-les une fois, elles sont conservées avec chaque sortie."
order: 18
---

Velorki peut afficher votre fréquence cardiaque, votre cadence de pédalage et votre puissance pendant l'enregistrement, puis conserver les trois avec la sortie. Les mesures viennent d'un capteur Bluetooth, d'une Apple Watch ou de l'app santé du téléphone ; tout est gratuit et tourne sur le téléphone.

Rien de tout cela n'est actif tant que vous ne l'avez pas activé. Quand toutes les sources sont désactivées, Velorki ne demande rien au système d'exploitation et aucun écran ne mentionne de capteur.

## Ce que vous pouvez mesurer

| Source | Ce qu'elle fournit | Ce qu'il faut |
|---|---|---|
| Capteur Bluetooth | fréquence cardiaque, cadence, vitesse de la roue, puissance | le capteur, associé une fois dans Velorki |
| Apple Watch | fréquence cardiaque, et la sortie à votre poignet | un iPhone auquel une montre est associée |
| Apple Santé ou Health Connect | fréquence cardiaque écrite sur le téléphone par autre chose | l'app santé du téléphone, et un réglage à activer |

Quand deux sources signalent la même mesure en même temps, la montre l'emporte sur un capteur Bluetooth, et un capteur Bluetooth l'emporte sur l'app santé. Une mesure est considérée comme actuelle pendant dix secondes, et quand la source prioritaire ne donne plus signe de vie, la suivante prend le relais d'elle-même : une ceinture oubliée à la maison n'est donc simplement pas là.

## Activer une source

Tout se trouve dans **Réglages → Capteurs**, juste sous **Enregistrement** :

- **Apple Santé** sur un iPhone, **Health Connect** sur Android, avec la ligne « Lit la fréquence cardiaque que d’autres apps enregistrent dans Santé, comme l’app Exercice de la montre. Interrogé toutes les quelques secondes, donc avec du retard ; une ceinture cardio ou l’app Velorki pour montre prend le relais dès qu’elle transmet ». L'activer est la seule action dans Velorki qui peut déclencher la demande d'autorisation d'accès aux données de santé. Si vous la refusez, Velorki affiche « Velorki n’a pas reçu l’accès à vos données de santé. » et laisse le réglage désactivé.
- **Enregistrer les sorties dans Santé**, juste dessous : « Chaque sortie terminée est ajoutée à Santé comme un entraînement vélo avec son début, sa fin et sa distance ». Vous pouvez le désactiver séparément. Il ne fait rien tant que le réglage au-dessus est désactivé.
- **Apple Watch**, avec la ligne « L’app Velorki pour montre : mesure votre pouls en direct pendant toute la sortie, affiche la sortie et propose Démarrer, Pause et Terminer au poignet. Consomme la batterie de la montre ». La ligne n'apparaît que sur un iPhone auquel une montre est associée. **Mettre le capteur en veille en pause**, juste dessous, est expliqué dans [la batterie au poignet](#la-batterie-au-poignet).
- **Capteurs Bluetooth**, avec la ligne « Ceintures cardio, capteurs de vitesse et de cadence, capteurs de puissance », ou « 1 capteur associé » dès que vous en avez un. Cette ligne ouvre un écran à part.

## Capteurs Bluetooth

### Associer un capteur

1. Réveillez le capteur : mettez la ceinture, ou faites tourner les manivelles. La plupart des capteurs ne signalent rien tant qu'on ne s'en sert pas.
2. Ouvrez **Réglages → Capteurs → Capteurs Bluetooth** et touchez **Rechercher**. Sur un iPhone, l'écran vous prévient avant que vous touchiez : « iOS demande l’accès au Bluetooth lors de la première recherche. » Une recherche dure une quinzaine de secondes.
3. Sous **Trouvés**, touchez le capteur que vous reconnaissez. Chaque ligne indique son nom, de petites icônes pour ce qu'il mesure et la puissance de son signal en dBm, le plus fort en haut.
4. Velorki se connecte une fois pour demander à l'appareil ce qu'il offre vraiment, le range sous **Associés**, puis le lâche.

Tant que cet écran est ouvert, vos capteurs associés sont connectés : chaque ligne montre donc ce que le capteur dit à l'instant, au lieu de **Connecté**, **Connexion…** ou **Non connecté**. Quand vous quittez l'écran, ils sont déconnectés, sauf si une sortie est en cours d'enregistrement. **Oublier**, dans le menu à droite d'une ligne associée, supprime un capteur.

### Ce que Velorki sait associer

Les trois profils cyclistes standard, ce que parle presque tout ce qui se vend comme capteur de vélo :

- les **ceintures cardio** et brassards,
- les **capteurs de vitesse et de cadence**, sur la roue, sur le pédalier, ou un seul appareil qui fait les deux,
- les **capteurs de puissance**, dont les compteurs de pédalier donnent aussi une cadence : un capteur de puissance rend donc un capteur de cadence séparé inutile.

Un appareil qui ne parle aucun de ces trois profils n'est pas proposé. Velorki s'associe à des capteurs, pas à des compteurs de vélo : un compteur est un autre genre d'appareil et n'est pas connecté ici.

### Circonférence de la roue

Un capteur de vitesse compte les tours de roue : il faut donc dire à Velorki quelle distance fait un tour. Le champ **Circonférence de roue** apparaît en bas de l'écran dès qu'un capteur associé signale une vitesse, avec l'indication « Millimètres par tour de roue. 2105 correspond à un pneu 700x25c. » et **mm** après le nombre.

Tant qu'un capteur de roue émet, sa vitesse remplace la vitesse GPS sur la fiche Rouler, et c'est tout l'intérêt : une roue est juste à vitesse de marche, sous les arbres et dans un tunnel, là où le GPS ne l'est pas. Rien d'autre dans la sortie ne s'en sert.

### Quand un capteur n'est pas trouvé

- **« Rien pour l’instant. Réveillez le capteur : mettez la ceinture ou faites tourner le pédalier. »** Une ceinture sans contact avec la peau et un pédalier à l'arrêt sont invisibles. Bougez, puis relancez la recherche.
- **« Activez le Bluetooth pour trouver vos capteurs. »** La radio du téléphone est éteinte.
- **« Velorki n'a pas été autorisé à utiliser le Bluetooth. »** L'autorisation a été refusée. Accordez-la à Velorki dans les réglages du téléphone et relancez la recherche.
- **Le capteur parle à autre chose.** Ces capteurs ne servent qu'un appareil à la fois. Fermez l'autre app, ou éteignez le compteur.
- **Un capteur associé qui indique Non connecté** est hors de portée, en veille ou à plat. Velorki continue d'essayer pendant l'enregistrement d'une sortie ou tant que cet écran est ouvert, en attendant un peu plus longtemps après chaque tentative.

## Apple Watch

L'app de la montre est un écran et un capteur, jamais un second enregistreur. Le téléphone enregistre la sortie ; la montre envoie ce qu'elle mesure et ce que vous touchez, et affiche ce que le téléphone lui renvoie.

### Installer l'app de la montre

L'app Velorki de la montre est livrée dans l'app de l'iPhone. Elle arrive toute seule sur la montre si celle-ci installe automatiquement les apps compagnons ; sinon, ouvrez l'app **Watch** sur l'iPhone et installez Velorki depuis la liste des apps disponibles. Activez ensuite **Apple Watch** dans **Réglages → Capteurs** ; cela demande aussi, une fois, l'autorisation d'envoyer des notifications, pour celle décrite sous les boutons. La première fois qu'une séance démarre sur la montre, celle-ci demande l'autorisation de lire votre fréquence cardiaque. Cette demande vient de la montre, pas du téléphone.

### Ce qu'affiche la montre

- Votre **fréquence cardiaque** en grands chiffres, avec le cœur qui bat pendant la mesure ; deux tirets quand rien n'est mesuré, et la dernière valeur estompée quand la sortie est en pause. Le cœur et les boutons prennent la couleur d'accent que vous avez choisie dans l'app.
- Une ligne orange quand quelque chose ne va pas : accès à Santé refusé, séance que la montre n'a pas voulu lancer, ou téléphone qui n'a pas répondu.
- Pendant une sortie, sa distance, le chronomètre écoulé et la vitesse, et **En pause** quand elle est en pause. Le téléphone met tout en forme : c'est donc dans vos unités et votre langue.
- Le prochain virage avec son icône, son nom et la distance qui reste, comme sur l'écran verrouillé, en orange quand vous êtes hors itinéraire ; une fois qu'un chemin de retour ou un nouvel itinéraire est calculé, ses virages.
- Une tape au poignet quand une indication de virage est due, et une quand vous quittez l'itinéraire. Une montre qui a dormi pendant trois virages tape une fois, pas trois.

Les mots propres à la montre, c'est-à-dire les boutons et les deux notes de bas d'écran, restent en anglais quelle que soit la langue du téléphone. Il n'y a pas encore de complications.

### Ce que font les boutons

| Bouton | Ce qu'il fait |
|---|---|
| **Démarrer** | démarre l'enregistrement sur le téléphone |
| **Pause**, **Reprendre** | mettent la sortie en pause et la reprennent, comme sur le téléphone |
| **Terminer** | arrête l'enregistrement ; « Après « Terminer », enregistrez la sortie sur le téléphone. » |
| **Arrêter la FC** | arrête la mesure sur la montre pendant que la sortie continue |
| **Mesurer la FC** | la relance, ou la démarre pour une sortie dans laquelle l'app de la montre a été ouverte en retard |

Quand une sortie démarre sur le téléphone, l'app de la montre s'ouvre toute seule et commence à mesurer : il n'y a rien à toucher au poignet. Dans l'autre sens, **Démarrer** sur la montre démarre l'enregistrement sur le téléphone et ouvre son onglet **Rouler**. Un téléphone dans votre poche, avec Velorki en arrière-plan, reçoit une notification, « Sortie démarrée depuis votre montre », et la toucher ouvre l'app ; cela compte, car iOS ne donne aucun GPS à une app réveillée en arrière-plan tant qu'elle n'a pas été ouverte une fois, et la trace ne commence donc qu'à ce moment. Une app que vous avez fermée complètement ne peut pas du tout être réveillée par la montre, c'est une règle d'iOS ; après quelques essais, la montre affiche « Le téléphone ne répond pas. Ouvrez Velorki sur le téléphone et réessayez. » Une sortie que vous terminez depuis le poignet est enregistrée comme n'importe quelle autre : l'enregistrement s'arrête, et la fiche d'enregistrement vous attend sur le téléphone la prochaine fois que vous le regardez.

### La batterie au poignet

Mesurer la fréquence cardiaque pendant des heures est ce qui coûte à la montre sa journée. La mesure tourne pendant toute la sortie, pauses comprises : une app de montre qui cesse de mesurer est mise en veille par watchOS en moins d'une minute et n'entend plus rien du téléphone ; la garder éveillée est donc ce qui fait arriver le pouls. Le téléphone n'enregistre aucun pouls pendant que la sortie est en pause. Pour les sorties avec beaucoup d'arrêts, **Mettre le capteur en veille en pause**, sous le réglage Apple Watch dans les Réglages, fait arrêter la mesure à chaque pause. Le compromis : le capteur se repose à chaque arrêt, mais le téléphone doit réveiller la montre quand vous repartez, le premier pouls après chaque arrêt prend un moment, et si le réveil échoue, le pouls manque jusqu'à ce que le téléphone réessaie. Laissez-le désactivé pour un pouls ininterrompu. Si la montre se tait pendant trois quarts de minute en pleine sortie, le téléphone relance son app tout seul. **Arrêter la FC** arrête la mesure sans toucher à la sortie. La note en bas de l'écran dit le reste : « Avec le mode économie d’énergie, dans les réglages de la montre, la batterie tient toute une longue sortie. » Désactiver **Apple Watch** dans les Réglages met aussi fin à une séance encore en cours.

## Apple Santé et Health Connect

Cette source est la fréquence cardiaque que votre téléphone connaît déjà : ce qu'une Apple Watch a écrit via sa propre séance d'entraînement, ou ce qu'une autre app a mis dans la base. C'est la plus lente et la moins en direct des trois, et une ceinture ou une montre qui émet directement prend aussitôt le relais.

### Ce qui est lu et ce qui est écrit

- **Lu** : la fréquence cardiaque, et rien d'autre. Pendant l'enregistrement d'une sortie, Velorki demande de nouveaux échantillons à la base toutes les cinq secondes, ou toutes les trente secondes avec l’**Économiseur de batterie** activé.
- **Complété après coup** : à l'enregistrement de la sortie, les échantillons de la base complètent les points de la trace qui n'ont pas de fréquence cardiaque, tant qu'un échantillon se trouve à moins d'une demi-minute du point, et les chiffres de la sortie sont recalculés. Un point qui a reçu une mesure en direct d'une ceinture ou d'une montre garde celle-ci.
- **Écrit** : une séance de vélo par sortie, avec son départ, son arrivée et sa distance, et seulement si **Enregistrer les sorties dans Santé** est activé. Chaque sortie n'est écrite qu'une fois. Réglage désactivé, Velorki ne fait que lire.

## Où apparaissent les chiffres

### Pendant la sortie

Une troisième rangée de chiffres apparaît sur la fiche Rouler avec ce qui a été signalé pendant la sortie : **Fréq. cardiaque** avec la **FC moy.** de la sortie en dessous, **Cadence** et **Puissance** ; une montre seule ajoute donc une tuile, et aucun capteur n'en ajoute aucune. Un capteur qui se tait garde sa tuile, estompée et marquée d'un lien brisé, jusqu'à la fin de la sortie. Sur un iPhone, le pouls rejoint les chiffres de la carte de l'écran verrouillé et de la Dynamic Island.

### Sur une sortie enregistrée

La fiche d'une sortie dans la [bibliothèque](./library) s'enrichit de ce que cette sortie contient réellement :

- **FC moy.**, **FC max**, **Cadence moy.** et **Puiss. moy.** parmi les chiffres, chacun seulement si la sortie le contient,
- un graphique de **Fréquence cardiaque** sous le graphique de vitesse, que vous pouvez faire glisser pour lire la valeur à n'importe quelle distance.

Le tableau des **Tronçons** ne change pas : **Tronçon**, **En mouvement**, **Moy.** et **Montée**, sans colonnes de capteurs. Une sortie importée d'un fichier GPX, FIT ou TCX apporte avec elle sa fréquence cardiaque, sa cadence et sa puissance, et les montre de la même façon.

## Ce qui est stocké, et ce qui quitte le téléphone

Les mesures font partie de la sortie : une fréquence cardiaque, une cadence et une puissance sur chaque point de la trace, et les moyennes et la fréquence cardiaque maximale parmi ses chiffres. Elles restent dans le stockage propre de Velorki sur le téléphone, avec la trace.

Rien n'est envoyé automatiquement. Un export GPX, FIT ou TCX emporte les valeurs avec la trace : une sortie que vous exportez ou envoyez à Strava ou Ride with GPS arrive donc complète. L'échange avec Apple Santé ou Health Connect se fait sur le téléphone. Voir [la confidentialité sur le téléphone](./privacy-on-the-phone) pour le tableau complet.

## Voir aussi

- [Enregistrer une sortie](./recording-a-ride)
- [Bibliothèque](./library)
- [Réglages et apparence](./settings-and-appearance)
- [Confidentialité sur le téléphone](./privacy-on-the-phone)
- [Dépannage](./troubleshooting)
