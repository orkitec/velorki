---
title: Datenschutzerklärung
description: "Was Velorki mit deinen Daten macht: kein Konto, Routen und Fahrten bleiben auf dem Handy oder im Browser, außer du synchronisierst sie mit deiner eigenen iCloud oder deinem Google Drive, und eine Liste dessen, was das Gerät wann verlässt."
draft: false
---

> **Hinweis zur Übersetzung.** Dies ist eine Übersetzung der englischen
> Fassung. Bei Abweichungen gilt die englische Fassung.

Gültig ab: 23. Oktober 2026.

Velorki ist eine App zum Planen von Radrouten und zum Aufzeichnen von Fahrten,
gemacht von Orkitec, für iPhone, iPad und Android, dazu ein Web-Planer unter
app.velorki.com. Diese Seite erklärt, was mit deinen Daten geschieht.

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
  Handy**, beim Web-Planer in deinem Browser. Schaltest du die Synchronisierung
  ein, gehen sie in deine eigene iCloud oder dein eigenes Google Drive, nie zu
  uns.
- Manches braucht einen Server: Kartenkacheln, Routing außerhalb der
  heruntergeladenen Gebiete, die Suche, wenn du sie anforderst, und, falls du
  sie nutzt, der KI-Assistent, die Verbindungen zu Strava und RideWithGPS (kostenlos)
  und die Teilen-Links. Jedes davon ist unten beschrieben.
- Diese **Website** hat keine Analyse, keine Werbung und kein Tracking — der
  kurze Hinweis unten auf der Seite verlangt deshalb nichts von dir.
- Der **Web-Planer** unter app.velorki.com hält es genauso: kein Konto, keine
  Analyse, deine Bibliothek bleibt in deinem Browser.
- Wir verkaufen deine Daten nicht, und wir nutzen sie nicht für Werbung oder
  Profilbildung.

## Was auf deinem Gerät bleibt

Geplante Routen, aufgezeichnete Fahrten, ihre GPS-Tracks, deine Einstellungen,
heruntergeladene Offline-Kartenregionen, heruntergeladene Routing-Kacheln und
die Ortssuch-Indizes, die mit ihnen kommen, liegen im eigenen Speicher der App
auf deinem Handy. Sie gehen nirgendwohin hoch, außer du forderst es an; die
einzige Ausnahme ist die Cloud-Synchronisierung, unten beschrieben, die in deine
eigene iCloud oder dein Google Drive geht und nicht zu uns. Was der Web-Planer
in deinem Browser ablegt, steht unter Der Web-Planer.

Puls, Trittfrequenz und Leistung von einer Apple Watch, einem Bluetooth-Sensor
oder deiner Health-App werden mit der Fahrt gespeichert, auf dem Handy, wie der
Track selbst. Ist der Health-Schalter in den Einstellungen an, liest die App
den Puls aus Apple Health oder Health Connect und schreibt deine beendeten
Fahrten dort als Radfahr-Trainings hinein; dieser Austausch findet auf deinem
Handy statt, und nichts davon erreicht uns. Sensorwerte verlassen das Handy nur
dort, wo die Fahrt es tut: in einer GPX-, FIT- oder TCX-Datei, die du exportierst,
in einem Upload zu Strava oder RideWithGPS, den du anstößt, oder in deine
eigene Cloud, solange die Synchronisierung an ist.

Verbindest du Strava oder RideWithGPS, liegen die Zugriffstoken für diese
Konten im sicheren Speicher des Handys (Keychain unter iOS, Keystore unter
Android), in einer verschlüsselten Form, die nur unser Relay öffnen kann, und was du von
Strava übernimmst, bleibt auf dem Handy; siehe den Abschnitt zu Strava und
RideWithGPS unten.

Unter Android ist die App aus Googles Cloud-Sicherung und aus der Übertragung
von Gerät zu Gerät ausgenommen, deine Fahrten und deine Zugriffstoken werden
also auch vom System nicht vom Handy kopiert. Für den Umzug auf ein neues Handy
schaltest du die Synchronisierung mit Google ein (unten beschrieben) oder
exportierst das Gewünschte als GPX-, FIT- oder TCX-Datei.

