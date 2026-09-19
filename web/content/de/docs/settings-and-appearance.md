---
title: Einstellungen und Darstellung
description: Jede Einstellung in Velorki, von Design, Akzent und Einheiten über Navigation, Aufnahme, Sensoren und Suche bis zu Offline-Daten, Verbindungen und Server-URLs.
order: 14
---

Der Tab Einstellungen ist eine einzige scrollende Seite mit einem Abschnitt je Thema. Diese Seite geht ihn von oben nach unten durch, damit du den gesuchten Schalter findest und weißt, was er tut.

## Darstellung

**Design**: **System**, **Hell** oder **Dunkel**. System folgt dem Handy.

**Karte**: wie die Karte selbst gezeichnet wird, unabhängig vom Design der App: **Folgt dem Design**, **Hell**, **Nacht** oder **Schwarz**. **Schwarz** ist das für eine Fahrt im Dunkeln mit gedimmtem Display, und Energiesparen erzwingt es ohnehin.

**Rad-Overlay auf dunklen Karten**: was mit dem CyclOSM-Overlay geschehen soll, wenn die Karte darunter dunkel ist: **Invertiert**, **Gedimmt** oder **Unverändert**. Das Overlay ist für einen hellen Untergrund gezeichnet, auf einer Nachtkarte braucht es also Hilfe. Diese Zeile erscheint nur in Builds, die das Overlay mitbringen.

**Akzent**: vier Farbvoreinstellungen: **Volt**, **Glut**, **Gletscher** und **Beere**. Der Akzent färbt die Schaltflächen, die Diagramme und die Routenlinie auf der Karte.

**Einheiten**: **Metrisch** oder **Imperial**, verwendet von jeder Zahl, jedem Schieberegler, jeder Diagrammachse, dem Abbiegeband und jeder Sprachansage in der App. Bis du wählst, folgt Velorki dem Land des Handys.

## Navigation

Die drei Schalter hier sind dieselben wie in der Übersicht des Tabs Aufnahme.

**Abbiegehinweise**: "Nächste Abbiegung während der Aufnahme auf einer Route zeigen". Der Hauptschalter; der Rest des Abschnitts ist ausgegraut, solange er aus ist.

**Stimme**: "Abbiegehinweise laut ansagen".

**Sprechstimme**: welche Stimme sie sagt. Öffnet die Stimmenliste, beschrieben unter [Navigation mit Abbiegehinweisen](./navigation).

**Abbiegehinweise ansagen** ist ein Schieberegler in Sekunden. Der Hinweis lautet "12 Sekunden vor der Abbiegung bei deinem Tempo, nie näher als 50 Meter". In Sekunden zu zählen heißt, dass die Ansage im selben Moment kommt, ob du steigst oder fällst.

**Abseits der Route neu berechnen**: "Nach dem Verlassen der Route einen Weg zurück planen". Aus heißt, dass du weiterhin erfährst, dass du daneben bist, aber nichts neu berechnet wird.

## Aufnahme

**GPS-Genauigkeit**: **Energiesparen**, **Normal** oder **Genau**, mit dem Hinweis "Genau für Trails, Normal reicht für Straßen". Es entscheidet, wie hart der eine GPS-Client während einer Fahrt gefordert wird.

**Energiesparen**: "Dunkle Karte, keine Animationen, nach 30 s eine schlichte Seite mit den Zahlen; der Bildschirm zieht den Akku leer". Das ganze Verhalten steht unter [Fahrt aufzeichnen](./recording-a-ride).

## Sensoren

**Apple Health**, unter Android **Health Connect**: "Herzfrequenz von deiner Uhr oder jeder App, die sie schreibt; Fahrten werden als Trainings gespeichert". Das Einschalten ist es, was das Handy um Zugriff auf deine Gesundheitsdaten bittet; lehnst du ab, bleibt der Schalter aus.

**Fahrten in Health speichern**: schreibt jede beendete Fahrt als Radfahr-Training in den Speicher. Der Schalter lässt sich einzeln ausschalten und tut nichts, solange der darüber aus ist.

