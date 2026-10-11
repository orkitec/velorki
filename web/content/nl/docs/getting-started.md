---
title: Aan de slag
description: Installeer Velorki, leer de vier tabbladen kennen, zie welke toestemmingen de app vraagt en waarom, en stel je eenheden in. Een account is niet nodig.
order: 1
---

Velorki is een gratis, open-source fietsrouteplanner en ritrecorder voor iPhone en Android, gebouwd op gegevens van OpenStreetMap. Deze pagina gaat over de eerste tien minuten: de installatie, wat de app vraagt, hoe hij is ingedeeld, en de ene instelling die de meeste fietsers meteen willen aanpassen.

## Wat je nodig hebt

- Een iPhone met iOS 15 of nieuwer, of een Android-telefoon met Android 8.0 of nieuwer.
- Geen account. Velorki heeft geen registratie, geen login en geen wachtwoord. Er wordt niets over jou op een server bewaard.
- Geen verbinding, zodra je een gebied hebt gedownload. Plannen, routeren, plaatsen zoeken, navigeren en opnemen draaien allemaal op de telefoon.

## Installeren

1. Installeer Velorki uit de App Store of Google Play, net als elke andere app.
2. Open de app. Er is geen registratiescherm en geen rondleiding om door te klikken; de app opent op de kaart.

