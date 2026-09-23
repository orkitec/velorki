---
title: Offline-Karten und Routing
description: Lade die Karte, die du siehst, und die Routing-Daten, aus denen Routen entstehen, damit Planen, Suche und Navigation auch ohne Empfang laufen.
order: 5
---

Zwei getrennte Downloads machen Velorki ohne Verbindung nutzbar: die **Karte**, die du siehst, und die **Routing-Daten**, aus denen Routen und die Offline-Suche berechnet werden. Lade beides für dein Fahrgebiet herunter, bevor du dorthin fährst, wo der Empfang aufhört.

## Die zwei Arten

| | Karte | Routing-Daten |
|---|---|---|
| Heißt in der App | **Karte** | **Routing-Daten** |
| Was es ist | Vektorkacheln von OpenFreeMap, gezeichnet aus OpenStreetMap | BRouter-Kacheln vom Velorki-Mirror, gebaut aus OpenStreetMap |
| Deckt ab | genau das Rechteck, das du auf dem Bildschirm hattest | ein festes 5° × 5° großes Quadrat der Welt |
| Größe | einige zehn Megabyte für eine Stadt | oft 125 bis 250 MB pro Kachel |
| Ohne sie | graue Flächen dort, wo die Karte nicht zwischengespeichert ist | kein Routing und keine Offline-Suche in diesem Gebiet |

Die Routing-Daten tragen auch den Ortsindex, ein heruntergeladenes Gebiet sucht also ebenfalls offline. Deshalb steht auf dem Bildschirm mit den Routing-Kacheln "Eine heruntergeladene Region bringt auch die Ortssuche ohne Empfang." Dieselbe heruntergeladene Region gibt einer aufgezeichneten Fahrt auch ihren Belag, siehe [die Bibliothek](./library).

## Ein Gebiet herunterladen

1. Verschiebe im Tab **Planen** die Karte so, dass das gewünschte Gebiet den Bildschirm ausfüllt. Zoom nicht weiter heraus als nötig: Der Kartendownload folgt genau dem, was auf dem Bildschirm zu sehen ist.
2. Tippe in der Spalte rechts neben der Karte auf **Offline-Daten**. Auf einem kleinen Bildschirm wie dem iPhone SE hat die Spalte dafür keinen Platz: Tippe dort unten in den Ergebnissen des Suchfelds auf **Gebiet herunterladen, um offline zu suchen** oder auf die Download-Schaltfläche unter einer Route, der Kacheln fehlen, und verwalte, was du hast, unter **Einstellungen → Offline-Daten**.
3. Lies die beiden Karten und tippe unten auf **Sichtbares Gebiet herunterladen**.
4. Der Dialog **Sichtbares Gebiet herunterladen** listet auf, was du gleich holst: "Karte des sichtbaren Gebiets · Größe erst nach dem Download bekannt" für die Karte, dann eine Zeile je Routing-Kachel mit ihrer Größe, zum Beispiel `E5_N45 · 187 MB`, oder "Routing-Daten für dieses Gebiet sind schon auf dem Gerät".
5. Tippe auf **Herunterladen**.

Beide Downloads laufen, solange die App offen ist. Die Karten zeigen **Karte wird heruntergeladen…** und **E5_N45 wird heruntergeladen…** mit Fortschrittsbalken.

Der Bildschirm warnt aus gutem Grund: "Kacheln sind groß, oft 125–250 MB pro Stück, und Velorki kann Wi-Fi nicht von mobilen Daten unterscheiden. Starte einen Download am besten im Wi-Fi."

Du erreichst diesen Bildschirm auch über **Einstellungen → Offline-Daten**, aber so geöffnet liegt keine Karte dahinter, die Download-Schaltfläche ist also gesperrt und der Hinweis lautet "Öffne diesen Bildschirm von der Karte aus, um das sichtbare Gebiet herunterzuladen."

## Die Kartengebiete verwalten

**Verwalten** auf der Karte **Karte** öffnet **Offline-Karten**, eine Zeile je heruntergeladenem Gebiet:

- Den Namen, den Velorki vergeben hat, **Kartengebiet 1**, **Kartengebiet 2** und so weiter.
- Größe und Datum, "12,3 MB · Heruntergeladen 14. Sept. 2026".
- **Aktualisierung verfügbar** in Orange, sobald das Gebiet älter als zwei Monate ist, und daneben eine Schaltfläche **Aktualisieren**. Eine Aktualisierung ist ein vollständiger neuer Download.
- Eine Schaltfläche **Löschen**, die fragt "Offline-Gebiet löschen?" mit "Die heruntergeladenen Kacheln werden von diesem Gerät entfernt."