**Apple Watch**: "Herzfrequenz von der Uhr, die Fahrt steuerst du am Handgelenk". Die Zeile gibt es nur auf einem iPhone, mit dem eine Uhr gekoppelt ist.

**Bluetooth-Sensoren**: "Brustgurte, Geschwindigkeits- und Trittfrequenzsensoren, Leistungsmesser", oder wie viele Sensoren gekoppelt sind. Dahinter liegt der Bildschirm, auf dem **Scannen** sie sucht. Alles davon steht ausführlich unter [Sensoren und deine Uhr](./sensors-and-watch).

## Abo

**Velorki Plus** mit **Aktiv** oder **Nicht aktiv** darunter, und dem Verlängerungs- oder Enddatum, wo es eines gibt. Ein Tipper darauf öffnet die Abo-Seite. Darunter sitzen **Verwalten**, was die Abo-Seite des Stores öffnet, und **Käufe wiederherstellen**. Siehe [Velorki Plus](./velorki-plus).

## Verbindungen

Je eine Zeile für **Strava** und für **Ride with GPS**, die entweder **Nicht verbunden**, nach dem Verbinden deinen Namen, oder **In diesem Build nicht verfügbar** zeigt. **Verbinden mit Strava** und **Mit Ride with GPS verbinden** stehen unter den nicht verbundenen, **Trennen** neben den verbundenen. Siehe [Strava und Ride with GPS](./strava-and-ridewithgps).

## KI-Assistent

**Was gesendet wird** sagt immer, welche Zustimmung du gegeben hast: "Noch nicht gefragt.", "Nichts. Der Assistent ist aus.", "Nur dein Text." oder "Dein Text und deine grobe Position (etwa 1 km)." **Ändern** daneben öffnet den Zustimmungsdialog erneut.

**KI-Antwort melden**: "Melde eine Antwort, die falsch oder unpassend war." Öffnet eine Mail an uns.

## Erweitert

**Offline-Daten**: "Karten und Routing-Daten für Fahrten ohne Empfang". Hat der Mirror Kacheln neu gebaut, die du besitzt, wird der Untertitel orange und zählt sie. Siehe [Offline-Karten und Routing](./offline-maps-and-routing).

**Suche**: "Was die Offline-Suche zeigt und in welcher Reihenfolge. Zum Ändern der Priorität ziehen." Siehe [Suche](./search).

**Routing**, also wo Routen berechnet werden:

- **Automatisch**: "Auf diesem Gerät überall dort, wo die Kacheln heruntergeladen sind, sonst auf dem Routing-Server." Das ist die vernünftige Voreinstellung.
- **Nur auf dem Gerät**: "Nie den Routing-Server fragen. Routen außerhalb der heruntergeladenen Kacheln bieten stattdessen den Download an."
- **Nur Server**: "Immer den Routing-Server fragen, auch wo Kacheln heruntergeladen sind."

**Server-URLs**: drei Felder, **BRouter-URL**, **Photon-URL** und **API-URL**, um diese Installation auf eigene Server zu richten: "Feld leer lassen, um die mitgelieferte Adresse zu nutzen." **Auf Standard zurücksetzen** leert alle drei. Die meisten rühren das nie an; es gibt das, weil Velorki Open Source ist und du eigene Server betreiben darfst.

## Über

- **Velorki**, mit der Versionsnummer.
- **© OpenStreetMap contributors**.
- **Open-Source-Lizenzen**: "Die Software und die Kartendaten, auf denen Velorki aufbaut."
- **Datenschutzerklärung** und **Nutzungsbedingungen**, die im Browser aufgehen.
- **Problem melden**: "Issue auf GitHub öffnen."

## Weiterlesen

- [Erste Schritte](./getting-started)
- [Navigation mit Abbiegehinweisen](./navigation)
- [Fahrt aufzeichnen](./recording-a-ride)
- [Sensoren und deine Uhr](./sensors-and-watch)
- [Offline-Karten und Routing](./offline-maps-and-routing)
- [Datenschutz auf dem Handy](./privacy-on-the-phone)
