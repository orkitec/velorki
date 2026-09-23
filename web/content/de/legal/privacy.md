---
title: Datenschutzerklärung
description: "Was Velorki mit deinen Daten macht: kein Konto, Routen und Fahrten bleiben auf dem Handy, und eine Liste dessen, was das Gerät wann verlässt."
draft: true
---

> **Hinweis zur Übersetzung.** Dies ist eine Übersetzung der englischen
> Fassung. Bei Abweichungen gilt die englische Fassung.

> **Dies ist ein Entwurf.** Er beschreibt, was die App tun soll. Er wurde nicht
> von einer Anwältin oder einem Anwalt geprüft, und das muss geschehen, bevor
> er als Datenschutzerklärung einer veröffentlichten App erscheint. Einige
> Punkte unten sind noch mit "noch zu entscheiden" gekennzeichnet.

Gültig ab: wird zum Start festgelegt.

Velorki ist eine App zum Planen von Radrouten und zum Aufzeichnen von Fahrten,
gemacht von Orkitec. Diese Seite erklärt, was mit deinen Daten geschieht.

## Die kurze Fassung

- Es gibt **kein Konto**. Du registrierst dich nicht, und wir wissen nicht, wer
  du bist.
- Deine Routen, deine Fahrten und deine Einstellungen bleiben **auf deinem
  Handy**.
- Manches braucht einen Server: Kartenkacheln, Routing außerhalb der
  heruntergeladenen Gebiete, die Suche, wenn du sie anforderst, und, falls du
  sie nutzt, der KI-Assistent, die Verbindungen zu Strava und RideWithGPS und
  die Teilen-Links. Jedes davon ist unten beschrieben.
- Wir verkaufen deine Daten nicht, und wir nutzen sie nicht für Werbung oder
  Profilbildung.

## Was auf deinem Gerät bleibt

Geplante Routen, aufgezeichnete Fahrten, ihre GPS-Tracks, deine Einstellungen,
heruntergeladene Offline-Kartenregionen, heruntergeladene Routing-Kacheln und
die Ortssuch-Indizes, die mit ihnen kommen, liegen im eigenen Speicher der App
auf deinem Handy. Sie gehen nirgendwohin hoch, außer du forderst es an.

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
Android), in einer verschlüsselten Form, die nur unser Relay öffnen kann; siehe
den Abschnitt zu Strava und RideWithGPS unten.

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

### Kartenkacheln

Die Karte wird aus Kacheln gezeichnet, die von OpenFreeMap geholt werden, und
von CyclOSM, wenn du das Rad-Overlay einschaltest. Eine Kachel zu holen verrät
dem Kachelanbieter, welchen Teil der Karte du ansiehst, und umfasst deine
IP-Adresse, wie jede Anfrage im Web. Kartendaten © OpenStreetMap contributors.

### Strava und RideWithGPS (Velorki Plus)

An Strava oder RideWithGPS geht nichts, außer du verbindest das Konto selbst
und löst dann eine Aktion aus: eine Fahrt hochladen, eine Route importieren.

Beim Verbinden übergibt die App einen Einmalcode an unseren Relay-Server, der
ihn unter Zugabe unseres Anwendungsgeheimnisses gegen einen Zugriffstoken
tauscht, den Token mit einem Schlüssel verschlüsselt, den nur der Relay hat,
und ihn in dieser Form an die App zurückgibt. Dein Handy speichert den
verschlüsselten Token; es kann ihn allein nicht verwenden, und wir speichern
ihn gar nicht.

Danach läuft jeder Upload, jede Routenübertragung, jeder Import und jedes
Trennen, das du auslöst, über den Relay: Er prüft, dass dein Abo aktiv ist,
entschlüsselt den Token für diese eine Anfrage, leitet die Anfrage an Strava
oder RideWithGPS weiter und gibt die Antwort an die App zurück. Er behält weder
die Datei noch den Token und nichts von der Antwort, und er wendet dieselbe
Ratenbegrenzung an wie bei jedem anderen Aufruf des Relays (siehe
Server-Protokolle unten). Seine Protokolle enthalten nie den Token, den Inhalt
der Anfrage oder die Abonnenten-ID.

Was Strava oder RideWithGPS dann mit den Daten machen, die du ihnen schickst,
richtet sich nach deren eigenen Datenschutzerklärungen.

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
- bei einer Routenbeschreibung eine kurze Zusammenfassung der Route (Distanz,
  Anstieg, Belagsanteile).

In die Anfrage kommt keine Kennung von dir oder deinem Handy. Das Modell
liefert eine strukturierte Anfrage zurück: eine Distanz, eine Form, Ortsnamen,
Vorlieben. Das eigentliche Routing geschieht danach in der App; das Modell
sieht deine Route nie.

Unser KI-Anbieter ist **OpenAI (oder der vom Betreiber konfigurierte
Anbieter)**. Der Assistent läuft auf einem gehosteten Modell, das unser Relay
über eine OpenAI-kompatible Schnittstelle erreicht: Der offizielle
Velorki-Build schickt Anfragen an OpenAI, und wer Velorki selbst betreibt, kann
den Relay auf einen anderen Anbieter oder auf ein eigenes Modell richten; dann
gilt die Erklärung dieses Betreibers. Wir erlauben dem Anbieter nicht, Modelle
mit diesen Daten zu trainieren, wo das als Option angeboten wird. Die
Rechtsordnung des Anbieters ist **vor der Veröffentlichung einzutragen**,
zusammen mit der Rechtsgrundlage für die Übermittlung.

