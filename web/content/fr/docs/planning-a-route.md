---
title: Planifier un itinéraire
description: "Touchez des points sur la carte, choisissez un profil de vélo, comparez les variantes, lisez les statistiques d’altitude et de revêtement, puis enregistrez l’itinéraire dans votre bibliothèque."
order: 2
---

L’onglet Planifier transforme des touchers sur la carte en itinéraire à vélo, calculé sur votre téléphone partout où vous avez téléchargé les données de routage. Utilisez-le chaque fois que vous voulez décider d’une sortie à l’avance, la retoucher et la garder.

## Fixer le départ et l’arrivée

1. Ouvrez l’onglet **Planifier** et déplacez la carte là où vous voulez partir.
2. **Touchez la carte** pour fixer le départ. La feuille en bas indique « Touchez à nouveau la carte pour ajouter une arrivée. »
3. **Touchez à nouveau** pour le point suivant. Chaque toucher ajoute un point à la fin de l’itinéraire, et le dernier, l’arrivée, porte un drapeau. Pour placer plutôt un point au milieu, **touchez la ligne de l’itinéraire** à l’endroit voulu : le point se pose sur la ligne à cet endroit, et vous pouvez le faire glisser comme n’importe quel autre.
4. Velorki attend un instant après votre dernière modification, puis calcule. Pendant ce temps, la feuille affiche un indicateur de chargement et **Calcul de l’itinéraire…** ; puis les chiffres apparaissent.

