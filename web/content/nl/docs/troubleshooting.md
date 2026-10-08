---
title: Problemen oplossen
description: "Oplossingen voor de gewone problemen: geen positie, geen route, de banner over ontbrekende tegels, een stille stem op iOS, vastgelopen downloads en links die niet openen."
order: 17
---

Wat het vaakst misgaat, en wat je er telkens aan doet. Staat je probleem er niet bij, dan zegt de laatste sectie hoe je het meldt.

## Velorki vindt mijn positie niet

De symptomen zijn "Nog geen positie bepaald.", een locatieknop die niets doet, of "Zet je locatie aan of tik op de kaart om een start te kiezen."

1. **Is de toestemming geweigerd?** Velorki vraagt het met een eigen venster, **Je positie tonen?**, vóór dat van het systeem. Antwoordde je **Niet nu**, tik dan nog eens op de locatieknop en antwoord **Doorgaan**.
2. **Staat het uit voor Velorki?** "Locatietoestemming staat uit voor Velorki. Zet die aan in de systeeminstellingen." komt met een actie **Instellingen** die je er direct heen brengt. Kies "Alleen toestaan bij gebruik van de app" of "Bij gebruik van app".
3. **Staan de locatievoorzieningen op de telefoon uit?** "Locatievoorzieningen staan uit op dit apparaat." gaat over de telefoon, niet over Velorki. De actie **Instellingen** opent de juiste plek.
4. **Binnen, of net aangezet?** "Nog geen positie bepaald." betekent vaak dat de telefoon nog helemaal geen positie heeft. Ga naar buiten en geef hem een halve minuut.

Velorki heeft nooit locatie op de achtergrond nodig. "Bij gebruik van de app" is genoeg, ook voor het opnemen van een rit.

## Er verschijnt geen route

**"Deze route heeft routeringstegels nodig die niet op dit apparaat staan."** Je telefoon heeft geen routeringsgegevens voor het gebied en er is geen routeringsserver om op terug te vallen. Tik op de knop, die de tegels en hun grootte telt, en download ze. Zie [offline kaarten en routering](./offline-maps-and-routing).

**"Geen routeringsserver ingesteld, stel er een in onder Instellingen → Geavanceerd."** Deze build levert geen serveradres mee. Download de routeringstegels voor waar je bent en routeer in plaats daarvan op de telefoon.

**Instellingen → Geavanceerd → Routering staat op "Alleen op het apparaat".** Dan vraagt Velorki met opzet nooit een server. Zet het op **Automatisch** of download de tegels.

**"Route berekenen mislukt:" met een reden.** Meestal was de server niet bereikbaar. Probeer het opnieuw, en controleer dat er geen routepunt in zee is beland of op een snelweg waar geen fiets mag komen. Het lastige punt een paar meter naar een echte weg schuiven lost het meestal op.

## De banner over ontbrekende tegels gaat niet weg

De banner staat in de planner zodra de route door een gebied gaat waarvan de routeringstegel niet op de telefoon staat. Velorki routeert nooit op gedeeltelijke dekking, omdat de router de ontbrekende tegel als leeg land zou behandelen en stilletjes een verkeerde route zou teruggeven.

1. Tik op de knop op de banner. Die opent **Offline routeringsgegevens** met precies de tegels die de route nodig heeft al uitgekozen.
2. Download ze. Tegels zijn 125 tot 250 MB per stuk, dus zorg dat je op wifi zit.
3. Als een tegel binnen is, routeert de planner vanzelf opnieuw en wordt de banner vervangen door de waarden van de route.

Tonen de tegels die je nodig hebt **Update vraagt een nieuwere Velorki**, werk dan eerst de app bij; het venster legt uit waarom.

## De stem zegt niets

Controleer in deze volgorde:

1. **Instellingen → Navigatie → Afslagaanwijzingen** aan, en **Stem** aan. Stem is grijs zolang Afslagaanwijzingen uit staat.
2. **De dempknop op de afslagbanner.** Die zet de stem alleen voor de rest van die rit stil. Tik er nog eens op.
3. **Volg je een route?** Begeleiding heeft een route nodig die gekozen is onder **Een route volgen** op het tabblad Opnemen, en een rit die echt wordt opgenomen.
4. **Het eigen volume en de stilteschakelaar van de telefoon.**

### Op een iPhone

Toont Velorki **Betere stemmen zijn een download verwijderd**, dan heeft de telefoon voor je taal alleen de compacte stem. Volg de stappen op de kaart: **Instellingen → Toegankelijkheid → Gesproken materiaal → Stemmen → je taal → tik op de wolk** naast een stem Verbeterd of Premium. Velorki gebruikt daarna vanzelf de beste stem op de telefoon.

