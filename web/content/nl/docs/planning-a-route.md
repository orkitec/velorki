---
title: Een route plannen
description: Tik punten op de kaart, kies een fietsprofiel, vergelijk varianten, lees de cijfers over hoogte en ondergrond, en sla de route op in je bibliotheek.
order: 2
---

Het tabblad Plannen maakt van tikken op de kaart een fietsroute, berekend op je telefoon overal waar je de routeringsgegevens hebt gedownload. Gebruik het als je een rit vooraf wilt bepalen, wilt bijschaven en wilt bewaren.

## De start en de bestemming kiezen

1. Open het tabblad **Plannen** en schuif de kaart naar waar je wilt beginnen.
2. **Tik op de kaart** om de start te kiezen. Het paneel onderaan zegt "Tik nog eens op de kaart om een bestemming toe te voegen."
3. **Tik nog eens** voor het volgende punt. Elke tik voegt een punt toe aan het einde van de route, en het laatste, de bestemming, draagt een vlag. Wil je een punt juist in het midden, **tik dan op de routelijn** waar het moet komen: het punt komt daar op de lijn, en je kunt het verslepen zoals elk ander.
4. Velorki wacht even na je laatste wijziging en berekent dan de route. Terwijl het rekent, toont het paneel een draaiend wieltje en **Route berekenen…**; daarna verschijnen de cijfers.

