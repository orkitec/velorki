---
title: Offline kaarten en routering
description: Download de kaart die je ziet en de routeringsgegevens waaruit je routes worden berekend, zodat plannen, zoeken en navigeren zonder bereik blijven werken.
order: 7
---

Twee aparte downloads laten Velorki werken zonder verbinding: de **kaart**, die je ziet, en de **routeringsgegevens**, waaruit routes en offline zoeken worden berekend. Download beide voor het gebied waar je rijdt, voor een rit die het bereik achter zich laat.

## De twee soorten

| | Kaart | Routeringsgegevens |
|---|---|---|
| Getoond als | **Kaart** | **Routeringsgegevens** |
| Wat het is | vectorkaarttegels van OpenFreeMap, getekend uit OpenStreetMap | BRouter-tegels van de Velorki-mirror, gebouwd uit OpenStreetMap |
| Beslaat | precies de rechthoek die je op het scherm had | een vast vierkant van 5° × 5° van de wereld |
| Grootte | tientallen megabytes voor een stad | vaak 125 tot 250 MB per tegel |
| Zonder | grijze tegels waar de kaart niet in de cache staat | geen routering en geen offline zoeken in dat gebied |

De routeringsgegevens bevatten ook de plaatsindex, dus een gedownload gebied kun je ook offline doorzoeken en toont het zijn [stopplekken op de kaart](./stops-on-the-map). Daarom zegt het scherm met routeringstegels "Met een gedownloade regio werkt ook het zoeken naar plaatsen zonder bereik." Dezelfde gedownloade regio geeft een opgenomen rit zijn verdeling naar ondergrond, zie [de bibliotheek](./library).

## Een gebied downloaden

1. Schuif de kaart op het tabblad **Plannen** zo dat het gebied dat je wilt het scherm vult. Zoom niet verder uit dan nodig: de kaartdownload volgt precies wat er op het scherm staat.
2. Start de download waar die wordt aangeboden. Overal wordt dezelfde ene vraag gesteld en wordt ter plekke over de kaart gedownload:
   - **Downloaden** in de chip op de kaart. Vanaf zoom 11 staat daar **Dit gebied is niet gedownload**, zodra het midden van de kaart op het tabblad Plannen boven een niet-gedownload gebied ligt; met [stopplekken](./stops-on-the-map) aan staat er in plaats daarvan "Geen stopplekken hier – gebied niet gedownload", met de fietskaart aan "Geen fietskaart hier – gebied niet gedownload".
   - **Downloaden** in de melding bovenaan de zoekresultaten.
   - **3 tegels downloaden (412 MB)** onder een route die tegels nodig heeft.
   - De ronde downloadknop in de kolom rechts van de kaart, die het scherm **Offline** opent: lees de twee kaarten en tik dan onderaan op **Zichtbaar gebied downloaden**. Op een klein scherm zoals een iPhone SE is er in de kolom geen ruimte voor; beheer wat je hebt onder **Instellingen → Kaarten en gegevens → Offline gegevens**. De knop toont een gevuld icoon zodra het gebied in beeld is gedownload (een tik zegt "Dit gebied is gedownload", met **Beheren**), een stip als er updates zijn en een draaiend rondje terwijl er wordt gedownload.
3. Het venster **Zichtbaar gebied downloaden** toont wat je gaat ophalen: "Kaart van het zichtbare gebied · grootte pas bekend na het downloaden" voor de kaart, dan één regel per routeringstegel met zijn grootte, bijvoorbeeld `E5_N45 · 187 MB`, of "Routeringsgegevens voor dit gebied staan al op het apparaat".
4. Tik op **Downloaden**.

Beide downloads lopen zolang de app open is. De chip en de kaart waarvan je startte tonen de voortgang; op het offlinescherm tonen de kaarten **Kaart downloaden…** en **E5_N45 downloaden…** met voortgangsbalken. Het kruisje van de chip is **Download annuleren** zolang de download loopt: het vraagt "Download stoppen?", en **Download annuleren** stopt de kaart en de routeringstegels, verwijdert het onafgemaakte kaartpakket en biedt het gebied opnieuw aan. **Doorgaan met downloaden** gaat verder. De chip verdwijnt zodra het gebied is gedownload. Een kaartdownload die geen vooruitgang meer boekt, wordt opgegeven.

Het scherm waarschuwt je niet voor niets: "Tegels zijn groot, vaak 125–250 MB per stuk, en Velorki kan wifi niet van mobiele data onderscheiden. Start een download als je op wifi zit."

Je komt ook op dit scherm via **Instellingen → Kaarten en gegevens → Offline gegevens**, maar zo geopend staat er geen kaart achter, dus de downloadknop is uitgeschakeld en de notitie zegt "Open dit scherm vanaf de kaart om het gebied te downloaden waar je naar kijkt."

## De kaartgebieden beheren

**Beheren** op de kaart **Kaart** opent **Offline kaarten**, met één rij per gedownload gebied:

