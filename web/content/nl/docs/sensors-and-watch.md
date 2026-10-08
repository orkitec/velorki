---
title: Sensoren en je horloge
description: Hartslag, cadans en vermogen van een Bluetooth-sensor, een Apple Watch of de gezondheidsapp van je telefoon, één keer ingesteld en bij elke rit bewaard.
order: 16
---

Velorki kan tijdens het opnemen je hartslag, je trapfrequentie (cadans) en je vermogen tonen, en alle drie daarna bij de rit bewaren. De waarden komen van een Bluetooth-sensor, van een Apple Watch of van de eigen gezondheidsapp van de telefoon, en dat alles is gratis en draait op de telefoon.

Niets hiervan gebeurt voordat je het aanzet. Met elke bron uit vraagt Velorki het besturingssysteem nergens om en noemt geen enkel scherm een sensor.

## Wat je kunt meten

| Bron | Wat het geeft | Wat het nodig heeft |
|---|---|---|
| Bluetooth-sensor | hartslag, cadans, wielsnelheid, vermogen | de sensor, één keer gekoppeld in Velorki |
| Apple Watch | hartslag, en de rit om je pols | een iPhone met een gekoppeld horloge |
| Apple Health of Health Connect | hartslag die iets anders op de telefoon heeft gezet | de gezondheidsapp van de telefoon, en één schakelaar |

Als twee ervan tegelijk hetzelfde melden, wint het horloge van een Bluetooth-sensor, en een Bluetooth-sensor van de gezondheidsapp. Een waarde telt tien seconden als actueel, en als de bron die won stil valt, neemt de volgende het vanzelf over; een band die je thuis hebt laten liggen is er dus gewoon niet.

## Een bron aanzetten

Alles staat in **Instellingen → Sensoren**, direct onder **Opname**:

