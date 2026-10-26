---
title: Privacyverklaring
description: "Wat Velorki met je gegevens doet: geen account, routes en ritten blijven op je telefoon of in je browser, tenzij je ze synchroniseert met je eigen iCloud of Google Drive, en een lijst van precies wat het apparaat verlaat en wanneer."
draft: false
---

> **Opmerking over de vertaling.** Dit is een vertaling van de Engelse versie.
> Bij verschillen geldt de Engelse versie.

Ingangsdatum: 23 oktober 2026.

Velorki is een app voor het plannen van fietsroutes en het opnemen van ritten,
gemaakt door Orkitec, voor iPhone, iPad en Android, en een webplanner op
app.velorki.com. Deze pagina legt uit wat er met je gegevens gebeurt.

**Wie verantwoordelijk is.** De verwerkingsverantwoordelijke voor alles wat hier
wordt beschreven is Steffen Roemer, handelend onder de naam "Orkitec", Straße der
Pariser Kommune 27, 10243 Berlijn, Duitsland, ride@velorki.com. Er is geen
functionaris voor gegevensbescherming aangesteld: de hieronder beschreven
verwerking vereist er geen op grond van artikel 37 van de Algemene Verordening
Gegevensbescherming (AVG, in het Engels GDPR). De volledige gegevens van de
aanbieder staan op de pagina [colofon](./imprint).

## De korte versie

- Er is **geen account**. Je meldt je niet aan, en we weten niet wie je bent.
- Je routes, je ritten en je instellingen blijven **op je telefoon**, of in je
  browser voor de webplanner. Als je synchronisatie aanzet, gaan ze naar je
  eigen iCloud of je eigen Google Drive, nooit naar ons.
- Sommige dingen hebben een server nodig: kaarttegels, routeplanning buiten de
  gebieden die je hebt gedownload, zoeken wanneer je daarom vraagt, en, als je
  ze gebruikt, de AI-assistent, de koppelingen met Strava en RideWithGPS (gratis) en
  deellinks. Elk daarvan wordt hieronder beschreven.
- Deze **website** heeft geen analytics, geen advertenties en geen tracking,
  dus de korte melding onderaan vraagt niets van je.
- De **webplanner** op app.velorki.com werkt op dezelfde manier: geen account,
  geen analytics, je bibliotheek bewaard in je browser.
- We verkopen je gegevens niet, en we gebruiken ze niet voor advertenties of
  profilering.

## Wat op je apparaat blijft

Geplande routes, opgenomen ritten, hun gps-tracks, je instellingen, gedownloade
offline kaartregio's, gedownloade routeringstegels en de zoekindexen voor
plaatsen die daarbij horen, worden opgeslagen in de eigen opslag van de app op
je telefoon. Ze worden nergens naartoe geüpload, tenzij je daarom vraagt; de enige
uitzondering is cloudsynchronisatie, hieronder beschreven, die naar je eigen
iCloud of Google Drive gaat en niet naar ons. Wat de webplanner in je browser
bewaart, staat beschreven onder De webplanner.

Hartslag, cadans en vermogen van een Apple Watch, een Bluetooth-sensor of je
gezondheidsapp worden bij de rit opgeslagen, op de telefoon, net als de track
zelf. Met de schakelaar Gezondheid aan in Instellingen leest de app de hartslag
uit Apple Health of Health Connect en schrijft hij je voltooide ritten daar weg
als fietstrainingen; die uitwisseling gebeurt op je telefoon en niets ervan
bereikt ons. Sensorwaarden gaan alleen daarheen waar de rit zelf heen gaat:
in een GPX-, FIT- of TCX-bestand dat je exporteert, in een upload naar Strava
of RideWithGPS die je zelf start, of naar je eigen cloud zolang synchronisatie
aan staat.

Als je Strava of RideWithGPS koppelt, worden de toegangstokens voor die accounts
opgeslagen in de beveiligde opslag van de telefoon (Keychain op iOS, Keystore
op Android), in een versleutelde vorm die alleen onze relay kan openen, en wat
je uit Strava haalt, blijft op de telefoon; zie het gedeelte over Strava en
RideWithGPS hieronder.

Op Android is de app uitgesloten van de cloudback-up van Google en van de
overdracht van apparaat naar apparaat, zodat ook het systeem je ritten en je
toegangstokens niet van de telefoon af kopieert. Om over te stappen naar
een nieuwe telefoon zet je synchronisatie met Google aan (hieronder beschreven)
of exporteer je wat je wilt bewaren als GPX-, FIT- of TCX-bestanden.

## Wat je apparaat verlaat, en wanneer

### Routeplanning

Routeplanning gebeurt normaal gesproken volledig op je telefoon, op basis van
routeringstegels die je hebt gedownload, en er wordt niets verstuurd. Voor een
gebied waarvoor je geen tegels hebt, stuurt de app de coördinaten van je
routepunten naar een routeringsserver (BRouter, door ons beheerd), die de route
terugstuurt. Die heeft de routepunten nodig om de route te berekenen; hij
ontvangt niet je identiteit, je andere routes of je ritten.

Routeringstegels en de zoekindexen die erbij horen, worden gedownload van onze
tegelmirror op GitHub (`raw.githubusercontent.com` en downloads van releases op
`github.com`). GitHub ziet welke tegels van 5° je downloadt en je IP-adres,
zoals bij elk webverzoek. De webplanner haalt ze in plaats daarvan op via
app.velorki.com, zodat GitHub Cloudflare ziet en niet jou.

### Zoeken

Plaatsen worden op je telefoon gezocht, in de zoekindexen die bij de
gedownloade routeringstegels horen. Niets van wat je daar typt verlaat het
apparaat.

Als je onderaan de resultaten op "Online zoeken naar …" tikt (of als je geen
routeringstegels hebt gedownload, in welk geval het zoekveld meteen online
gaat), wordt wat je hebt getypt naar Photon gestuurd, een geocodingdienst,
samen met een globale positie zodat resultaten in de buurt bovenaan komen.
Photon stuurt suggesties voor plaatsen terug.

