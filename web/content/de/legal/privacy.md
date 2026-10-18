---
title: Datenschutzerklärung
description: "Was Velorki mit deinen Daten macht: kein Konto, Routen und Fahrten bleiben auf dem Handy, und eine Liste dessen, was das Gerät wann verlässt."
draft: false
---

> **Hinweis zur Übersetzung.** Dies ist eine Übersetzung der englischen
> Fassung. Bei Abweichungen gilt die englische Fassung.

Gültig ab: 16. Oktober 2026.

Velorki ist eine App zum Planen von Radrouten und zum Aufzeichnen von Fahrten,
gemacht von Orkitec. Diese Seite erklärt, was mit deinen Daten geschieht.

**Wer verantwortlich ist.** Verantwortlich für alles, was hier beschrieben wird,
ist Steffen Roemer, handelnd unter „Orkitec“, Straße der Pariser Kommune 27,
10243 Berlin, Deutschland, ride@velorki.com. Ein Datenschutzbeauftragter ist
nicht bestellt; die unten beschriebene Verarbeitung erfordert das nach Art. 37
DSGVO nicht. Die vollständigen Anbieterangaben stehen im
[Impressum](./imprint).

## Die kurze Fassung

- Es gibt **kein Konto**. Du registrierst dich nicht, und wir wissen nicht, wer
  du bist.
- Deine Routen, deine Fahrten und deine Einstellungen bleiben **auf deinem
  Handy**. Auf einem iPhone oder iPad werden sie außerdem zwischen deinen
  eigenen Geräten über deine iCloud abgeglichen, nicht über uns.
- Manches braucht einen Server: Kartenkacheln, Routing außerhalb der
  heruntergeladenen Gebiete, die Suche, wenn du sie anforderst, und, falls du
  sie nutzt, der KI-Assistent, die Verbindungen zu Strava und RideWithGPS (kostenlos)
  und die Teilen-Links. Jedes davon ist unten beschrieben.
- Diese **Website** hat keine Analyse, keine Werbung und kein Tracking — der
  kurze Hinweis unten auf der Seite verlangt deshalb nichts von dir.
- Wir verkaufen deine Daten nicht, und wir nutzen sie nicht für Werbung oder
  Profilbildung.

## Was auf deinem Gerät bleibt

Geplante Routen, aufgezeichnete Fahrten, ihre GPS-Tracks, deine Einstellungen,
heruntergeladene Offline-Kartenregionen, heruntergeladene Routing-Kacheln und
die Ortssuch-Indizes, die mit ihnen kommen, liegen im eigenen Speicher der App
auf deinem Handy. Sie gehen nirgendwohin hoch, außer du forderst es an; die einzige Ausnahme ist
die iCloud-Synchronisierung auf einem iPhone oder iPad, unten beschrieben, die
in deine eigene iCloud geht und nicht zu uns.

Puls, Trittfrequenz und Leistung von einer Apple Watch, einem Bluetooth-Sensor
oder deiner Health-App werden mit der Fahrt gespeichert, auf dem Handy, wie der
Track selbst. Ist der Health-Schalter in den Einstellungen an, liest die App
den Puls aus Apple Health oder Health Connect und schreibt deine beendeten
Fahrten dort als Radfahr-Trainings hinein; dieser Austausch findet auf deinem
Handy statt, und nichts davon erreicht uns. Sensorwerte verlassen das Handy nur
dort, wo die Fahrt es tut: in einer GPX-, FIT- oder TCX-Datei, die du exportierst,
oder in einem Upload zu Strava oder RideWithGPS, den du anstößt.

Verbindest du Strava oder RideWithGPS, liegen die Zugriffstoken für diese
Konten im sicheren Speicher des Handys (Keychain unter iOS, Keystore unter
Android), in einer verschlüsselten Form, die nur unser Relay öffnen kann, und was du von
Strava übernimmst, bleibt auf dem Handy; siehe den Abschnitt zu Strava und
RideWithGPS unten.

Unter Android ist die App aus Googles Cloud-Sicherung und aus der Übertragung
von Gerät zu Gerät ausgenommen, deine Fahrten und deine Zugriffstoken werden
also auch vom System nicht vom Handy kopiert. Der Umzug auf ein neues Handy
heißt, das Gewünschte als GPX-, FIT- oder TCX-Datei zu exportieren.

## Was dein Gerät verlässt und wann

### Routing

Das Routing läuft normalerweise vollständig auf deinem Handy, aus
heruntergeladenen Routing-Kacheln, und es geht nichts irgendwohin. Für ein
Gebiet, für das du keine Kacheln hast, schickt die App die Koordinaten deiner
Wegpunkte an einen Routing-Server (BRouter, von uns betrieben), der die Route
zurückschickt. Er braucht die Wegpunkte, um die Route zu berechnen; er erhält
weder deine Identität noch deine anderen Routen noch deine Fahrten.

### Suche

