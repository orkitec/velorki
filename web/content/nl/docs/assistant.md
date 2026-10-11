---
title: Assistent
description: Beschrijf in één zin de rit die je wilt en Velorki maakt er een route van, met je toestemming, hooguit een afgeronde positie en zonder routegeschiedenis te versturen.
order: 14
---

De assistent maakt van een zin als "een gravelrondje van zo'n 80 km over rustige wegen" een route in de planner. Het is het enige deel van Velorki dat wat je typte naar een server stuurt, dus vraagt het eerst om je toestemming en vertelt het je precies wat er meegaat.

De assistent hoort bij [Velorki Plus](./velorki-plus).

## Openen

Tik op **Vragen** in de werkbalk van het routepaneel op het tabblad **Plannen**. De kaart van de assistent neemt de plaats van het routepaneel in, met de titel **Vraag om een route**: "Beschrijf de rit die je in gedachten hebt. Velorki maakt er een verzoek van en plant de route op je telefoon." De kaart erboven blijft de kaart: verschuif, zoom en tik erop zoals met het routepaneel open. Veeg de kaart naar beneden of ga terug, en het routepaneel is er weer zoals je het verliet; wat je typte en de antwoorden blijven staan voor de volgende keer.

Met een route op de kaart opent het paneel in plaats daarvan op **Deze route**, een vraag over die route (zie [Vraag over deze route](#vraag-over-deze-route)); **Nieuwe route** erboven schakelt terug.

Staat de knop **Vragen** er niet, dan heeft deze build van Velorki helemaal geen serveradres, wat het geval is bij een zelfgebouwde kopie zonder eigen relay.

## Toestemming, en wat de telefoon verlaat

De eerste keer dat je iets verstuurt, toont Velorki **Voordat de assistent iets vraagt**:

> Wat je typt, gaat naar de Velorki-server, die het doorstuurt naar onze AI-aanbieder. Verder gaat er niets mee: geen naam, geen account, geen routegeschiedenis.
>
> Als je het toestaat, wordt ook je positie verstuurd, afgerond op ongeveer een kilometer, zodat "vanaf hier" iets betekent.

Drie antwoorden:

- **Toestaan, met mijn globale positie** verstuurt je tekst en een positie afgerond op ongeveer een kilometer.
- **Toestaan, alleen tekst** verstuurt je tekst en verder niets.
- **Niet nu** verstuurt niets en zet de assistent uit.

Wat er echt meegaat: je tekst, eventueel de afgeronde positie, je taal- en eenheidsinstellingen zodat het antwoord past, en, voor een routebeschrijving of een vraag over een route, een samenvatting van de route (zie hieronder). Er komt geen identificatie van jou of je telefoon in de prompt.

Je kunt je bedenken wanneer je wilt onder **Instellingen → AI-assistent → Wat er wordt verstuurd**, waarvan de ondertitel altijd zegt in welke van de vier toestanden je zit, met een knop **Wijzigen** ernaast.

## Iets vragen

Typ een zin en tik op **Vragen**. Er staan drie voorbeelden klaar om op te tikken:

- **Een vlak rondje van 30 km vanaf hier**
- **Een rondje van 50 km over rustige wegen**
- **Een gravelrondje van zo'n 80 km**

Zodra je typt, bieden chips onder **Toevoegen** de wensen waar de planner iets mee doet: **vlak**, **heuvelachtig**, **over gravel**, **over rustige wegen** en **terug naar de start**, elk tot het gezegd is.

Andere dingen die goed werken: een afstand en een richting, een plaats om langs te rijden, een ondergrond, hoeveel klimmen je wilt, een start die niet is waar je bent.

Het paneel toont **Even denken…** terwijl het model antwoordt, dan **Plaatsen opzoeken…** terwijl de plaatsnamen in coördinaten worden omgezet. Daarna vat het samen wat het begreep: "Rondje van ongeveer 80 km", "Start waar je nu bent" of "Start bij Freiburg", en een chip per plaats om langs te rijden.

Past een naam op meer dan één plaats ver uit elkaar, dan vraagt Velorki **Welk Freiburg?** met maximaal drie keuzes. Een tik op een ervan lost het op de telefoon op, zonder tweede rondje naar het model.

## Wat er met het antwoord gebeurt

Het paneel sluit zichzelf en de planner neemt het over:

- **Een rondje zonder bepaalde plaats om langs te gaan** opent het [rondjespaneel](./loops) met het zoeken al bezig. Is het zoeken klaar, dan sluit het rondjespaneel en komt de assistent terug op **Deze route**, met wat je vroeg boven de vraag, zodat je meteen iets over het rondje kunt vragen. Vond het zoeken geen rondje, dan komt hij terug op **Nieuwe route** en zegt dat. Sluit je het rondjespaneel of doe je er iets in terwijl het zoekt, dan is het zoeken van jou: de assistent blijft weg.
- **Een rondje langs genoemde plaatsen** wordt routepunten met het rondje gesloten, en Velorki zegt "De route staat op de kaart."
- **Een route van A naar B** wordt routepunten met het fietsprofiel ingesteld, en weer "De route staat op de kaart."

Vanaf daar is het een gewoon plan: bewerk het, vraag om varianten, sla het op.

## Wat hij niet doet

Het model geeft nooit coördinaten terug en berekent nooit een route. Het geeft een gestructureerd verzoek terug, een afstand, een vorm, wat plaatsnamen en een voorkeur of twee, en alles daarna gebeurt op je telefoon. Daarom werkt de assistent als manier om te zeggen wat je wilt, en niet als bron van feiten over wegen.

Hij kan het ook mis hebben. Zegt hij iets wat je niet bedoelde, formuleer het dan opnieuw met een duidelijke afstand en een duidelijke plaats.

## Vraag over deze route

Met een route op de kaart van de planner opent **Vragen** op **Deze route**: "Vraag alles over de route op de kaart." Voorbeelden om op te tikken: **Controleer deze route**, **Waar kan ik halverwege koffie drinken?**, **Waar kan ik mijn water bijvullen?**, **Vermijd de hoofdweg**, **Kan dit met een racefiets?**

Wat er meegaat: je vraag en de samenvatting van de route die bij [Deze route beschrijven](#deze-route-beschrijven) wordt beschreven, posities inbegrepen. Je eigen positie gaat in deze modus niet mee.

Het antwoord is een paar zinnen en maximaal zes bevindingen langs de route, elk met waar het is. **Tonen** verplaatst de kaart erheen. Een bevinding waar de planner iets mee kan, heeft een knop:

- **Als tussenstop** routeert langs een café, een kraan of een andere plek uit de samenvatting, ingevoegd waar de route er langskomt.
- **Vermijden** houdt de router weg van dat stuk. Het wordt gestreept op de kaart getekend, en de chip **1 stuk wordt vermeden** boven de kaart heeft **Weer toestaan**.
- **Gravel gebruiken** (of een andere fiets) plant de route opnieuw met dat profiel.

Elk ervan is één stap die **Ongedaan maken** terugdraait, en het paneel blijft open en markeert hem als **Toegepast**. Het model stelt alleen plekken uit de samenvatting voor; het verzint nooit een stop of een coördinaat.

**Deze route** wordt niet aangeboden voor een route die uit Strava is geïmporteerd.

## Deze route beschrijven

Het andere wat de assistent doet, is een alinea schrijven over een route die je al hebt. Open een route in de bibliotheek en tik op **Deze route beschrijven**; het paneel begint meteen te schrijven, en **Opslaan als beschrijving** bewaart de tekst bij de route. **Opnieuw schrijven** vraagt om een nieuwe poging.

Voordat hij iets vraagt, legt de telefoon de route naast zijn routeringstegels en zijn offline plaatszoeker en maakt een samenvatting: de afstand, de stijging, het aandeel verhard en onverhard, de namen van de routepunten, de stukken van de route met hun soort weg, ondergrond en helling, de klimmen, de steden en dorpen waar hij langskomt, en cafés, bakkers, waterkranen, toiletten, uitzichtpunten en fietsenwinkels binnen 300 m ervan, elk met de afstand langs de route en de positie. Zonder gedownloade tegels voor het gebied gaan alleen de cijfers mee. Het model krijgt ook de posities, tot op ongeveer 10 m, zodat het weet waar de rit is; een route die bij je voordeur begint, laat zien waar je voordeur is. Elke plek die de beschrijving noemt, komt uit de samenvatting, dus hij kan "het café in Caniço bij km 9" zeggen en een café bedoelen dat bestaat. Hij schrijft in de taal en de eenheden waarop de app is ingesteld.

De knop wordt niet aangeboden voor een route die uit Strava is geïmporteerd, omdat de voorwaarden van Strava niet toestaan dat hun gegevens aan een AI-aanbieder worden gegeven.

## Limieten en fouten

De assistent heeft een limiet: twintig verzoeken per uur en honderd per dag.

| Wat het paneel zegt | Wat het betekent |
|---|---|
| "Te veel verzoeken. Probeer het over 90 seconden opnieuw." | je hebt de limiet bereikt |
| "De AI-assistent hoort bij Velorki Plus." | geen abonnement |
| "De assistent heeft je toestemming nodig voordat hij iets kan versturen." | toestemming ontbreekt of is geweigerd |
| "Ik weet niet zeker of ik dat begreep. Noem een afstand en een plaats." | het model was niet zeker |
| "Ik kon “Freiburg” niet vinden. Probeer een andere spelling of een plaats in de buurt." | de plaatsnaam leverde niets op |
| "Ik moet weten waar je start. Zet je locatie aan of noem een startplaats." | "vanaf hier" zonder positie |
| "De assistent kon niet antwoorden:" | de server of het model faalde |

**Opnieuw proberen** wist de fout en houdt wat je typte.

## Een slecht antwoord melden

**Instellingen → AI-assistent → AI-antwoord melden** opent een mail aan ons: "Laat ons weten welk antwoord fout of ongepast was." Gebruik het alsjeblieft. Foute en ongepaste antwoorden zijn hoe de prompts beter worden.

## Zie ook

- [Velorki Plus](./velorki-plus)
- [Rondjes](./loops)
- [Een route plannen](./planning-a-route)
- [Privacy op de telefoon](./privacy-on-the-phone)
