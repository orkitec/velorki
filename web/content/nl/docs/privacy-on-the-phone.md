---
title: Privacy op de telefoon
description: "In fietsertaal: wat er op je telefoon blijft, wat hem verlaat, wanneer en naar wie. Er is geen account en er wordt niets geüpload tenzij je erom vraagt."
order: 16
---

Velorki heeft geen account, dus er is niets om op in te loggen en niets over jou op een server. Deze pagina is de versie in gewone taal van wat dat in de praktijk betekent; het [privacybeleid](/privacy) is de formele.

## Wat er op de telefoon blijft

Alles wat je maakt en alles wat je downloadt:

- geplande routes, opgenomen ritten en hun GPS-tracks,
- je instellingen, waaronder welke eenheden en welke stem je koos, en het gewicht, geboortejaar, geslacht, de maximale hartslag, het fietsgewicht, het fietstype en het drempelvermogen die je misschien invult onder Instellingen → Fietser; dat zijn instellingen op de telefoon en ze worden nergens heen gestuurd,
- gedownloade offline kaartgebieden,
- gedownloade routeringstegels en de zoekindexen voor plaatsen die erbij horen,
- de toegangstokens voor Strava en Ride with GPS als je die koppelt, die in de beveiligde opslag van de telefoon gaan in een vorm die alleen de Velorki-relay kan openen.

Niets daarvan wordt ergens heen geüpload, tenzij je erom vraagt.

Op Android is Velorki bewust uitgesloten van de cloudback-up van Google en van overzetten van apparaat naar apparaat, dus ook het systeem kopieert je ritten niet van de telefoon af. Overstappen op een nieuwe telefoon betekent wat je wilt houden exporteren als GPX-, FIT- of TCX-bestanden, zie [importeren en exporteren](./import-and-export).

## Wat de telefoon verlaat, en wanneer

### Terwijl je naar de kaart kijkt

Kaarttegels worden opgehaald bij OpenFreeMap, en bij CyclOSM als je **Fietskaart** aanzet onder **Kaartlagen**. Een tegel opvragen vertelt de tegelserver naar welk vierkant van de wereld je kijkt, en daarbij hoort je IP-adres, zoals bij elk verzoek. Een gebied dat je hebt gedownload, komt van de telefoon en vraagt nergens om.

### Terwijl je plant

Routering gebeurt op je telefoon overal waar je de routeringstegels hebt. Voor een gebied dat je niet hebt gedownload, gaan de routepunten naar een routeringsserver, die de route terugstuurt. Die krijgt de routepunten en verder niets: geen identiteit, geen andere routes, geen ritten.

**Instellingen → Geavanceerd → Routering → Alleen op het apparaat** zet de server helemaal uit; Velorki biedt dan de download aan in plaats van te routeren.

### Terwijl je zoekt

Zoeken wordt beantwoord op de telefoon overal waar de index van het gebied is gedownload, en niets wat je typt verlaat het apparaat.

Het gaat online als je op **Online zoeken naar "…"** tikt, of als je geen index hebt voor het gebied waar je naar kijkt. Dan gaat wat je typte naar Photon, samen met een globale positie zodat resultaten in de buurt bovenaan komen.

[Stopplekken op de kaart](./stops-on-the-map) worden gelezen uit de index op de telefoon en vragen nergens om.

Een tik op **Details** op de kaart van een plaats haalt de details ervan (openingstijden, website en dergelijke) op bij OpenStreetMap.

Een korte kaartlink die je met Velorki deelt (`maps.app.goo.gl`, `maps.apple/p`, `osm.org/go`) wordt één keer geopend bij de dienst die hem maakte, om te weten waar hij naartoe wijst; die dienst ziet de link en je IP-adres, net als in een browser.

### Terwijl je opneemt