## Was dein Gerät verlässt und wann

### Routing

Das Routing läuft normalerweise vollständig auf deinem Handy, aus
heruntergeladenen Routing-Kacheln, und es geht nichts irgendwohin. Für ein
Gebiet, für das du keine Kacheln hast, schickt die App die Koordinaten deiner
Wegpunkte an einen Routing-Server (BRouter, von uns betrieben), der die Route
zurückschickt. Er braucht die Wegpunkte, um die Route zu berechnen; er erhält
weder deine Identität noch deine anderen Routen noch deine Fahrten.

Routing-Kacheln und die Suchindizes daneben werden von unserem Kachel-Spiegel
auf GitHub heruntergeladen (`raw.githubusercontent.com` und Release-Downloads
von `github.com`). GitHub erfährt dabei, welche 5°-Kacheln du herunterlädst,
und deine IP-Adresse, wie bei jeder Anfrage im Web. Der Web-Planer holt sie
stattdessen über app.velorki.com, GitHub sieht dann Cloudflare und nicht dich.

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

### Cloud-Synchronisierung (iCloud oder Google Drive)

Jedes Gerät synchronisiert mit höchstens einer Cloud, gewählt unter
**Einstellungen → Synchronisieren mit**: iCloud (iPhone und iPad mit iOS 17
oder neuer, und der Web-Planer), Google (iPhone, iPad, Android und der
Web-Planer) oder Aus. Auf einem iPhone oder iPad ist iCloud standardmäßig an;
unter Android und im Browser ist die Synchronisierung aus, bis du eine Cloud
wählst.

**Was abgeglichen wird.** Deine gespeicherten Routen und deine aufgezeichneten
Fahrten, jeweils mit Track, Notizen, Statistiken, Runden und den mit ihr
aufgezeichneten Werten für Puls, Trittfrequenz, Leistung und Temperatur. Einige
Einstellungen werden ebenfalls abgeglichen: Design, Akzentfarbe, Kartenstil,
der Stil des Regenradars, Leistenstil, Spaltenseite, Einheiten sowie die
Einstellungen für Abbiegehinweise, Sprachansagen und Neuberechnung. Im Browser
mit iCloud bleiben die Einstellungen im Browser. Jede App legt außerdem einen
kleinen Plus-Eintrag in dieselbe Cloud, beschrieben unter Abos.

**Manches wird nie abgeglichen.** Aus Strava gelesene Routen und daraus
bearbeitete Routen sowie die Strava-Links von Fahrten, die du zu Strava
hochgeladen hast, bleiben auf dem einen Handy, wie oben unter Strava
beschrieben. Auch die Links von Uploads zu Ride with GPS werden nicht
abgeglichen; eine Route, die du aus Ride with GPS importierst, wird als deine
eigene Route abgeglichen, ohne ihre Ride-with-GPS-ID. Heruntergeladene
Kartenregionen und Routing-Kacheln, Berechtigungen, gekoppelte Sensoren, die
Stimme, die Sprache, verbundene Konten und das Abo selbst gehören nicht dazu.

