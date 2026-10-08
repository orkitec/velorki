---
title: Importeren en exporteren
description: GPX-, FIT- en TCX-bestanden van overal op de telefoon openen, ze opslaan als routes of ritten, en die van jou exporteren naar Komoot, Garmin of iets anders.
order: 10
---

Velorki leest en schrijft GPX-, FIT- en TCX-bestanden, en zo verhuizen routes en ritten tussen Velorki en de rest van de wereld. Het is allemaal gratis, heeft geen account en geen verbinding nodig, en werkt met Komoot, Garmin Connect, Strava, een fietscomputer of gewoon een bestand op de telefoon.

## Een bestand binnenhalen

Er zijn drie manieren, en alle drie eindigen op hetzelfde importscherm.

**Openen met.** Tik op een GPX-, FIT- of TCX-bestand in je bestandenapp, in een e-mail of bij de downloads van de browser, en kies Velorki. Op een iPhone is dat "Open in Velorki" vanuit Bestanden, Mail of Safari.

**Deelmenu.** Deel het bestand in een andere app en kies Velorki. Zo komt een route binnen vanuit Komoot of uit een bericht van een vriend.

**De kiezer.** Tik op het tabblad **Bibliotheek** rechtsboven op **Bestand importeren** en kies het bestand zelf.

**Een Ride with GPS-link.** Deel de link van een route vanuit de Ride with GPS-app of een browser en kies Velorki, en de route komt op het importscherm terecht. Een openbare route heeft verder niets nodig; een privéroute wordt opgehaald via je gekoppelde Ride with GPS-account, en zonder account zegt het scherm "Deze Ride with GPS-route is privé. Koppel Ride with GPS in Instellingen om hem te openen."

Een bestand dat niet kan worden geïmporteerd, opent hetzelfde scherm met de reden: geen GPX-, FIT- of TCX-bestand, onleesbaar, leeg, of een link die niet kon worden opgehaald.

Velorki bepaalt wat het bestand is door de eerste bytes te lezen, niet door op de naam of het type te vertrouwen, dus een `.gpx` die eigenlijk een FIT-bestand is, wordt toch geïmporteerd. Een TCX-bestand wordt herkend aan zijn hoofdelement.

## Een plek uit een andere app

