---
title: Zoeken
description: Vind plaatsen, straten, huisnummers en dingen als drinkwater of toiletten, op de telefoon waar je een gebied hebt gedownload en online overal anders.
order: 4
---

Het zoekveld bovenaan het tabblad Plannen vindt steden, straten, huisnummers en interessante punten zoals cafés, drinkwater en fietsenwinkels. Waar je een gebied hebt gedownload, antwoordt het vanaf de telefoon, meteen en zonder bereik; overal anders vraagt het een online geocoder.

## Zo zoek je

1. Open het tabblad **Plannen** en tik op het veld bovenaan, met de hint **Zoek een plaats**.
2. Typ minstens drie tekens. Terwijl je typt, verschijnen de resultaten in een kaart onder het veld.
3. Tik op een resultaat.

Er verschijnt een kaart met de naam van de plek, wat het is, hoe ver het van je af ligt en, met een route, hoe ver naast de route. De kaart schuift naar de plek en zet er een speld op. Wat de kaart aanbiedt, hangt af van het plan:

- **Nog niets gepland**: **Route hierheen** rijdt van waar je bent naar de plek; **Hier starten** maakt er het eerste punt van de route van.
- **Alleen een start**: **Als bestemming** maakt er het einde van de route van.
- **Een route**: **Als tussenstop** voegt de plek in de route in op de plaats waar hij onderweg ligt; **Als bestemming** voegt hem aan het einde toe.

Daaronder haalt **Details** de openingstijden (en of de plek nu open is), website, telefoonnummer en dergelijke op uit OpenStreetMap, alleen als je erop tikt; voor straten en plaatsen zonder OpenStreetMap-id ontbreekt de knop. **Openen in…** toont de plek in een andere kaartapp of op openstreetmap.org, of deelt hem.

De kaart sluiten (de **X**, omlaag vegen of een tik op de kaart) verandert niets en wist de zoekopdracht. Een stopplek die je op de kaart aantikt, opent dezelfde kaart.

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
- **Interessante punten**, elk met een eigen icoon en label: Café, Drinkwater, Toiletten, Fietsreparatiepunt, Fietsenwinkel, Fietsverhuur, Fietsenstalling, E-bike-laadpunt, Schuilhut, Camping, Hotel, Hostel, Berghut, Supermarkt, Bakker, Apotheek, Picknickplek, Station, Veerhaven, Vliegveld, Uitzichtpunt, Top, Bergpas, Park, Strand, Water, Natuurgebied, Bezienswaardigheid, Museum, Historische plek, Gebedshuis, Ziekenhuis, Universiteit, Sportaccommodatie, Winkelcentrum, Toren, Vuurtoren, Gebouw.

Offline regels tonen onder de naam het soort, de afstand, het huisnummer en de plaats, in die volgorde, voor zover elk bekend is: "Drinkwater · 350 m", "Straat · 400 · Manhattan". Een kraan, een toilet, een schuilhut of een fietsenrek zonder eigen naam staat in de lijst onder zijn soort.

## Zoeken op soort

Typ de naam van een soort in plaats van de naam van een plek. "drinkwater", "bakker", "toiletten" en de rest werken allemaal, in de taal waarin de app draait.

De lijst opent dan met de vijf dichtstbijzijnde van die soort rond het midden van de kaart, elk met de afstand, en de gewone naamtreffers volgen daaronder. Velorki zoekt in een vak dat van 5 tot 50 km rond het midden van de kaart groeit tot er genoeg zijn. Zo beantwoord je midden in een rit snel de vraag "waar is de dichtstbijzijnde kraan".

Zoeken op soort negeert de groepsschakelaars die hieronder worden beschreven.

## Huisnummers

Zet het nummer aan het begin of aan het einde: "Hauptstrasse 12", "400 W 42nd". Velorki haalt het nummer eraf, zoekt de straat en antwoordt op de eigen positie van het nummer langs die straat.

Staat precies dat nummer in de index, dan is de positie exact. Valt het nummer tussen twee bekende in, dan interpoleert Velorki en markeert de regel als **≈ 400**, zodat je ziet dat het een schatting is. Een nummer midden in een zoekopdracht wordt als deel van de naam behandeld, net als een rangtelwoord zoals "42nd".

## Typefouten

Levert een zoekopdracht helemaal niets op, dan neemt Velorki de woorden die het niet herkent, zoekt in de index de waarschijnlijkste woorden die een of twee letters verschillen, en zoekt opnieuw. De kaart toont dan **Resultaten voor "…"** boven de lijst, met waar er echt op is gezocht.

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

- [Offline kaarten en routering](./offline-maps-and-routing)
- [Een route plannen](./planning-a-route)
- [Instellingen en weergave](./settings-and-appearance)
- [Privacy op de telefoon](./privacy-on-the-phone)