Orte werden auf deinem Handy gesucht, in den Suchindizes, die mit den
heruntergeladenen Routing-Kacheln kommen. Nichts von dem, was du dort eingibst,
verlässt das Gerät.

Tippst du unten in den Ergebnissen auf "Online nach … suchen" (oder hast du
keine Routing-Kacheln heruntergeladen, in welchem Fall das Suchfeld sofort
online geht), geht dein Text an Photon, einen Geocoding-Dienst, zusammen mit
einer groben Position, damit nahe Ergebnisse zuerst stehen. Photon liefert
Ortsvorschläge zurück.

Tippst du auf der Ortskarte auf "Details", werden die Details des Orts
(Öffnungszeiten, Website und Ähnliches) von OpenStreetMap abgerufen.

### Kartenkacheln

Die Karte wird aus Kacheln gezeichnet, die von OpenFreeMap geholt werden, und
von CyclOSM, wenn du das Rad-Overlay einschaltest. Eine Kachel zu holen verrät
dem Kachelanbieter, welchen Teil der Karte du ansiehst, und umfasst deine
IP-Adresse, wie jede Anfrage im Web. Kartendaten © OpenStreetMap contributors.

### Wetter

**Die Wetterkarte und die kostenlose Vorhersage für die Route.** Schaltest du
auf der Karte den Regen, die Wolken oder den Wind ein oder färbst du eine Route
ohne Velorki Plus nach Wind oder Regen ein, holt die App Bilder und
Vorhersagedaten direkt von öffentlichen Wetterdiensten: vom Deutschen
Wetterdienst (Deutschland), von der US National Oceanic and Atmospheric
Administration und der Iowa State University (USA), der NASA, EUMETSAT, dem KNMI
(Niederlande) und dem Finnischen Meteorologischen Institut. Jede Anfrage nennt
einen Kartenausschnitt oder einen Rahmen um deine Route sowie einen Zeitpunkt
und umfasst deine IP-Adresse, wie jede Anfrage im Web. Deine Route selbst, deine
Fahrten und deine Identität werden nicht gesendet.

**Feineres Wetter entlang der Route (Velorki Plus).** Die App schickt unserem
Relay die Punkte entlang der Route, gerundet auf ein Raster von etwa 2,5 km,
jeweils mit ihrer auf 50 m gerundeten Höhe, und die Stunden, in denen du dort
fährst — nicht die Route, ihren Namen oder deine Fahrten. Der Relay prüft, ob
dein Abo aktiv ist, und fragt beim US National Weather Service, bei Bright Sky
(für die Vorhersagen des Deutschen Wetterdienstes) und bei MET Norway nach
diesen Rasterpunkten. Sie sehen unseren Server, nicht dein Handy. Jede Antwort
wird pro Rasterpunkt bis zu zwei Stunden aufbewahrt und mit allen geteilt, die
nach demselben Punkt fragen.

**Regenradar für ganz Europa (Velorki Plus).** Die App fragt unseren Relay nach
dem Kartenausschnitt, den du ansiehst, und einem Zeitpunkt. Der Relay holt das
Radar einmal für alle aus dem offenen Archiv von EUMETNET OPERA und, für
Italien, vom Dipartimento della Protezione Civile, bewahrt es bis zu zweieinhalb
Stunden auf und schickt ein Bild dieses Kartenausschnitts zurück. Die Anbieter
des Radars sehen unseren Server, nicht dein Handy, und der Relay hält nicht
fest, nach welchem Kartenausschnitt du gefragt hast.

### Strava und RideWithGPS

Beide Verbindungen sind kostenlos. An Strava oder RideWithGPS geht nichts,
außer du verbindest das Konto selbst und löst dann eine Aktion aus: eine Fahrt
hochladen, eine Route importieren.

Beim Verbinden übergibt die App einen Einmalcode an unseren Relay-Server
(api.velorki.com), der ihn unter Zugabe unseres Anwendungsgeheimnisses gegen
einen Zugriffstoken tauscht, den Token mit einem Schlüssel verschlüsselt, den
nur der Relay hat, und ihn in dieser Form an die App zurückgibt. Dein Handy
speichert den verschlüsselten Token in seinem sicheren Speicher (Keychain unter
iOS, Keystore unter Android), von Sicherungen ausgenommen; es kann ihn allein
nicht verwenden, und wir speichern ihn gar nicht.

Danach läuft jeder Upload, jede Routenübertragung, jeder Import und jedes
Trennen, das du auslöst, über den Relay: Er entschlüsselt den Token für diese
eine Anfrage, leitet die Anfrage an Strava oder RideWithGPS weiter und gibt die
Antwort an die App zurück. Er behält weder die Datei noch den Token, nichts von
der Antwort und keine Aufzeichnung des Aufrufs. Für diese Aufrufe wird kein Abo
geprüft; um Missbrauch zu verhindern, führt der Relay nur kurzlebige
Ratenbegrenzungs-Zähler, geordnet nach der anonymen ID deiner Installation und
nach IP-Adresse (siehe Server-Protokolle unten). Seine Protokolle enthalten nie
den Token, den Inhalt der Anfrage oder diese ID.