Is de gekozen stem gemarkeerd met **Heeft internet nodig**, dan wordt hij op een server gemaakt: zonder bereik blijft de afslag onuitgesproken of komt hij te laat. Kies voor ritten een stem zonder dat kenmerk. Die stemmen zijn verborgen tenzij **Onlinestemmen tonen** onderaan de lijst met stemmen aan staat.

"Er is geen stem voor je taal geïnstalleerd." betekent dat de telefoon niets heeft om mee te spreken; voeg een stem toe in de eigen instellingen voor tekst-naar-spraak of Gesproken materiaal van de telefoon.

## Een download loopt vast of mislukt

- **Downloads lopen alleen zolang de app open is.** Laat Velorki op de voorgrond staan voor een grote tegel. Stopt hij, dan blijft wat binnen was bewaard en gaat de volgende poging vanaf daar verder.
- **"De download is mislukt:"** met een reden. Tik nog eens op de tegel om het opnieuw te proberen. Een hervatte download begint niet bij nul.
- **"De tegellijst kon niet worden geladen:"** betekent dat de mirror niet bereikbaar was. **Opnieuw proberen** staat op het scherm.
- **Controleer de vrije ruimte op de telefoon.** Een routeringstegel van 250 MB heeft 250 MB nodig, en het kaartgebied komt daar nog bij.
- **Annuleer en start opnieuw** met de sluitknop in de voortgangskop als een download duidelijk stilstaat.
- Velorki kan wifi niet van mobiele data onderscheiden, dus het waarschuwt in plaats van te blokkeren. Start grote downloads zelf op wifi.

## Een deellink opent niet in de app

- **De link is ouder dan een jaar.** Gedeelde items worden na 365 dagen automatisch verwijderd, en de pagina zegt dan dat hij niet gevonden is. Vraag om een nieuwe link.
- **De app is niet op die telefoon geïnstalleerd.** De pagina werkt nog steeds in de browser: de kaart, de waarden en **GPX downloaden**.
- **"Openen in Velorki" deed niets.** Download de GPX van de pagina en open hem in plaats daarvan met Velorki; hij komt op hetzelfde importscherm terecht. Een verlopen of verkeerd getypte link wordt stil genegeerd in plaats van een fout te tonen.

## Een bestand wil niet importeren

Velorki leest GPX, FIT en TCX, en beslist op basis van de bytes, niet van de bestandsnaam.

| Melding | Betekenis |
|---|---|
| "Dat is geen GPX-, FIT- of TCX-bestand." | de inhoud is geen van de drie formaten, wat de naam ook zegt |
| "Dat bestand kon niet worden gelezen." | het bestand is een van de formaten, maar beschadigd |
| "Dat bestand heeft geen trackpunten." | een leeg bestand, of een GPX met alleen routepunten |
| "Dat bestand kon niet worden geopend." | het systeem wilde het bestand niet doorgeven |

Wordt een bestand als het verkeerde soort geïmporteerd, zet dan **OPSLAAN ALS** op het importscherm om tussen **Route** en **Rit** voordat je opslaat. FIT-courses worden als ritten geraden vanwege de manier waarop hun tijdstempels werken.

## De opname stopte vanzelf

Antwoord op Android bij **Op de achtergrond blijven opnemen** met **Instellingen openen**, sta daar onbeperkt batterijgebruik toe, en geef de toestemming voor meldingen; die twee houden het systeem ervan af de opname te beëindigen terwijl de telefoon slaapt. Op beide platforms wordt de track doorlopend weggeschreven, dus als de app werd afgesloten krijg je bij de volgende start **Onafgemaakte rit**, met **Hervatten**, **Beëindigen** en **Weggooien**. Zie [een rit opnemen](./recording-a-ride).

## Een Bluetooth-sensor wordt niet gevonden

1. **Maak de sensor wakker.** Een band zendt alleen met huidcontact, een cadanssensor alleen als de crank draait. Het scherm zegt het ook: "Nog niets. Maak de sensor wakker: doe de band om of draai aan de cranks."
2. **Zet Bluetooth aan.** "Zet Bluetooth aan om je sensoren te vinden." gaat over de radio van de telefoon, niet over de sensor.
3. **Geef de toestemming.** "Velorki mocht Bluetooth niet gebruiken." betekent dat die is geweigerd. iOS vraagt het de eerste keer dat je op **Zoeken** tikt, en alleen dan.
4. **Maak de sensor vrij.** Deze sensoren bedienen één apparaat tegelijk, dus een fietscomputer of een andere app die de jouwe vasthoudt, zorgt dat Velorki hem niet ziet.
5. **Zoek opnieuw.** Een zoekronde duurt ongeveer vijftien seconden en toont alleen apparaten die de standaardprofielen voor hartslag, snelheid en cadans, of vermogen spreken.

