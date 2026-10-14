---
title: Strava en Ride with GPS
description: Velorki werkt gratis met Strava en Ride with GPS. Koppel een account om opgenomen ritten te uploaden en routes te importeren, en lees waarom een route naar Strava sturen een bestand is.
order: 13
---

Velorki is compatibel met Strava en met Ride with GPS: het kan een rit uploaden die je hebt opgenomen, en je routes uit die accounts in je bibliotheek halen. Een van beide diensten koppelen is gratis, met of zonder [Velorki Plus](./velorki-plus). Velorki is niet gemaakt, goedgekeurd of gesponsord door Strava of Ride with GPS.

Er wordt niets naar een van beide diensten gestuurd tot je het account zelf koppelt en daarna ergens om vraagt.

## Een account koppelen

1. Open **Instellingen** en zoek het onderdeel **Koppelingen**.
2. Tik op **Koppelen met Strava** of **Koppelen met Ride with GPS**.
3. De eigen aanmeldpagina van de dienst opent in een browser. Meld je daar aan en geef toegang.
4. Je komt terug in Velorki, en de rij toont je naam in plaats van **Niet gekoppeld**.

Velorki vraagt Strava maar om twee machtigingen: **read**, je openbare profiel (je id en naam, getoond in Instellingen), en **activity:write**, om de ritten te uploaden die jij wilt uploaden. Je activiteiten leest het niet.

Je telefoon bewaart het toegangstoken in de beveiligde opslag van de telefoon, in een vorm die alleen de Velorki-server kan openen, en laat het buiten back-ups. Vanaf dan gaat elke upload en import via die server, die het token voor dat ene verzoek opent en het doorstuurt. Hij bewaart het bestand noch het token, ook geen enkel spoor van de aanroep, en kan het token niet op eigen houtje gebruiken.

Mislukt een poging om te koppelen, dan zegt Velorki "Koppelen mislukt:" met de reden. Als je de aanmeldpagina annuleert, zegt het helemaal niets.

Een rij met **Niet beschikbaar in deze build** betekent dat deze build van Velorki zonder de sleutels van die dienst is gecompileerd, wat het geval is bij een zelfgebouwde kopie tot je je eigen sleutels levert.

## Ontkoppelen

Tik op **Ontkoppelen** in de gekoppelde rij en bevestig. Ontkoppelen vraagt de dienst ook om de toegang van Velorki in te trekken, als de server bereikbaar is. Het verwijdert niets van je Strava- of Ride with GPS-account.

**Strava.** Ontkoppelen verwijdert alle Strava-gegevens van de telefoon: het toegangstoken, de routes die je uit Strava hebt geïmporteerd en routes die je daaruit hebt bewerkt, de lijst met routes in de cache, en de koppelingen van je ritten naar hun Strava-activiteiten. Je ritten zelf blijven. Velorki zegt dan "Je Strava-gegevens zijn van deze telefoon verwijderd."

Verwijder je Velorki op strava.com zelf uit je Strava-account, dan merkt Velorki dat bij de volgende aanroep naar Strava, verwijdert dezelfde gegevens en vertelt het je.

**Ride with GPS.** Velorki vergeet het toegangstoken. Routes en ritten die al in de bibliotheek staan, blijven.

## Een rit uploaden

1. Open de rit in **Bibliotheek → Ritten**.
2. Tik op de wolkknop rechtsboven, met het label **Uploaden**.
3. Kies **Uploaden naar Strava** of **Uploaden naar Ride with GPS**.

Velorki zegt "Uploaden naar Strava…", dan "Geüpload naar Strava" met een actie **View on Strava** die hem opent. Velorki bewaart daarvoor de link naar de activiteit bij de rit, tot je ontkoppelt. Een rit die er al staat, wordt nooit twee keer geüpload: het menu-item wordt dan **View on Strava** of **Openen op Ride with GPS**.