Vous pouvez aussi partir d’un lieu plutôt que d’un toucher. Saisissez dans le champ de recherche en haut et choisissez un résultat, ou touchez une [halte sur la carte](./stops-on-the-map) ; tant que le plan est vide, la [fiche du lieu](./search#la-fiche-du-lieu) propose :

- **Itinéraire jusqu’ici** part de votre position jusqu’au lieu.
- **Partir d’ici** fait du lieu le premier point de l’itinéraire.

Avec un départ seulement, elle propose **Arrivée**. Une fois qu’un itinéraire est en cours de planification, la fiche propose **Ajouter comme étape**, qui insère le lieu dans l’itinéraire à l’endroit où il se trouve sur le trajet, et **Arrivée**, qui l’ajoute à la fin. Voir [recherche](./search) pour ce que le champ de recherche peut trouver.

## Marquer un lieu à côté de l’itinéraire

**Maintenez le doigt sur la carte** à un endroit qui mérite d’être retenu, et la feuille de point s’ouvre pour un lieu à cet endroit : une fontaine, une gare, un camping. L’itinéraire n’y passe pas. Le marqueur porte l’icône du type que vous choisissez, avec son nom à côté, et un toucher dessus rouvre la feuille.

Pour déplacer un point que vous avez déjà, **faites glisser son marqueur**. Sur une boucle fermée, faire glisser le marqueur de départ déplace les deux extrémités pour que la boucle reste fermée. Une modification ne recalcule que les tronçons voisins du point touché ; le reste de l’itinéraire reste tel quel.

## Sur l’itinéraire ou à côté

Chaque point est l’une de deux choses, et l’interrupteur en haut de sa feuille indique laquelle :

- **Sur l’itinéraire** : un point par lequel passe la sortie. Il porte un disque numéroté, l’arrivée un drapeau avec son numéro à côté, et le calculateur infléchit l’itinéraire pour le visiter.
- **À côté de l’itinéraire** : un lieu devant lequel passe la sortie. Il porte l’icône de son type, et l’itinéraire l’ignore.

Basculez un point sur **À côté de l’itinéraire** et il quitte l’itinéraire, qui est retracé sans lui ; le marqueur reste où il est. Basculez-le sur **Sur l’itinéraire** et il devient un point intermédiaire, à l’endroit de l’itinéraire où il se trouve, et l’itinéraire est retracé en passant par lui. Dans les deux cas, le nom, le type et la note le suivent.

## Modifier ou supprimer un point

Touchez un marqueur pour ouvrir sa feuille. De haut en bas :

- **Sur l’itinéraire** ou **À côté de l’itinéraire**, l’interrupteur ci-dessus,
- **Nom**, avec l’icône du type devant, rempli avec le nom du point ou, pour un point sur l’itinéraire qui n’en a pas, son numéro ; un numéro laissé tel quel ne nomme rien. Un lieu à côté de l’itinéraire s’ouvre avec un nom vide,
- **Catégorie** : une grille de tuiles, quatre rangées de quatre, toutes visibles à la fois quelle que soit la largeur : **Danger**, **Eau**, **Ravitaillement**, **Autre**, **Sommet**, **Point de vue**, **Abri**, **Commerce**, **Réparation vélo**, **Premiers secours**, **Toilettes**, **Camping**, **Hébergement**, **Parking**, **Transports** et **Changement de direction**. **Hébergement** désigne un lit plutôt qu’un emplacement : un hôtel, une auberge de jeunesse, une chambre d’hôtes. Un **Changement de direction** prend une **Direction** en dessous (gauche, droite, légèrement, franchement, rester à gauche ou à droite, tout droit, demi-tour) et devient une ligne de la feuille de route de l’itinéraire, de sorte que la bannière de virage et la voix l’annoncent à cet endroit ; un itinéraire importé avec une feuille de route s’ouvre avec ses virages écrits sous forme de points de ce type, prêts à être modifiés. **Changement de direction** n’est proposé que pour un point sur l’itinéraire : une indication sur une route que la sortie n’emprunte pas ne dit rien,
- **Remarque**,
- **Passer plus tôt** et **Passer plus tard**, qui échangent aussitôt le point avec son voisin dans l’ordre et laissent la feuille ouverte, si bien qu’on peut déplacer et nommer un point en une seule visite. Uniquement pour un point sur l’itinéraire ; un lieu à côté n’a pas de place dans l’ordre,
- **Supprimer le point**, pour les deux types,
- **OK**, qui applique l’interrupteur, le nom, le type et la note. Tirez la feuille vers le bas pour les laisser tels qu’ils étaient.

Un échange, une suppression, une bascule et un OK qui a changé quelque chose comptent chacun pour une étape de la pile d’annulation. Un point nommé sur l’itinéraire affiche son nom sur son marqueur à la place de son numéro, avec l’icône de son type à côté. Les détails sont enregistrés avec l’itinéraire et reviennent quand il est rouvert dans le planificateur ; sur un itinéraire ouvert depuis la bibliothèque, ils passent aussitôt dans la bibliothèque, tant que l’itinéraire n’a pas été recalculé depuis, de sorte qu’il n’y a pas d’Enregistrer à toucher pour un simple nom ou une simple note.

## Ce que devient chaque point dans un fichier exporté

Les deux types sont exportés, et un compteur de vélo les distingue aussi bien que le format le permet :

- **GPX** : chaque lieu à côté de l’itinéraire, et chaque point sur l’itinéraire ayant un nom ou une note, est écrit sous forme de `<wpt>` avec son type et sa note. Les points sur l’itinéraire forment aussi la liste des `<rtept>`, de sorte que le fichier peut être replanifié.
- **FIT** et **TCX** : les deux types deviennent des points de parcours sur le parcours, à côté des virages de la feuille de route. FIT a un type propre pour l’eau, la restauration, un danger, un sommet, les premiers secours, des toilettes et un camping ; TCX seulement pour l’eau, la restauration, un danger, un sommet et les premiers secours. L’hébergement, le parking et le transport n’ont de type dans aucun des deux et sortent comme des points de parcours génériques avec leur nom. Tout le reste sort comme un point de parcours générique avec son nom.
- Un point issu d’un fichier garde le mot que ce fichier employait pour lui. Réexportez-le sans changer son type et ce mot est réécrit, de sorte qu’une catégorie de montée, un sprint ou un repère de segment — des choses pour lesquelles Velorki n’a pas de type propre — survit à l’aller-retour. Changez le type et c’est le mot du nouveau type qui est écrit.

## Choisir le vélo

La rangée de pastilles sous le champ de recherche est le profil de vélo, et elle détermine quelles routes et quels chemins le calculateur préfère :

| Profil | À quoi il sert |
|---|---|
| **Rando** | le profil par défaut : un bon mélange de routes calmes et de pistes cyclables |
| **Route** | bitume, moins de détours, évite les revêtements dégradés |
| **Gravel** | à l’aise sur les chemins et les revêtements non goudronnés |
| **VTT** | sentiers et single track |
| **Direct** | le chemin le plus court, sans égard pour le confort |

Tous les profils sauf **Direct** sont ceux de BRouter, avec une seule modification de Velorki : il ne vous enverra pas à contresens dans une rue à sens unique ni sur un trottoir pour gagner un pâté de maisons. Changer de profil recalcule tout le plan, un itinéraire issu d’un fichier compris, et efface les variantes que vous aviez chargées ; **Annuler** rétablit l’itinéraire et le profil. Velorki garde le dernier profil choisi pour le prochain lancement.

## Un itinéraire issu d’un fichier

Un itinéraire ouvert depuis un fichier garde la ligne exacte du fichier, avec des points seulement à son départ, à son arrivée et aux lieux nommés de son tracé. Déplacer, ajouter ou supprimer un point ne recalcule que les tronçons voisins ; partout ailleurs, la ligne reste celle du fichier. Tant que l’itinéraire diffère du fichier, la ligne du fichier est dessinée en pâle dessous et une pastille au-dessus de la carte indique **Diffère du fichier** ; son bouton **Rétablir** remet l’itinéraire du fichier, en une seule étape que Annuler peut reprendre.

## La barre d’outils

La rangée de boutons dans la feuille d’itinéraire :

- **Annuler** reprend la dernière modification. Il n’y a pas de limite et pas de rétablissement. Ajouter, insérer, déplacer, supprimer et réordonner des points, **Inverser**, **Effacer**, changer de profil de vélo, **Rétablir**, fermer une boucle et prendre un autre chemin de retour sont tous annulables ; changer de variante et charger un itinéraire enregistré ne le sont pas.
- **Inverser** parcourt l’itinéraire dans l’autre sens.
- **Effacer** jette le plan. C’est aussi annulable.
- **Variantes** demande des alternatives (voir ci-dessous).
- **Boucle** ouvre la feuille de boucle intelligente, décrite dans [boucles](./loops).
- **Demander** ouvre l’[assistant](./assistant). Il n’est là que si la version communique avec un serveur Velorki.

Sous la rangée se trouve le bouton **Enregistrer** pleine largeur.

## Variantes

Velorki ne va pas chercher d’alternatives de lui-même, car chacune est un calcul d’itinéraire à part. Touchez **Variantes** et il demande jusqu’à quatre itinéraires pour les mêmes points.

Une rangée de pastilles apparaît alors au-dessus de la barre d’outils : **Principal**, **Var. 1**, **Var. 2**, **Var. 3**, chacune avec un point de couleur correspondant à sa ligne sur la carte. Toucher une pastille bascule instantanément, sans nouveau calcul, et dessine cette ligne par-dessus.

Les variantes sont des itinéraires entiers tracés par le calculateur, donc sur un itinéraire issu d’un fichier elles remplacent la ligne du fichier ; **Annuler** la rétablit. Il en revient souvent moins de quatre ; vous obtenez ce que le calculateur a trouvé. S’il n’en trouve aucune, Velorki dit « Aucune variante disponible. » Modifier un point de passage ou changer de profil de vélo efface les variantes, il faut donc les redemander ensuite.

## Lire l’itinéraire

L’en-tête de la feuille affiche quatre chiffres : **Distance**, **Montée**, **Descente** et **Durée est.** La durée estimée vient de la vitesse typique du profil de vélo choisi, et non d’un serveur, et ne tient pas compte de vos pauses café.

La feuille défile à n’importe quelle hauteur ; tirez sa poignée ou son titre vers le haut pour plus de place, ou n’importe où sur elle quand il n’y a rien à faire défiler. Tirée tout en bas, elle se replie dans la barre de navigation et ne laisse que la poignée au-dessus des onglets, de sorte que la carte est libre ; tirez la poignée vers le haut pour la ramener.

### Profil altimétrique

Le graphique **Profil altimétrique** trace la hauteur en fonction de la distance. Touchez-le et faites glisser le doigt dessus : une valeur apparaît à côté de la légende, sous la forme `12,3 km · 340 m`, et suit votre doigt. Levez le doigt et elle disparaît. Un itinéraire sans données d’altitude indique « Aucune donnée d’altitude pour cet itinéraire. »

### Revêtement

La barre **Revêtement** est une barre empilée unique de trois parts dont la somme fait tout l’itinéraire, **Revêtu**, **Non revêtu** et **Inconnu**, avec une légende de pourcentages en dessous. Deux autres entrées de la légende, **Pistes & bandes** et **Routes fréquentées**, recoupent les trois premières au lieu de s’y ajouter : elles indiquent quelle part de l’itinéraire suit des pistes cyclables, des chemins signalés pour les vélos, des rues cyclables, ou une bande ou piste cyclable le long de la route, et quelle part suit une grande route. Pour un itinéraire dont tout n’est pas du calculateur, avec une ligne de fichier dedans, toute la ligne est superposée aux données de routage pour établir les chiffres, ce qui demande que la région soit téléchargée.

## L’enregistrer

1. Touchez **Enregistrer**.
2. La boîte de dialogue **Enregistrer l’itinéraire** propose un nom, soit celui sous lequel il a déjà été enregistré, soit **Itinéraire du 17 sept. 2026** avec la date du jour.
3. Saisissez votre propre nom, ou laissez celui-ci, et touchez **Enregistrer**.

Vous obtenez « Itinéraire enregistré », et l’itinéraire est dans **Bibliothèque → Itinéraires**. Enregistrer un itinéraire déjà enregistré met à jour cette même entrée au lieu d’en créer une seconde.

## Quand le calcul échoue

- **« Cet itinéraire nécessite des tuiles de routage absentes de cet appareil. »** s’affiche à la place des chiffres quand votre téléphone n’a pas de données de routage pour la zone et aucun serveur de routage de repli. Le bouton en dessous compte les tuiles et leur taille, par exemple **Télécharger 3 tuiles (412 Mo)**, et ouvre l’écran hors ligne avec exactement ces tuiles sélectionnées. Voir [cartes et routage hors ligne](./offline-maps-and-routing).
- **« Aucun serveur de routage configuré, définissez-en un dans Réglages → Avancé. »** est une carte sous les pastilles de vélo, et signifie que cette version n’a aucune adresse de serveur.
- Tout le reste s’affiche sous la forme **Échec du calcul :** suivi de la raison.

## Voir aussi

- [Boucles](./loops)
- [Recherche](./search)
- [Cartes et routage hors ligne](./offline-maps-and-routing)
- [Bibliothèque](./library)
- [Navigation guidée](./navigation)
