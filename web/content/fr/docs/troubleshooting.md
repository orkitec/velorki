---
title: Dépannage
description: "Solutions aux problèmes courants : pas de position, pas d’itinéraire, la bannière de tuiles manquantes, une voix muette sur iOS, des téléchargements bloqués et des liens qui ne s’ouvrent pas."
order: 18
---

Les problèmes les plus fréquents, et que faire pour chacun. Si le vôtre n’y figure pas, la dernière section explique comment le signaler.

## Velorki ne trouve pas ma position

Les symptômes sont « Pas encore de position. », un bouton de localisation qui ne fait rien, ou « Activez la localisation ou touchez la carte pour placer le départ. »

1. **L’autorisation a-t-elle été refusée ?** Velorki demande avec sa propre boîte de dialogue, **Afficher votre position ?**, avant celle du système. Si vous avez répondu **Plus tard**, touchez à nouveau le bouton de localisation et répondez **Continuer**.
2. **Est-elle désactivée pour Velorki ?** « La localisation est désactivée pour Velorki. Activez-la dans les réglages du système. » s’accompagne d’une action **Réglages** qui vous y mène directement. Accordez « Lorsque l’app est active » ou « Pendant l’utilisation de l’app ».
3. **Les services de localisation sont-ils désactivés sur le téléphone ?** « Les services de localisation sont désactivés sur cet appareil. » concerne le téléphone, pas Velorki. L’action **Réglages** ouvre le bon endroit.
4. **À l’intérieur, ou à peine allumé ?** « Pas encore de position. » signifie souvent que le téléphone n’a pas encore de signal GPS. Sortez et laissez-lui une demi-minute.

Velorki n’a jamais besoin de la localisation en arrière-plan. « Lorsque l’app est active » suffit, y compris pour enregistrer une sortie.

## Aucun itinéraire n’apparaît

**« Cet itinéraire nécessite des tuiles de routage absentes de cet appareil. »** Votre téléphone n’a pas de données de routage pour la zone et il n’y a pas de serveur de routage de secours. Touchez le bouton, qui compte les tuiles et leur taille, et téléchargez-les. Voir [cartes hors ligne et routage](./offline-maps-and-routing).

**« Aucun serveur de routage configuré, définissez-en un dans Réglages → Avancé. »** Cette version ne contient aucune adresse de serveur. Téléchargez les tuiles de routage de l’endroit où vous êtes et calculez l’itinéraire sur le téléphone.

**Réglages → Avancé → Routage est sur « Sur l’appareil uniquement ».** Dans ce cas, Velorki n’interrogera jamais de serveur, par conception. Passez sur **Automatique** ou téléchargez les tuiles.

**« Échec du calcul : » suivi d’une raison.** Le plus souvent, le serveur était injoignable. Réessayez, et vérifiez qu’un point de passage n’est pas tombé en mer ou sur une autoroute où les vélos sont interdits. Déplacer le point fautif de quelques mètres sur une vraie route règle généralement le problème.

## La bannière de tuiles manquantes ne disparaît pas

La bannière s’affiche dans le planificateur chaque fois que l’itinéraire traverse une zone dont la tuile de routage n’est pas sur le téléphone. Velorki ne calcule jamais un itinéraire sur une couverture partielle, car le routeur traiterait la tuile manquante comme une terre vide et renverrait discrètement un itinéraire faux.

1. Touchez le bouton de la bannière. Il ouvre **Données de routage hors ligne** avec exactement les tuiles dont l’itinéraire a besoin déjà sélectionnées.
2. Téléchargez-les. Les tuiles pèsent de 125 à 250 Mo chacune, soyez donc en Wi-Fi.
3. Quand une tuile arrive, le planificateur recalcule tout seul et la bannière est remplacée par les chiffres de l’itinéraire.

Si les tuiles dont vous avez besoin indiquent **Mise à jour : nouvelle version requise**, mettez d’abord l’app à jour ; la boîte de dialogue en explique la raison.

## La voix ne dit rien

Vérifiez dans cet ordre :

1. **Réglages → Navigation → Indications de direction** activées, et **Voix** activée. La voix est grisée tant que les indications de virage sont désactivées.
2. **Le bouton de sourdine de la bannière de virage.** Il coupe la voix pour le reste de cette sortie seulement. Touchez-le à nouveau.
3. **Suivez-vous un itinéraire ?** Le guidage nécessite un itinéraire choisi sous **Itinéraire suivi** dans l’onglet Rouler, et une sortie qui s’enregistre réellement.
4. **Le volume du téléphone et son interrupteur de mode silencieux.**

### Sur un iPhone

Si Velorki affiche **De meilleures voix à télécharger**, le téléphone n’a que la voix compacte de votre langue. Suivez les étapes de la carte : **Réglages → Accessibilité → Contenu énoncé → Voix → votre langue → touchez le nuage** à côté d’une voix Améliorée ou Premium. Velorki utilise ensuite tout seul la meilleure voix du téléphone.

