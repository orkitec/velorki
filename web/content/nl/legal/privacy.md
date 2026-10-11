---
title: Privacyverklaring
description: "Wat Velorki met je gegevens doet: geen account, routes en ritten blijven op je telefoon, en een lijst van precies wat het apparaat verlaat en wanneer."
draft: true
---

> **Opmerking over de vertaling.** Dit is een vertaling van de Engelse versie.
> Bij verschillen geldt de Engelse versie.

Ingangsdatum: 30 september 2026.

Velorki is een app voor het plannen van fietsroutes en het opnemen van ritten,
gemaakt door Orkitec. Deze pagina legt uit wat er met je gegevens gebeurt.

**Wie verantwoordelijk is.** De verwerkingsverantwoordelijke voor alles wat hier
wordt beschreven is Steffen Roemer, handelend onder de naam "Orkitec", Straße der
Pariser Kommune 27, 10243 Berlijn, Duitsland, ride@velorki.com. Er is geen
functionaris voor gegevensbescherming aangesteld: de hieronder beschreven
verwerking vereist er geen op grond van artikel 37 van de Algemene Verordening
Gegevensbescherming (AVG, in het Engels GDPR). De volledige gegevens van de
aanbieder staan op de pagina [colofon](./imprint).

## De korte versie

- Er is **geen account**. Je meldt je niet aan, en we weten niet wie je bent.
- Je routes, je ritten en je instellingen blijven **op je telefoon**.
- Sommige dingen hebben een server nodig: kaarttegels, routeplanning buiten de
  gebieden die je hebt gedownload, zoeken wanneer je daarom vraagt, en, als je
  ze gebruikt, de AI-assistent, de koppelingen met Strava en RideWithGPS en
  deellinks. Elk daarvan wordt hieronder beschreven.
- Deze **website** heeft geen analytics, geen advertenties en geen tracking,
  dus de korte melding onderaan vraagt niets van je.
- We verkopen je gegevens niet, en we gebruiken ze niet voor advertenties of
  profilering.

## Wat op je apparaat blijft

Geplande routes, opgenomen ritten, hun gps-tracks, je instellingen, gedownloade
offline kaartregio's, gedownloade routeringstegels en de zoekindexen voor
plaatsen die daarbij horen, worden opgeslagen in de eigen opslag van de app op
je telefoon. Ze worden nergens naartoe geüpload, tenzij je daarom vraagt.

Hartslag, cadans en vermogen van een Apple Watch, een Bluetooth-sensor of je
gezondheidsapp worden bij de rit opgeslagen, op de telefoon, net als de track
zelf. Met de schakelaar Gezondheid aan in Instellingen leest de app de hartslag
uit Apple Health of Health Connect en schrijft hij je voltooide ritten daar weg
als fietstrainingen; die uitwisseling gebeurt op je telefoon en niets ervan
bereikt ons. Sensorwaarden gaan alleen mee met een rit waar de rit zelf
naartoe gaat: in een GPX-, FIT- of TCX-bestand dat je exporteert, of in een
upload naar Strava of RideWithGPS die je zelf start.

Als je Strava of RideWithGPS koppelt, worden de toegangstokens voor die accounts
opgeslagen in de beveiligde opslag van de telefoon (Keychain op iOS, Keystore
op Android), in een versleutelde vorm die alleen onze relay kan openen; zie het
gedeelte over Strava en RideWithGPS hieronder.

Op Android is de app uitgesloten van de cloudback-up van Google en van de
overdracht van apparaat naar apparaat, zodat je ritten en je toegangstokens ook
niet door het systeem van de telefoon worden gekopieerd. Overstappen naar een
nieuwe telefoon betekent dat je wat je wilt bewaren exporteert als GPX-, FIT-
of TCX-bestanden.

## Wat je apparaat verlaat, en wanneer

### Routeplanning

Routeplanning gebeurt normaal gesproken volledig op je telefoon, op basis van
routeringstegels die je hebt gedownload, en er wordt niets verstuurd. Voor een
gebied waarvoor je geen tegels hebt, stuurt de app de coördinaten van je
routepunten naar een routeringsserver (BRouter, door ons beheerd), die de route
terugstuurt. Die heeft de routepunten nodig om de route te berekenen; hij
ontvangt niet je identiteit, je andere routes of je ritten.

### Zoeken

Plaatsen worden op je telefoon gezocht, in de zoekindexen die bij de
gedownloade routeringstegels horen. Niets van wat je daar typt verlaat het
apparaat.

Als je onderaan de resultaten op "Online zoeken naar …" tikt (of als je geen
routeringstegels hebt gedownload, in welk geval het zoekveld meteen online
gaat), wordt wat je hebt getypt naar Photon gestuurd, een geocodingdienst,
samen met een globale positie zodat resultaten in de buurt bovenaan komen.
Photon stuurt suggesties voor plaatsen terug.

Tikken op "Details" op de kaart van een plaats haalt de details ervan
(openingstijden, website en dergelijke) op bij OpenStreetMap.

### Kaarttegels