Er verlaat helemaal niets de telefoon. De opname, de statistieken, de grafieken en de splits worden allemaal op het apparaat berekend. Hetzelfde geldt voor hartslag, cadans en vermogen van een horloge, een Bluetooth-sensor of je gezondheidsapp: ze worden bij de rit bewaard en, als je Gezondheid hebt aangezet, op de telefoon zelf uitgewisseld met Apple Health of Health Connect.

### Als je de assistent iets vraagt

Alleen met je toestemming, en alleen wat je toestond: je tekst, eventueel een positie afgerond op ongeveer een kilometer, je taal- en eenheidsinstellingen. Geen naam, geen account, geen routegeschiedenis, en nooit je track. Zie [assistent](./assistant).

### Als je Strava of Ride with GPS koppelt

Naar geen van beide gaat iets voordat je het account koppelt en dan om iets vraagt, een upload of een import.

Koppelen geeft een eenmalige code aan de Velorki-relay, die er een toegangstoken van maakt door ons applicatiegeheim toe te voegen, en het token verpakt aan je telefoon geeft, zodat alleen de relay het kan openen. Wij bewaren het token niet. Daarna gaat elke upload en import via de relay: die controleert je abonnement, opent het token voor dat ene verzoek en stuurt het door naar Strava of Ride with GPS. Hij bewaart het bestand noch het token, en kan het token niet zelfstandig gebruiken.

### Als je een deellink maakt

Die route of rit, met track, naam en waarden, wordt naar onze server gekopieerd zodat de link kan worden geopend. De link is openbaar voor iedereen die hem heeft, hij laat zien waar de track begint en eindigt, en hij wordt na een jaar automatisch verwijderd. Zie [delen](./sharing).

### Als je Velorki Plus koopt

De store regelt de betaling en wij zien je kaart nooit. Het abonnement wordt gecontroleerd tegen een anonieme willekeurige id die niet gekoppeld is aan een naam, een e-mailadres of een apparaat-id.

## Wat Velorki nooit doet

- Geen account, geen aanmelding, geen e-mailadres.
- Geen advertenties, geen advertentie-SDK, geen profilering.
- Op het moment van schrijven geen analyse- of crashrapportage-SDK in de app. Als er ooit een bijkomt, noemt het privacybeleid hem en zegt het wat hij verzamelt voordat hij wordt uitgebracht.
- Geen verkoop van gegevens, aan niemand, nooit.
- Geen sociale functies en geen berichten tussen gebruikers.

## Dingen kwijtraken

| Wat | Hoe |
|---|---|
| Een route of een rit | verwijder hem in de [bibliotheek](./library) |
| Offline kaartgebieden en routeringstegels | verwijder ze in [offline gegevens](./offline-maps-and-routing) |
| Een token voor Strava of Ride with GPS | **Ontkoppelen** in Instellingen → Koppelingen |
| Alles wat de app heeft opgeslagen | verwijder de app |
| Een deellink | die verloopt na een jaar; mail [hello@orkitec.com](mailto:hello@orkitec.com) met de link om hem eerder te laten verwijderen |

De app verwijderen haalt geen deellinks weg die je hebt gemaakt, en ook niets wat je naar Strava of Ride with GPS hebt geüpload.

## Je rechten

Als je in de EU of het VK bent, geeft de AVG (GDPR) je rechten over je persoonsgegevens. De meeste kun je zelf uitoefenen, omdat de gegevens op je telefoon staan en op elk moment als GPX, FIT of TCX te exporteren zijn. Voor alles aan onze kant, dat wil zeggen deellinks, logregels en het abonnementsrecord, schrijf je naar [hello@orkitec.com](mailto:hello@orkitec.com). De volledige verklaring, met de rechtsgrond en bij wie je een klacht kunt indienen, staat in het [privacybeleid](/privacy).

## Zie ook

- [Privacybeleid](/privacy)
- [Delen](./sharing)
- [Assistent](./assistant)
- [Strava en Ride with GPS](./strava-and-ridewithgps)
- [Offline kaarten en routering](./offline-maps-and-routing)
