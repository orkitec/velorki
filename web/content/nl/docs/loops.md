---
title: Rondjes
description: Vraag Velorki om een rondrit van een bepaalde afstand die eindigt waar hij begon, en blader door de kandidaten tot er een goed uitziet.
order: 3
---

Een rondje is een rit die terugkomt waar hij begon, en Velorki maakt ze op basis van een afstand in plaats van punten die je aantikt. Gebruik de knop **Rondje** als je weet hoe ver je wilt fietsen maar niet waarheen, en gebruik hem om een route te sluiten die je al hebt getekend.

De rondjesgenerator is een gewoon algoritme dat op je telefoon draait. Hij is gratis, heeft geen server nodig behalve voor de routering zelf, en er komt geen model aan te pas.

## Openen

Tik op **Rondje** in de werkbalk van het routepaneel op het tabblad **Plannen**. Het paneel heet **Rondje maken**, en wat het aanbiedt, hangt af van wat er al in de planner staat.

## Een getekende route sluiten

Staan er al twee of meer punten in de planner, dan biedt het paneel aan de route terug te brengen naar de start.

1. Er staat "Terugrijden naar waar je begon."
2. Kies onder **FIETS** het profiel. Het is dezelfde instelling als de knoppen in de planner, dus als je hem hier wijzigt, verandert hij daar ook.
3. **Andere weg terug** staat standaard aan, met de opmerking "Vermijdt de wegen die je al hebt gereden." Zet je hem uit, dan kan de terugweg de heenweg hergebruiken.
4. Tik op **Rondje sluiten**. Velorki voegt een kopie van je eerste punt toe, berekent de weg terug en toont het resultaat als `48.2 km · 720 m omhoog`.
5. **Andere weg terug** laat de heenweg precies zoals hij is en vraagt alleen om een andere terugweg. Druk erop zo vaak je wilt; elke druk is één stap om ongedaan te maken. De knop is grijs zolang **Andere weg terug** uit staat.
6. **Klaar** sluit het paneel. Het rondje staat op de kaart van de planner als een gewone route die je kunt bewerken en opslaan.

## Een rondje vanaf nul maken

Is de planner leeg, of staat er één punt in, dan vraagt het paneel in plaats daarvan om een afstand.

1. **Waar het begint.** Staat er al een punt op de kaart, dan is dat de start. Anders staat er **Vanaf je positie**, en vraagt Velorki de eerste keer om je locatie. Lukt het niet je positie te bepalen, dan valt het terug op het midden van de kaart en verandert de regel in **Vanaf het midden van de kaart**.
2. **AFSTAND.** Sleep de schuifregelaar. Metrisch loopt van 5 tot 200 km in stappen van 5 km, imperiaal van 3 tot 125 mijl in stappen van 1 mijl, en het gekozen getal staat groot erboven. Hij opent op wat je de vorige keer vroeg, de eerste keer 30 km.
3. **FIETS.** Dezelfde vijf profielen als in de planner.
4. **Andere weg terug.** Aan betekent een echte cirkel; uit betekent naar een ver punt rijden en via dezelfde weg terug.
5. Tik op **Rondje maken**.

## Tijdens het zoeken

Velorki stuurt het verzoek in acht richtingen uit en geeft zichzelf 25 seconden. Een voortgangsbalk telt de afgeronde verzoeken, en **Stoppen** rechts beëindigt het zoeken vroeg en houdt wat al gevonden is.

## Kiezen tussen de kandidaten

Je krijgt geen lijst om te lezen. Elke kandidaat krijgt een score op hoe dicht hij bij de gevraagde afstand komt, hoeveel hij klimt per kilometer, hoeveel ervan onverhard is, hoeveel over fietspaden en fietsnetwerken loopt, hoeveel dezelfde wegen herhaalt en hoeveel over hoofdwegen gaat. De beste gaat meteen naar de planner en wordt op de kaart getekend, en het paneel toont alleen de samenvatting, `48.2 km · 720 m omhoog`.

Wil je de volgende zien, tik dan op **Een ander**. Dat gaat één stap omlaag in de rangschikking zonder nieuwe routering, dus het gaat meteen. Is de rangschikking op, dan zoekt Velorki opnieuw met de acht richtingen een halve stap gedraaid, zodat de nieuwe pogingen tussen de oude in vallen.

Elke kandidaat die je bekijkt, is een echte route in de planner: schuif eromheen, sleep een punt, bekijk het hoogteprofiel en tik op **Opslaan** als er een goed is.

Veranderen de schuifregelaar of het fietsprofiel na een zoekopdracht, dan is het resultaat verouderd en wordt de knop weer **Rondje maken**.

## Een rondje langs een bepaalde plek vragen

Het rondjespaneel heeft geen veld voor een plek om langs te rijden, en geen voorkeur voor heuvels of ondergrond. Die komen van de [assistent](./assistant): een zin als "Een gravelrondje van zo'n 80 km met een koffiestop" of "een heuvelachtig rondje van 60 km vanaf hier langs het meer" wordt een verzoek met een via-punt en voorkeuren erbij, en de rondjesgenerator doet het werk. De assistent hoort bij Velorki Plus; het rondjespaneel zelf is gratis.

## Als er niets wordt gevonden

- **"Hier geen rondje gevonden, probeer een andere afstand."** Sommige plekken, een eiland of een doodlopend dal, hebben gewoon geen wegennet voor een cirkel van die lengte. Verander de afstand flink omhoog of omlaag, of begin ergens anders.
- **"Zet je locatie aan of tik op de kaart om een start te kiezen."** Er kon geen startpunt worden bepaald. Sta je locatie toe, of tik eerst op de kaart.
- **"Rondje zoeken mislukt:"** met een reden betekent dat de routering zelf is mislukt. Kijk bij [problemen oplossen](./troubleshooting).

Het paneel sluiten breekt een lopende zoekopdracht af, maar houdt wat al gevonden was.

## Zie ook

- [Een route plannen](./planning-a-route)
- [Assistent](./assistant)
- [Offline kaarten en routering](./offline-maps-and-routing)
- [Bibliotheek](./library)