Velorki neemt ook een enkele plek aan om naartoe te rijden, en opent die op het tabblad **Plannen** zoals een zoekresultaat opent: vastgeprikt op de kaart, op zijn [plaatskaart](./search#de-plaatskaart).

- **Deelmenu.** Deel een plek vanuit Google Maps, Apple Maps, OpenStreetMap, een browser of een berichtenapp en kies Velorki. Een kaartlink, coördinaten zoals `52.5200, 13.4050` of `52°31'12"N 13°24'18"E`, of een adres werken allemaal; een adres gaat naar het zoekveld, dat het vindt.
- **Openen met** (Android). Een locatie die een andere app opent (een `geo:`-link) biedt Velorki aan in de kiezer.
- **Korte links** zoals `maps.app.goo.gl/…`, `maps.apple/p/…` of `osm.org/go/…` zeggen pas waar ze naartoe wijzen als ze worden geopend. Online opent Velorki ze (één verzoek aan die dienst, verder wordt er niets verstuurd) en komt op de plek uit; offline zegt het dat: open de link eerst in een browser en deel de plek dan vanaf daar.

**Voor app-ontwikkelaars** opent Velorki deze links:

| Link | Opent |
|---|---|
| `velorki://navigate?lat=52.52&lon=13.405&name=Brandenburger%20Tor` | de plek op die coördinaten, met `name` als label (optioneel) |
| `velorki://navigate?q=Pariser%20Platz%201%2C%20Berlin` | een zoekopdracht naar het adres of de plaatsnaam |

Coördinaten zijn decimale graden (WGS 84); elke waarde is URL-gecodeerd. Op Android werkt ook een `geo:`-intent (`geo:LAT,LON`, `geo:0,0?q=LAT,LON(Label)`, `geo:0,0?q=address`).

## Het importscherm

Met de titel **Import** toont het:

- een kaartvoorbeeld van de track, met de waypoints van het bestand als kleine markeringen met hun naam: de interessante punten die een route meebracht, een afstapzone, een drinkwaterpunt, een slecht stuk, in de kleur van hun soort,
- een veld **Naam**, vooraf ingevuld met de bestandsnaam,
- het formaat en de grootte, "GPX · 4.812 punten",
- de tijdspanne, "16 sep 2026, 09:12 – 16 sep 2026, 13:40", of "Het bestand bevat geen tijdstempels.",
- de afstand, stijging, daling en duur,
- **OPSLAAN ALS**, een schakelaar tussen **Route** en **Rit**.

De kaart blijft bovenaan terwijl de pagina's eronder scrollen, met puntjes onder de kaart die laten zien welke pagina er open is. Eén veeg naar links is het hoogteprofiel. Heeft het bestand afslagen of interessante punten, dan is nog een veeg de **ROUTEBESCHRIJVING**, elke afslag en elk interessant punt met de afstand vanaf de start, ingeklapt tot acht regels met **Alle tonen**. Tik op een regel en de kaart schuift daarheen op je huidige zoomniveau, vastgeprikt met de naam; tik op een markering op de kaart en de routebeschrijving komt tevoorschijn met die regel geselecteerd en in beeld gescrold. Een geselecteerde regel opent met wat er te weten valt, de notitie bij een gevaar of de gewone manoeuvre onder de woorden van de maker.

Een GPX-route met een routebeschrijving, de route-export van Ride with GPS of een Garmin-course, neemt zijn afslagen mee: elke aanwijzing wordt een afslaginstructie met de woorden van de maker, getoond in de afslagbanner, op de pagina van de routebeschrijving en uitgesproken door de stem. Een GPX-track heeft geen routebeschrijving; de eigen afslagbanner van Velorki werkt er toch op, aan de hand van de vorm van de route.

Velorki raadt **Route** of **Rit** aan de hand van of de punten tijden hebben: een opname heeft ze, een geplande route niet. Een FIT-course wordt herkend als course en als route geraden, wat zijn kunstmatige tijdbasis ook zegt, en dat geldt ook voor een TCX-course; de coursepunten worden de routebeschrijving (afslagen) en de interessante punten (water, eten, gevaren, plekken met een naam) van de route. Er wordt niets weggeschreven tot je op **Opslaan** tikt.

Een route opent met de fiets die zijn bestand noemt: een GPX-`<type>` zoals `road_biking` of `mountain_biking`, of de subsport van een FIT-course of -activiteit (weg, mountainbike, gravel), wordt **Racefiets**, **MTB**, **Gravel** of **Toer**. Een bestand dat er geen noemt, opent met de fiets waarmee je het laatst reed. Een geëxporteerde route schrijft zijn fiets op dezelfde manier terug; een TCX-bestand heeft er geen woord voor.

Een FIT-activiteit van een fietscomputer brengt meer mee dan alleen de track: de ronden die het apparaat heeft gezet, vervangen de vaste splits op de pagina van de rit, de totalen die het apparaat schreef (afstand, rijtijd, stijging, calorieën) staan onder **Zoals opgenomen door het apparaat** waar ze afwijken van wat Velorki uit de posities berekent, en een temperatuur, als het apparaat er een vastlegde, krijgt een eigen grafiek. Een GPX-rit brengt op dezelfde manier hartslag, cadans, vermogen en temperatuur mee uit zijn extensies. Een GPX-bestand met meerdere tracks, bijvoorbeeld een meerdaagse tocht, toont ze elk met een vinkje, en slaat per aangevinkte track één rit (of route) op.

Daarna krijg je "Alpenrondje toegevoegd aan de bibliotheek" of "Alpenrondje toegevoegd aan je ritten", en kom je uit op de kaart van het nieuwe item op het tabblad Bibliotheek.

Opent het bestand niet, dan zegt Velorki welk probleem het was: "Dat is geen GPX-, FIT- of TCX-bestand.", "Dat bestand kon niet worden gelezen.", "Dat bestand heeft geen trackpunten." of "Dat bestand kon niet worden geopend."

## Een bestand naar buiten zetten

**Vanuit een route** (Bibliotheek → Routes → openen → **Exporteren**):

| Formaat | Gebruik het voor |
|---|---|
| **GPX-route** | een geplande route voor een andere planner, een telefoonapp of een fietscomputer. Een route met een routebeschrijving gaat naar buiten zoals Ride with GPS er een schrijft: een `<rte>` van de afslagen, elk met zijn richting en woorden, en ernaast een `<trk>` van de hele lijn; een route zonder routebeschrijving houdt elk punt op de `<rte>`. |
| **FIT-course** | een fietscomputer van Garmin, Wahoo of iets vergelijkbaars die een course verwacht; de routebeschrijving en de interessante punten gaan mee als coursepunten, zodat het apparaat de volgende afslag toont |
| **TCX-course** | een ouder Garmin-apparaat of een trainingssite die Training Center XML leest; de routebeschrijving en de interessante punten gaan mee als coursepunten, met namen ingekort tot de tien tekens die het formaat toestaat |

**Vanuit een rit** (Bibliotheek → Ritten → openen, of de kaart van de rit na het beëindigen):

| Formaat | Gebruik het voor |
|---|---|
| **GPX-track exporteren** | de opgenomen track met zijn tijdstempels; hartslag, cadans, vermogen en temperatuur gaan mee. |
| **FIT-activiteit exporteren** | een activiteitsbestand voor een trainingsplatform |
| **TCX-activiteit exporteren** | hetzelfde als Training Center XML, één ronde per ronde die de rit had, hartslag, cadans en vermogen op elk punt |

Hoe dan ook schrijft Velorki het bestand en geeft het door aan het deelmenu van het systeem, zodat je het in je bestanden kunt zetten, kunt mailen of naar een andere app kunt sturen.

## Komoot, Garmin en de rest

Velorki heeft geen koppeling met Komoot of Garmin, en heeft die ook niet nodig: ze spreken allemaal GPX en FIT, en de meeste lezen nog steeds TCX.

- **Van Komoot naar Velorki**: exporteer de tocht als GPX in Komoot en deel hem dan met Velorki, of sla hem op en open hem met de knop **Bestand importeren**.
- **Van Velorki naar Komoot**: exporteer de route als **GPX-route** en deel hem met de import van Komoot.
- **Naar een Garmin-fietscomputer**: exporteer de route als **FIT-course**, of als **GPX-route** als je apparaat dat liever heeft, en zet hem op het apparaat zoals je gewend bent, via Garmin Connect of door het bestand te kopiëren.
- **Van een Garmin**: de `.fit`-activiteit van het apparaat wordt als rit geïmporteerd.

Een route **naar Strava** sturen gaat ook via een bestand, omdat de API van Strava geen routes kan aanmaken. Zie [Strava en Ride with GPS](./strava-and-ridewithgps).

## Zie ook

- [Bibliotheek](./library)
- [Strava en Ride with GPS](./strava-and-ridewithgps)
- [Delen](./sharing)
- [Een rit opnemen](./recording-a-ride)