Die Karte auf dem Offline-Bildschirm fasst dasselbe zusammen: "3 Gebiete, 48 MB" und "2 Gebiete sind älter als zwei Monate und können aktualisiert werden".

## Die Routing-Kacheln verwalten

**Verwalten** auf der Karte **Routing-Daten** öffnet **Offline-Routing-Daten**. Jede Zeile ist eine 5° × 5° große Kachel mit Name, Größe und Zustand:

| Zustand | Bedeutet |
|---|---|
| **Auf diesem Gerät** | bereit, Routing und Offline-Suche funktionieren hier |
| **Update verfügbar** | der Mirror hat diese Kachel neu gebaut; **Aktualisieren** lädt sie neu |
| **Update braucht ein neueres Velorki** | die neu gebaute Kachel hat ein Datenformat, das diese App-Version nicht lesen kann |
| **Wird heruntergeladen…** | läuft gerade |
| **Nicht heruntergeladen** | dem Mirror bekannt, nicht auf dem Handy |

Ebenfalls auf dem Bildschirm:

- **Für diese Route nötig** erscheint, wenn du über das Kachel-Banner aus dem Planer kommst, mit den für diese Route nötigen Kacheln bereits ausgewählt und einer Schaltfläche, die sie zählt, zum Beispiel **1 Kachel herunterladen (187 MB)**.
- **Für das sichtbare Gebiet herunterladen** ganz unten, mit der Summe über alles, was du hast: "3 Kacheln, 540 MB".
- **Mirror-Stand 1. Sept. 2026** unter jeder Zeile, also das Datum, an dem der Mirror diese Kachel zuletzt erzeugt hat.
- Eine Schaltfläche **Löschen** in jeder Zeile, mit der Warnung "Die Kachel wird von diesem Gerät entfernt. Routen in diesem Gebiet brauchen dann wieder den Routing-Server."
- Eine Schaltfläche **Download abbrechen** im Fortschrittskopf, solange einer läuft.

Velorki prüft wöchentlich, ob der Mirror etwas neu gebaut hat, was du besitzt. Ist das der Fall, wird die Zeile **Offline-Daten** in den Einstellungen orange, zeigt "Für 2 Kacheln gibt es Updates" und setzt eine Zahl an den Pfeil.

## Das Ortsverzeichnis, also der Suchindex

Zu jeder Routing-Kachel, die der Mirror veröffentlicht, liegt ein kleiner Suchindex daneben, und Velorki lädt beide zusammen herunter. Nichts davon ist als eigene Einstellung oder eigener Download sichtbar.

Schlägt der Download des Index fehl, ist die Kachel selbst trotzdem in Ordnung: Das Gebiet bleibt routingfähig und seine Suche geht einfach online. Dasselbe gilt für einen Index in einem Format, das diese App-Version nicht liest; er wird übersprungen, die anderen Gebiete antworten weiter offline, und dieses Gebiet sucht online.

## Wo alles liegt und wie du es wieder loswirst

Alles liegt im eigenen Speicher der App auf dem Handy, nicht in deinen Dokumenten oder deiner Fotomediathek, und nichts wird in eine Cloud-Sicherung kopiert.

Um Platz zu schaffen:

- lösche einzelne Kartengebiete unter **Offline-Karten**,
- lösche einzelne Routing-Kacheln unter **Offline-Routing-Daten**,
- oder deinstalliere die App, was alles davon entfernt, zusammen mit deinen Routen und Fahrten. Exportiere vorher, was du behalten willst, siehe [Import und Export](./import-and-export).

## "Erst Velorki aktualisieren"

Routing-Kacheln ändern gelegentlich ihr Format. Bietet der Mirror eine Kachel an, die diese App-Version nicht lesen kann, sagt Velorki das, statt Unsinn herunterzuladen: **Erst Velorki aktualisieren**, "Diese Kacheln haben das Datenformat 5, dieses Velorki liest bis 4. Sie brauchen ein neueres Velorki; lade sie herunter, sobald du aktualisiert hast." Antworte **Jetzt nicht** oder **Store öffnen**, um die App zu aktualisieren.

Kacheln, die du schon hast, funktionieren weiter.

## Weiterlesen

- [Suche](./search)
- [Route planen](./planning-a-route)
- [Navigation mit Abbiegehinweisen](./navigation)
- [Fehlerbehebung](./troubleshooting)