Daten von Strava gehen nie an den KI-Anbieter.

### Teilen-Links (Velorki Plus)

Erstellst du einen Teilen-Link für eine Route oder eine Fahrt, wird diese Route
oder Fahrt mit ihrem Track, ihrem Namen und ihren Statistiken auf unseren
Server hochgeladen und dort gespeichert, damit jeder mit dem Link sie öffnen
kann. Der Link ist öffentlich: Wer ihn hat, kann den Inhalt sehen, samt Start-
und Endpunkt des Tracks. Bedenke das, bevor du eine Fahrt teilst, die an deinem
Zuhause beginnt.

Ein geteilter Eintrag wird **ein Jahr** lang aufbewahrt und dann automatisch
gelöscht. Damit er früher verschwindet, schick den Link an die unten genannte
Kontaktadresse, und wir löschen ihn. Das Ansehen eines geteilten Links braucht
kein Konto.

### Abos

Velorki Plus wird über den App Store und Google Play verkauft und in unserem
Auftrag von RevenueCat abgewickelt. RevenueCat weist deiner Installation eine
**anonyme App-Nutzer-ID** zu, eine zufällige Zeichenfolge, die weder mit einem
Namen noch mit einer E-Mail-Adresse noch mit einer Gerätekennung verknüpft ist.
RevenueCat erhält außerdem den Kaufbeleg vom Store. Unser Relay schickt diese
anonyme ID an RevenueCat, um zu prüfen, ob dein Abo aktiv ist, und zu sonst
nichts.

Deine Zahlungsdaten sehen wir nie; die bleiben bei Apple oder Google.

### Absturzberichte

**Noch zu entscheiden.** Zum jetzigen Zeitpunkt ist kein SDK für
Absturzberichte oder Analysen enthalten. Kommt eines dazu, wird dieser
Abschnitt es beim Namen nennen und sagen, was es erhebt, bevor die Funktion
ausgeliefert wird.

### Server-Protokolle

Unser Routing-Server und unser Relay führen Betriebsprotokolle (Zeitpunkt der
Anfrage, Endpunkt, Status, IP-Adresse und einen Header mit der Client-Version),
um den Dienst zu betreiben und Ratenbegrenzungen durchzusetzen. Die
Aufbewahrungsdauer dieser Protokolle ist **noch zu entscheiden**. Sie werden
nicht dazu genutzt, Profile von Nutzenden zu bilden.

## Aufbewahrung und Löschung

| Daten | Aufbewahrt | Wie du sie löschst |
|---|---|---|
| Routen, Fahrten, Einstellungen, Offline-Daten | auf deinem Handy, bis du sie löschst | in der App löschen oder die App deinstallieren |
| Token von Strava / RideWithGPS | auf deinem Handy, so verschlüsselt, dass nur unser Relay sie öffnen kann, bis du trennst; nie bei uns gespeichert | in der App trennen oder deinstallieren |
| Teilen-Links | ein Jahr, dann automatisch gelöscht | in der App löschen |
| KI-Anfragen | von uns nicht gespeichert, über die oben genannten Protokolle hinaus | entfällt |
| Daten bei RevenueCat | nach der eigenen Erklärung von RevenueCat | schreib uns, und wir geben die Anfrage weiter |

Das Deinstallieren der App entfernt alles, was die App auf dem Gerät
gespeichert hat. Es entfernt keine von dir erstellten Teilen-Links (die laufen
nach einem Jahr ab oder auf Anfrage), und es entfernt nichts, was du zu Strava
oder RideWithGPS hochgeladen hast.

## Deine Rechte

Wenn du in der EU oder im Vereinigten Königreich bist, gibt dir die DSGVO das
Recht, deine personenbezogenen Daten einzusehen, zu berichtigen und zu löschen,
ihre Verarbeitung einzuschränken oder ihr zu widersprechen und sie in einem
übertragbaren Format zu erhalten. Das meiste davon kannst du selbst wahrnehmen,
weil die Daten auf deinem Handy liegen und sich jederzeit als GPX-, FIT-
oder TCX-Datei exportieren lassen.

Für alles, was auf unserer Seite liegt (Teilen-Links, Protokolleinträge, der
Datensatz bei RevenueCat), schreib an **ride@velorki.com**. Wir brauchen genug
Angaben, um die Daten zu finden, was bei Teilen-Links den Link selbst bedeutet,
da wir kein Konto haben, über das wir dich nachschlagen könnten. Du hast
außerdem das Recht, dich bei deiner Datenschutzaufsichtsbehörde zu beschweren.

Verantwortlich ist Orkitec. Postanschrift und eine etwaige
Datenschutzvertretung: **vor der Veröffentlichung einzutragen.**

## Kinder

Velorki richtet sich nicht an Kinder und erhebt wissentlich keine Daten von
ihnen. Die App hat keine sozialen Funktionen, keine Nachrichten zwischen
Nutzenden und keine Werbung.

## Änderungen

Ändert sich diese Erklärung so, dass es betrifft, was dein Gerät verlässt,
sagt die App es dir beim nächsten Öffnen, und das Datum oben ändert sich. Alte
Fassungen bleiben in der Git-Historie des Repositorys.

## Kontakt

Orkitec, ride@velorki.com. Für Sicherheitsmeldungen siehe
[SECURITY.md](https://github.com/orkitec/velorki/blob/main/SECURITY.md) im
Quellcode-Repository.
