---
title: Strava und Ride with GPS
description: Velorki funktioniert kostenlos mit Strava und Ride with GPS. Verbinde ein Konto, um Fahrten hochzuladen und Routen zu importieren, und sieh, warum eine Route an Strava eine Datei ist.
order: 13
---

Velorki ist kompatibel mit Strava und mit Ride with GPS: Es kann eine aufgezeichnete Fahrt hochladen und deine Routen aus diesen Konten in die Bibliothek holen. Einen der beiden Dienste zu verbinden ist kostenlos, mit oder ohne [Velorki Plus](./velorki-plus). Velorki wird nicht von Strava oder Ride with GPS hergestellt, unterstützt oder gesponsert.

An keinen der beiden Dienste geht etwas, bevor du das Konto selbst verbunden und dann etwas angefordert hast.

## Ein Konto verbinden

1. Öffne die **Einstellungen** und such den Abschnitt **Verbindungen**.
2. Tippe auf **Verbinden mit Strava** oder **Mit Ride with GPS verbinden**.
3. Die Anmeldeseite des Dienstes öffnet sich im Browser. Melde dich dort an und bestätige den Zugriff.
4. Du kommst zurück zu Velorki, und in der Zeile steht dein Name statt **Nicht verbunden**.

Velorki bittet Strava nur um zwei Berechtigungen: **read**, dein öffentliches Profil (deine ID und dein Name, in den Einstellungen angezeigt), und **activity:write**, um die Fahrten hochzuladen, die du hochladen willst. Es liest deine Aktivitäten nicht.

Dein Handy bewahrt den Zugriffstoken im sicheren Speicher des Handys auf, in einer Form, die nur der Velorki-Server öffnen kann, und nimmt ihn von Sicherungen aus. Von da an läuft jeder Upload und jeder Import über diesen Server: Er öffnet den Token für diese eine Anfrage und leitet sie weiter. Er behält weder die Datei noch den Token, auch keine Aufzeichnung des Aufrufs, und kann den Token allein nicht verwenden.

Scheitert ein Verbindungsversuch, sagt Velorki "Verbindung fehlgeschlagen:" mit dem Grund. Brichst du die Anmeldeseite ab, sagt es gar nichts.

Eine Zeile mit **In diesem Build nicht verfügbar** heißt, dass dieser Velorki-Build ohne die Schlüssel dieses Dienstes gebaut wurde, was bei einer selbst gebauten Kopie so ist, bis du eigene hinterlegst.

## Trennen

Tippe in der verbundenen Zeile auf **Trennen** und bestätige. Beim Trennen bittet Velorki den Dienst außerdem, den Zugriff zu widerrufen, sofern der Server erreichbar ist. Es entfernt nichts aus deinem Strava- oder Ride-with-GPS-Konto.

**Strava.** Das Trennen löscht jedes Stück Strava-Daten vom Handy: den Zugriffstoken, die Routen, die du aus Strava importiert hast, und daraus bearbeitete Routen, die zwischengespeicherte Routenliste und die Links von deinen Fahrten zu ihren Strava-Aktivitäten. Deine Fahrten selbst bleiben erhalten. Velorki sagt dann "Deine Strava-Daten wurden von diesem Handy gelöscht."

Entfernst du Velorki stattdessen auf strava.com aus deinem Strava-Konto, bemerkt Velorki das beim nächsten Strava-Aufruf, löscht dieselben Daten und sagt es dir.

**Ride with GPS.** Velorki vergisst den Zugriffstoken. Routen und Fahrten in der Bibliothek bleiben erhalten.

## Eine Fahrt hochladen

1. Öffne die Fahrt unter **Bibliothek → Fahrten**.
2. Tippe oben rechts auf die Wolken-Schaltfläche, beschriftet mit **Hochladen**.
3. Wähle **Zu Strava hochladen** oder **Zu Ride with GPS hochladen**.

Velorki sagt "Wird zu Strava hochgeladen…", dann "Zu Strava hochgeladen" mit der Aktion **View on Strava**, die sie öffnet. Dafür behält Velorki den Link der Aktivität bei der Fahrt, bis du trennst. Eine Fahrt, die schon oben ist, wird nie zweimal hochgeladen: Der Menüeintrag wird stattdessen zu **View on Strava** oder **Auf Ride with GPS öffnen**.