De kaart wordt getekend uit tegels die worden opgehaald bij OpenFreeMap, en bij
CyclOSM als je de fietslaag aanzet. Het ophalen van een tegel vertelt de
tegelaanbieder naar welk deel van de kaart je kijkt, en daarbij komt je
IP-adres kijken, zoals bij elk webverzoek. Kaartgegevens © OpenStreetMap-bijdragers.

### Strava en RideWithGPS (Velorki Plus)

Er wordt niets naar Strava of RideWithGPS gestuurd, tenzij je het account zelf
koppelt en daarna een actie start: een rit uploaden, een route importeren.

Bij het koppelen geeft de app een eenmalige code aan onze relayserver, die
deze inwisselt voor een toegangstoken door ons applicatiegeheim toe te voegen,
het token versleutelt met een sleutel die alleen de relay heeft, en het in die
vorm teruggeeft aan de app. Je telefoon bewaart het versleutelde token; hij kan
het zelf niet gebruiken, en wij slaan het helemaal niet op.

Daarna gaat elke upload, routeoverdracht, import en ontkoppeling die je start
via de relay: die controleert of je abonnement actief is, ontsleutelt het token
voor dat ene verzoek, stuurt het verzoek door naar Strava of RideWithGPS en
geeft het antwoord terug aan de app. Hij bewaart het bestand niet, het token
niet en niets van het antwoord, en hij past dezelfde snelheidsbeperking toe als
bij elke andere relay-aanroep (zie Serverlogs hieronder). Zijn logs bevatten
nooit het token, de inhoud van het verzoek of de abonnee-id.

Wat Strava of RideWithGPS vervolgens doen met de gegevens die je hun stuurt,
valt onder hun eigen privacybeleid.

### De AI-assistent (Velorki Plus)

De assistent staat uit totdat je hem inschakelt, en de eerste keer dat je hem
opent wordt je om toestemming gevraagd. Je kunt kiezen om alleen je tekst te
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
Staten berust op de modelcontractbepalingen (Standard Contractual Clauses) van
de Europese Commissie. OpenRouter en de modelaanbieder ontvangen het verzoek
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

### Abonnementen

Velorki Plus wordt verkocht via de App Store en Google Play, en namens ons
afgehandeld door RevenueCat. RevenueCat geeft je installatie een **anonieme
app-gebruikers-id**, een willekeurige tekenreeks die niet gekoppeld is aan een
naam, een e-mailadres of een apparaat-id. RevenueCat ontvangt ook het
aankoopbewijs van de store. Onze relay stuurt die anonieme id naar RevenueCat om
te controleren of je abonnement actief is, en voor niets anders.

We zien je betaalgegevens nooit; die blijven bij Apple of Google.

### Crashrapportage en analytics

Die zijn er niet. De app bevat geen crashrapportage, geen analytics en geen
advertentie-SDK, en hij stuurt geen gebruiksstatistieken; elk netwerkverzoek dat
hij doet is een van de hierboven beschreven verzoeken. Crashes worden door de
app stores geaggregeerd aan het ontwikkelaarsaccount gemeld, zonder iets wat
jou identificeert, en alleen als je dat in de eigen instellingen van je
telefoon hebt aangezet. Als er ooit een crashrapportage wordt toegevoegd, noemt
dit gedeelte die en zegt het wat die verzamelt, voordat die versie uitkomt.

### Serverlogs

Onze relay en onze routeringsserver houden operationele logs bij (tijdstip van
het verzoek, endpoint, status, IP-adres en een header met de clientversie) om
de dienst te laten draaien, fouten op te sporen en snelheidsbeperkingen toe te
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
footer haalt haar terug.

- **Serverlogs.** Elk verzoek wordt gelogd zoals hierboven onder Serverlogs
  beschreven: tijdstip, pad, status, grootte, je IP-adres en de user agent van
  je browser, 14 dagen bewaard.
- **Foutmeldingen.** Als een pagina van deze site in je browser misgaat, stuurt
  die de fout, het adres van de pagina en de user agent van je browser naar
  onze server, alleen zodat we de bug kunnen oplossen.
- **Cloudflare.** De site wordt geleverd via Cloudflare, dat de verbinding
  afhandelt, aanvallen filtert en het verzoek doorgeeft aan onze server.
  Cloudflare verwerkt daarom je IP-adres en het verzoek zelf. Cloudflare zit in
  de Verenigde Staten; de doorgifte berust op de modelcontractbepalingen van de
  EU.
- **Een taalcookie.** Een taal kiezen in de header zet een cookie met de naam
  `NEXT_LOCALE` (de waarde `en` of `de`, één jaar). Die bestaat zodat de site
  opent in de taal die je hebt gekozen. Er staat verder niets in, en hij wordt
  alleen gezet wanneer je die keuze maakt — hij is strikt noodzakelijk voor een
  functie waar je om hebt gevraagd en heeft geen toestemming nodig op grond van
  § 25 lid 2 TTDSG.
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

## Bewaren en verwijderen