**iCloud.** Die Daten laufen über Apples CloudKit in deine eigene private
iCloud-Datenbank. Apple speichert und überträgt sie, und sie zählen auf deinen
iCloud-Speicher. Apple verschlüsselt sie bei der Übertragung und auf seinen
Servern; mit eingeschaltetem erweiterten Datenschutz (Advanced Data Protection)
sind sie Ende-zu-Ende-verschlüsselt, wie in [Apples Übersicht zur
Datensicherheit von iCloud](https://support.apple.com/en-us/102651)
beschrieben. Im Browser meldest du dich mit Apples eigener Schaltfläche an, in
einem Fenster von Apple; Apples Skript CloudKit JS wird erst von Apple geladen,
wenn du iCloud wählst, und hält deine Apple-Anmeldung in einem Cookie auf der
Website des Planers, bis du dich abmeldest (auch das Löschen der Websitedaten
im Browser entfernt es).

Apples Upload-Server nimmt keine Uploads an, die direkt von unserer Website
kommen. Speichert der Web-Planer eine Route oder eine Fahrt in iCloud, geht die
Datei des Eintrags (Track und Details der Route oder Fahrt) deshalb an
app.velorki.com/cloudkit/upload, eine kleine Cloudflare-Funktion, die sie
unverändert an die einmalige Upload-Adresse weiterreicht, die Apple dafür
genannt hat, und Apples Quittung zurückgibt. Sie speichert nichts, und wir
führen keine Protokolle darüber. Die übrigen Felder des Eintrags gehen direkt
an Apple.

**Google Drive.** Du meldest dich mit deinem Google-Konto an, und Velorki bittet
um nur eine Berechtigung: seinen eigenen ausgeblendeten App-Ordner in deinem
Drive (`drive.appdata`). Es kann keine andere Datei in deinem Drive sehen oder
ändern, und der Ordner erscheint nicht zwischen deinen Dateien. Google
speichert die Daten, und sie zählen auf deinen Google-Speicher; Google
verschlüsselt sie bei der Übertragung und auf seinen Servern, nicht
Ende-zu-Ende. Das Handy behält die ID und die E-Mail-Adresse deines
Google-Kontos, um anzuzeigen, wer angemeldet ist. Im Browser meldest du dich mit
Googles eigener Schaltfläche an; Googles Anmeldeskript wird erst geladen, wenn
du Google wählst, und sein Zugriffstoken lebt nur so lange wie die Seite und
höchstens eine Stunde.

**Was Orkitec sieht.** Nichts. Orkitec betreibt für die Synchronisierung keinen
Server und kann nicht lesen, darauf zugreifen oder löschen, was in deiner
iCloud oder deinem Drive liegt; es gibt kein Velorki-Konto. Apple und Google
handeln nach deiner eigenen Vereinbarung mit ihnen.

**Löschen, ausschalten.** Solange die Synchronisierung an ist, löscht das
Löschen einer Route oder Fahrt auf einem Gerät sie auch in deiner Cloud und auf
deinen anderen Geräten. **Aus** zu wählen, dich abzumelden oder zur anderen
Cloud zu wechseln, beendet den Abgleich auf diesem Gerät und löscht nichts;
ein Wechsel schickt deine Bibliothek in die neue Cloud und lässt die alte Kopie,
wo sie war. Was schon in iCloud liegt, bleibt dort, bis du es in den
iCloud-Einstellungen auf einem Apple-Gerät löschst. Was in Google Drive liegt,
bleibt, bis du es löschst: in Google Drive im Web unter Einstellungen → Apps
verwalten → Velorki → Optionen → Ausgeblendete App-Daten löschen; entziehst du
Velorki unter myaccount.google.com/permissions den Zugriff, erreicht es den
Ordner nicht mehr.

### Abos

Velorki Plus wird über den App Store und Google Play verkauft und in unserem
Auftrag von RevenueCat abgewickelt. RevenueCat weist deiner Installation eine
**anonyme App-Nutzer-ID** zu, eine zufällige Zeichenfolge, die weder mit einem
Namen noch mit einer E-Mail-Adresse noch mit einer Gerätekennung verknüpft ist.
RevenueCat erhält außerdem den Kaufbeleg vom Store. Unser Relay schickt diese
anonyme ID an RevenueCat, um zu prüfen, ob dein Abo aktiv ist, und zu sonst
nichts.

Deine Zahlungsdaten sehen wir nie; die bleiben bei Apple oder Google.

**Plus im Browser.** Im Web-Planer kann man Plus nicht kaufen. Damit ein in
einer Handy-App gekauftes Plus dort gilt, legt jede App, die synchronisiert,
einen eigenen Eintrag in die Cloud, mit der sie synchronisiert: ihre
RevenueCat-App-Nutzer-ID, ob es eine iPhone- oder Android-App ist, ob ihr Store
zuletzt gemeldet hat, dass Plus aktiv ist, und wann sie zuletzt geschrieben hat,
unter einer zufälligen ID für das Gerät. Sie schreibt ihn alle sechs Stunden
neu und wenn Plus beginnt oder endet. Der Web-Planer, angemeldet bei demselben
iCloud- oder Google-Konto, liest diese Einträge, hält sie im Browser und
schickt die ID des neuesten mit jeder Plus-Anfrage an unseren Relay, genau wie die
App es täte. Der Relay prüft diese ID bei RevenueCat wie bei den Apps; der
Browser kontaktiert RevenueCat nicht, erzeugt keine eigene ID für Plus und
schreibt nie einen Plus-Eintrag.

Der Eintrag geht nur in das Konto, mit dem die Synchronisierung zuerst lief,
oder in eines, das du danach unter Einstellungen → Synchronisieren mit wählst:
Nach einer Abmeldung, mit einem anderen Konto oder bei ausgeschalteter
Synchronisierung schreibt die App ihn nicht mehr und kopiert ihn nie von sich
aus in ein zweites Konto. Aus der Cloud gelöscht wird er nicht; der Web-Planer
übergeht einen Eintrag, der 30 Tage nicht geschrieben wurde, und vergisst die
gehaltenen Einträge, wenn du dich abmeldest oder Konto oder Cloud wechselst.

### Update-Hinweise und Bewertungen

Einige Sekunden nach dem Start und erneut nach einem Tag im Hintergrund fragt
die App ihren Store, ob es eine neuere Version gibt. Unter iOS fragt sie Apples
öffentliche App-Store-Abfrage (`itunes.apple.com`) mit der Bundle-ID von Velorki
und den Länder- und Sprachcodes deines Handys; unter Android fragt sie den
In-App-Update-Dienst von Google Play auf dem Handy, der nur für eine
Installation aus Play antwortet. Dabei fällt jeweils deine IP-Adresse an, wie
bei jeder Anfrage im Web, und sonst nichts von dir.

Ab und zu bittet die App das System, sein eigenes Bewertungsfenster zu zeigen.
Ob und wie oft es erscheint, entscheiden Apple oder Google; eine Bewertung oder
Rezension, die du dort abgibst, geht unter deinem Store-Konto an sie, und die
App erfährt nicht, ob oder wie du bewertet hast. Der Web-Planer tut beides
nicht.

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

## Der Web-Planer (app.velorki.com)

app.velorki.com ist dieselbe App in deinem Browser: Sie plant, sucht und führt
eine Bibliothek, zeichnet aber nicht auf und navigiert nicht. Es gibt kein
Konto, keine Analyse und keine Werbung. Auf einem Handy oder Tablet zeigt die
Adresse die Download-Seite der App und lädt sonst nichts.

- **Im Browser gespeichert.** Deine Routen, Fahrten und Einstellungen liegen in
  einer Datenbank im eigenen Speicher des Browsers (IndexedDB oder, in manchen
  Browsern, das Origin Private File System), die heruntergeladenen
  Routing-Kacheln und Suchindizes in seinem Cache Storage, und Einstellungen,
  das Cloud-Konto, bei dem du angemeldet bist, und eine anonyme ID wie die der
  App in seinem lokalen Speicher. Sie bleiben in diesem Browser auf diesem
  Computer, bis du sie im Planer löschst oder die Websitedaten im Browser
  löschst. Dieser Speicher ist das, wofür der Planer da ist, und braucht nach
  § 25 Abs. 2 TTDSG keine Einwilligung.
- **Was er kontaktiert.** Dieselben Dienste wie die App, nach denselben Regeln
  wie oben: Kartenkacheln von OpenFreeMap (und CyclOSM, wenn du es
  einschaltest), Photon für eine Online-Suche, die öffentlichen Wetterdienste
  für die Wetterebenen und unseren Relay für den KI-Assistenten, das Plus-Wetter
  und Teilen-Links. Den Routing-Server nutzt er nie: Routen werden im Browser
  berechnet. Routing-Kacheln kommen über app.velorki.com. Braucht ein Text eine
  Schrift, die den eigenen Schriften der App fehlt, lädt der Browser eine
  Ersatzschrift von Google Fonts (`fonts.gstatic.com`), das deine IP-Adresse
  sieht. Die Cloud-Synchronisierung kontaktiert Apple oder Google, erst wenn du
  eines davon wählst.
- **Cloudflare.** Der Planer wird von Cloudflare Pages ausgeliefert. Zwei kleine
  Funktionen dort beantworten `/tiles/` (sie holen die Kacheln von unserem
  GitHub-Spiegel) und `/cloudkit/upload` (siehe Cloud-Synchronisierung). Wie
  jeder Server sehen sie deine IP-Adresse und die Anfrage; sie speichern nichts,
  und wir führen keine Protokolle darüber.

## Aufbewahrung und Löschung

| Daten | Aufbewahrt | Wie du sie löschst |
|---|---|---|
| Routen, Fahrten, Einstellungen, Offline-Daten | auf deinem Handy, bis du sie löschst | in der App löschen oder die App deinstallieren (bei eingeschalteter Synchronisierung löscht das Löschen einer Route oder Fahrt sie auch in deiner Cloud) |
| Token von Strava / RideWithGPS | auf deinem Handy, so verschlüsselt, dass nur unser Relay sie öffnen kann, bis du trennst; nie bei uns gespeichert | in der App trennen oder deinstallieren |
| Strava-Daten: dein Name, Aktivitätslinks | auf deinem Handy, bis du trennst; nie bei uns gespeichert | Strava in der App trennen oder deinstallieren; Fragen an ride@velorki.com |
| Aus Strava importierte Routen und daraus bearbeitete Routen | auf deinem Handy, nur solange die Route bei Strava noch existiert: alle 48 Stunden erneut geprüft, entfernt, wenn sie dort gelöscht wurde oder 7 Tage lang nicht geprüft werden konnte; nie bei uns gespeichert | in der App löschen, Strava trennen oder deinstallieren |
| Die zwischengespeicherte Liste deiner Strava-Routen | auf deinem Handy, höchstens 48 Stunden | Strava trennen oder deinstallieren |
| Ratenbegrenzungs-Zähler (anonyme Installations-ID, IP-Adresse) | auf unserem Server, für das Zählfenster, höchstens einen Tag | nicht anwendbar |
| Teilen-Links | ein Jahr, dann automatisch gelöscht | in der App löschen |
| Über iCloud abgeglichene Routen, Fahrten und Einstellungen | in deiner eigenen iCloud, bis du sie dort löschst; nie bei uns gespeichert | in den iCloud-Einstellungen auf einem Apple-Gerät löschen |
| Über Google Drive abgeglichene Routen, Fahrten und Einstellungen | im ausgeblendeten Velorki-Ordner deines Drive, bis du ihn löschst; nie bei uns gespeichert | in Google Drive im Web: Einstellungen → Apps verwalten → Velorki → Optionen → Ausgeblendete App-Daten löschen |
| Plus-Einträge (RevenueCat-ID, Plattform, Plus aktiv, zuletzt geschrieben) | in der Cloud, mit der du synchronisierst, bis du dort die Daten der App löschst; vom Web-Planer nach 30 Tagen übergangen | wie bei den abgeglichenen Routen oben |
| Bibliothek, Kacheln und Einstellungen des Web-Planers | in deinem Browser, bis du sie löschst | im Planer löschen oder die Websitedaten im Browser löschen |
| KI-Anfragen | von uns nicht gespeichert, über die oben genannten Protokolle hinaus | entfällt |
| Daten bei RevenueCat | nach der eigenen Erklärung von RevenueCat | schreib uns, und wir geben die Anfrage weiter |
| Support-Chat-Gespräche | in unserem Discord-Kanal, bis wir sie löschen | schreib an ride@velorki.com |

Das Deinstallieren der App entfernt alles, was die App auf dem Gerät
gespeichert hat. Was die Synchronisierung in deine iCloud oder dein Google
Drive gelegt hat, bleibt dort; siehe Cloud-Synchronisierung oben. Es entfernt
keine von dir erstellten Teilen-Links (die laufen
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
| Cloud-Synchronisierung mit iCloud oder Google Drive, solange sie an ist, samt den Plus-Einträgen und dem Upload des Web-Planers über `/cloudkit/upload` | (b) Erfüllung des von dir gewünschten Dienstes; Apple und Google handeln nach deiner eigenen Vereinbarung mit ihnen |
| Der Web-Planer: seine Auslieferung, das Speichern deiner Bibliothek in deinem Browser, das Holen der Kacheln über app.velorki.com | (b) Erfüllung der von dir angeforderten Leistung, und (f) für die IP-Adresse und die Anfrage, die zur Antwort nötig sind |
| Update-Hinweise | (f) berechtigtes Interesse daran, dich auf eine neuere Version hinzuweisen; gesendet werden nur die Bundle-ID, das Land und die Sprache |
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
  velorki.com und api.velorki.com sowie das Hosting des Web-Planers unter
  app.velorki.com mit seinen Funktionen `/tiles/` und `/cloudkit/upload`.
  IP-Adressen und Metadaten der Anfragen, und der iCloud-Upload, den es
  ungelesen weiterreicht.
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
- **Apple Inc.** (iCloud) — die Routen, Fahrten, Einstellungen und
  Plus-Einträge der iCloud-Synchronisierung, in deiner eigenen iCloud und nur,
  solange du mit iCloud synchronisierst. Wir erhalten sie nicht; Apple handelt
  nach deiner eigenen iCloud-Vereinbarung mit Apple.
- **Google Ireland Ltd**, Dublin (Google LLC, USA, außerhalb des EWR und der
  Schweiz) — die Routen, Fahrten, Einstellungen und Plus-Einträge der
  Synchronisierung mit Google, im ausgeblendeten App-Ordner deines eigenen
  Drive und nur, solange du mit Google synchronisierst. Wir erhalten sie nicht;
  Google handelt nach deiner eigenen Vereinbarung mit Google. Google liefert
  außerdem die Ersatzschriften des Web-Planers (`fonts.gstatic.com`) und unter
  Android die Update-Prüfung von Google Play.
- **GitHub, Inc.**, San Francisco, USA — unser Kachel-Spiegel, von dem die App
  Routing-Kacheln und Suchindizes herunterlädt; die Namen der Kacheln und deine
  IP-Adresse.
- **Apple Inc.** und **Google Ireland Ltd** — der Verkauf von Velorki Plus, die
  Update-Prüfung und das Bewertungsfenster. Sie sind die Verkäufer; deine
  Zahlungsdaten sehen wir nie.
- **Strava, Inc.** und **Ride with GPS** — erst nachdem du das Konto verbunden
  hast, und nur für eine von dir ausgelöste Übertragung. Was dort damit
  geschieht, richtet sich nach deren eigenen Erklärungen.

Außerdem geben wir Daten heraus, wo ein Gericht oder eine Behörde es nach dem
Gesetz verlangt.

## Übermittlungen außerhalb der EU

Cloudflare, RevenueCat, OpenRouter und der Modellanbieter dahinter, Discord,
Klipy, Strava, Ride with GPS, GitHub, Apple und Google sitzen in den USA oder
übermitteln dorthin. Diese Übermittlungen stützen sich auf die
Standardvertragsklauseln der Europäischen Kommission oder, wo der Anbieter
zertifiziert ist, auf das EU-US Data Privacy Framework, zusammen mit den
technischen Maßnahmen des Anbieters. Hetzner, komoot und die Kartendienste, auf
die wir uns stützen, liegen in der EU, OpenStreetMap im Vereinigten Königreich.
Alles, was die App für dich speichert, bleibt auf deinem Handy oder in deinem
Browser und wird nirgendwohin übermittelt, außer du schaltest die
Synchronisierung ein, die in deine eigene iCloud oder dein Google Drive geht.

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
meiste davon kannst du selbst wahrnehmen, weil die Daten auf deinem Handy, in
deinem Browser oder in deiner eigenen Cloud liegen und sich jederzeit als GPX-,
FIT- oder TCX-Datei exportieren lassen.

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

Änderungen an dieser Erklärung werden auf dieser Seite veröffentlicht, mit
geändertem Datum oben; wesentliche Änderungen werden zusätzlich auf der Website
angekündigt. Alte Fassungen bleiben in der Git-Historie des Repositorys.

## Kontakt

Orkitec, ride@velorki.com; Postanschrift im [Impressum](./imprint). Für
Sicherheitsmeldungen siehe
[SECURITY.md](https://github.com/orkitec/velorki/blob/main/SECURITY.md) im
Quellcode-Repository.