Een gekoppelde sensor die **Niet verbonden** zegt, is buiten bereik, slaapt of is leeg. Velorki blijft het proberen zolang een rit wordt opgenomen of het scherm **Bluetooth-sensoren** open is. Zie [sensoren en je horloge](./sensors-and-watch).

## Het horloge maakt geen verbinding

- **Er is geen schakelaar Apple Watch.** Die verschijnt in **Instellingen → Sensoren** alleen op een iPhone waaraan een horloge is gekoppeld.
- **De horloge-app staat niet op het horloge.** Hij zit in de iPhone-app; kwam hij niet vanzelf, installeer Velorki dan via de app **Watch** op de iPhone.
- **De rit loopt maar het horloge meet niets.** Een rit die op de telefoon start, opent de horloge-app en laat hem vanzelf meten. Toont de horloge-app toch twee streepjes, tik er dan op **Hartslag meten**; een oranje regel onder het hart zegt wat er misging, als het horloge het weet.
- **Het horloge toont geen hartslag.** Het horloge vraagt toestemming om je hartslag te lezen de eerste keer dat er een training start. Is die geweigerd, geef hem dan in de eigen privacyinstellingen van het horloge.
- **"Rit starten" op het horloge doet niets op de telefoon.** Met Velorki op de achtergrond start de rit en toont de telefoon een melding om op te tikken. Een app die je hebt weggeveegd kan het horloge niet wekken, dat is een regel van iOS: het horloge zegt "De telefoon reageert niet", en Velorki openen op de telefoon is de oplossing.
- **De track begint pas als ik de telefoon open.** iOS geeft een app die op de achtergrond is gewekt geen GPS tot hij één keer is geopend. Tik op de melding, of open Velorki, en de track begint; daarna mag de telefoon op slot.

## Geen hartslag uit Gezondheid

- **De schakelaar staat uit.** **Apple Health**, of **Health Connect** op Android, moet aan staan in **Instellingen → Sensoren**. Zolang hij uit staat, wordt er niets gelezen.
- **De toegang is geweigerd.** "Velorki heeft geen toegang tot je gezondheidsgegevens gekregen." laat de schakelaar uit. Zet hem opnieuw aan en sta de hartslag toe, of geef de toegang in de gezondheidsapp zelf.
- **Niets heeft een hartslag weggeschreven.** Velorki leest alleen wat al in de opslag staat, dus zonder horloge en zonder app die er een hartslag in zet, valt er niets te lezen.
- **Hij komt laat binnen.** De opslag wordt elke vijf seconden gevraagd, of elke dertig met batterijbesparing aan, en de gaten worden nog eens gevuld als de rit wordt opgeslagen. Een band of een horloge dat direct meldt, is altijd sneller.

## Een Plus-functie ontbreekt

- **"Niet beschikbaar in deze build"** op een rij bij de koppelingen, of op de abonnementspagina, betekent dat deze kopie van Velorki is gebouwd zonder de sleutels voor die dienst of store. Zo ziet een zelfgebouwde kopie eruit.
- **De knop Vragen of de knop Link delen is er helemaal niet** in een build zonder ingestelde Velorki-server.
- **Al het andere** zou "… hoort bij Velorki Plus" moeten zeggen en de abonnementspagina moeten aanbieden. Heb je een abonnement en gebeurt dat niet, tik dan op **Aankopen herstellen** in **Instellingen → Abonnement**.

## Een bug melden

**Instellingen → Over → Probleem melden** opent de issuetracker, of ga direct naar [github.com/orkitec/velorki/issues](https://github.com/orkitec/velorki/issues).

Een goede melding heeft:

1. wat je deed, stap voor stap, en wat er gebeurde in plaats van wat je verwachtte;
2. de telefoon en de versie van het besturingssysteem;
3. de versie van Velorki, uit **Instellingen → Over**;
4. waar het gebeurde, als de kaart of de routering erbij betrokken is, want veel problemen horen bij één hoekje van de kaartgegevens;
5. een schermafbeelding, die meestal alles hierboven waard is.

Velorki heeft geen crashrapportage en stuurt ons uit zichzelf niets, dus een melding van jou is de enige manier waarop we van een probleem horen.

## Zie ook

- [Offline kaarten en routering](./offline-maps-and-routing)
- [Navigatie met afslagaanwijzingen](./navigation)
- [Een rit opnemen](./recording-a-ride)
- [Sensoren en je horloge](./sensors-and-watch)
- [Importeren en exporteren](./import-and-export)
- [Aan de slag](./getting-started)