| Gegevens | Bewaard | Hoe je ze verwijdert |
|---|---|---|
| Routes, ritten, instellingen, offline gegevens | op je telefoon, totdat je ze verwijdert | verwijder ze in de app, of verwijder de app |
| Tokens van Strava / RideWithGPS | op je telefoon, zo versleuteld dat alleen onze relay ze kan openen, totdat je ontkoppelt; nooit bij ons opgeslagen | ontkoppel in de app, of verwijder de app |
| Deellinks | één jaar, daarna automatisch verwijderd | verwijder ze vanuit de app |
| AI-prompts | door ons niet bewaard, buiten wat de logs hierboven bevatten | niet van toepassing |
| Gegevens bij RevenueCat | volgens het eigen beleid van RevenueCat | neem contact met ons op en we geven het verzoek door |
| Gesprekken in de supportchat | in ons Discord-kanaal totdat we ze verwijderen | vraag het via ride@velorki.com |

De app verwijderen wist alles wat de app op het apparaat heeft opgeslagen. Het
verwijdert geen deellinks die je hebt gemaakt (die verlopen na één jaar, of op
verzoek), en het verwijdert niets wat je naar Strava of RideWithGPS hebt
geüpload.

## Rechtsgronden

Voor lezers in de EU en het VK zijn de rechtsgronden op grond van artikel 6
lid 1 AVG:

| Wat | Grondslag |
|---|---|
| De website en de deelpagina's leveren, de servers draaiende houden, fouten opsporen, snelheidsbeperkingen, verdediging tegen aanvallen | (f) gerechtvaardigd belang bij het draaien van een dienst die werkt en niet wordt misbruikt |
| Online routeplanning en online zoeken, wanneer je daarom vraagt | (b) uitvoering van de dienst waar je om hebt gevraagd, en (f) voor de coördinaten die strikt nodig zijn om te antwoorden |
| Velorki Plus: bij RevenueCat controleren of een abonnement actief is | (b) uitvoering van de overeenkomst |
| Strava en RideWithGPS: een account koppelen en elke overdracht die je start | (b) uitvoering van de overeenkomst, plus (a) toestemming, gegeven door het account te koppelen |
| Deellinks die je maakt | (b) uitvoering van de overeenkomst |
| De AI-assistent | (a) toestemming, apart gevraagd in de app en in te trekken in de instellingen |
| Je antwoorden in de supportchat | (b) als het om een abonnement gaat, anders (f) gerechtvaardigd belang bij het antwoorden van wie ons heeft geschreven |
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
  aanvallen voor velorki.com en api.velorki.com. IP-adressen en metadata van
  verzoeken.
- **RevenueCat, Inc.**, San Francisco, VS — de abonnementscontrole. De anonieme
  app-gebruikers-id en het aankoopbewijs van de store, geen naam en geen
  e-mailadres.
- **Orkify**, beheerd door dezelfde beheerder op de Hetzner-infrastructuur
  hierboven — het deploymentdashboard dat de applicatielogs en procesmetrics
  verzamelt die onder Serverlogs worden beschreven en de foutmeldingen van deze
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
  wanneer je op "Details" op de kaart ervan tikt.
- **Apple Inc.** en **Google Ireland Ltd** — de verkoop van Velorki Plus. Zij
  zijn de verkopers; wij zien je betaalgegevens nooit.
- **Strava, Inc.** en **Ride with GPS** — alleen nadat je het account koppelt en
  alleen voor een overdracht die je start. Wat zij ermee doen valt onder hun
  eigen beleid.

We geven gegevens ook aan een rechter of een instantie als de wet dat vereist.

## Doorgifte buiten de EU

Cloudflare, RevenueCat, OpenRouter en de modelaanbieder daarachter, Discord,
Klipy, Strava, Ride with GPS, Apple en Google zitten in de Verenigde Staten of
geven gegevens daarheen door. Die doorgifte berust op de
modelcontractbepalingen van de Europese Commissie, of op de certificering van
de aanbieder onder het EU-VS Data Privacy Framework als die er een heeft, samen
met de eigen technische waarborgen van de aanbieder. Hetzner, komoot en de
kaarttegeldiensten waarop we vertrouwen zitten in de EU, OpenStreetMap in het
VK. Alles wat de app voor je opslaat blijft op je telefoon en wordt nergens
naartoe doorgegeven.

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
uitoefenen, omdat de gegevens op je telefoon staan en wanneer je maar wilt als
GPX-, FIT- of TCX-bestanden kunnen worden geëxporteerd.

Voor alles wat aan onze kant wordt bewaard (deellinks, logregels, het gegeven
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

Als dit beleid verandert op een manier die invloed heeft op wat je apparaat
verlaat, vertelt de app je dat de volgende keer dat je hem opent, en verandert
de datum bovenaan. Oude versies blijven in de git-geschiedenis van de
repository.

## Contact

Orkitec, ride@velorki.com; postadres in het [colofon](./imprint). Voor
beveiligingsmeldingen zie
[SECURITY.md](https://github.com/orkitec/velorki/blob/main/SECURITY.md) in de
broncoderepository.
