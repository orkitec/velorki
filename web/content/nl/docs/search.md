---
title: Zoeken
description: Vind plaatsen, straten, huisnummers en dingen als drinkwater of toiletten, op de telefoon waar je een gebied hebt gedownload en online overal anders.
order: 4
---

Het zoekveld bovenaan het tabblad Plannen vindt steden, straten, huisnummers en interessante punten zoals cafés, drinkwater en fietsenwinkels. Waar je een gebied hebt gedownload, antwoordt het vanaf de telefoon, meteen en zonder bereik; overal anders vraagt het een online geocoder.

## Zo zoek je

1. Open het tabblad **Plannen** en tik op het veld bovenaan, met de hint **Zoek een plaats**.
2. Typ minstens drie tekens. Terwijl je typt, verschijnen de resultaten in een kaart onder het veld.
3. Tik op een resultaat. De kaart schuift naar de plek, zet er een speld op en opent de plaatskaart.

Coördinaten die je in het veld typt of plakt, `40.71747, -73.94840` of `40,71747° N, 73,94840° W` zoals kaartapps ze kopiëren, zijn de plek zelf: één resultaat op die plek, zonder iets op te zoeken en zonder iets te versturen. Een plek die uit een andere app is gedeeld, opent op dezelfde manier, zie [importeren en exporteren](./import-and-export#een-plek-uit-een-andere-app).

## De plaatskaart

Een zoekresultaat, een [stopplek op de kaart](./stops-on-the-map) of een plek uit een andere app opent een kaart met de naam van de plek, wat het is, de plaats, hoe ver het van je af ligt en, met een route, hoe ver naast de route. Niets verandert tot je een actie kiest, die afhangt van het plan:

- **Nog niets gepland**: **Route hierheen** rijdt van waar je bent naar de plek; **Hier starten** maakt er het eerste punt van de route van.
- **Alleen een start**: **Als bestemming** maakt er het einde van de route van.
- **Een route**: **Als tussenstop** voegt de plek in de route in op de plaats waar hij onderweg ligt; **Als bestemming** voegt hem aan het einde toe.

Op het tabblad Opnemen vertelt de kaart alleen, zonder acties.

Daaronder:

- **Details** haalt de plek op uit OpenStreetMap, alleen als je erop tikt: openingstijden met of de plek nu open is, website, telefoonnummer, keuken, toegankelijkheid voor rolstoelen, buitenzitplaatsen en het Wikipedia-artikel, voor zover ze in kaart zijn gebracht. Details blijven een week op de telefoon bewaard, dus de plek toont ze de volgende keer meteen. De knop ontbreekt voor straten en voor plaatsen zonder OpenStreetMap-id.
- **Openen in…** toont de plek in Apple Maps, in Google Maps als die is geïnstalleerd (iPhone), in een kaartapp die je kiest (Android) of op OpenStreetMap in de browser, of geeft hem aan **Delen…**.

De kaart sluiten (de **X**, omlaag vegen of een tik op de kaart) verandert niets en wist de zoekopdracht.

## Offline of online

Velorki beslist op basis van het **midden van de kaart**, niet van je verbinding. Elke gedownloade routeringstegel brengt een zoekindex van zijn gebied mee, dus:

- als de index van de tegel onder het midden van de kaart op de telefoon staat, wordt de zoekopdracht op de telefoon beantwoord;
- als dat niet zo is, gaat de zoekopdracht online naar Photon.

Onderaan de resultatenkaart staat precies één regel, en welke het is, zegt je waar de resultaten vandaan komen:

| Regel | Betekent | Erop tikken |
|---|---|---|
| **Online zoeken naar "…"** | je kijkt naar offline resultaten | zoekt dezelfde tekst online |
| **Offline resultaten tonen** | je kijkt naar online resultaten | zoekt dezelfde tekst weer op de telefoon |
| **Download dit gebied om offline te zoeken** | dit gebied heeft geen index op de telefoon | opent het offlinescherm voor het zichtbare gebied |

Die regel blijft zichtbaar terwijl je door de lijst scrolt, en staat ook onder een foutmelding, waar hij het meest nodig is.

## Wat het vindt

- **Plaatsen**: steden, kleine steden, dorpen, gehuchten, stadsdelen, wijken, buurtschappen en eilanden.
- **Straten**, met huisnummers.
- **Interessante punten**, elk met een eigen icoon en label: Café, Restaurant, Snackbar, IJssalon, Tankstation, Fietspomp, Drinkwater, Toiletten, Fietsreparatiepunt, Fietsenwinkel, Fietsverhuur, Fietsenstalling, E-bike-laadpunt, Schuilhut, Camping, Hotel, Hostel, Berghut, Supermarkt, Bakker, Apotheek, Picknickplek, Station, Veerhaven, Vliegveld, Uitzichtpunt, Top, Bergpas, Park, Strand, Water, Natuurgebied, Bezienswaardigheid, Museum, Historische plek, Gebedshuis, Ziekenhuis, Universiteit, Sportaccommodatie, Winkelcentrum, Toren, Vuurtoren, Gebouw.
- **Bekende plekken in jouw taal**: "Parigi" vindt Parijs, en een beroemd oriëntatiepunt komt vóór zijn naamgenoten.

Offline regels tonen onder de naam het soort, de afstand en de plaats, voor zover elk bekend is: "Drinkwater · 350 m", "Straat · Manhattan". Een kraan, een toilet, een schuilhut of een fietsenrek zonder eigen naam staat in de lijst onder zijn soort.

## Zoeken op soort

Typ de naam van een soort in plaats van de naam van een plek. "drinkwater", "bakker", "toiletten" en de rest werken allemaal, in de taal waarin de app draait.

De lijst opent dan met de vijf dichtstbijzijnde van die soort rond het midden van de kaart, elk met de afstand, en de gewone naamtreffers volgen daaronder. Velorki zoekt in een vak dat van 5 tot 50 km rond het midden van de kaart groeit tot er genoeg zijn. Zo beantwoord je midden in een rit snel de vraag "waar is de dichtstbijzijnde kraan".

Zoeken op soort negeert de groepsschakelaars die hieronder worden beschreven.

## Huisnummers

Typ het nummer waar jouw land het zet: "Hauptstrasse 12", "400 W 42nd", "Via Roma 12/A", "Budapest, Fő utca 12". Velorki vindt de straat en antwoordt op de eigen positie van het nummer langs die straat; de regel is het adres zoals je het typte, "400 West 42nd Street". Een plaats vóór de straat met een komma, of erna, zegt welke straat je bedoelt. Een postcode blijft weg, en een nummer dat bij de naam van een straat hoort, "Route 66", blijft deel van de naam.

Valt het nummer tussen twee die de index kent, dan schat Velorki de positie en zegt de regel **≈ 400**, zodat je ziet dat het een gok is.

## Typefouten, afkortingen en andere alfabetten

Offline zoeken vergeeft een letter of twee fout, een woord aan elkaar of los geschreven, en afkortingen zoals "St" of "Str.". Namen in cyrillisch of Grieks kun je in Latijnse letters typen, "aleksandar nevski" of "Nafplio". Als niets goed antwoordt, probeert Velorki in plaats daarvan de waarschijnlijkste woorden uit de index en toont de kaart **Resultaten voor "…"** boven de lijst, met waar er echt op is gezocht.

## De groepen ordenen

Offline resultaten zijn gegroepeerd, en jij bepaalt welke groepen verschijnen en in welke volgorde.

1. Open **Instellingen**.
2. Tik op **Zoeken**, met als ondertitel "Wat offline zoeken toont, en in welke volgorde. Sleep om de prioriteit te wijzigen."
3. Sleep een regel aan zijn greep omhoog of omlaag. Met de schakelaar rechts zet je een groep uit.

De acht groepen, in hun standaardvolgorde: **Plaatsen**, **Straten en adressen**, **Bezienswaardigheden**, **Stops onderweg**, **Overnachten**, **Natuur**, **Vervoer**, **Voorzieningen**.

Er is geen opslaanknop; wijzigingen gelden bij je volgende toetsaanslag. Een groep die uit staat, verdwijnt uit de naamtreffers, en de volgorde beslist tussen resultaten die even goed bij de tekst passen.

## Als zoeken niet werkt

- **"Niets gevonden."** De tekst leverde niets op, offline noch online. Probeer de regel onderaan om van bron te wisselen, of minder woorden.
- **"Zoeken mislukt."** met een reden betekent dat de online geocoder niet bereikbaar was. Offline zoeken blijft werken waar je een gebied hebt gedownload.
- **"Geen zoekserver ingesteld, stel er een in onder Instellingen → Geavanceerd."** betekent dat deze build geen geocoderadres en geen gedownloade index heeft. Het veld is uitgeschakeld tot er een is.

## Zie ook

- [Stopplekken op de kaart](./stops-on-the-map)
- [Offline kaarten en routering](./offline-maps-and-routing)
- [Een route plannen](./planning-a-route)
- [Instellingen en weergave](./settings-and-appearance)
- [Privacy op de telefoon](./privacy-on-the-phone)