- **Apple Health** op een iPhone, **Health Connect** op Android, met de regel "Leest de hartslag die andere apps in Gezondheid zetten, zoals de eigen Workout-app van het horloge. Wordt om de paar seconden opgevraagd, loopt dus achter; een borstband of de Velorki-horloge-app neemt het over zodra die iets meldt". Dit aanzetten is het enige in Velorki dat de vraag om toegang tot gezondheidsgegevens kan oproepen. Weiger je, dan zegt Velorki "Velorki heeft geen toegang tot je gezondheidsgegevens gekregen." en laat de schakelaar uit.
- **Ritten opslaan in Gezondheid** daaronder, "Elke beëindigde rit komt in Gezondheid als één fietstraining met start, einde en afstand", dat je los kunt uitzetten. Het doet niets zolang de schakelaar erboven uit staat.
- **Apple Watch**, met de regel "De eigen horloge-app van Velorki: meet je hartslag live tijdens de hele rit, toont de rit en heeft Start, Pauze en Beëindigen om je pols. Kost batterij van het horloge". De rij is er alleen op een iPhone waaraan een horloge is gekoppeld. **Sensor laten rusten tijdens pauzes** daaronder wordt uitgelegd bij [batterij om je pols](#batterij-om-je-pols).
- **Bluetooth-sensoren**, met de regel "Hartslagbanden, snelheids- en cadanssensoren, vermogensmeters", of "1 sensor gekoppeld" zodra je er een hebt. Het opent een eigen scherm.

## Bluetooth-sensoren

### Een sensor koppelen

1. Maak de sensor wakker: doe de band om, of draai aan de cranks. De meeste sensoren zeggen helemaal niets tot ze gebruikt worden.
2. Open **Instellingen → Sensoren → Bluetooth-sensoren** en tik op **Zoeken**. Op een iPhone waarschuwt het scherm "iOS vraagt om Bluetooth de eerste keer dat je zoekt." voordat je tikt. Een zoekronde duurt ongeveer vijftien seconden.
3. Tik onder **Gevonden** op de sensor die je herkent. Elke rij heeft de naam, kleine pictogrammen voor wat hij meet, en de signaalsterkte in dBm, met de sterkste bovenaan.
4. Velorki maakt één keer verbinding om het apparaat te vragen wat het echt heeft, zet het onder **Gekoppeld**, en laat het weer los.

Zolang dat scherm open is, zijn je gekoppelde sensoren verbonden, dus elke rij toont wat hij op dit moment meldt in plaats van **Verbonden**, **Verbinden…** of **Niet verbonden**. Verlaat je het scherm, dan worden ze weer losgekoppeld, tenzij er een rit wordt opgenomen. **Vergeten**, in het menu rechts van een gekoppelde rij, verwijdert een sensor.

### Waarmee Velorki koppelt

De drie standaard fietsprofielen, die bijna alles spreekt wat als fietssensor wordt verkocht:

- **hartslagbanden** en armbanden,
- **snelheids- en cadanssensoren**, op het wiel, op de crank, of één apparaat dat beide doet,
- **vermogensmeters**, waarvan de crankteller ook een cadans geeft, zodat een aparte cadanssensor naast een vermogensmeter overbodig is.

Een apparaat dat geen van de drie spreekt, wordt niet aangeboden. Velorki koppelt met sensoren, niet met fietscomputers: een fietscomputer is iets anders en wordt hier niet verbonden.

### Wielomtrek

Een snelheidssensor telt wielomwentelingen, dus Velorki moet weten hoe ver één omwenteling is. Het veld **Wielomtrek** verschijnt onderaan het scherm zodra een gekoppelde sensor snelheid meldt, met de hint "Millimeter per omwenteling. 2105 is een 700x25c-band." en **mm** achter het getal.

Zolang een wielsensor meldt, vervangt zijn snelheid de GPS-snelheid op het opnamepaneel, en daar draait het om: een wiel klopt op wandeltempo, onder bomen en in een tunnel, waar GPS dat niet doet. Niets anders in de rit gebruikt hem.

### Als een sensor niet wordt gevonden

- **"Nog niets. Maak de sensor wakker: doe de band om of draai aan de cranks."** Een band zonder huidcontact en een stilstaande crank zijn onzichtbaar. Beweeg, en zoek dan opnieuw.
- **"Zet Bluetooth aan om je sensoren te vinden."** De radio van de telefoon staat uit.
- **"Velorki mocht Bluetooth niet gebruiken."** De toestemming is geweigerd. Geef Velorki die in de instellingen van de telefoon en zoek opnieuw.
- **De sensor praat met iets anders.** Deze sensoren bedienen één apparaat tegelijk. Sluit de andere app, of zet de fietscomputer uit.
- **Een gekoppelde sensor die Niet verbonden zegt**, is buiten bereik, slaapt of is leeg. Velorki blijft het proberen zolang een rit wordt opgenomen of dat scherm open is, en wacht na elke poging iets langer.

## Apple Watch

De horloge-app is een scherm en een sensor, nooit een tweede recorder. De telefoon neemt de rit op; het horloge stuurt wat het meet en waar je op tikt, en toont wat de telefoon terugmeldt.

### De horloge-app krijgen

De horloge-app van Velorki zit in de iPhone-app. Hij komt vanzelf op het horloge als je horloge bijbehorende apps automatisch installeert; open anders de app **Watch** op de iPhone en installeer Velorki uit de lijst met beschikbare apps. Zet daarna **Apple Watch** aan in **Instellingen → Sensoren**; dat vraagt ook één keer of Velorki meldingen mag tonen, voor de melding die onder de knoppen wordt beschreven. De eerste keer dat er een training op het horloge start, vraagt het horloge toestemming om je hartslag te lezen. Die vraag komt van het horloge, niet van de telefoon.

### Wat het horloge toont

- Je **hartslag** in grote cijfers, met een kloppend hart zolang het horloge meet; twee streepjes zolang er niets gemeten wordt, en de laatste waarde gedimd zolang de rit gepauzeerd is. Het hart en de knoppen krijgen de accentkleur die je in de app hebt gekozen.
- Een regel in oranje als er iets mis is: toegang tot Gezondheid geweigerd, een training die het horloge niet wilde starten, of een telefoon die niet antwoordde.
- Zolang een rit loopt de afstand, de verstreken tijd en de snelheid, en **Gepauzeerd** als hij gepauzeerd is. De telefoon maakt ze allemaal op, dus ze staan in jouw eenheden en jouw taal.
- De volgende afslag met pictogram, naam en afstand, zoals op het toegangsscherm, in oranje zolang je van de route af bent; zodra een weg terug of een nieuwe route berekend is, de afslagen daarvan.
- Eén tik op je pols als een afslagaanwijzing komt, en één als je de route verlaat. Een horloge dat drie afslagen heeft verslapen, tikt één keer in plaats van drie keer.

De eigen woorden van het horloge, dus de knoppen en de twee voetnoten, zijn Engels, in welke taal de telefoon ook staat. Complicaties zijn er nog niet.

### Wat de knoppen doen

| Knop | Wat hij doet |
|---|---|
| **Rit starten** | start de opname op de telefoon |
| **Pauze**, **Hervatten** | pauzeren en verder rijden, zoals op de telefoon |
| **Beëindigen** | stopt de opname; "Na ‘Beëindigen’ sla je de rit op de telefoon op." |
| **Hartslag stoppen** | stopt het meten op het horloge terwijl de rit doorgaat |
| **Hartslag meten** | start het weer, of start het voor een rit waarin de horloge-app pas later werd geopend |

Als een rit op de telefoon start, opent de horloge-app vanzelf en begint te meten, dus om je pols hoef je niets te tikken. Andersom start **Rit starten** op het horloge de opname op de telefoon en brengt de telefoon naar het tabblad **Opnemen**. Een telefoon in je zak, met Velorki op de achtergrond, krijgt een melding, "Rit gestart vanaf je horloge", en een tik erop opent de app; dat is belangrijk omdat iOS een app die op de achtergrond is gewekt geen GPS geeft tot hij één keer is geopend, dus dan begint de track. Een app die je helemaal hebt weggeveegd kan het horloge helemaal niet wekken, dat is een regel van iOS; na een paar pogingen zegt het horloge "De telefoon reageert niet. Open Velorki op de telefoon en probeer het opnieuw." Een rit die je om je pols beëindigt, wordt opgeslagen zoals elke andere: de opname stopt, en het opslagpaneel wacht op de telefoon als je er de volgende keer op kijkt.

### Batterij om je pols

Urenlang een hartslag meten is wat het horloge zijn dag kost. Er wordt de hele rit gemeten, pauzes inbegrepen: een horloge-app die stopt met meten, wordt door watchOS binnen een minuut in slaap gebracht en hoort dan niets meer van de telefoon, dus wakker blijven is wat de hartslag laat doorkomen. Zolang de rit gepauzeerd is, neemt de telefoon geen hartslag op. Voor ritten met veel stops laat **Sensor laten rusten tijdens pauzes** onder de schakelaar Apple Watch in Instellingen het horloge bij elke pauze stoppen met meten. De ruil: de sensor rust bij elke stop, maar de telefoon moet het horloge weer wekken als je verder rijdt, de eerste hartslag na elke stop duurt even, en als het wekken mislukt ontbreekt de hartslag tot de telefoon het opnieuw probeert. Laat het uit voor een ononderbroken hartslag. Valt het horloge midden in een rit toch driekwart minuut stil, dan start de telefoon zijn app vanzelf opnieuw. **Hartslag stoppen** stopt het meten zonder aan de rit te komen. De voetnoot op het scherm zegt de rest, "Met de energiebesparingsmodus in de instellingen van het horloge houdt de batterij een lange rit vol." Zet je **Apple Watch** uit in Instellingen, dan eindigt ook een sessie die nog loopt.

## Apple Health en Health Connect

Deze bron is de hartslag die je telefoon al kent: wat een Apple Watch via zijn eigen training heeft weggeschreven, of wat een andere app in de opslag heeft gezet. Het is de traagste en minst live van de drie, en een band of een horloge dat direct meldt, neemt het meteen over.

### Wat er wordt gelezen en wat er wordt geschreven

- **Gelezen**: hartslag, en verder niets. Zolang een rit wordt opgenomen vraagt Velorki de opslag elke vijf seconden om nieuwe metingen, of elke dertig seconden met **Batterijbesparing** aan.
- **Achteraf aangevuld**: als de rit wordt opgeslagen, vullen metingen uit de opslag de punten van de track die geen hartslag hebben, zolang een meting binnen een halve minuut van het punt ligt, en worden de waarden van de rit opnieuw berekend. Een punt dat live een waarde van een band of een horloge kreeg, houdt die.
- **Geschreven**: één fietstraining per rit, met start, einde en afstand, en alleen met **Ritten opslaan in Gezondheid** aan. Elke rit wordt één keer geschreven. Met die schakelaar uit leest Velorki alleen.

## Waar de waarden verschijnen

### Tijdens het rijden

Er verschijnt een derde rij waarden op het opnamepaneel met wat er tijdens de rit is gemeld: **Hartslag** met de **Gem. hartslag** van de rit eronder, **Cadans** en **Vermogen**; een horloge alleen voegt dus één tegel toe en zonder sensor komt er niets bij. Een sensor die stil valt houdt zijn tegel, gedimd en gemarkeerd met een verbroken link, tot de rit eindigt. Op een iPhone komt de hartslag bij de waarden op de kaart op het toegangsscherm en in het Dynamic Island.

### Bij een opgeslagen rit

De kaart van een rit in de [bibliotheek](./library) krijgt wat die rit echt bevat:

- **Gem. hartslag**, **Max. hartslag**, **Gem. cadans** en **Gem. vermogen** tussen de waarden, elk alleen als de rit het heeft,
- een grafiek **Hartslag** onder de snelheidsgrafiek, waar je langs kunt slepen voor de waarde op elke afstand.

De tabel **Splits** blijft gelijk: **Split**, **Rijtijd**, **Gem.** en **Stijging**, zonder sensorkolommen. Een rit die uit een GPX-, FIT- of TCX-bestand is geïmporteerd, neemt zijn hartslag, cadans en vermogen mee en toont ze op dezelfde manier.

## Wat er wordt bewaard, en wat de telefoon verlaat

De waarden horen bij de rit: een hartslag, een cadans en een vermogen op elk punt van de track, en de gemiddelden en de maximale hartslag tussen de waarden. Ze staan in de eigen opslag van Velorki op de telefoon, bij de track.

Niets wordt vanzelf geüpload. Een export als GPX, FIT of TCX neemt de waarden mee met de track, dus een rit die je exporteert of naar Strava of Ride with GPS stuurt, komt compleet aan. De uitwisseling met Apple Health of Health Connect gebeurt op de telefoon. Zie [privacy op de telefoon](./privacy-on-the-phone) voor het hele plaatje.

## Zie ook

- [Een rit opnemen](./recording-a-ride)
- [Bibliotheek](./library)
- [Instellingen en weergave](./settings-and-appearance)
- [Privacy op de telefoon](./privacy-on-the-phone)
- [Problemen oplossen](./troubleshooting)