#### Strava

**Worum Velorki bittet.** Um zwei Berechtigungen: `read`, dein öffentliches
Strava-Profil (deine Athleten-ID und dein Name), und `activity:write`, um die
Fahrten hochzuladen, die du hochladen willst. Velorki liest deine Aktivitäten
nicht.

**Was es liest und behält, alles nur auf deinem Handy:**

- deine Athleten-ID und deinen Namen, angezeigt unter Einstellungen →
  Verbindungen, bis du trennst;
- deine Liste der Strava-Routen (Name, Distanz, Höhenmeter, Beschreibung und
  Datum), abgerufen, wenn du den Importbildschirm öffnest, und höchstens
  **48 Stunden** auf dem Handy aufbewahrt;
- die GPX-Datei einer Route, wenn du diese Route importierst; sie wird als
  Route in der Bibliothek der App gespeichert, und ebenso jede Route, die du
  daraus bearbeitest, nur solange die Route bei Strava noch existiert: Solange
  die App geöffnet, online und verbunden ist, prüft sie die Route alle 48
  Stunden erneut bei Strava und entfernt sie, wenn sie bei Strava gelöscht wurde
  oder 7 Tage lang nicht geprüft werden konnte, und sagt dir das. Sie wird auch
  entfernt, wenn du sie löschst oder trennst;
- nach einem Upload die ID der Strava-Aktivität und ihren Link, zusammen mit der
  Fahrt gespeichert, damit die App „View on Strava“ zeigen kann, bis du
  trennst.