Je kunt ook vanaf een plek beginnen in plaats van een tik. Typ in het zoekveld bovenaan en kies een resultaat, of tik op een [stopplek op de kaart](./stops-on-the-map); zolang het plan nog leeg is, biedt de [kaart van de plek](./search#de-plaatskaart):

- **Route hierheen** rijdt van waar je bent naar de plek.
- **Hier starten** maakt de plek het eerste punt van de route.

Met alleen een start biedt de kaart **Als bestemming**. Zodra er een route wordt gepland, biedt de kaart **Als tussenstop**, dat de plek in de route invoegt waar hij onderweg ligt, en **Als bestemming**, dat hem aan het einde toevoegt. Zie [zoeken](./search) voor wat het zoekveld kan vinden.

## Een plek naast de route markeren

**Houd de kaart ingedrukt** waar iets is dat het onthouden waard is, en het puntpaneel opent voor een plek daar: een fontein, een station, een camping. De route wordt er niet doorheen getekend. De markering draagt het icoon van het soort dat je kiest, met de naam ernaast, en een tik erop opent het paneel opnieuw.

Om een punt te verplaatsen dat je al hebt, **sleep je de markering**. Bij een gesloten rondje verplaatst het slepen van de startmarkering beide uiteinden, zodat het rondje gesloten blijft. Een wijziging berekent alleen de stukken naast het punt dat je hebt aangeraakt opnieuw; de rest van de route blijft zoals hij was.

## Op de route of ernaast

Elk punt is een van twee dingen, en de schakelaar bovenaan het paneel zegt welk:

- **Op de route**: een punt waar de rit doorheen gaat. Het draagt een genummerde schijf, de bestemming een vlag met het nummer ernaast, en de router buigt de route om het aan te doen.
- **Naast de route**: een plek waar de rit langs komt. Het draagt het icoon van zijn soort, en de route negeert het.

Zet een punt op **Naast de route** en het verlaat de route, die opnieuw zonder het punt wordt getekend; de markering blijft waar hij is. Zet het op **Op de route** en het wordt een punt in het midden, op de plaats langs de route waar het ligt, en de route wordt er opnieuw doorheen getekend. In beide gevallen gaan de naam, het soort en de notitie mee.

## Een punt wijzigen of verwijderen

Tik op een markering om het paneel te openen. Van boven naar beneden:

- **Op de route** of **Naast de route**, de schakelaar hierboven,
- **Naam**, met het icoon van het soort ervoor, ingevuld met de naam van het punt of, voor een punt op de route zonder naam, het nummer; een nummer dat je laat staan, benoemt niets. Een plek naast de route opent met een lege naam,
- **Soort**: een raster van tegels, vier rijen van vier, bij elke breedte allemaal tegelijk in beeld: **Gevaar**, **Water**, **Eten**, **Overig**, **Top**, **Uitzicht**, **Schuilplek**, **Winkel**, **Fietsenmaker**, **EHBO**, **Toilet**, **Camping**, **Onderdak**, **Parkeerplaats**, **Trein/veer** en **Afslag**. **Onderdak** is een bed in plaats van een staanplaats: een hotel, een hostel, een pension. Een **Afslag** krijgt daaronder een **Richting** (links, rechts, flauw, scherp, links of rechts aanhouden, rechtdoor, omkeren) en wordt een regel van de routebeschrijving, zodat de afslagbanner en de stem hem daar uitspreken; een route die met een routebeschrijving is geïmporteerd, opent met de geschreven afslagen als punten van dit soort, klaar om te wijzigen. **Afslag** wordt alleen aangeboden voor een punt op de route: een aanwijzing voor een weg waar de rit niet langs gaat, zegt niets,
- **Notitie**,
- **Eerder aandoen** en **Later aandoen**, die het punt meteen met zijn buur in de volgorde verwisselen en het paneel open laten, zodat je een punt in één keer kunt verplaatsen en een naam geven. Alleen voor een punt op de route; een plek ernaast heeft geen plaats in de volgorde,
- **Punt verwijderen**, voor beide soorten,
- **Klaar**, dat de schakelaar, de naam, het soort en de notitie toepast. Trek het paneel omlaag om ze te laten zoals ze waren.

Een verwisseling, een verwijdering, een omzetting en een Klaar die iets veranderde, zijn elk één stap om ongedaan te maken. Een punt op de route met een naam toont die naam op de markering in plaats van het nummer, met het icoon van het soort ernaast. De gegevens worden met de route opgeslagen en komen terug als je hem weer in de planner opent; bij een route die uit de bibliotheek is geopend, gaan ze meteen de bibliotheek in, zolang de route sindsdien niet opnieuw is berekend, dus voor alleen een naam of een notitie hoef je niet op Opslaan te drukken.

## Wat elk punt wordt in een geëxporteerd bestand

Beide soorten gaan mee, en een fietscomputer kan ze zo goed uit elkaar houden als het formaat toelaat:

- **GPX**: elke plek naast de route, en elk punt op de route met een naam of een notitie, wordt geschreven als `<wpt>` met het soort en de notitie. De punten op de route zijn ook de `<rtept>`-lijst, zodat het bestand opnieuw kan worden gepland.
- **FIT** en **TCX**: beide soorten worden coursepunten op de course, naast de afslagen uit de routebeschrijving. FIT heeft een eigen type voor water, eten, een gevaar, een top, EHBO, een toilet en een camping; TCX alleen voor water, eten, een gevaar, een top en EHBO. Onderdak, parkeren en vervoer hebben in geen van beide een type, en gaan mee als algemene coursepunten met hun naam. Al het andere gaat mee als algemeen coursepunt met zijn naam.
- Een punt dat uit een bestand kwam, houdt het woord dat dat bestand ervoor gebruikte. Exporteer je het opnieuw zonder het soort te wijzigen, dan wordt dat woord teruggeschreven, zodat een klimcategorie, een sprint of een segmentmarkering — dingen waarvoor Velorki geen eigen soort heeft — de rondgang overleeft. Wijzig je het soort, dan wordt het woord van het nieuwe soort geschreven.

## De fiets kiezen

De rij knoppen onder het zoekveld is het fietsprofiel, en dat bepaalt welke wegen en paden de router mooi vindt:

| Profiel | Waarvoor het is |
|---|---|
| **Toer** | de standaard: een verstandige mix van rustige wegen en fietspaden |
| **Racefiets** | asfalt, minder omwegen, vermijdt ruwe ondergrond |
| **Gravel** | voelt zich thuis op karrensporen en onverharde ondergrond |
| **MTB** | paden en singletracks |
| **Direct** | de kortste weg, met het minste oog voor comfort |

Elk profiel behalve **Direct** is dat van BRouter zelf, met één wijziging van Velorki: het stuurt je niet tegen de richting in door een eenrichtingsstraat of over een stoep om een blok uit te sparen. Een ander profiel kiezen berekent het hele plan opnieuw, ook een route uit een bestand, en wist geladen varianten; **Ongedaan maken** zet de route en het profiel terug. Velorki onthoudt het laatst gekozen profiel voor de volgende keer.

## Een route uit een bestand

Een route die uit een bestand is geopend, houdt precies de lijn van het bestand, met alleen punten aan het begin, aan het einde en bij de plekken met een naam op de track. Een punt verplaatsen, toevoegen of verwijderen berekent alleen de stukken ernaast opnieuw; overal anders blijft de lijn die van het bestand. Zolang de route van het bestand afwijkt, wordt de lijn van het bestand vaag eronder getekend en staat er op de kaart een label **Wijkt af van het bestand**; de knop **Herstellen** daarin zet de route van het bestand terug, in één stap die Ongedaan maken kan terugdraaien.

## De werkbalk

De rij knoppen in het routepaneel:

- **Ongedaan maken** draait de laatste wijziging terug. Er is geen limiet en geen opnieuw. Punten toevoegen, invoegen, verplaatsen, verwijderen en herschikken, **Omkeren**, **Wissen**, het fietsprofiel wijzigen, **Herstellen**, een rondje sluiten en een andere weg terug nemen kunnen allemaal ongedaan worden gemaakt; van variant wisselen en een opgeslagen route laden niet.
- **Omkeren** rijdt de route andersom.
- **Wissen** gooit het plan weg. Ook dat kan ongedaan worden gemaakt.
- **Varianten** vraagt om alternatieven (zie hieronder).
- **Rondje** opent het paneel voor slimme rondjes, beschreven bij [rondjes](./loops).
- **Vragen** opent de [assistent](./assistant). Die knop is er alleen als de build met een Velorki-server praat.

Onder de rij staat de knop **Opslaan** over de volle breedte.

## Varianten

Velorki haalt niet uit zichzelf alternatieven op, omdat elk ervan een aparte routeberekening is. Tik op **Varianten** en het vraagt om maximaal vier routes voor dezelfde punten.

Boven de werkbalk verschijnt dan een rij knoppen: **Hoofd**, **Alt. 1**, **Alt. 2**, **Alt. 3**, elk met een gekleurde stip die past bij de lijn op de kaart. Tikken op een knop wisselt meteen, zonder nieuwe berekening, en tekent die lijn bovenop.

Varianten zijn hele routes die de router heeft getekend, dus bij een route uit een bestand vervangen ze de lijn van het bestand; **Ongedaan maken** brengt die terug. Vaak komen er minder dan vier terug; wat de router vond, is wat je krijgt. Komt er geen enkele, dan zegt Velorki "Geen alternatieven beschikbaar." Een routepunt bewerken of het fietsprofiel wijzigen wist de varianten, dus vraag daarna opnieuw.

## De route lezen

De kop van het paneel toont vier cijfers: **Afstand**, **Stijging**, **Daling** en **Duur**. De geschatte tijd komt van de gebruikelijke snelheid van het gekozen fietsprofiel, niet van een server, en houdt geen rekening met je koffiestops.

Het paneel scrolt op elke hoogte; sleep de greep of de titel omhoog voor meer ruimte, of sleep ergens op het paneel als er niets te scrollen is. Helemaal omlaag getrokken, klapt het in tot in de navigatiebalk en blijft alleen de greep boven de tabbladen over, zodat de kaart vrij is; sleep de greep omhoog om het terug te halen.

### Hoogte

De grafiek **Hoogteprofiel** tekent de hoogte tegen de afstand. Raak hem aan en sleep erlangs: naast het bijschrift verschijnt een uitlezing in de vorm `12.3 km · 340 m`, die je vinger volgt. Laat los en de uitlezing verdwijnt. Een route zonder hoogtegegevens zegt "Geen hoogtegegevens voor deze route."

### Ondergrond

De balk **Ondergrond** is één gestapelde balk van drie delen die samen de hele route vormen, **Verhard**, **Onverhard** en **Onbekend**, met daaronder een legenda met percentages. Twee andere items in de legenda, **Fietspad** en **Drukke wegen**, overlappen met de eerste drie in plaats van erbij op te tellen: ze vertellen hoeveel van de route over een vrijliggend fietspad gaat, en hoeveel over een grote weg. Voor een route die niet helemaal van de router zelf komt, met de lijn van een bestand erin, wordt de hele lijn voor de cijfers over de routeringsgegevens gelegd, en daarvoor moet de regio gedownload zijn.

## Opslaan

1. Tik op **Opslaan**.
2. Het venster **Route opslaan** stelt een naam voor, ofwel die waaronder hij eerder is opgeslagen, ofwel **Route 17 sep. 2026** met de datum van vandaag.
3. Typ je eigen naam, of laat hem staan, en tik op **Opslaan**.

Je krijgt "Route opgeslagen", en de route staat in **Bibliotheek → Routes**. Sla je een route op die je al had opgeslagen, dan wordt dezelfde vermelding bijgewerkt in plaats van een tweede gemaakt.

## Als er geen route komt

- **"Deze route heeft routeringstegels nodig die niet op dit apparaat staan."** verschijnt in plaats van de cijfers als je telefoon geen routeringsgegevens voor het gebied heeft en geen routeringsserver om op terug te vallen. De knop eronder telt de tegels en hun grootte, bijvoorbeeld **3 tegels downloaden (412 MB)**, en opent het offlinescherm met precies die tegels geselecteerd. Zie [offline kaarten en routering](./offline-maps-and-routing).
- **"Geen routeringsserver ingesteld, stel er een in onder Instellingen → Geavanceerd."** is een kaart onder de fietsknoppen, en betekent dat deze build helemaal geen serveradres heeft.
- Al het andere verschijnt als **Route berekenen mislukt:** met de reden.

## Zie ook

- [Rondjes](./loops)
- [Zoeken](./search)
- [Offline kaarten en routering](./offline-maps-and-routing)
- [Bibliotheek](./library)
- [Navigatie per afslag](./navigation)