Tikken op "Details" op het kaartje van een plaats haalt de details ervan
(openingstijden, website en dergelijke) op bij OpenStreetMap.

### Kaarttegels

De kaart wordt getekend uit tegels die worden opgehaald bij OpenFreeMap, en bij
CyclOSM als je de fietslaag aanzet. Het ophalen van een tegel vertelt de
tegelaanbieder naar welk deel van de kaart je kijkt, en daarbij komt je
IP-adres kijken, zoals bij elk webverzoek. Kaartgegevens © OpenStreetMap-bijdragers.

### Weer

**De weerkaart en de gratis weersverwachting voor de route.** Wanneer je de
regen, de wolken of de wind op de kaart aanzet, of zonder Velorki Plus een route
naar de wind of de regen inkleurt, haalt de app beelden en verwachtingsgegevens
rechtstreeks op bij openbare weerdiensten: de Deutscher Wetterdienst
(Duitsland), de Amerikaanse National Oceanic and Atmospheric Administration en
Iowa State University (VS), NASA, EUMETSAT, het KNMI (Nederland) en het Finse
Meteorologische Instituut. Elk verzoek noemt een deel van de kaart, of een kader
rond je route, en een tijdstip, en daarbij komt je IP-adres kijken, zoals bij
elk webverzoek. Je route zelf, je ritten en je identiteit worden niet verstuurd.

**Fijner weer langs de route (Velorki Plus).** De app stuurt onze relay
de punten langs de route, afgerond op een raster van ongeveer 2,5 km, elk met de
hoogte afgerond op 50 m, en de uren waarin je daar fietst — niet de route, de
naam ervan of je ritten. De relay controleert of je abonnement actief is en
vraagt de Amerikaanse National Weather Service, Bright Sky (voor de
verwachtingen van de Deutscher Wetterdienst) en MET Norway naar die
rasterpunten. Zij zien onze server, niet je telefoon. Elk antwoord wordt per
rasterpunt maximaal twee uur bewaard en gedeeld met iedereen die naar hetzelfde
punt vraagt.

**Regenradar voor heel Europa (Velorki Plus).** De app vraagt onze relay om het
deel van de kaart waar je naar kijkt en een tijdstip. De relay haalt de radar
één keer voor iedereen op uit het open archief van EUMETNET OPERA en, voor
Italië, bij het Dipartimento della Protezione Civile, bewaart die maximaal
tweeënhalf uur en stuurt een beeld van dat deel van de kaart terug. De
aanbieders van de radar zien onze server, niet je telefoon, en de relay houdt
niet bij naar welk deel van de kaart je hebt gevraagd.

### Strava en RideWithGPS

Beide koppelingen zijn gratis. Er wordt niets naar Strava of RideWithGPS
gestuurd, tenzij je het account zelf koppelt en daarna een actie start: een rit
uploaden, een route importeren.

Bij het koppelen geeft de app een eenmalige code aan onze relayserver
(api.velorki.com), die deze inwisselt voor een toegangstoken door ons
applicatiegeheim toe te voegen, het token versleutelt met een sleutel die alleen
de relay heeft, en het in die vorm teruggeeft aan de app. Je telefoon bewaart
het versleutelde token in zijn beveiligde opslag (Keychain op iOS, Keystore op
Android), uitgesloten van back-ups; hij kan het zelf niet gebruiken, en wij
slaan het helemaal niet op.

Daarna gaat elke upload, routeoverdracht, import en ontkoppeling die je start
via de relay: die ontsleutelt het token voor dat ene verzoek, stuurt het
verzoek door naar Strava of RideWithGPS en geeft het antwoord terug aan de app.
Hij bewaart het bestand niet, het token niet, niets van het antwoord en geen
enkel spoor van de aanroep. Voor deze aanroepen wordt geen abonnement
gecontroleerd; om misbruik te voorkomen houdt de relay alleen kortlevende
tellers voor de verzoeklimiet bij, op basis van de anonieme id van je
installatie en van het IP-adres (zie Serverlogs hieronder). Zijn logs bevatten
nooit het token, de inhoud van het verzoek of die id.

#### Strava

**Wat Velorki vraagt.** Twee machtigingen: `read`, je openbare Strava-profiel
(je atleet-id en naam), en `activity:write`, om de ritten te uploaden die jij
wilt uploaden. Velorki leest je activiteiten niet.

**Wat het leest en bewaart, alles alleen op je telefoon:**

- je atleet-id en naam, getoond in Instellingen → Koppelingen, tot je
  ontkoppelt;
- je lijst met Strava-routes (naam, afstand, hoogtewinst, beschrijving en
  datum), opgehaald wanneer je het importscherm opent en hooguit **48 uur** op
  de telefoon bewaard;
- het GPX-bestand van een route, wanneer je die route importeert; het wordt als
  route in de bibliotheek van de app bewaard, en dat geldt ook voor elke route
  die je daaruit hebt bewerkt, maar alleen zolang de route nog op Strava
  bestaat: zolang de app open, online en gekoppeld is, controleert hij de route
  elke 48 uur opnieuw bij Strava en verwijdert hem als hij op Strava is
  verwijderd of 7 dagen lang niet kon worden gecontroleerd, en meldt je dat. Hij
  wordt ook verwijderd als je hem zelf verwijdert of als je Strava ontkoppelt;
- na een upload de id van de Strava-activiteit en de link ernaar, bij de rit
  bewaard zodat de app "View on Strava" kan tonen, tot je ontkoppelt.