- De naam die Velorki het gaf, **Kaartgebied 1**, **Kaartgebied 2** enzovoort.
- De grootte en de datum, "12,3 MB · Gedownload 14 sep. 2026".
- **Vernieuwing beschikbaar** in oranje zodra het gebied ouder is dan twee maanden, met een knop **Vernieuwen** ernaast. Vernieuwen is een volledige nieuwe download.
- Een knop **Verwijderen**, die vraagt "Offline gebied verwijderen?" met "De gedownloade tegels worden van dit apparaat verwijderd."

De kaart op het offline scherm vat hetzelfde samen: "3 gebieden, 48 MB", en "2 gebieden zijn ouder dan twee maanden en kunnen worden vernieuwd".

## De routeringstegels beheren

**Beheren** op de kaart **Routeringsgegevens** opent **Offline routeringsgegevens**. Elke rij is één tegel van 5° × 5° met naam, grootte en status:

| Status | Betekent |
|---|---|
| **Op dit apparaat** | klaar, routering en offline zoeken werken hier |
| **Update beschikbaar** | de mirror heeft deze tegel opnieuw gebouwd; **Bijwerken** downloadt hem opnieuw |
| **Update vraagt een nieuwere Velorki** | de opnieuw gebouwde tegel heeft een gegevensformaat dat deze appversie niet kan lezen |
| **Downloaden…** | bezig |
| **Niet gedownload** | bekend bij de mirror, niet op de telefoon |

Verder op het scherm:

- **Nodig voor deze route** verschijnt als je via de banner over ontbrekende tegels in de planner kwam, met de tegels die die route nodig heeft al uitgekozen en een knop die ze telt, bijvoorbeeld **1 tegel downloaden (187 MB)**.
- **Downloaden voor het zichtbare gebied** onderaan, met het totaal van alles wat je hebt: "3 tegels, 540 MB".
- **Mirror gebouwd 1 sep. 2026** onder elke rij, de datum waarop de mirror die tegel voor het laatst maakte.
- Een knop **Verwijderen** op elke rij, met de waarschuwing "De tegel wordt van dit apparaat verwijderd. Routes in dat gebied hebben dan weer de routeringsserver nodig."
- Een knop **Download annuleren** in de voortgangskop zolang er een loopt.

Velorki controleert wekelijks of de mirror iets opnieuw heeft gebouwd dat jij hebt. Een tegel telt pas als bijgewerkt als zijn inhoud is veranderd, niet elke keer dat de mirror draait. Is dat zo, dan toont een chip op de kaart **Nieuwe kaartgegevens voor dit gebied** met **Bijwerken**, krijgt de downloadknop een stip, en wordt de rij **Offline gegevens** onder **Instellingen → Kaarten en gegevens** oranje, toont "Voor 2 tegels zijn updates" en zet een teller op de pijl. **Bijwerken** op de chip stelt de gebruikelijke vraag en downloadt de gewijzigde tegels opnieuw; het kruisje verbergt de chip voor dit gebied tot je de app opnieuw start.

## De gazetteer, of zoekindex

Naast elke routeringstegel die de mirror publiceert staat een kleine zoekindex, en Velorki downloadt die twee samen. Er is geen aparte instelling voor. Is alleen de zoekindex van een tegel veranderd, dan is de update een kleine download van alleen de index, niet de tegel opnieuw.

Mislukt het downloaden van de index, dan is de tegel zelf nog steeds in orde: het gebied blijft routeerbaar en het zoeken gaat er gewoon online. Hetzelfde geldt voor een index in een formaat dat deze appversie niet leest; die wordt overgeslagen, de andere gebieden blijven offline antwoorden, en in dat gebied wordt online gezocht.

## Waar het allemaal staat, en hoe je het kwijtraakt

Alles staat in de eigen opslag van de app op de telefoon, niet in je documenten of je fotobibliotheek, en niets wordt naar een cloudback-up gekopieerd.

Om ruimte vrij te maken:

- verwijder losse kaartgebieden in **Offline kaarten**,
- verwijder losse routeringstegels in **Offline routeringsgegevens**,
- of verwijder de app, wat alles weghaalt, samen met je routes en ritten. Exporteer eerst wat je wilt houden, zie [importeren en exporteren](./import-and-export).

## "Werk Velorki eerst bij"

Routeringstegels veranderen af en toe van formaat. Als de mirror een tegel aanbiedt die deze appversie niet kan lezen, zegt Velorki dat in plaats van onzin te downloaden: **Werk Velorki eerst bij**, "Deze tegels hebben gegevensformaat 5, en deze Velorki leest tot 4. Ze hebben een nieuwere Velorki nodig; download ze zodra je hebt bijgewerkt." Antwoord **Niet nu**, of **Store openen** om te gaan bijwerken.

Tegels die je al hebt, blijven werken.

## Zie ook

- [Zoeken](./search)
- [Een route plannen](./planning-a-route)
- [Navigatie met afslagaanwijzingen](./navigation)
- [Problemen oplossen](./troubleshooting)
