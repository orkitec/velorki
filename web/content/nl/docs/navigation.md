---
title: Navigatie per afslag
description: Volg een route terwijl je opneemt, met een afslagbanner en gesproken aanwijzingen, en zie wat Velorki doet als je de route verlaat.
order: 7
---

Velorki leidt je langs een route terwijl een rit wordt opgenomen: een banner boven de kaart toont de volgende afslag, en een stem spreekt hem hardop uit. Zet de navigatieschakelaars aan, kies op het tabblad Opnemen een route om te volgen en start de rit.

Navigatie is gratis, werkt offline waar je de routeringsgegevens hebt gedownload, en vraagt geen account.

## Aanzetten

De instellingen staan op twee plekken tegelijk, en het is beide keren dezelfde instelling: in **Instellingen → Navigatie**, en in het paneel van het tabblad Opnemen onder **Scherm aan laten**.

1. **Afslagaanwijzingen**, "De volgende afslag tonen terwijl je langs een route opneemt". Dit is de hoofdschakelaar; de rest is grijs zolang hij uit staat.
2. **Stem**, "De afslagen hardop uitspreken".
3. **Als je de route verlaat**: **Terugleiden**, **Nieuwe route naar de bestemming** of **Niet herberekenen**. Zie [als je de route verlaat](#als-je-de-route-verlaat).

Kies daarna op het tabblad **Opnemen** iets onder **Een route volgen**: **De route op het tabblad Plannen** als de planner een route heeft, of een willekeurige route uit je bibliotheek. Start de rit en de banner verschijnt.

## De afslagbanner

Een balk bovenaan de kaart, boven de kaartknoppen. Van links naar rechts: een pijl voor de afslag, de afstand ernaartoe in grote cijfers, en de aanwijzing.

De aanwijzingen zijn: **Linksaf**, **Rechtsaf**, **Flauw linksaf**, **Flauw rechtsaf**, **Scherp linksaf**, **Scherp rechtsaf**, **Links aanhouden**, **Rechts aanhouden**, **Omkeren**, **Op de rotonde de 3e afslag**, **De afslag links nemen**, **De afslag rechts nemen**, **Rechtdoor** en **Aankomst op je bestemming**.

Volgt er vlak na de eerste afslag nog een, dan staat daar een klein grijs pijltje voor aan het einde van de balk.

Een route die met een routebeschrijving is geïmporteerd, toont in plaats daarvan de eigen woorden van de maker voor een afslag, "Turn left onto Main Street", en de stem spreekt die ook uit.

Een interessant punt op de route, een drinkwaterpunt of een afstapzone uit een geïmporteerd bestand, neemt de banner over als het dichterbij is dan de volgende afslag en binnen 300 m ligt: het icoon, de afstand en de naam, een gevaar als "Let op: …" in de waarschuwingskleur. De stem kondigt het één keer aan, met dezelfde aanloop als een afslag, "Over 100 meter let op: begin afstapzone". Zie [sensoren en je horloge](./sensors-and-watch) voor wat er op het horloge komt, en [importeren en exporteren](./import-and-export) voor waar de punten vandaan komen.

Aan het einde van de route wordt de banner groen en staat er **Je bent er**.

## De stem

Met **Stem** aan wordt elke afslag één keer aangekondigd als je hem nadert en nog een keer bij de afslag: "Over 200 meter linksaf", daarna "Nu linksaf". Twee afslagen vlak na elkaar worden als één aanwijzing uitgesproken, "linksaf, dan rechtsaf". Met imperiale eenheden hoor je "Over 500 voet", "Over een kwart mijl", "Over een halve mijl", "Over een mijl".

**Afslagen aankondigen** in Instellingen → Navigatie bepaalt hoe vroeg: de schuifregelaar is in seconden, en de hint luidt "12 seconden voor de afslag bij je snelheid, nooit dichter dan 50 meter". Omdat hij seconden telt in plaats van meters, komt de aanwijzing op hetzelfde moment, of je nu een heuvel op kruipt of eraf vliegt.

Zolang Stem aan staat, heeft de banner ook een knop om te **dempen**. Die zet de stem stil **alleen voor de rest van deze rit** en laat je instelling met rust; de volgende rit begint weer met geluid.

## Een stem kiezen

1. **Instellingen → Navigatie → Spreekstem**.
2. De eerste regel is **Systeemstandaard**, "De eigen stem van de telefoon voor je taal". Daaronder staat elke stem die op de telefoon is geïnstalleerd, met een naam als "Stem 2 (vrouwelijk, Verenigd Koninkrijk)".
3. Tik op een regel om hem te kiezen. Hij spreekt dan een voorbeeld uit.
4. Tik op **Beluisteren** bij een regel om hem te horen zonder hem te kiezen.

Twee dingen om te weten:

- **Stemmen die internet nodig hebben.** Sommige telefoons bieden stemmen die op een server worden gemaakt. Ze zijn verborgen tot je onderaan **Onlinestemmen tonen** aanzet, en elk is gemarkeerd met **Heeft internet nodig**. Velorki waarschuwt: "Een stem met een wolkje wordt online gemaakt. Waar geen bereik is, blijft de aanwijzing uit of komt die te laat. Kies voor ritten liever een stem die op de telefoon staat."
- **Op een iPhone met alleen de compacte stem** toont Velorki **Betere stemmen zijn een download verwijderd** en loopt het met je door: Instellingen → Toegankelijkheid → Gesproken materiaal → Stemmen → je taal → tik op de wolk naast een stem Verbeterd of Premium. Daarna kiest de app vanzelf de beste stem op de telefoon.

Heeft de telefoon helemaal geen stem voor je taal: "Er is geen stem voor je taal geïnstalleerd. Voeg er een toe in de instellingen van de telefoon, onder tekst-naar-spraak of Gesproken materiaal."

## Als je de route verlaat

De meeste verkeerde afslagen zijn binnen een blok weer goedgemaakt, dus er gebeurt niets op het moment dat je afdwaalt.

Ongeveer **75 meter** van de route, twee positiebepalingen achter elkaar of zo'n acht seconden lang, en de banner wordt oranje: **Terug naar de route, links van je**, met de afstand tot het dichtstbijzijnde punt van de route dat nog voor je ligt. Zoveel gebeurt in elke modus, en het kost geen routering.

Wat er daarna gebeurt, is de keuze onder **Als je de route verlaat**. De wachttijd is voor beide modi die routeren hetzelfde: ongeveer **driekwart minuut naast de route, of 150 meter van waar je hem verliet**, en nooit eerder dan 15 seconden, zodat een reeks slechte positiebepalingen niets kost. **Tik op de banner** om het wachten over te slaan.

### Terugleiden

De standaard. Je plan wordt nooit vervangen. Velorki zoekt een weg terug ernaartoe, naar een punt **voor** je: het probeert 300 meter, 800 meter en 2 kilometer verder langs het plan, gerekend vanaf waar je naast het plan bent gekomen in plaats van waar je het verliet, en neemt de eerste die geen onzinnige omweg is en je niet tegen de richting in door een eenrichtingsstraat, over een stoep of terug langs de weg die je kwam stuurt. De weg terug wordt als eigen lijn in een eigen kleur getekend, met het plan nog op de kaart, en de banner en de stem volgen hem. Terug op het plan verdwijnt de weg terug zonder iets te zeggen en gaan de eigen afslagen van het plan verder.

Rijd je in plaats daarvan je eigen weg, dan wordt de weg terug opnieuw berekend, maar pas als je **300 meter** verwijderd bent van waar de vorige werd berekend, en nooit naar een punt vóór de vorige: hij schuift met je mee in plaats van je terug te roepen, en één minuut rijden is het meeste dat hij van de router vraagt. Hij geeft het plan nooit op en plant nooit uit zichzelf een nieuwe route.

### Nieuwe route naar de bestemming

Als je de route verlaat, plant Velorki opnieuw van waar je bent naar de bestemming, via de tussenstops die je nog niet hebt bereikt, en dat wordt de route voor de rest van de rit. Het oude plan blijft vaag op de kaart staan. Verlaat je ook de nieuwe route, dan plant het opnieuw, zodra je 300 meter verwijderd bent van waar het dat de vorige keer deed, zodat het niet in rondjes kan blijven draaien.

### Niet herberekenen

Alleen de oranje banner, met de afstand tot de route en de richting terug. Velorki vraagt de router niets, en op de banner tikken doet niets.

### Terwijl je naast de route bent

De banner toont **Opnieuw berekenen…** terwijl een weg terug of een nieuwe route wordt berekend, en **Route opnieuw berekend** als er een nieuwe route is. **Nieuwe route vanaf hier**, een knop naast de oranje banner, plant meteen van waar je staat naar de bestemming, ongeacht de instelling.

Alle afstanden hierboven groeien mee met hoe slecht je GPS-positie is, ruwweg een verdubbeling met de opgegeven nauwkeurigheid, zodat een telefoon onder bomen je niet steeds kwijt verklaart. Ze groeien niet verder bij een nauwkeurigheid van 100 meter, zodat een telefoon die de lucht helemaal kwijt is, de detectie van het verlaten van de route niet kan uitschakelen.

## De kaart tijdens het navigeren

- De kompasknop op de kaart wisselt tussen **Noorden boven** en **Kaart draait mee**. Je keuze wordt onthouden voor de volgende rit.
- Je positie staat in het deel van de kaart boven het paneel: in het midden met het noorden boven, laag als de kaart meedraait, zodat je vooral de weg voor je ziet.
- De kaart houdt de zoom aan die je met knijpen kiest terwijl hij je volgt, van een paar kilometer breed tot één blok; alleen slepen stopt het volgen.
- **Mijn positie tonen** pakt het volgen weer op nadat je de kaart hebt verschoven, op de gewone zoom op straatniveau.
- Zolang je op de route bent, wordt de positiemarkering op de route getekend en langs de route gericht, in plaats van met de positiebepaling mee te zwerven.
- De eigen punten van de route staan ook op de kaart: de start, de bestemming met haar vlag, elke tussenstop met een naam of een soort, en de plekken naast de route. Een punt dat alleen de lijn vormt, blijft weg. De tussenstops waar je voorbij bent, vervagen, en ze blijven vaag als je teruggaat. Na een nieuwe route naar de bestemming zijn de markeringen nog die van je eigen route.
- Met **Stopplekken** aan onder **Kaartlagen** staan de stopplekken naast de route voor je op de kaart, en een regel noemt de eerstvolgende van elke soort met zijn afstand; zie [stopplekken op de kaart](./stops-on-the-map#langs-de-route-vooruit).

## Zie ook

- [Een rit opnemen](./recording-a-ride)
- [Een route plannen](./planning-a-route)
- [Offline kaarten en routering](./offline-maps-and-routing)
- [Instellingen en weergave](./settings-and-appearance)
- [Problemen oplossen](./troubleshooting)