Eine Fahrt, die du hochlädst, geht an Strava, das sie verarbeitet, wie in der
[Datenschutzerklärung von Strava](https://www.strava.com/legal/privacy)
beschrieben. Strava und Orkitec sind jeweils für ihre eigene Verarbeitung
verantwortlich.

**Strava-Daten bleiben bei dir.** Strava-Daten werden nur dir angezeigt, in der
App. Sie werden nie an den KI-Assistenten gesendet, nie in einen Teilen-Link
gelegt und nie an RideWithGPS oder einen anderen Dienst geschickt. Wir halten
keine Strava-Daten auf unseren Servern.

**Löschung.** Strava unter Einstellungen → Verbindungen zu trennen widerruft die
Autorisierung von Velorki bei Strava, löscht die Tokens und löscht jeden Eintrag,
der von Strava stammt, vom Handy: importierte Strava-Routen und daraus
bearbeitete Routen, die zwischengespeicherte Routenliste und die gespeicherten
Aktivitätslinks. Die App bestätigt dann: „Deine Strava-Daten wurden von diesem
Handy gelöscht.“ Widerrufst du den Zugriff von Velorki stattdessen auf
strava.com, bemerkt die App es beim nächsten Strava-Aufruf, löscht dieselben
Daten und sagt es dir. Auch das Deinstallieren der App löscht sie. Da alles auf
deinem Handy liegt, sind das die Wege, es zu löschen; für Fragen oder einen
Löschantrag schreib an ride@velorki.com.

**Nutzungsdaten bei Strava.** Strava darf überwachen und erfassen, wie Velorki
die Strava-API nutzt (Nutzungsdaten), und darf sie für jeden geschäftlichen
Zweck verwenden, intern oder extern, einschließlich der Verbesserung der
Strava-API oder der Strava-Plattform, der Entwickler- oder Nutzerunterstützung
und der Sicherstellung der Einhaltung seiner API-Vereinbarung.

#### RideWithGPS

Was RideWithGPS mit den Daten macht, die du ihm schickst, richtet sich nach
seiner eigenen Datenschutzerklärung.

### Der KI-Assistent (Velorki Plus)

Der Assistent ist aus, bis du ihn einschaltest, und beim ersten Öffnen wirst du
um deine Zustimmung gebeten. Du kannst wählen, nur deinen Text zu senden, oder
deinen Text zusammen mit einer groben Startposition, oder abzulehnen. Du kannst
die Zustimmung jederzeit in den Einstellungen widerrufen.

Wenn du ihn nutzt, geht Folgendes über unseren Relay-Server an unseren
KI-Anbieter:

- der Text, den du eingegeben hast,
- auf Wunsch eine Startposition, **auf etwa einen Kilometer gerundet**,
- die Sprach- und Einheiteneinstellung, damit die Antwort passt,
- bei einer Routenbeschreibung eine auf deinem Handy erstellte Übersicht der
  Route: Distanz, Anstieg, Belagsanteile, die Abschnitte mit Straßenart, Belag
  und Steigung, ihre Anstiege, die Orte, durch die sie führt, und
  Einkehrmöglichkeiten in ihrer Nähe, jeweils mit dem Kilometer entlang der
  Route und ihrer Position (auf etwa 10 m). Auch die Positionen erhält der
  KI-Anbieter; beginnt die Route bei dir zu Hause, zeigt sie also, wo du wohnst.

In die Anfrage kommt keine Kennung von dir oder deinem Handy. Das Modell
liefert eine strukturierte Anfrage zurück: eine Distanz, eine Form, Ortsnamen,
Vorlieben. Das eigentliche Routing geschieht danach in der App; das Modell
sieht deine Route nie.

Unser Relay gibt die Anfrage an **OpenRouter, Inc.** (USA) weiter, einen Dienst,
der Zugang zu Sprachmodellen verschiedener Anbieter bietet, und OpenRouter leitet
sie an den Anbieter weiter, der das von uns genutzte Modell bereitstellt. Wir
haben OpenRouter so eingestellt, dass Anfragen nur an Anbieter gehen, die damit
keine Modelle trainieren und sie nicht speichern. Die Übermittlung in die USA
stützt sich auf die Standardvertragsklauseln der Europäischen Kommission.
OpenRouter und der Modellanbieter erhalten die Anfrage von unserem Relay, nicht
von deinem Handy; sie sehen also die Adresse unseres Servers, nicht deine.

Der Assistent erreicht das Modell über eine OpenAI-kompatible Schnittstelle. Wer
Velorki selbst betreibt, kann seinen Relay deshalb auf jeden Anbieter oder auf
ein eigenes Modell richten; dann gilt die Erklärung dieses Betreibers und nicht
diese.

Daten von Strava gehen nie an den KI-Anbieter.

### Teilen-Links (Velorki Plus)

Erstellst du einen Teilen-Link für eine Route oder eine Fahrt, wird diese Route
oder Fahrt mit ihrem Track, ihrem Namen und ihren Statistiken auf unseren
Server hochgeladen und dort gespeichert, damit jeder mit dem Link sie öffnen
kann. Puls, Trittfrequenz und Leistung bleiben dabei weg: Eine geteilte Fahrt
enthält ihren Track und ihre Zeiten, nicht, was ein Sensor gemessen hat. Der
Link ist öffentlich: Wer ihn hat, kann den Inhalt sehen, samt Start-
und Endpunkt des Tracks. Bedenke das, bevor du eine Fahrt teilst, die an deinem
Zuhause beginnt.

Ein geteilter Eintrag wird **ein Jahr** lang aufbewahrt und dann automatisch
gelöscht. Damit er früher verschwindet, schick den Link an die unten genannte
Kontaktadresse, und wir löschen ihn. Das Ansehen eines geteilten Links braucht
kein Konto.

### iCloud-Synchronisierung (iPhone und iPad)

Auf einem iPhone oder iPad mit iOS 17 oder neuer werden deine gespeicherten
Routen und deine aufgezeichneten Fahrten, mit dem Track, den Notizen und den
Statistiken jeder Fahrt, zwischen deinen eigenen Apple-Geräten abgeglichen, die
mit demselben Apple Account angemeldet sind. Einige Einstellungen werden
ebenfalls abgeglichen: Design, Akzentfarbe, Kartenstil, Leistenstil, Spaltenseite,
Einheiten sowie die Einstellungen für Abbiege- und Sprachansagen. Die
Synchronisierung ist standardmäßig an, und der Schalter **Mit iCloud
synchronisieren** in den Einstellungen schaltet sie auf diesem Gerät aus.

Die Daten laufen über Apples CloudKit und liegen in deiner eigenen privaten
iCloud-Datenbank. Apple speichert und überträgt sie, und sie zählen auf deinen
iCloud-Speicher. Orkitec betreibt dafür keinen Server und kann sie weder lesen
noch darauf zugreifen noch sie löschen; es gibt kein Velorki-Konto. Apple
verschlüsselt die Daten bei der Übertragung und auf seinen Servern; mit
eingeschaltetem erweiterten Datenschutz (Advanced Data Protection) sind sie
Ende-zu-Ende-verschlüsselt, wie in [Apples Übersicht zur Datensicherheit von
iCloud](https://support.apple.com/en-us/102651) beschrieben.

Manches wird nie abgeglichen. Aus Strava gelesene Routen und daraus bearbeitete
Routen sowie die Strava-Links von Fahrten, die du zu Strava hochgeladen hast,
bleiben auf dem einen Handy, wie oben unter Strava beschrieben. Auch die Links
von Uploads zu Ride with GPS werden nicht abgeglichen; eine Route, die du aus
Ride with GPS importierst, wird als deine eigene Route abgeglichen, ohne ihre
Ride-with-GPS-ID. Heruntergeladene Kartenregionen und Routing-Kacheln,
Berechtigungen, gekoppelte Sensoren, verbundene Konten und der Abo-Status
gehören nicht dazu. Die Android-App synchronisiert nicht.

Wenn du den Schalter ausschaltest, hört der Abgleich auf diesem Gerät auf. Was
schon in iCloud liegt, bleibt dort, bis du es in den iCloud-Einstellungen des
Geräts löschst.

### Abos

Velorki Plus wird über den App Store und Google Play verkauft und in unserem
Auftrag von RevenueCat abgewickelt. RevenueCat weist deiner Installation eine
**anonyme App-Nutzer-ID** zu, eine zufällige Zeichenfolge, die weder mit einem
Namen noch mit einer E-Mail-Adresse noch mit einer Gerätekennung verknüpft ist.
RevenueCat erhält außerdem den Kaufbeleg vom Store. Unser Relay schickt diese
anonyme ID an RevenueCat, um zu prüfen, ob dein Abo aktiv ist, und zu sonst
nichts.

Deine Zahlungsdaten sehen wir nie; die bleiben bei Apple oder Google.

### Absturzberichte und Analyse

Es gibt keine. Die App enthält kein SDK für Absturzberichte, keine Analyse und
keine Werbung, und sie schickt keine Nutzungsstatistik; jede Netzwerkanfrage,
die sie stellt, ist eine der oben beschriebenen. Abstürze meldet der App-Store
gesammelt an das Entwicklerkonto, ohne etwas, das dich identifiziert, und nur
wenn du das in den Einstellungen deines Handys eingeschaltet hast. Kommt später
ein Absturzbericht-Dienst dazu, nennt dieser Abschnitt ihn beim Namen und sagt,
was er erhebt, bevor diese Version ausgeliefert wird.

### Server-Protokolle

Unser Relay und unser Routing-Server führen Betriebsprotokolle (Zeitpunkt der
Anfrage, Endpunkt, Status, IP-Adresse und einen Header mit der Client-Version),
um den Dienst zu betreiben, Fehler zu finden und Ratenbegrenzungen
durchzusetzen. Sie werden nicht dazu genutzt, Profile von Nutzenden zu bilden,
und sie enthalten nie ein Zugriffstoken, einen Anfragetext oder eine
Abonnenten-Kennung.

- Die Zugriffsprotokolle des Webservers bleiben **14 Tage** auf der Maschine und
  werden dann von der Protokollrotation gelöscht.
- Die Protokollzeilen der Anwendung sammelt Orkify, das Deployment-Dashboard
  desselben Betreibers auf derselben Hetzner-Infrastruktur, und löscht sie dort
  spätestens nach **90 Tagen**.

## Diese Website

velorki.com ist eine einfache Website: kein Konto, keine Werbung, keine
Analyse, kein Tracking. Nichts, was du hier tust, wird gemessen — der Hinweis,
den du unten auf der Seite gesehen haben magst, ist deshalb genau das, ein
Hinweis: Es gibt keine Einwilligung zu erteilen und keine zu verweigern, denn
auf deinem Gerät wird nichts gespeichert, bis du es verlangst. Der Eintrag
🍪 Cookies im Fußbereich holt ihn zurück.

- **Server-Protokolle.** Jede Anfrage wird protokolliert wie oben unter
  Server-Protokolle beschrieben: Zeitpunkt, Pfad, Status, Größe, deine
  IP-Adresse und die Kennung deines Browsers, 14 Tage lang.
- **Fehlerberichte.** Schlägt eine Seite dieser Website in deinem Browser fehl,
  schickt sie den Fehler, die Adresse der Seite und die Kennung deines Browsers
  an unseren Server, nur damit wir den Fehler beheben können.
- **Cloudflare.** Die Website wird über Cloudflare ausgeliefert, das die
  Verbindung annimmt, Angriffe abfängt und die Anfrage an unseren Server
  weitergibt. Cloudflare verarbeitet dabei deine IP-Adresse und die Anfrage
  selbst. Cloudflare sitzt in den USA; die Übermittlung stützt sich auf die
  Standardvertragsklauseln der EU.
- **Ein Sprach-Cookie.** Wählst du oben eine Sprache, wird ein Cookie
  `NEXT_LOCALE` gesetzt (Wert `en` oder `de`, ein Jahr). Es sorgt dafür, dass die
  Website in der gewählten Sprache öffnet. Mehr steht nicht darin, und es wird
  nur gesetzt, wenn du diese Wahl triffst — es ist für eine von dir
  angeforderte Funktion unbedingt erforderlich und braucht nach § 25 Abs. 2
  TTDSG keine Einwilligung.
- **Die Darstellung.** Wählst du hell, dunkel oder eine Akzentfarbe, wird
  `velorki.theme` im lokalen Speicher deines Browsers abgelegt. Das verlässt den
  Browser nie und ist für uns nicht lesbar. Schließt du den Hinweis oben, kommt
  ein weiterer Schlüssel dazu, `velorki.cookie-notice`, damit er nicht wieder
  erscheint.
- **Freigabe-Seiten.** Öffnest du einen `velorki.com/s/…`-Link, kommt die
  geteilte Route von unserem Server und die Kartenkacheln von OpenFreeMap, das
  dabei deine IP-Adresse sieht wie bei jeder Webanfrage. Weitere fremde Inhalte
  hat die Seite nicht.
- **Der Support-Chat.** Die Chat-Schaltfläche in der Ecke ist das Widget von
  Orkify. Orkitec betreibt auch Orkify, es ist also unsere eigene
  Infrastruktur, aber eine andere Website: Das Skript wird von orkify.com
  geladen und fragt dort beim Öffnen der Seite seine Einstellungen ab — dabei
  erreicht orkify.com deine IP-Adresse, wie bei jedem Server, den du anfragst.
  Mehr passiert nicht, bis du den Chat öffnest.

  Schreibst du uns, geht deine Nachricht — mit dem Namen und der E-Mail-Adresse,
  die du in das Formular einträgst — in einen privaten Discord-Kanal, in dem wir
  antworten, und das Gespräch bleibt dort, bis wir es löschen. Schreib an
  ride@velorki.com, dann entfernen wir deines. Das Widget legt die Kennung des
  Gesprächs und den angegebenen Namen und die E-Mail-Adresse im lokalen Speicher
  deines Browsers ab, damit eine Antwort dich wiederfindet, wenn du
  zurückkommst, und löscht sie, wenn du den Chat beendest. Öffnest du die
  Stickerauswahl, geht deine Suche an Klipy, das die Bilder zurückgibt. Schreib
  in den Chat nichts, was nicht in einem Support-Ticket stehen soll; für eine
  Sicherheitsmeldung nutze die Adresse in
  [SECURITY.md](https://github.com/orkitec/velorki/blob/main/SECURITY.md).
- **Schriften und Bilder** kommen alle von diesem Server, und außer dem
  Support-Chat gibt es kein fremdes Skript, kein CDN für unsere eigenen Dateien
  und keinen Schriftdienst.

## Aufbewahrung und Löschung

| Daten | Aufbewahrt | Wie du sie löschst |
|---|---|---|
| Routen, Fahrten, Einstellungen, Offline-Daten | auf deinem Handy, bis du sie löschst | in der App löschen oder die App deinstallieren |
| Token von Strava / RideWithGPS | auf deinem Handy, so verschlüsselt, dass nur unser Relay sie öffnen kann, bis du trennst; nie bei uns gespeichert | in der App trennen oder deinstallieren |
| Strava-Daten: dein Name, Aktivitätslinks | auf deinem Handy, bis du trennst; nie bei uns gespeichert | Strava in der App trennen oder deinstallieren; Fragen an ride@velorki.com |
| Aus Strava importierte Routen und daraus bearbeitete Routen | auf deinem Handy, nur solange die Route bei Strava noch existiert: alle 48 Stunden erneut geprüft, entfernt, wenn sie dort gelöscht wurde oder 7 Tage lang nicht geprüft werden konnte; nie bei uns gespeichert | in der App löschen, Strava trennen oder deinstallieren |
| Die zwischengespeicherte Liste deiner Strava-Routen | auf deinem Handy, höchstens 48 Stunden | Strava trennen oder deinstallieren |
| Ratenbegrenzungs-Zähler (anonyme Installations-ID, IP-Adresse) | auf unserem Server, für das Zählfenster, höchstens einen Tag | nicht anwendbar |
| Teilen-Links | ein Jahr, dann automatisch gelöscht | in der App löschen |
| Über iCloud abgeglichene Routen, Fahrten und Einstellungen (iPhone und iPad) | in deiner eigenen iCloud, bis du sie dort löschst; nie bei uns gespeichert | in den iCloud-Einstellungen des Geräts löschen |
| KI-Anfragen | von uns nicht gespeichert, über die oben genannten Protokolle hinaus | entfällt |
| Daten bei RevenueCat | nach der eigenen Erklärung von RevenueCat | schreib uns, und wir geben die Anfrage weiter |
| Support-Chat-Gespräche | in unserem Discord-Kanal, bis wir sie löschen | schreib an ride@velorki.com |

Das Deinstallieren der App entfernt alles, was die App auf dem Gerät
gespeichert hat. Was die iCloud-Synchronisierung in deine iCloud gelegt hat,
bleibt dort; siehe iCloud-Synchronisierung oben. Es entfernt keine von dir erstellten Teilen-Links (die laufen
nach einem Jahr ab oder auf Anfrage), und es entfernt nichts, was du zu Strava
oder RideWithGPS hochgeladen hast.

## Rechtsgrundlagen

Für Leserinnen und Leser in der EU und im Vereinigten Königreich sind die
Rechtsgrundlagen nach Art. 6 Abs. 1 DSGVO:

| Wofür | Grundlage |
|---|---|
| Betrieb der Website und der Freigabe-Seiten, Verfügbarkeit der Server, Fehlersuche, Ratenbegrenzung, Abwehr von Angriffen | (f) berechtigtes Interesse an einem Dienst, der funktioniert und nicht missbraucht wird |
| Online-Routing und Online-Suche, wenn du sie anforderst | (b) Erbringung der von dir angeforderten Leistung, und (f) für die Koordinaten, die zur Antwort nötig sind |
| Velorki Plus: Prüfung bei RevenueCat, ob ein Abo aktiv ist | (b) Erfüllung des Vertrags |
| Velorki Plus: das feinere Wetter entlang der Route und das Regenradar | (b) Erfüllung des Vertrags |
| Strava und RideWithGPS: Verbinden eines Kontos, jede von dir ausgelöste Übertragung und die Strava-Daten, die auf deinem Handy bleiben | (b) Erfüllung der von dir angeforderten Leistung und (a) Einwilligung, erteilt durch das Verbinden des Kontos und widerrufen durch dessen Trennen |
| Von dir erstellte Freigabe-Links | (b) Erfüllung des Vertrags |
| iCloud-Synchronisierung (iPhone und iPad), solange der Schalter an ist | (b) Erfüllung des von dir gewünschten Dienstes; Apple handelt nach deiner eigenen iCloud-Vereinbarung mit Apple |
| Der KI-Assistent | (a) Einwilligung, in der App gesondert erfragt und in den Einstellungen widerruflich |
| Antworten im Support-Chat | (b), soweit es ein Abo betrifft, sonst (f) berechtigtes Interesse daran, der Person zu antworten, die uns geschrieben hat |
| Aufbewahrung steuerlich relevanter Unterlagen zu einem Abo | (c) rechtliche Verpflichtung — die Zahlungsdaten liegen bei Apple und Google, nicht bei uns |

Wir bilden keine Profile, treffen keine automatisierten Entscheidungen über dich
und nutzen nichts davon für Direktwerbung.

## Wer sonst Daten erhält

Wir verkaufen, vermieten und tauschen keine personenbezogenen Daten. Sie
erreichen diese Stellen und keine anderen:

**Auftragsverarbeiter, die mit Vertrag zur Auftragsverarbeitung für uns tätig
sind**

- **Hetzner Cloud GmbH**, Gunzenhausen, Deutschland — der Server, auf dem der
  Relay, die Freigabe-Links und diese Website laufen. Die Daten bleiben in
  Deutschland.
- **Cloudflare, Inc.**, San Francisco, USA — DNS, CDN und Angriffsabwehr für
  velorki.com und api.velorki.com. IP-Adressen und Metadaten der Anfragen.
- **RevenueCat, Inc.**, San Francisco, USA — die Abo-Prüfung. Die anonyme
  App-Nutzer-Kennung und der Kaufbeleg, kein Name und keine E-Mail-Adresse.
- **Orkify**, betrieben von demselben Betreiber auf der oben genannten
  Hetzner-Infrastruktur — das Deployment-Dashboard, das die Anwendungsprotokolle
  und Prozessmetriken aus dem Abschnitt Server-Protokolle sowie die
  Fehlerberichte dieser Website sammelt, und das Widget des Support-Chats.
- **Discord Netherlands B.V.** (für Nutzende in Europa; dahinter Discord Inc.,
  San Francisco, USA) — dorthin wird ein Support-Chat geliefert und dort bleibt
  er.
- **Klipy** — die Sticker- und GIF-Suche im Support-Chat, und nur solange diese
  Auswahl geöffnet ist.
- **OpenRouter, Inc.**, USA, und der Modellanbieter, an den es weiterleitet — der
  KI-Assistent, nur nach deiner Einwilligung, beschränkt auf Anbieter, die
  Anfragen weder zum Training nutzen noch speichern.

**Dienste, die dein Handy oder dein Browser direkt kontaktiert und die jeweils
selbst verantwortlich sind**

- **OpenFreeMap** (Kartenkacheln) und **OpenStreetMap France** (die
  CyclOSM-Überlagerung, nur wenn du sie einschaltest) — die Kacheln für den
  Kartenausschnitt, den du ansiehst, und deine IP-Adresse.
- **komoot GmbH**, Potsdam, Deutschland — der Photon-Geocoder unter
  `photon.komoot.io`, und nur für eine von dir angeforderte Online-Suche.
- **OpenStreetMap** (`api.openstreetmap.org`) — die Details eines Orts, wenn du
  auf der Ortskarte auf "Details" tippst.
- **Öffentliche Wetterdienste** — der Deutsche Wetterdienst, die NOAA, die Iowa
  State University, die NASA, EUMETSAT, das KNMI und das Finnische
  Meteorologische Institut — der angefragte Kartenausschnitt oder Rahmen um
  deine Route, ein Zeitpunkt und deine IP-Adresse, nur solange eine Wetterebene
  oder die kostenlose Vorhersage für die Route eingeschaltet ist.
- **Apple Inc.** (iCloud) — die Routen, Fahrten und Einstellungen der
  iCloud-Synchronisierung, in deiner eigenen iCloud und nur, solange der
  Schalter an ist. Wir erhalten sie nicht; Apple handelt nach deiner eigenen
  iCloud-Vereinbarung mit Apple.
- **Apple Inc.** und **Google Ireland Ltd** — der Verkauf von Velorki Plus. Sie
  sind die Verkäufer; deine Zahlungsdaten sehen wir nie.
- **Strava, Inc.** und **Ride with GPS** — erst nachdem du das Konto verbunden
  hast, und nur für eine von dir ausgelöste Übertragung. Was dort damit
  geschieht, richtet sich nach deren eigenen Erklärungen.

Außerdem geben wir Daten heraus, wo ein Gericht oder eine Behörde es nach dem
Gesetz verlangt.

## Übermittlungen außerhalb der EU

Cloudflare, RevenueCat, OpenRouter und der Modellanbieter dahinter, Discord,
Klipy, Strava, Ride with GPS, Apple und Google sitzen in den USA oder
übermitteln dorthin. Diese Übermittlungen stützen sich auf die
Standardvertragsklauseln der Europäischen Kommission oder, wo der Anbieter
zertifiziert ist, auf das EU-US Data Privacy Framework, zusammen mit den
technischen Maßnahmen des Anbieters. Hetzner, komoot und die Kartendienste, auf
die wir uns stützen, liegen in der EU, OpenStreetMap im Vereinigten Königreich.
Alles, was die App für dich speichert,
bleibt auf deinem Handy und wird überhaupt nicht übermittelt.

## Sicherheit

Jede Verbindung zu unseren Servern und zu den oben genannten Diensten ist mit
TLS verschlüsselt. Tokens von Strava und RideWithGPS liegen nirgends
unverschlüsselt: Dein Handy hält sie im sicheren Speicher der Plattform,
verpackt mit einem Schlüssel, den nur der Relay hat; der Relay öffnet einen für
die eine Anfrage, für die er gebraucht wird, und behält nichts. Die
Freigabe-Datenbank liegt auf der Platte des Servers, außerhalb des
Release-Verzeichnisses, lesbar nur für den Dienstbenutzer. Protokolle sind
bereinigt: kein `Authorization`-Header, kein Anfragetext, keine
Abonnenten-Kennung. Der Zugang zum Server verlangt einen Schlüssel, kein
Passwort, und steht nur dem Betreiber offen. Sollte eine Verletzung deine Rechte
gefährden, melden wir sie binnen 72 Stunden der Aufsichtsbehörde (Art. 33
DSGVO) und, wo das Gesetz es verlangt, dir.

## Deine Rechte

Wenn du in der EU oder im Vereinigten Königreich bist, hast du das Recht auf
Auskunft (Art. 15 DSGVO), Berichtigung (16), Löschung (17), Einschränkung der
Verarbeitung (18), Datenübertragbarkeit (20) und Widerspruch gegen eine
Verarbeitung auf Grundlage eines berechtigten Interesses (21); und wo wir uns
auf deine Einwilligung stützen — beim Assistenten — kannst du sie jederzeit
widerrufen, ohne dass das Bisherige unrechtmäßig wird (Art. 7 Abs. 3). Das
meiste davon kannst du selbst wahrnehmen, weil die Daten auf deinem Handy liegen
und sich jederzeit als GPX-, FIT- oder TCX-Datei exportieren lassen.

Für alles, was auf unserer Seite liegt (Teilen-Links, Protokolleinträge, der
Datensatz bei RevenueCat), schreib an **ride@velorki.com**. Wir antworten
innerhalb von 30 Tagen. Wir brauchen genug Angaben, um die Daten zu finden, was
bei einem Teilen-Link den Link selbst bedeutet, da es kein Konto gibt, über das
wir dich nachschlagen könnten.

Du kannst dich außerdem bei einer Aufsichtsbehörde beschweren. Für uns ist das
die [Berliner Beauftragte für Datenschutz und Informationsfreiheit](https://www.datenschutz-berlin.de);
du kannst dich ebenso an die Behörde deines Wohnorts wenden.

Verantwortlich ist Steffen Roemer, handelnd unter „Orkitec“, Straße der Pariser
Kommune 27, 10243 Berlin, Deutschland.

## Kinder

Velorki richtet sich nicht an Kinder und erhebt wissentlich keine Daten von
ihnen. Die App hat keine sozialen Funktionen, keine Nachrichten zwischen
Nutzenden und keine Werbung.

## Änderungen

Ändert sich diese Erklärung so, dass es betrifft, was dein Gerät verlässt,
sagt die App es dir beim nächsten Öffnen, und das Datum oben ändert sich. Alte
Fassungen bleiben in der Git-Historie des Repositorys.

## Kontakt

Orkitec, ride@velorki.com; Postanschrift im [Impressum](./imprint). Für
Sicherheitsmeldungen siehe
[SECURITY.md](https://github.com/orkitec/velorki/blob/main/SECURITY.md) im
Quellcode-Repository.
