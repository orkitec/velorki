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

**Split-Länge**: **Automatisch**, **1 km**, **5 km** oder **10 km**, bei imperialen Einheiten in Meilen, mit dem Hinweis "Automatisch hält die Tabelle kurz: Splits von 1 km bis 30 km, 5 km bis 150 km, darüber 10 km". Es bestimmt die Zeilen der Split-Tabelle einer gespeicherten Fahrt.

**Energiesparen**: "Dunkle Karte, keine Animationen, nach 30 s eine schlichte Seite mit den Zahlen; der Bildschirm zieht den Akku leer". Das ganze Verhalten steht unter [Fahrt aufzeichnen](./recording-a-ride).

## Fahrer

Drei Schalter, alle standardmäßig aus, und die Felder, die sie brauchen.

**Kalorien schätzen** setzt eine Zahl **Kalorien** auf jede Fahrtenseite: aus deinem Leistungsmesser, wenn du einen hast, sonst aus deinem Puls, sonst aus deinem Tempo. Es braucht dein Gewicht; die Schätzung aus dem Puls braucht außerdem dein Geburtsjahr und dein Geschlecht.

**Pulszonen** setzt die Zeit in fünf Zonen deines Maximalpulses unter das Herzfrequenz-Diagramm einer Fahrt. Es braucht deinen Maximalpuls oder dein Geburtsjahr, um ihn als 220 minus dein Alter zu schätzen.

**Leistung schätzen** setzt eine Zahl **Gesch. Leistung** auf Fahrten, die ohne Leistungsmesser aufgezeichnet wurden: aus deinem Tempo, der Steigung und deinem Gewicht. Brauchbar auf langen Anstiegen, schlecht bei Wind oder in der Gruppe, und nie live: nur auf gespeicherten Fahrten.

**Leistungszonen** setzt die Zeit in sieben Zonen deiner Schwellenleistung und die **Intensität** der Fahrt auf Fahrten mit Leistungsmesser. Es braucht deine Schwellenleistung, das Meiste, was du etwa eine Stunde halten kannst.

Ist einer der Schalter an, erscheinen die Felder: **Gewicht** (kg, bei imperialen Einheiten lb: "Kilogramm oder Pfund folgen Einstellungen → Einheiten, die von deinem Land ausgehen"), **Geburtsjahr**, **Geschlecht** (**Keine Angabe**, **Weiblich**, **Männlich**) und **Maximalpuls** (bpm, "Bleibt es leer, gilt 220 minus dein Alter"). Ist **Leistung schätzen** an, folgen zwei weitere: **Gewicht des Rads** (kg oder lb, 9 kg, bis du es änderst) und **Rad** (**Rennrad**, **Trekking, Gravel**, **MTB**), das den Luft- und Rollwiderstand festlegt, den die Schätzung annimmt. **Leistungszonen** allein fragt nach nichts davon; ist es an, folgt nach den Rad-Feldern ein Feld **Schwellenleistung** (W, 50 bis 600), mit der Zeile "Die höchste Leistung, die du etwa eine Stunde halten kannst. Aus einem 20-Minuten-Test nimm 95 % des Schnitts. Bestimmt die Zonen und die Intensität". Alles hier bleibt auf dem Handy; siehe [Datenschutz auf dem Handy](./privacy-on-the-phone). Die Zahlen selbst sind unter [Bibliothek](./library) beschrieben.

## Sensoren

**Apple Health**, unter Android **Health Connect**: "Liest den Puls, den andere Apps in Health ablegen, etwa das Training der Uhr. Wird alle paar Sekunden abgefragt, hinkt also nach; ein Gurt oder die Velorki-Uhren-App übernimmt, sobald sie melden". Das Einschalten ist es, was das Handy um Zugriff auf deine Gesundheitsdaten bittet; lehnst du ab, bleibt der Schalter aus.

**Fahrten in Health speichern**: "Jede beendete Fahrt landet in Health als ein Radfahr-Training mit Start, Ende und Distanz". Der Schalter lässt sich einzeln ausschalten und tut nichts, solange der darüber aus ist.

**Apple Watch**: "Velorkis eigene Uhren-App: misst deinen Puls die ganze Fahrt live, zeigt die Fahrt und hat Start, Pause und Ende am Handgelenk. Kostet Akku der Uhr". Die Zeile gibt es nur auf einem iPhone, mit dem eine Uhr gekoppelt ist. Einschalten fragt einmal, ob Velorki Mitteilungen zeigen darf, für den Hinweis "Ride started from your watch". Darunter **Sensor in Pausen ruhen lassen**: "Die Uhr hört in jeder Pause auf zu messen, und das Handy weckt sie, wenn du weiterfährst. Spart Akku der Uhr bei Fahrten mit vielen Stopps; der erste Puls nach jedem Stopp braucht einen Moment, und schlägt das Wecken fehl, fehlt der Puls, bis das Handy es nach 45 Sekunden erneut versucht". Ausgeschaltet misst die Uhr durch eine Pause hindurch weiter, genau das hält sie wach für das Weiterfahren, und der Puls läuft sofort weiter, wenn du weiterfährst.

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