Een upload naar Strava kan even duren, omdat Strava het bestand verwerkt voordat het als activiteit bestaat; Velorki wacht erop en linkt naar het resultaat.

## Routes importeren

1. Open het tabblad **Bibliotheek**.
2. Tik op de wolkknop rechtsboven en kies **Importeren uit Strava** of **Importeren uit Ride with GPS**.
3. De lijst heet **Routes op Strava** of **Routes op Ride with GPS**. Elke rij toont de naam, de afstand, de stijging en de datum.
4. Tik op **Importeren** bij de route die je wilt. Die komt in je bibliotheek terecht, en Velorki zegt "Alpenrondje geïmporteerd". Een route uit Strava blijft op de telefoon: hij wordt nooit naar de assistent gestuurd, in een deellink gezet of naar Ride with GPS of een andere dienst gestuurd, en Strava ontkoppelen verwijdert hem.

Een route uit Strava, en elke route die je ervan bewerkt, blijft alleen zolang hij nog op Strava bestaat. Zolang Velorki open, online en gekoppeld is, controleert het zo'n route elke 48 uur opnieuw bij Strava; je bewerkingen blijven zolang de route er nog is. Is hij op Strava verwijderd of kon hij 7 dagen lang niet worden gecontroleerd (offline, ontkoppeld of mislukte controles), dan verwijdert Velorki hem en zegt het "Een route uit Strava is verwijderd: hij bestaat niet meer op Strava, of kon 7 dagen lang niet worden gecontroleerd."

Onderaan staat **Opgehaald 16 sep 2026**, het moment waarop de lijst werd opgehaald. Velorki bewaart de lijst hooguit 48 uur op de telefoon, en **Vernieuwen** rechtsboven haalt hem opnieuw op.

Is het account niet gekoppeld, dan zegt het scherm "Koppel eerst Strava onder Instellingen → Koppelingen."

## Een route naar Ride with GPS sturen

Open de route, tik op **Sturen** en kies **Naar Ride with GPS sturen**. Hij wordt naar je account geüpload en Velorki biedt **Openen** aan om hem daar te bekijken.

## Een route naar Strava sturen

De API van Strava kan routes lezen maar niet aanmaken, dus er is niets waar Velorki naartoe kan uploaden. **Naar Strava sturen** opent daarom een uitleg:

> **Strava kan geen routes ontvangen.** De API van Strava kan routes lezen maar niet aanmaken. Velorki exporteert in plaats daarvan een GPX-bestand: deel het en importeer het dan op strava.com.

Tik op **GPX exporteren**, sla het bestand op of verstuur het, en upload het als route op strava.com. Die weg is gratis en heeft helemaal geen koppeling nodig.

## Het is allemaal gratis

Strava of Ride with GPS koppelen, een rit uploaden, routes importeren en een route naar Ride with GPS sturen is gratis, net als GPX-, FIT- en TCX-bestanden, die met de hand hetzelfde doen. Niets daarvan heeft Velorki Plus nodig.

## Strava-gegevens blijven op de telefoon

Strava-gegevens worden alleen aan jou getoond. De API-voorwaarden van Strava staan niet toe dat hun gegevens aan een AI-aanbieder of aan andere diensten worden gegeven, dus Velorki stuurt een route die van Strava komt nooit naar de assistent, zet hem nooit in een deellink en stuurt hem nooit naar Ride with GPS of ergens anders heen. **Deze route beschrijven** wordt er bijvoorbeeld niet voor aangeboden.

Wij bewaren geen Strava-gegevens op onze servers: alles staat op je telefoon. Vragen, of een verzoek om gegevens te verwijderen, gaan naar [ride@velorki.com](mailto:ride@velorki.com); zie het [privacybeleid](/privacy).

## Zie ook

- [Velorki Plus](./velorki-plus)
- [Importeren en exporteren](./import-and-export)
- [Bibliotheek](./library)
- [Assistent](./assistant)
- [Privacy op de telefoon](./privacy-on-the-phone)