Ein Upload zu Strava kann dauern, weil Strava die Datei verarbeitet, bevor daraus eine Aktivität wird; Velorki wartet darauf und verlinkt das Ergebnis.

## Routen importieren

1. Öffne den Tab **Bibliothek**.
2. Tippe oben rechts auf die Wolken-Schaltfläche und wähle **Aus Strava importieren** oder **Aus Ride with GPS importieren**.
3. Die Liste heißt **Strava-Routen** oder **Ride with GPS-Routen**. Jede Zeile zeigt Name, Distanz, Anstieg und Datum.
4. Tippe bei der gewünschten auf **Importieren**. Sie landet in deiner Bibliothek, und Velorki sagt "Alpenrunde importiert". Eine aus Strava importierte Route bleibt auf dem Handy: Sie wird nie an den Assistenten gesendet, in einen Teilen-Link gelegt oder an Ride with GPS oder einen anderen Dienst geschickt, und das Trennen von Strava löscht sie.

Eine Route aus Strava und jede Route, die du daraus bearbeitest, bleibt nur, solange sie bei Strava noch existiert. Solange Velorki geöffnet, online und verbunden ist, prüft es eine solche Route alle 48 Stunden erneut bei Strava; deine Änderungen bleiben, solange die Route dort noch da ist. Wurde sie bei Strava gelöscht oder konnte 7 Tage lang nicht geprüft werden (offline, getrennt oder fehlgeschlagene Prüfungen), entfernt Velorki sie und sagt "Eine Route aus Strava wurde entfernt: Sie existiert bei Strava nicht mehr oder konnte 7 Tage lang nicht geprüft werden."

Die Fußzeile sagt **Abgerufen 16. Sept. 2026**, also den Moment, in dem die Liste geholt wurde. Velorki hält die Liste höchstens 48 Stunden auf dem Handy vor, und **Aktualisieren** oben rechts holt sie erneut.

Ist das Konto nicht verbunden, sagt der Bildschirm "Zuerst Strava unter Einstellungen → Verbindungen verbinden."

## Eine Route an Ride with GPS senden

Öffne die Route, tippe auf **Senden** und wähle **An Ride with GPS senden**. Sie wird in dein Konto hochgeladen, und Velorki bietet **Öffnen** an, um sie dort anzusehen.

## Eine Route an Strava senden

Die API von Strava kann Routen lesen, aber nicht anlegen, es gibt für Velorki also nichts, wohin es hochladen könnte. **An Strava senden** öffnet darum eine Erklärung:

> **Strava kann keine Routen empfangen**. Die API von Strava kann Routen lesen, aber nicht anlegen. Velorki exportiert stattdessen eine GPX-Datei: teilen und dann auf strava.com importieren.

Tippe auf **GPX exportieren**, speichere oder verschicke die Datei und lade sie auf strava.com als Route hoch. Dieser Weg ist kostenlos und braucht überhaupt keine Verbindung.

## Alles ist kostenlos

Strava oder Ride with GPS verbinden, eine Fahrt hochladen, Routen importieren und eine Route an Ride with GPS senden sind kostenlos, ebenso GPX-, FIT- und TCX-Dateien, die dieselbe Aufgabe von Hand erledigen. Nichts davon braucht Velorki Plus.

## Strava-Daten bleiben auf dem Handy

Strava-Daten werden nur dir angezeigt. Die API-Bedingungen von Strava erlauben nicht, ihre Daten an einen KI-Anbieter oder an andere Dienste weiterzugeben, deshalb sendet Velorki eine Route, die von Strava kam, nie an den Assistenten, legt sie nie in einen Teilen-Link und schickt sie nie an Ride with GPS oder sonst wohin. **Diese Route beschreiben** wird dafür zum Beispiel nicht angeboten.

Wir halten keine Strava-Daten auf unseren Servern: Alles liegt auf deinem Handy. Fragen oder ein Antrag auf Löschung von Daten gehen an [ride@velorki.com](mailto:ride@velorki.com); siehe die [Datenschutzerklärung](/privacy).

## Weiterlesen

- [Velorki Plus](./velorki-plus)
- [Import und Export](./import-and-export)
- [Bibliothek](./library)
- [Assistent](./assistant)
- [Datenschutz auf dem Handy](./privacy-on-the-phone)