Velorki is open source. Bouw je hem liever zelf, of draai je je eigen servers voor de onderdelen die er een gebruiken, dan vind je de code en de instructies op [github.com/orkitec/velorki](https://github.com/orkitec/velorki).

## De eerste keer openen

Velorki opent op het tabblad **Plannen**, met een wereldkaart. Er is nog niets gedownload en er is nog geen toestemming gevraagd.

Een goede eerste sessie:

1. Schuif de kaart naar waar je fietst en zoom in door te knijpen.
2. Tik op de kaart om een start te kiezen en tik nog eens om een bestemming toe te voegen. Binnen een ogenblik verschijnt er een route.
3. Tik op de downloadknop rechts op de kaart (**Offline gegevens**) en download het gebied, zodat de kaart en de routering blijven werken als het bereik dat niet doet. Zie [offline kaarten en routering](./offline-maps-and-routing) voor wat de twee downloads zijn en hoe groot ze worden.
4. Stel je eenheden in onder **Instellingen → Weergave → Eenheden** als de app verkeerd heeft gegokt.

## De toestemmingen die de app vraagt, en waarom

Velorki vraagt niets bij het opstarten. Elke toestemming wordt gevraagd op het moment dat hij voor het eerst nodig is, en elke toestemming wordt uitgelegd voordat het systeemvenster verschijnt.

### Locatie

Gevraagd de eerste keer dat je op **Mijn positie tonen** tikt, een rit start of om een rondje vanaf je positie vraagt.

Velorki toont eerst een eigen venster met de titel **Je positie tonen?**: "Velorki gebruikt je locatie om de kaart op jou te centreren en ritten op te nemen. De positie blijft op dit apparaat; hij wordt nooit geüpload." Je kunt **Niet nu** antwoorden en de app gewoon blijven gebruiken; alleen de functies die moeten weten waar je bent, werken dan niet.

Met de toestemming opent de kaart waar je hem achterliet en glijdt daarna naar je positie: meteen naar waar de telefoon je het laatst zag als dat minder dan een uur geleden is, en naar de eerste verse positiebepaling als dat niet zo is, of als die bepaling je meer dan zo'n 300 m daarvandaan plaatst, zowel bij het starten van de app als wanneer je na een halfuur of langer terugkomt. De kaart blijft staan zolang er een plan op het tabblad Plannen staat, een route- of ritkaart open is, een rit wordt opgenomen, je al in beeld bent of je de kaart zelf hebt verschoven.

"Bij gebruik van de app" is genoeg. Op Android vraagt Velorki bewust **geen** locatie op de achtergrond: het opnemen van een rit draait in plaats daarvan als voorgronddienst met een melding. Op iOS dekt "Bij gebruik van app" samen met de locatiemodus op de achtergrond een opgenomen rit met het scherm uit.

### Meldingen (Android)

Gevraagd de eerste keer dat je een rit start. De opname draait in een melding die je afstand en tijd toont, en Android stopt de opname als die melding niet kan worden geplaatst. Weiger je, dan zegt Velorki dat: "Zonder toestemming voor meldingen stopt Android de opname zodra je de app verlaat."

### Batterijoptimalisatie (Android)

Eén keer gevraagd, en nooit meer, de eerste keer dat je een rit start: **Op de achtergrond blijven opnemen**: "Android kan de opname stoppen terwijl de telefoon slaapt. Kies in de batterij-instellingen die opengaan Velorki en sta onbeperkt batterijgebruik toe (op sommige telefoons: niet geoptimaliseerd), dan blijft de track compleet. Dit wordt maar één keer gevraagd." Antwoord **Instellingen openen** of **Niet nu**; het wordt nooit meer gevraagd.

### Bestanden

Geen vaste toestemming. Als je een GPX-, FIT- of TCX-bestand importeert, geeft de bestandskiezer van het systeem dat ene bestand aan de app; als je exporteert, neemt het deelmenu van het systeem het weer mee.

Verder vraagt Velorki niets. Nergens in de app is er toegang tot contacten, foto's, microfoon, gezondheid of advertenties.

## De vier tabbladen

De balk onderaan heeft vier tabbladen.

| Tabblad | Wat je er vindt |
|---|---|
| **Plannen** | De kaart, het zoeken naar plaatsen, de routeplanner, slimme rondjes en de assistent. |
| **Opnemen** | Een rit starten, pauzeren en beëindigen, de live waarden en je recente ritten. |
| **Bibliotheek** | Alles wat je hebt opgeslagen: **Routes** en **Ritten**, met importeren en exporteren. |
| **Instellingen** | Weergave, eenheden en taal, opties voor navigatie en opname, offline gegevens, zoeken, koppelingen, abonnement en de juridische pagina's. |

De balk zweeft boven de inhoud, dus lijsten scrollen eronderdoor.

## Eenheden

Velorki toont afstanden in kilometers en meters, of in mijlen en voet, en gebruikt je keuze overal: de statistieken, de schuifregelaars, de assen van de grafieken, de afslagbanner en de gesproken aanwijzingen.

1. Open **Instellingen**.
2. Zoek onder **Weergave** naar **Eenheden**.
3. Kies **Metrisch** of **Imperiaal**.

Tot je kiest, volgt Velorki het land van de telefoon: imperiaal alleen waar het land dat gebruikt, metrisch overal anders.

## Waar alles zit

- **De kaartknoppen** staan in een kolom rechts op de kaart: **Mijn positie tonen**, **Kaartlagen** ([de fietskaart](./map-layers) en [stopplekken op de kaart](./stops-on-the-map)), **Offline gegevens** (niet op een klein scherm zoals een iPhone SE), **Inzoomen** en **Uitzoomen**. Op het tabblad Opnemen komt er een kompasknop bij, die wisselt tussen **Noorden boven** en **Kaart draait mee**.
- **Het zoekveld** staat bovenaan het tabblad Plannen.
- **Het fietsprofiel** (Toer, Racefiets, Gravel, MTB, Direct) is de rij knoppen onder het zoekveld.
- **Het routepaneel** is het paneel onderaan het tabblad Plannen. Sleep het omhoog voor het hoogteprofiel en de verdeling van de ondergrond, omlaag om meer kaart te zien.
- **Een paneel over de kaart**, zoals Kaartlagen, de kaart van een plek, het paneel van een punt of het rondjespaneel, zet de kaart van het tabblad op de laagste hoogte zolang het open is; hij komt weer omhoog als het paneel sluit.

## Zie ook

- [Een route plannen](./planning-a-route)
- [Offline kaarten en routering](./offline-maps-and-routing)
- [Een rit opnemen](./recording-a-ride)
- [Instellingen en weergave](./settings-and-appearance)
- [Privacy op de telefoon](./privacy-on-the-phone)
