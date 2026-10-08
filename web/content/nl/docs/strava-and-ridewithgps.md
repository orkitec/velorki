---
title: Strava en Ride with GPS
description: Koppel je Strava- of Ride with GPS-account om opgenomen ritten te uploaden en routes te importeren, en lees waarom een route naar Strava sturen een bestand is.
order: 11
---

Velorki kan namens jou met Strava en met Ride with GPS praten: een rit uploaden die je hebt opgenomen, en je routes uit die accounts in je bibliotheek halen. Een van beide diensten koppelen hoort bij [Velorki Plus](./velorki-plus); GPX-, FIT- en TCX-bestanden blijven gratis en doen hetzelfde met de hand.

Er wordt niets naar een van beide diensten gestuurd tot je het account zelf koppelt en daarna ergens om vraagt.

## Een account koppelen

1. Open **Instellingen** en zoek het onderdeel **Koppelingen**.
2. Tik op **Koppelen met Strava** of **Koppelen met Ride with GPS**.
3. De eigen aanmeldpagina van de dienst opent in een browser. Meld je daar aan en geef toegang.
4. Je komt terug in Velorki, en de rij toont je naam in plaats van **Niet gekoppeld**.

Je telefoon bewaart het toegangstoken in de beveiligde opslag van de telefoon, in een vorm die alleen de Velorki-server kan openen. Vanaf dan gaat elke upload en import via die server, die je abonnement controleert, het token voor dat ene verzoek opent en het doorstuurt. Hij bewaart het bestand noch het token, en kan het token niet op eigen houtje gebruiken.

Mislukt een poging om te koppelen, dan zegt Velorki "Koppelen mislukt:" met de reden. Als je de aanmeldpagina annuleert, zegt het helemaal niets.

Een rij met **Niet beschikbaar in deze build** betekent dat deze build van Velorki zonder de sleutels van die dienst is gecompileerd, wat het geval is bij een zelfgebouwde kopie tot je je eigen sleutels levert.

## Ontkoppelen

Tik op **Ontkoppelen** in de gekoppelde rij. Velorki vraagt "Strava ontkoppelen?" en legt uit: "Velorki vergeet het toegangstoken. Routes en ritten die al in de bibliotheek staan, blijven."

Ontkoppelen vraagt de dienst ook om de toegang van Velorki in te trekken, als de server bereikbaar is. Het verwijdert niets van Strava of Ride with GPS, en niets uit je bibliotheek.

## Een rit uploaden

1. Open de rit in **Bibliotheek → Ritten**.
2. Tik op de wolkknop rechtsboven, met het label **Uploaden**.
3. Kies **Uploaden naar Strava** of **Uploaden naar Ride with GPS**.

Velorki zegt "Uploaden naar Strava…", dan "Geüpload naar Strava" met een actie **Bekijken op Strava** die hem opent. Een rit die er al staat, wordt nooit twee keer geüpload: het menu-item wordt dan **Bekijken op Strava** of **Openen op Ride with GPS**.

Een upload naar Strava kan even duren, omdat Strava het bestand verwerkt voordat het als activiteit bestaat; Velorki wacht erop en linkt naar het resultaat.

## Routes importeren

1. Open het tabblad **Bibliotheek**.
2. Tik op de wolkknop rechtsboven en kies **Importeren uit Strava** of **Importeren uit Ride with GPS**.
3. De lijst heet **Routes op Strava** of **Routes op Ride with GPS**. Elke rij toont de naam, de afstand, de stijging en de datum.
4. Tik op **Importeren** bij de route die je wilt. Die komt als gewone route in je bibliotheek terecht, en Velorki zegt "Alpenrondje geïmporteerd".

Onderaan staat **Opgehaald 16 sep 2026**, het moment waarop de lijst werd opgehaald. Velorki bewaart hem tot zeven dagen in de cache, zoals de voorwaarden van Strava vereisen, en **Vernieuwen** rechtsboven haalt hem opnieuw op.

Is het account niet gekoppeld, dan zegt het scherm "Koppel eerst Strava onder Instellingen → Koppelingen."

## Een route naar Ride with GPS sturen

Open de route, tik op **Sturen** en kies **Naar Ride with GPS sturen**. Hij wordt naar je account geüpload en Velorki biedt **Openen** aan om hem daar te bekijken.

## Een route naar Strava sturen

De API van Strava kan routes lezen maar niet aanmaken, dus er is niets waar Velorki naartoe kan uploaden. **Naar Strava sturen** opent daarom een uitleg:

> **Strava kan geen routes ontvangen.** De API van Strava kan routes lezen maar niet aanmaken. Velorki exporteert in plaats daarvan een GPX-bestand: deel het en importeer het dan op strava.com.

Tik op **GPX exporteren**, sla het bestand op of verstuur het, en upload het als route op strava.com. Die weg is gratis en heeft helemaal geen koppeling nodig.

## Wat gratis is en wat Plus nodig heeft

| | Plus nodig |
|---|---|
| Strava of Ride with GPS koppelen | ja |
| Een rit naar een van beide uploaden | ja |
| Routes uit een van beide importeren | ja |
| Een route naar Ride with GPS sturen | ja |
| GPX, FIT of TCX exporteren en zelf uploaden | nee |
| Een GPX-, FIT- of TCX-bestand van een van beide diensten importeren | nee |

## Over de assistent en Strava

**Deze route beschrijven** wordt niet aangeboden voor een route die van Strava komt. De API-voorwaarden van Strava staan niet toe dat hun gegevens naar een AI-aanbieder worden gestuurd, dus verbergt Velorki de knop in plaats van ze te overtreden.

## Zie ook

- [Velorki Plus](./velorki-plus)
- [Importeren en exporteren](./import-and-export)
- [Bibliotheek](./library)
- [Assistent](./assistant)
- [Privacy op de telefoon](./privacy-on-the-phone)