Si la voix choisie est marquée **Nécessite Internet**, elle est générée sur un serveur : sans réseau, l’indication n’est pas prononcée ou arrive en retard. Choisissez pour vos sorties une voix sans cette mention. Elles sont masquées tant que **Afficher les voix en ligne** n’est pas activé en bas de la liste des voix.

« Aucune voix n’est installée pour votre langue. » signifie que le téléphone n’a rien pour parler ; ajoutez une voix dans les réglages de synthèse vocale ou de Contenu énoncé du téléphone.

## Un téléchargement est bloqué ou échoue

- **Les téléchargements ne se déroulent que lorsque l’app est ouverte.** Laissez Velorki au premier plan pour une grosse tuile. S’il s’arrête, la partie reçue est conservée et la tentative suivante reprend à partir de là.
- **« Le téléchargement a échoué : »** suivi d’une raison. Touchez à nouveau la tuile pour réessayer. Un téléchargement repris ne repart pas de zéro.
- **« La liste des tuiles n’a pas pu être chargée : »** signifie que le miroir est injoignable. **Réessayer** est affiché à l’écran.
- **Vérifiez l’espace libre sur le téléphone.** Une tuile de routage de 250 Mo demande 250 Mo, et la zone de carte s’y ajoute.
- **Annulez et relancez** avec le bouton de fermeture de l’en-tête de progression si un téléchargement est manifestement bloqué.
- Velorki ne sait pas distinguer le Wi-Fi des données mobiles : il avertit plutôt que de bloquer. Lancez vous-même les gros téléchargements en Wi-Fi.

## Un lien de partage ne s’ouvre pas dans l’app

- **Le lien a plus d’un an.** Les éléments partagés sont supprimés automatiquement après 365 jours, et la page indique alors « introuvable ». Demandez un lien récent.
- **L’app n’est pas installée sur ce téléphone.** La page fonctionne quand même dans le navigateur : la carte, les chiffres et **Télécharger le GPX**.
- **« Ouvrir dans Velorki » n’a rien fait.** Téléchargez plutôt le GPX depuis la page et ouvrez-le avec Velorki ; il arrive sur le même écran d’import. Un lien expiré ou mal saisi est ignoré silencieusement, sans message d’erreur.

## Un fichier ne s’importe pas

Velorki lit les formats GPX, FIT et TCX, et se fie au contenu des octets, pas au nom du fichier.

| Message | Signification |
|---|---|
| « Ce n’est pas un fichier GPX, FIT ou TCX. » | le contenu n’est d’aucun de ces trois formats, quel que soit le nom |
| « Impossible de lire ce fichier. » | le fichier est de l’un des trois formats mais endommagé |
| « Ce fichier ne contient aucun point de trace. » | un fichier vide, ou un GPX qui ne contient que des points de passage |
| « Impossible d’ouvrir ce fichier. » | le système n’a pas voulu transmettre le fichier |

Si un fichier s’importe sous le mauvais type, basculez **ENREGISTRER COMME** entre **Itinéraire** et **Sortie** sur l’écran d’import avant d’enregistrer. Les parcours FIT sont considérés comme des sorties à cause du fonctionnement de leurs horodatages.

## L’enregistrement s’est arrêté tout seul

Sur Android, répondez **Ouvrir les réglages** à **Continuer l’enregistrement en arrière-plan**, autorisez-y Velorki à utiliser la batterie sans restriction et accordez l’autorisation de notification ; ce sont elles qui empêchent le système de tuer l’enregistrement pendant que le téléphone est en veille. Sur les deux plateformes, la trace est écrite en continu : si l’app a été tuée, vous voyez **Sortie non terminée** au lancement suivant, avec **Reprendre**, **Terminer** et **Supprimer**. Voir [enregistrer une sortie](./recording-a-ride).

## Un capteur Bluetooth est introuvable

1. **Réveillez le capteur.** Une ceinture n’émet qu’au contact de la peau, un capteur de cadence que si le pédalier tourne. L’écran le dit : « Rien pour l’instant. Réveillez le capteur : mettez la ceinture ou faites tourner le pédalier. »
2. **Activez le Bluetooth.** « Activez le Bluetooth pour trouver vos capteurs. » concerne la radio du téléphone, pas le capteur.
3. **Accordez l’autorisation.** « Velorki n’a pas été autorisé à utiliser le Bluetooth. » signifie qu’elle a été refusée. iOS la demande la première fois que vous touchez **Rechercher**, et seulement alors.
4. **Libérez le capteur.** Ces capteurs ne servent qu’un appareil à la fois : un compteur GPS ou une autre app qui tient le vôtre empêche Velorki de le voir.
5. **Relancez la recherche.** Une recherche dure une quinzaine de secondes et ne liste que les appareils parlant les profils standard de fréquence cardiaque, de vitesse et cadence, ou de puissance.

