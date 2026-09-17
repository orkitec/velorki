---
title: Strava und Ride with GPS
description: Dein Strava- oder Ride-with-GPS-Konto verbinden, Fahrten hochladen und Routen importieren, und warum eine Route an Strava eine Datei ist.
order: 11
---

Velorki kann in deinem Namen mit Strava und mit Ride with GPS sprechen: eine aufgezeichnete Fahrt hochladen und deine Routen aus diesen Konten in die Bibliothek holen. Einen der beiden Dienste zu verbinden gehört zu [Velorki Plus](./velorki-plus); GPX- und FIT-Dateien bleiben kostenlos und erledigen dieselbe Aufgabe von Hand.

An keinen der beiden Dienste geht etwas, bevor du das Konto selbst verbunden und dann etwas angefordert hast.

## Ein Konto verbinden

1. Öffne die **Einstellungen** und such den Abschnitt **Verbindungen**.
2. Tippe auf **Verbinden mit Strava** oder **Mit Ride with GPS verbinden**.
3. Die Anmeldeseite des Dienstes öffnet sich im Browser. Melde dich dort an und bestätige den Zugriff.
4. Du kommst zurück zu Velorki, und in der Zeile steht dein Name statt **Nicht verbunden**.

Dein Handy bewahrt den Zugriffstoken im sicheren Speicher des Handys auf, und von da an spricht es **direkt** mit Strava und Ride with GPS. Deine Fahrten und Routen laufen über keinen Velorki-Server.

Scheitert ein Verbindungsversuch, sagt Velorki "Verbindung fehlgeschlagen:" mit dem Grund. Brichst du die Anmeldeseite ab, sagt es gar nichts.

Eine Zeile mit **In diesem Build nicht verfügbar** heißt, dass dieser Velorki-Build ohne die Schlüssel dieses Dienstes gebaut wurde, was bei einer selbst gebauten Kopie so ist, bis du eigene hinterlegst.

## Trennen

Tippe in der verbundenen Zeile auf **Trennen**. Velorki fragt "Strava trennen?" und erklärt: "Velorki vergisst den Zugriffstoken. Routen und Fahrten in der Bibliothek bleiben erhalten."

Das Trennen entfernt nichts bei Strava oder Ride with GPS und nichts aus deiner Bibliothek.

## Eine Fahrt hochladen

1. Öffne die Fahrt unter **Bibliothek → Fahrten**.
2. Tippe oben rechts auf die Wolken-Schaltfläche, beschriftet mit **Hochladen**.
3. Wähle **Zu Strava hochladen** oder **Zu Ride with GPS hochladen**.

Velorki sagt "Wird zu Strava hochgeladen…", dann "Zu Strava hochgeladen" mit der Aktion **Auf Strava ansehen**, die sie öffnet. Eine Fahrt, die schon oben ist, wird nie zweimal hochgeladen: Der Menüeintrag wird stattdessen zu **Auf Strava ansehen** oder **Auf Ride with GPS öffnen**.

Ein Upload zu Strava kann dauern, weil Strava die Datei verarbeitet, bevor daraus eine Aktivität wird; Velorki wartet darauf und verlinkt das Ergebnis.

## Routen importieren

1. Öffne den Tab **Bibliothek**.
2. Tippe oben rechts auf die Wolken-Schaltfläche und wähle **Aus Strava importieren** oder **Aus Ride with GPS importieren**.
3. Die Liste heißt **Strava-Routen** oder **Ride with GPS-Routen**. Jede Zeile zeigt Name, Distanz, Anstieg und Datum.
4. Tippe bei der gewünschten auf **Importieren**. Sie landet als gewöhnliche Route in deiner Bibliothek, und Velorki sagt "Alpenrunde importiert".

Die Fußzeile sagt **Abgerufen 16. Sept. 2026**, also den Moment, in dem die Liste geholt wurde. Velorki hält sie bis zu sieben Tage vor, wie es die Bedingungen von Strava verlangen, und **Aktualisieren** oben rechts holt sie erneut.

Ist das Konto nicht verbunden, sagt der Bildschirm "Zuerst Strava unter Einstellungen → Verbindungen verbinden."

## Eine Route an Ride with GPS senden

Öffne die Route, tippe auf **Senden** und wähle **An Ride with GPS senden**. Sie wird in dein Konto hochgeladen, und Velorki bietet **Öffnen** an, um sie dort anzusehen.

## Eine Route an Strava senden

Die API von Strava kann Routen lesen, aber nicht anlegen, es gibt für Velorki also nichts, wohin es hochladen könnte. **An Strava senden** öffnet darum eine Erklärung:

> **Strava kann keine Routen empfangen**. Die API von Strava kann Routen lesen, aber nicht anlegen. Velorki exportiert stattdessen eine GPX-Datei: teilen und dann auf strava.com importieren.

Tippe auf **GPX exportieren**, speichere oder verschicke die Datei und lade sie auf strava.com als Route hoch. Dieser Weg ist kostenlos und braucht überhaupt keine Verbindung.

## Was kostenlos ist und was Plus braucht

| | Braucht Plus |
|---|---|
| Strava oder Ride with GPS verbinden | ja |
| Eine Fahrt zu einem der beiden hochladen | ja |
| Routen aus einem der beiden importieren | ja |
| Eine Route an Ride with GPS senden | ja |
| GPX oder FIT exportieren und selbst hochladen | nein |
| Eine GPX- oder FIT-Datei aus einem der Dienste importieren | nein |

## Eine Anmerkung zu Assistent und Strava

**Diese Route beschreiben** wird für eine Route, die von Strava kam, nicht angeboten. Die API-Bedingungen von Strava erlauben nicht, ihre Daten an einen KI-Anbieter zu geben, deshalb versteckt Velorki die Schaltfläche, statt sie zu brechen.

## Weiterlesen

- [Velorki Plus](./velorki-plus)
- [Import und Export](./import-and-export)
- [Bibliothek](./library)
- [Assistent](./assistant)
- [Datenschutz auf dem Handy](./privacy-on-the-phone)