Een rit die je uploadt, wordt naar Strava gestuurd, dat hem verwerkt zoals
beschreven in [het privacybeleid van Strava](https://www.strava.com/legal/privacy).
Strava en Orkitec zijn elk verantwoordelijk voor hun eigen verwerking.

**Strava-gegevens blijven bij jou.** Strava-gegevens worden alleen aan jou
getoond, in de app. Ze worden nooit naar de AI-assistent gestuurd, nooit in een
deellink gezet en nooit naar RideWithGPS of een andere dienst gestuurd. Wij
bewaren geen Strava-gegevens op onze servers.

**Verwijderen.** Strava ontkoppelen onder Instellingen → Koppelingen trekt de
machtiging van Velorki bij Strava in, verwijdert de tokens en verwijdert alles
wat van Strava kwam van de telefoon: geïmporteerde Strava-routes en routes die
je daaruit hebt bewerkt, de lijst met routes in de cache en de bewaarde links
naar activiteiten. De app bevestigt dan: "Je Strava-gegevens zijn van deze
telefoon gewist." Trek je de toegang van Velorki in op strava.com, dan merkt de
app dat bij de volgende aanroep naar Strava, verwijdert hij dezelfde gegevens
en laat het je weten. De app verwijderen wist ze ook. Omdat alles op je telefoon
staat, zijn dit de manieren om het te verwijderen; voor vragen of een
verzoek tot verwijdering schrijf je naar ride@velorki.com.

**Gebruiksgegevens bij Strava.** Strava mag gegevens bijhouden en verzamelen
over hoe Velorki de Strava-API gebruikt (gebruiksgegevens) en mag ze voor elk
zakelijk doel gebruiken, intern of extern, waaronder het aanbieden van
verbeteringen aan de Strava-API of het Strava-platform, het bieden van
ontwikkelaars- of gebruikersondersteuning, en het waarborgen van naleving van
zijn API-overeenkomst.

#### RideWithGPS

Wat RideWithGPS doet met de gegevens die je het stuurt, valt onder zijn eigen
privacybeleid.

### De AI-assistent (Velorki Plus)

De assistent staat uit totdat je hem inschakelt, en de eerste keer dat je hem
opent word je om toestemming gevraagd. Je kunt kiezen om alleen je tekst te
sturen, of je tekst samen met een globale startpositie, of te weigeren. Je
kunt je toestemming op elk moment intrekken in de instellingen.

Wanneer je hem gebruikt, wordt het volgende via onze relayserver naar onze
AI-aanbieder gestuurd:

- de tekst die je hebt getypt,
- optioneel een startpositie, **afgerond op ongeveer één kilometer**,
- de instellingen voor taal en eenheden, zodat het antwoord past,
- als je om een routebeschrijving vraagt, een samenvatting van de route die op
  je telefoon is gemaakt: afstand, stijging, aandelen per ondergrond, de
  stukken waar de route over loopt met hun weg, ondergrond en hellingspercentage,
  de klimmen, de plaatsen waar de route door komt en de plekken om te stoppen
  in de buurt, elk met de afstand langs de route en de positie (tot op
  ongeveer 10 m). Ook de AI-aanbieder ontvangt die; een route die bij je thuis
  begint, laat dus zien waar je woont.

Er komt geen identificatie van jou of je telefoon in de prompt. Het model geeft
een gestructureerd verzoek terug: een afstand, een vorm, plaatsnamen,
voorkeuren. De eigenlijke routeplanning gebeurt daarna in de app; het model
ziet je route nooit.

Onze relay geeft het verzoek door aan **OpenRouter, Inc.** (VS), een dienst die
toegang geeft tot taalmodellen van verschillende aanbieders, en OpenRouter
stuurt het door naar de aanbieder die het model levert dat we gebruiken. We
hebben OpenRouter zo ingesteld dat verzoeken alleen naar aanbieders gaan die er
geen modellen mee trainen en ze niet bewaren. De doorgifte naar de Verenigde
Staten berust op de standaardcontractbepalingen (Standard Contractual Clauses)
van de Europese Commissie. OpenRouter en de modelaanbieder ontvangen het verzoek
van onze relay, niet van je telefoon, dus ze zien het adres van onze server en
niet het jouwe.

De assistent bereikt het model via een OpenAI-compatibele interface, zodat
iedereen die Velorki zelf host zijn relay op elke aanbieder of op een eigen
model kan richten; dan geldt het beleid van die beheerder, niet dit beleid.

Gegevens van Strava worden nooit naar de AI-aanbieder gestuurd.

### Deellinks (Velorki Plus)

Als je een deellink maakt voor een route of een rit, wordt die route of rit,
met de track, de naam en de statistieken, naar onze server geüpload en daar
opgeslagen, zodat iedereen met de link hem kan openen. Hartslag, cadans en
vermogen worden weggelaten: een gedeelde rit bevat de track en de tijden, niet
wat een sensor heeft gemeten. De link is openbaar: iedereen die hem heeft, kan
de inhoud zien, inclusief het begin- en eindpunt van de track. Denk daaraan
voordat je een rit deelt die bij je thuis begint.

Een gedeeld item wordt **één jaar** bewaard en daarna automatisch verwijderd.
Wil je het eerder laten verwijderen, stuur de link dan naar het contactadres
hieronder en we verwijderen het. Voor het bekijken van een gedeelde link is
geen account nodig.

### Cloudsynchronisatie (iCloud of Google Drive)

Elk apparaat synchroniseert met hooguit één cloud, gekozen onder **Instellingen
→ Synchroniseren met**: iCloud (iPhone en iPad met iOS 17 of nieuwer, en de
webplanner), Google (de iPhone, de iPad, Android en de webplanner) of uit. Op
een iPhone of iPad staat iCloud standaard aan; op Android en in de browser
staat synchronisatie uit totdat je een cloud kiest.

**Wat er wordt gesynchroniseerd.** Je opgeslagen routes, en je opgenomen ritten
met de track, de notities, de statistieken, de ronden en de hartslag, cadans,
het vermogen en de temperatuur die bij elke rit zijn opgenomen. Een paar
instellingen worden ook gesynchroniseerd: thema, accentkleur, kaartstijl, de
stijl van de regenradar, balkstijl, kant van de kolom, eenheden, en de
instellingen voor afslagen, stem en herberekenen. In de browser met iCloud
blijven de instellingen in de browser. Elke app schrijft ook één klein
Plus-record in dezelfde cloud, beschreven onder Abonnementen.

**Sommige dingen worden nooit gesynchroniseerd.** Routes die uit Strava zijn
gelezen en routes die je daaruit hebt bewerkt, en de Strava-links van ritten
die je naar Strava hebt geüpload, blijven op die ene telefoon, zoals hierboven bij
Strava beschreven. De links van uploads naar Ride with GPS worden evenmin
gesynchroniseerd; een route die je uit Ride with GPS importeert, wordt
gesynchroniseerd als je eigen route, zonder haar Ride-with-GPS-id. Gedownloade
kaartregio's en routeringstegels, toestemmingen, gekoppelde sensoren, de stem,
de taal, gekoppelde accounts en het abonnement zelf horen er niet bij.

**iCloud.** De gegevens gaan via CloudKit van Apple naar je eigen privédatabase
in iCloud. Apple slaat ze op en verstuurt ze, en ze tellen mee voor je
iCloud-opslag. Apple versleutelt ze tijdens het transport en op zijn servers;
met Geavanceerde gegevensbescherming ingeschakeld zijn ze end-to-end
versleuteld, zoals beschreven in [Apples overzicht van de gegevensbeveiliging van iCloud](https://support.apple.com/en-us/102651).
In de browser meld je je aan met de eigen knop van Apple, in een venster van
Apple; het CloudKit JS-script van Apple wordt pas bij Apple geladen als je
iCloud kiest, en bewaart je aanmelding bij Apple in een cookie op de site van
de planner totdat je je afmeldt (de sitegegevens in de browser wissen
verwijdert hem ook).

De uploadserver van Apple accepteert geen uploads die rechtstreeks vanaf onze
site worden verstuurd. Wanneer de webplanner een route of een rit in iCloud
opslaat, wordt het bestand van het record (de track en de details van de route
of rit) daarom naar app.velorki.com/cloudkit/upload gestuurd, een kleine
Cloudflare-functie die het ongewijzigd doorgeeft aan het eenmalige uploadadres
dat Apple ervoor gaf en het ontvangstbewijs van Apple teruggeeft. Ze bewaart
niets, en we houden er geen logs van bij. De andere velden van het record gaan
rechtstreeks naar Apple.

**Google Drive.** Je meldt je aan met je Google-account, en Velorki vraagt maar
één machtiging: zijn eigen verborgen app-map in je Drive (`drive.appdata`).
Het kan geen enkel ander bestand in je Drive zien of wijzigen, en de map
verschijnt niet tussen je bestanden. Google slaat de gegevens op en ze tellen
mee voor je Google-opslag; Google versleutelt ze tijdens het transport en op
zijn servers, niet end-to-end. De telefoon bewaart de id en het e-mailadres van
je Google-account om te tonen wie er is aangemeld. In de browser meld je je aan
met de eigen knop van Google; het aanmeldscript van Google wordt pas geladen
als je Google kiest, en het toegangstoken ervan leeft alleen zo lang als de
pagina en hooguit een uur.

**Wat Orkitec ziet.** Niets. Orkitec heeft geen server voor synchronisatie en
kan niet lezen, openen of verwijderen wat in je iCloud of je Drive staat; er is
geen Velorki-account. Apple en Google handelen onder je eigen overeenkomst met
hen.

**Verwijderen, uitzetten.** Zolang synchronisatie aan staat, wordt een route of
rit die je op één apparaat verwijdert ook uit je cloud en van je andere
apparaten verwijderd. **Uit** kiezen, afmelden of overstappen naar de andere
cloud stopt het synchroniseren op dat apparaat en verwijdert niets;
overstappen stuurt je bibliotheek naar de nieuwe cloud en laat de oude kopie
waar die was. Wat al in iCloud staat, blijft daar totdat je het verwijdert in de
iCloud-instellingen op een Apple-apparaat. Wat in Google Drive staat, blijft
daar totdat je het verwijdert: in Google Drive op het web, Instellingen → Apps
beheren → Velorki → Opties → Verborgen app-gegevens verwijderen; de toegang van
Velorki intrekken op myaccount.google.com/permissions zorgt dat het de map niet
meer bereikt.

### Abonnementen

Velorki Plus wordt verkocht via de App Store en Google Play, en namens ons
afgehandeld door RevenueCat. RevenueCat geeft je installatie een **anonieme
app-gebruikers-id**, een willekeurige tekenreeks die niet gekoppeld is aan een
naam, een e-mailadres of een apparaat-id. RevenueCat ontvangt ook het
aankoopbewijs van de store. Onze relay stuurt die anonieme id naar RevenueCat om
te controleren of je abonnement actief is, en voor niets anders.

We zien je betaalgegevens nooit; die blijven bij Apple of Google.

**Plus in de browser.** Plus kun je niet in de webplanner kopen. Om daar een
Plus-abonnement te gebruiken dat je in een telefoonapp hebt gekocht, schrijft
elke app die synchroniseert één eigen record in de cloud waarmee hij
synchroniseert: zijn
RevenueCat-app-gebruikers-id, of het een iPhone- of Android-app is, of zijn
store het laatst zei dat Plus actief is, en wanneer hij het laatst schreef,
onder een willekeurige id voor het apparaat. Hij schrijft het elke zes uur
opnieuw en wanneer Plus begint of eindigt. De webplanner, aangemeld bij
hetzelfde iCloud- of Google-account, leest deze records, bewaart ze in de
browser en stuurt de id van het meest recente met elk Plus-verzoek naar onze
relay, precies zoals de app zou doen. De relay controleert die id bij
RevenueCat zoals hij dat voor de apps doet; de browser neemt geen contact op
met RevenueCat, maakt geen eigen id voor Plus en schrijft nooit een
Plus-record.

Het record gaat alleen naar het account waarmee synchronisatie het eerst
draaide, of een account dat je daarna kiest onder Instellingen →
Synchroniseren met: na een afmelding, een ander account of uitgezette
synchronisatie stopt de app met het schrijven ervan en kopieert hij het nooit
uit zichzelf naar een tweede account. Het wordt niet uit de cloud verwijderd;
de webplanner negeert een record dat 30 dagen niet is geschreven, en vergeet
de records die hij bewaarde wanneer je je afmeldt of van account of cloud
wisselt.

### Updatemeldingen en beoordelingen

Een paar seconden na het starten, en opnieuw na een dag op de achtergrond,
vraagt de app aan zijn store of er een nieuwere versie is. Op iOS vraagt hij
het aan de openbare zoekdienst van de App Store van Apple
(`itunes.apple.com`), met de bundle-id van Velorki en de land- en taalcode van
je telefoon; op Android vraagt hij het aan de in-app-updatedienst van Google
Play op de telefoon, die alleen antwoordt voor een installatie uit Play. Bij
beide komt je IP-adres kijken, zoals bij elk webverzoek, en verder niets van
jou.

Af en toe vraagt de app het systeem om zijn eigen beoordelingsvenster te tonen.
Apple of Google beslissen of het verschijnt en hoe vaak; een beoordeling of
recensie die je daar geeft, gaat naar hen onder je store-account, en de app
hoort niet of je hebt beoordeeld of wat. De webplanner doet geen van beide.

### Crashrapportage en analytics

Die zijn er niet. De app bevat geen crashrapportage, geen analytics en geen
advertentie-SDK, en hij stuurt geen gebruiksstatistieken; elk netwerkverzoek dat
hij doet is een van de hierboven beschreven verzoeken. Crashes worden door de
appstores geaggregeerd aan het ontwikkelaarsaccount gemeld, zonder iets wat
jou identificeert, en alleen als je dat in de eigen instellingen van je
telefoon hebt aangezet. Als er ooit een crashrapportage wordt toegevoegd, noemt
dit gedeelte die en zegt het wat die verzamelt, voordat die versie uitkomt.

### Serverlogs

Onze relay en onze routeringsserver houden operationele logs bij (tijdstip van
het verzoek, endpoint, status, IP-adres en een header met de clientversie) om
de dienst te laten draaien, fouten op te sporen en verzoeklimieten toe te
passen. Ze worden niet gebruikt om profielen van gebruikers op te bouwen, en ze
bevatten nooit een toegangstoken, de inhoud van een verzoek of een abonnee-id.

- De toegangslogs van de webserver blijven **14 dagen** op de machine en worden
  daarna door logrotatie verwijderd.
- De eigen logregels van de applicatie worden verzameld door Orkify, het
  deploymentdashboard dat de beheerder op dezelfde Hetzner-infrastructuur
  draait, en worden daar na uiterlijk **90 dagen** gewist.

## Deze website

velorki.com is een eenvoudige website: geen account, geen advertenties, geen
analytics, geen tracking. Niets van wat je hier doet wordt gemeten, dus de
melding die je misschien onderaan de pagina hebt gezien, is precies dat, een
melding: er is geen toestemming te geven of te weigeren, want er wordt niets op
je apparaat opgeslagen totdat je daarom vraagt. Het item 🍪 Cookies in de
footer brengt die terug.

- **Serverlogs.** Elk verzoek wordt gelogd zoals hierboven onder Serverlogs
  beschreven: tijdstip, pad, status, grootte, je IP-adres en de user agent van
  je browser, 14 dagen bewaard.
- **Foutrapporten.** Als een pagina van deze site in je browser misgaat, stuurt
  die de fout, het adres van de pagina en de user agent van je browser naar
  onze server, alleen zodat we de bug kunnen oplossen.
- **Cloudflare.** De site wordt geleverd via Cloudflare, dat de verbinding
  afhandelt, aanvallen filtert en het verzoek doorgeeft aan onze server.
  Cloudflare verwerkt daarom je IP-adres en het verzoek zelf. Cloudflare zit in
  de Verenigde Staten; de doorgifte berust op de standaardcontractbepalingen
  van de EU.
- **Een taalcookie.** Een taal kiezen in de header zet een cookie met de naam
  `NEXT_LOCALE` (de code van de gekozen taal, bijvoorbeeld `nl`, één jaar). Die bestaat zodat de site
  opent in de taal die je hebt gekozen. Er staat verder niets in, en hij wordt
  alleen gezet wanneer je die keuze maakt — hij is strikt noodzakelijk voor een
  functie waar je om hebt gevraagd en heeft geen toestemming nodig op grond van
  § 25 lid 2 TDDDG.
- **Een themavoorkeur.** Licht, donker of een accentkleur kiezen schrijft
  `velorki.theme` in de lokale opslag van je browser. Dat verlaat de browser
  nooit en is voor ons niet leesbaar. De melding hierboven wegklikken schrijft
  nog één sleutel, `velorki.cookie-notice`, zodat die niet opnieuw wordt
  getoond.
- **Deelpagina's.** Een link `velorki.com/s/…` openen laadt de gedeelde route
  van onze server en de kaarttegels van OpenFreeMap, dat je IP-adres ziet zoals
  bij elk webverzoek. De pagina heeft geen andere inhoud van derden.
- **De supportchat.** De chatknop in de hoek is de widget van Orkify. Orkitec
  beheert Orkify ook, dus het is onze eigen infrastructuur, maar het is een
  andere site: het script wordt geladen van orkify.com en vraagt orkify.com om
  zijn instellingen wanneer de pagina opent, wat betekent dat je IP-adres het
  bereikt zoals het elke server bereikt waaraan je een verzoek doet. Verder
  gebeurt er niets totdat je de chat opent.

  Wanneer je ons wel schrijft, wordt je bericht — en de naam en het e-mailadres
  die je in het formulier invult — afgeleverd in een privékanaal op Discord waar
  we antwoorden, en het gesprek blijft daar totdat we het verwijderen. Vraag het
  via ride@velorki.com en we verwijderen het jouwe. De widget bewaart de id van
  het gesprek en de naam en het e-mailadres die je hebt opgegeven in de lokale
  opslag van je browser, zodat een antwoord je nog vindt wanneer je terugkomt,
  en wist ze wanneer je de chat beëindigt. Als je de stickerkiezer opent, gaat
  je zoekopdracht naar Klipy, dat de afbeeldingen terugstuurt. Zet niets in de
  chat wat je niet in een supportticket zou willen; gebruik voor een
  beveiligingsmelding in plaats daarvan het adres in
  [SECURITY.md](https://github.com/orkitec/velorki/blob/main/SECURITY.md).
- **Lettertypen en afbeeldingen** komen allemaal van deze server, en afgezien
  van de supportchat is er geen script van derden, geen CDN voor onze eigen
  bestanden en geen lettertypedienst.

## De webplanner (app.velorki.com)

app.velorki.com is dezelfde app, draaiend in je browser: hij plant, zoekt en
houdt een bibliotheek bij, maar neemt niet op en navigeert niet. Er is geen
account, er zijn geen analytics en geen advertenties. Op een telefoon of tablet
toont het adres de downloadpagina van de app en laadt het verder niets.

- **Bewaard in je browser.** Je routes, ritten en instellingen worden bewaard in
  een database in de eigen opslag van de browser (IndexedDB, of in sommige
  browsers het Origin Private File System), de routeringstegels en zoekindexen
  die je hebt gedownload in de Cache Storage ervan, en instellingen, het
  cloudaccount waarbij je je hebt aangemeld en een anonieme id zoals die van de
  app in de lokale opslag ervan. Ze blijven in die browser, op die computer,
  totdat je ze verwijdert in de planner of de sitegegevens in de browser wist.
  Deze opslag is waar de planner voor dient, dus er is geen toestemming voor
  nodig op grond van § 25 lid 2 TDDDG.
- **Waarmee hij contact maakt.** Met dezelfde diensten als de app, onder
  dezelfde regels als hierboven: kaarttegels van OpenFreeMap (en CyclOSM als je
  die aanzet), Photon voor een online zoekopdracht, de openbare weerdiensten
  voor de weerlagen, en onze relay voor de AI-assistent, het Plus-weer en
  deellinks. Hij gebruikt nooit de routeringsserver: routes worden in de
  browser berekend. Routeringstegels komen via app.velorki.com. Als een tekst
  een schrift nodig heeft dat de eigen lettertypen van de app missen, laadt de
  browser een reservelettertype van Google Fonts (`fonts.gstatic.com`), dat je
  IP-adres ziet. Cloudsynchronisatie maakt contact met Apple of Google, en pas
  als je er een kiest.
- **Cloudflare.** De planner wordt geleverd door Cloudflare Pages. Twee kleine
  functies daar beantwoorden `/tiles/` (die de tegels van onze GitHub-mirror
  ophaalt) en `/cloudkit/upload` (zie Cloudsynchronisatie). Zoals elke server
  zien ze je IP-adres en het verzoek; ze bewaren niets, en we houden er geen
  logs van bij.

## Bewaren en verwijderen

| Gegevens | Bewaard | Hoe je ze verwijdert |
|---|---|---|
| Routes, ritten, instellingen, offline gegevens | op je telefoon, totdat je ze verwijdert | verwijder ze in de app, of verwijder de app (met synchronisatie aan wordt een route of rit die je verwijdert ook uit je cloud verwijderd) |
| Tokens van Strava / RideWithGPS | op je telefoon, zo versleuteld dat alleen onze relay ze kan openen, totdat je ontkoppelt; nooit bij ons opgeslagen | ontkoppel in de app, of verwijder de app |
| Strava-gegevens: je naam, links naar activiteiten | op je telefoon, tot je ontkoppelt; nooit bij ons opgeslagen | ontkoppel Strava in de app, of verwijder de app; vragen naar ride@velorki.com |
| Routes geïmporteerd uit Strava, en routes die je daaruit hebt bewerkt | op je telefoon, alleen zolang de route nog op Strava bestaat: elke 48 uur opnieuw gecontroleerd, verwijderd als hij daar is verwijderd of 7 dagen lang niet kon worden gecontroleerd; nooit bij ons opgeslagen | verwijder hem in de app, ontkoppel Strava, of verwijder de app |
| De lijst met je Strava-routes in de cache | op je telefoon, hooguit 48 uur | ontkoppel Strava, of verwijder de app |
| Tellers voor de verzoeklimiet (anonieme installatie-id, IP-adres) | op onze server, voor het telvenster, hooguit een dag | niet van toepassing |
| Deellinks | één jaar, daarna automatisch verwijderd | verwijder ze vanuit de app |
| Routes, ritten en instellingen gesynchroniseerd via iCloud | in je eigen iCloud, totdat je ze daar verwijdert; nooit bij ons opgeslagen | verwijder ze in de iCloud-instellingen op een Apple-apparaat |
| Routes, ritten en instellingen gesynchroniseerd via Google Drive | in de verborgen Velorki-map van je Drive, totdat je die verwijdert; nooit bij ons opgeslagen | in Google Drive op het web: Instellingen → Apps beheren → Velorki → Opties → Verborgen app-gegevens verwijderen |
| Plus-records (RevenueCat-id, platform, Plus actief, laatst geschreven) | in de cloud waarmee je synchroniseert, totdat je de gegevens van de app daar verwijdert; na 30 dagen genegeerd door de webplanner | zoals de gesynchroniseerde routes hierboven |
| De bibliotheek, tegels en instellingen van de webplanner | in je browser, totdat je ze verwijdert | verwijder ze in de planner, of wis de sitegegevens in de browser |
| AI-prompts | door ons niet bewaard, buiten wat de logs hierboven bevatten | niet van toepassing |
| Gegevens bij RevenueCat | volgens het eigen beleid van RevenueCat | neem contact met ons op en we geven het verzoek door |
| Gesprekken in de supportchat | in ons Discord-kanaal totdat we ze verwijderen | vraag het via ride@velorki.com |

De app verwijderen wist alles wat de app op het apparaat heeft opgeslagen. Wat
synchronisatie in je iCloud of je Google Drive heeft gezet, blijft daar; zie
Cloudsynchronisatie hierboven. Het
verwijdert geen deellinks die je hebt gemaakt (die verlopen na één jaar, of op
verzoek), en het verwijdert niets wat je naar Strava of RideWithGPS hebt
geüpload.

## Rechtsgronden

Voor lezers in de EU en het VK zijn de rechtsgronden op grond van artikel 6
lid 1 AVG:

| Wat | Grondslag |
|---|---|
| De website en de deelpagina's leveren, de servers draaiende houden, fouten opsporen, verzoeklimieten, verdediging tegen aanvallen | (f) gerechtvaardigd belang bij het draaien van een dienst die werkt en niet wordt misbruikt |
| Online routeplanning en online zoeken, wanneer je daarom vraagt | (b) uitvoering van de dienst waar je om hebt gevraagd, en (f) voor de coördinaten die strikt nodig zijn om te antwoorden |
| Velorki Plus: bij RevenueCat controleren of een abonnement actief is | (b) uitvoering van de overeenkomst |
| Velorki Plus: het fijnere weer langs de route en de regenradar | (b) uitvoering van de overeenkomst |
| Strava en RideWithGPS: een account koppelen, elke overdracht die je start en de Strava-gegevens op je telefoon | (b) uitvoering van de dienst waar je om hebt gevraagd, plus (a) toestemming, gegeven door het account te koppelen en ingetrokken door te ontkoppelen |
| Deellinks die je maakt | (b) uitvoering van de overeenkomst |
| Cloudsynchronisatie met iCloud of Google Drive, zolang die aan staat, inclusief de Plus-records en de upload van de webplanner via `/cloudkit/upload` | (b) uitvoering van de dienst waar je om vroeg; Apple en Google handelen onder je eigen overeenkomst met hen |
| De webplanner: hem leveren, je bibliotheek in je browser bewaren, tegels ophalen via app.velorki.com | (b) uitvoering van de dienst waar je om hebt gevraagd, en (f) voor het IP-adres en het verzoek die strikt nodig zijn om te antwoorden |
| Updatemeldingen | (f) gerechtvaardigd belang bij het melden van een nieuwere versie; alleen de bundle-id, het land en de taal worden verstuurd |
| De AI-assistent | (a) toestemming, apart gevraagd in de app en in te trekken in de instellingen |
| Je vraag in de supportchat beantwoorden | (b) als het om een abonnement gaat, anders (f) gerechtvaardigd belang bij het antwoorden van wie ons heeft geschreven |
| Fiscaal relevante gegevens van een abonnement bewaren | (c) wettelijke verplichting — en Apple en Google, niet wij, hebben de factuurgegevens |

We profileren niet, we nemen geen geautomatiseerde besluiten over jou, en we
gebruiken niets hiervan voor direct marketing.

## Wie verder gegevens ontvangt

We verkopen, verhuren of verhandelen geen persoonsgegevens. Ze bereiken deze
partijen, en geen andere:

**Verwerkers, die voor ons handelen op grond van een verwerkersovereenkomst**

- **Hetzner Cloud GmbH**, Gunzenhausen, Duitsland — de server waarop de relay,
  de deellinks en deze website draaien. Gegevens blijven in Duitsland.
- **Cloudflare, Inc.**, San Francisco, VS — DNS, CDN en bescherming tegen
  aanvallen voor velorki.com en api.velorki.com, en hosting van de webplanner op
  app.velorki.com met zijn functies `/tiles/` en `/cloudkit/upload`.
  IP-adressen en metadata van verzoeken, en de iCloud-upload die het ongelezen
  doorgeeft.
- **RevenueCat, Inc.**, San Francisco, VS — de abonnementscontrole. De anonieme
  app-gebruikers-id en het aankoopbewijs van de store, geen naam en geen
  e-mailadres.
- **Orkify**, beheerd door dezelfde beheerder op de Hetzner-infrastructuur
  hierboven — het deploymentdashboard dat de applicatielogs en procesmetrieken
  verzamelt die onder Serverlogs worden beschreven en de foutrapporten van deze
  website, en de widget van de supportchat.
- **Discord Netherlands B.V.** (voor gebruikers in Europa; Discord Inc., San
  Francisco, VS, voor de onderliggende dienst) — waar een gesprek in de
  supportchat wordt afgeleverd en bewaard.
- **Klipy** — het zoeken naar stickers en GIF's in de supportchat, en alleen
  zolang die kiezer open is.
- **OpenRouter, Inc.**, VS, en de modelaanbieder waarnaar het doorstuurt — de
  AI-assistent, alleen nadat je toestemming hebt gegeven, beperkt tot
  aanbieders die niet op verzoeken trainen en ze niet bewaren.

**Diensten waarmee je telefoon of browser rechtstreeks contact maakt, elk
verantwoordelijk voor de eigen verwerking**

- **OpenFreeMap** (kaarttegels) en **OpenStreetMap France** (de CyclOSM-laag,
  alleen wanneer je die aanzet) — de tegels voor het deel van de kaart waar je
  naar kijkt, en je IP-adres.
- **komoot GmbH**, Potsdam, Duitsland — de Photon-geocoder op
  `photon.komoot.io`, en alleen voor een online zoekopdracht waar je om hebt
  gevraagd.
- **OpenStreetMap** (`api.openstreetmap.org`) — de details van een plaats,
  wanneer je op "Details" op het kaartje ervan tikt.
- **Openbare weerdiensten** — de Deutscher Wetterdienst, NOAA, Iowa State
  University, NASA, EUMETSAT, het KNMI en het Finse Meteorologische Instituut —
  het deel van de kaart of het kader rond je route waar je om vroeg, een
  tijdstip en je IP-adres, alleen zolang een weerlaag of de gratis
  weersverwachting voor de route aanstaat.
- **Apple Inc.** (iCloud) — de routes, ritten, instellingen en Plus-records van
  de iCloud-synchronisatie, in je eigen iCloud en alleen zolang je met iCloud
  synchroniseert. Wij ontvangen ze niet; Apple handelt onder je eigen
  iCloud-overeenkomst met Apple.
- **Google Ireland Ltd**, Dublin (Google LLC, VS, buiten de EER en
  Zwitserland) — de routes, ritten, instellingen en Plus-records van de
  synchronisatie met Google, in de verborgen app-map van je eigen Drive, en
  alleen zolang je met Google synchroniseert. Wij ontvangen ze niet; Google
  handelt onder je eigen overeenkomst met Google. Google levert ook de
  reservelettertypen van de webplanner (`fonts.gstatic.com`) en de
  updatecontrole van Google Play op Android.
- **GitHub, Inc.**, San Francisco, VS — onze tegelmirror, waarvan de app
  routeringstegels en zoekindexen downloadt; de namen van de tegels en je
  IP-adres.
- **Apple Inc.** en **Google Ireland Ltd** — de verkoop van Velorki Plus, de
  updatecontrole en het beoordelingsvenster. Zij zijn de verkopers; wij zien je
  betaalgegevens nooit.
- **Strava, Inc.** en **Ride with GPS** — alleen nadat je het account koppelt en
  alleen voor een overdracht die je start. Wat zij ermee doen valt onder hun
  eigen beleid.

We geven gegevens ook aan een rechtbank of een autoriteit als de wet dat vereist.

## Doorgifte buiten de EU

Cloudflare, RevenueCat, OpenRouter en de modelaanbieder daarachter, Discord,
Klipy, Strava, Ride with GPS, GitHub, Apple en Google zitten in de Verenigde Staten of
geven gegevens daarheen door. Die doorgifte berust op de
standaardcontractbepalingen van de Europese Commissie, of op de certificering van
de aanbieder onder het EU-VS Data Privacy Framework als die er een heeft, samen
met de eigen technische waarborgen van de aanbieder. Hetzner, komoot en de
kaarttegeldiensten waarop we vertrouwen zitten in de EU, OpenStreetMap in het
VK. Alles wat de app voor je opslaat blijft op je telefoon, of in je browser, en
wordt nergens naartoe doorgegeven, tenzij je synchronisatie aanzet, die naar je
eigen iCloud of Google Drive gaat.

## Beveiliging

Elke verbinding met onze servers en met de diensten hierboven is versleuteld
met TLS. Tokens van Strava en RideWithGPS staan nergens onversleuteld: je
telefoon bewaart ze in de beveiligde opslag van het platform, verpakt met een
sleutel die alleen de relay heeft, en de relay pakt er een uit voor het ene
verzoek waarvoor het nodig is en bewaart niets. De database met gedeelde items
staat op de schijf van de server, buiten de releasemap, alleen leesbaar voor
de servicegebruiker. Logs worden geschoond: geen `Authorization`-header, geen
inhoud van verzoeken, geen abonnee-id. Toegang tot de server vereist een
sleutel, geen wachtwoord, en is beperkt tot de beheerder. Mocht een inbreuk je
rechten in gevaar brengen, dan melden we dat binnen 72 uur aan de
toezichthoudende autoriteit (artikel 33 AVG) en, als de wet dat vereist, aan
jou.

## Je rechten

Als je in de EU of het VK bent, heb je recht op inzage (artikel 15 AVG),
rectificatie (16), wissing (17), beperking van de verwerking (18),
overdraagbaarheid van gegevens (20) en bezwaar tegen verwerking op grond van
een gerechtvaardigd belang (21), en waar we op je toestemming vertrouwen — de
assistent — kun je die op elk moment intrekken, zonder dat dit afdoet aan wat
daarvoor rechtmatig was (artikel 7 lid 3). Het meeste daarvan kun je zelf
uitoefenen, omdat de gegevens op je telefoon, in je browser of in je eigen
cloud staan en wanneer je maar wilt als GPX-, FIT- of TCX-bestanden kunnen
worden geëxporteerd.

Voor alles wat aan onze kant wordt bewaard (deellinks, logregels, het record
bij RevenueCat) schrijf je naar **ride@velorki.com**. We antwoorden binnen 30
dagen. We hebben genoeg informatie nodig om de gegevens te vinden, wat voor een
deellink de link zelf betekent, omdat er geen account is om je op te zoeken.

Je kunt ook een klacht indienen bij een toezichthoudende autoriteit. De onze is
de
[Berliner Beauftragte für Datenschutz und Informationsfreiheit](https://www.datenschutz-berlin.de),
en je kunt evengoed naar de autoriteit gaan waar je woont.

De verwerkingsverantwoordelijke is Steffen Roemer, handelend onder de naam
"Orkitec", Straße der Pariser Kommune 27, 10243 Berlijn, Duitsland.

## Kinderen

Velorki is niet op kinderen gericht en verzamelt niet bewust gegevens van hen.
De app heeft geen sociale functies, geen berichten tussen gebruikers en geen
advertenties.

## Wijzigingen

Wijzigingen in dit beleid worden op deze pagina gepubliceerd, met een nieuwe
datum bovenaan; belangrijke wijzigingen worden ook op de website aangekondigd.
Oude versies blijven in de git-geschiedenis van de repository.

## Contact

Orkitec, ride@velorki.com; postadres in het [colofon](./imprint). Voor
beveiligingsmeldingen zie
[SECURITY.md](https://github.com/orkitec/velorki/blob/main/SECURITY.md) in de
broncoderepository.