Un capteur associé qui indique **Non connecté** est hors de portée, en veille ou à plat. Velorki continue d’essayer pendant qu’une sortie s’enregistre ou que l’écran **Capteurs Bluetooth** est ouvert. Voir [capteurs et montre](./sensors-and-watch).

## La montre ne se connecte pas

- **Il n’y a pas d’interrupteur Apple Watch.** Il n’apparaît dans **Réglages → Capteurs** que sur un iPhone auquel une montre est associée.
- **L’app de la montre n’est pas sur la montre.** Elle est livrée dans l’app iPhone ; si elle n’est pas arrivée toute seule, installez Velorki depuis l’app **Watch** de l’iPhone.
- **La sortie est en cours mais la montre ne mesure rien.** Une sortie lancée depuis le téléphone ouvre l’app de la montre et la fait mesurer toute seule. Si l’app de la montre affiche quand même deux tirets, touchez-y **Mesurer la FC** ; une ligne orange sous le cœur indique ce qui a échoué, si la montre le sait.
- **La montre n’affiche aucun pouls.** La montre demande l’autorisation de lire votre fréquence cardiaque la première fois qu’une séance y démarre. Si elle a été refusée, accordez-la dans les réglages de confidentialité de la montre.
- **« Démarrer » sur la montre ne fait rien sur le téléphone.** Si Velorki est en arrière-plan, la sortie démarre et le téléphone affiche une notification à toucher. Une app que vous avez fermée d’un balayage ne peut pas être réveillée par la montre, c’est une règle d’iOS : la montre affiche « Le téléphone n’a pas répondu », et ouvrir Velorki sur le téléphone règle le problème.
- **La trace ne commence qu’une fois le téléphone ouvert.** iOS ne donne aucun GPS à une app réveillée en arrière-plan tant qu’elle n’a pas été ouverte une fois. Touchez la notification, ou ouvrez Velorki, et la trace démarre ; le téléphone peut ensuite être verrouillé.

## Pas de fréquence cardiaque depuis Santé

- **L’interrupteur est désactivé.** **Apple Santé**, ou **Health Connect** sur Android, doit être activé dans **Réglages → Capteurs**. Rien n’est lu tant qu’il est désactivé.
- **L’accès a été refusé.** « Velorki n’a pas reçu l’accès à vos données de santé. » laisse l’interrupteur désactivé. Réactivez-le et autorisez la fréquence cardiaque, ou accordez-la dans l’app de santé elle-même.
- **Rien n’a enregistré de fréquence cardiaque.** Velorki lit seulement ce qui se trouve déjà dans le magasin de données : sans montre ni app qui y dépose un pouls, il n’y a rien à lire.
- **Elle arrive en retard.** Le magasin est interrogé toutes les cinq secondes, ou toutes les trente avec l’économie de batterie activée, et les trous sont comblés une dernière fois à l’enregistrement de la sortie. Une ceinture ou une montre qui transmet directement est toujours plus rapide.

## Une fonction Plus est absente

- **« Non disponible dans cette version »** sur une ligne de connexion, ou sur la page d’abonnement, signifie que cette copie de Velorki a été compilée sans les clés de ce service ou de ce store. C’est l’aspect d’une version compilée par vos soins.
- **Le bouton Demander ou le bouton Partager un lien est absent** dans une version sans serveur Velorki configuré.
- **Tout le reste** devrait indiquer « … fait partie de Velorki Plus » et proposer la page d’abonnement. Si vous avez un abonnement et que ce n’est pas le cas, touchez **Restaurer les achats** dans **Réglages → Abonnement**.

## Signaler un bug

**Réglages → À propos → Signaler un problème** ouvre le suivi des tickets, ou allez directement sur [github.com/orkitec/velorki/issues](https://github.com/orkitec/velorki/issues).

Un bon rapport contient :

1. ce que vous avez fait, étape par étape, et ce qui s’est passé au lieu de ce que vous attendiez ;
2. le téléphone et la version du système d’exploitation ;
3. la version de Velorki, dans **Réglages → À propos** ;
4. l’endroit où cela s’est produit, si la carte ou le routage sont en cause, car beaucoup de problèmes sont propres à un coin des données cartographiques ;
5. une capture d’écran, qui vaut généralement tout ce qui précède.

Velorki n’a pas de rapport de plantage et ne nous envoie rien de lui-même : un rapport de votre part est donc le seul moyen pour nous d’avoir connaissance d’un problème.

## Voir aussi

- [Cartes hors ligne et routage](./offline-maps-and-routing)
- [Navigation guidée](./navigation)
- [Enregistrer une sortie](./recording-a-ride)
- [Capteurs et montre](./sensors-and-watch)
- [Import et export](./import-and-export)
- [Premiers pas](./getting-started)
