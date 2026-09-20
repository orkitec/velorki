---
title: Import und Export
description: GPX- und FIT-Dateien von überall auf dem Handy öffnen, als Route oder Fahrt speichern und eigene zu Komoot, Garmin oder sonst wohin exportieren.
order: 9
---

Velorki liest und schreibt GPX- und FIT-Dateien, und so wandern Routen und Fahrten zwischen der App und dem Rest der Welt. Alles davon ist kostenlos, braucht kein Konto und keine Verbindung und funktioniert mit Komoot, Garmin Connect, Strava, einem Radcomputer oder einer schlichten Datei auf dem Handy.

## Eine Datei hereinbekommen

Es gibt drei Wege, und alle drei enden auf demselben Importbildschirm.

**Öffnen mit.** Tippe in deiner Dateien-App, in einer E-Mail oder in den Downloads des Browsers auf eine GPX- oder FIT-Datei und wähle Velorki. Auf einem iPhone ist das "In Velorki öffnen" aus Dateien, Mail oder Safari.

**Teilen-Menü.** Teile die Datei in einer anderen App und wähle Velorki. So kommt eine Route von Komoot oder aus der Nachricht eines Freundes an.

**Die Dateiauswahl.** Tippe im Tab **Bibliothek** oben rechts auf **Datei importieren** und such die Datei selbst heraus.

**Ein Ride-with-GPS-Link.** Teile den Link einer Route aus der Ride-with-GPS-App oder dem Browser und wähle Velorki, und die Route landet auf dem Importbildschirm. Eine öffentliche Route braucht sonst nichts; eine private wird über dein verbundenes Ride-with-GPS-Konto geholt, und ohne Konto sagt der Bildschirm "Diese Ride-with-GPS-Route ist privat. Verbinde Ride with GPS in den Einstellungen, um sie zu öffnen."

Eine Datei, die sich nicht importieren lässt, öffnet denselben Bildschirm mit dem Grund: keine GPX- oder FIT-Datei, nicht lesbar, leer, oder ein Link, der sich nicht laden ließ.

Velorki erkennt am Anfang der Datei, was sie ist, und vertraut weder ihrem Namen noch ihrem Typ, eine `.gpx`, die in Wahrheit eine FIT-Datei ist, wird also trotzdem importiert.

## Der Importbildschirm

Er heißt **Import** und zeigt:

- eine Kartenvorschau des Tracks, mit den Wegpunkten der Datei als kleinen Markern mit ihrem Namen: die Punkte von Interesse, die eine Route mitbringt, eine Absteigezone, ein Trinkbrunnen, ein rauer Abschnitt, in der Farbe ihrer Art,
- ein Feld **Name**, vorbelegt aus dem Dateinamen,
- Format und Größe, "GPX · 4.812 Punkte",
- den Zeitraum, "16. Sept. 2026, 09:12 – 16. Sept. 2026, 13:40", oder "Die Datei enthält keine Zeitstempel.",
- Distanz, Anstieg, Abstieg und Dauer sowie das Höhenprofil,
- **Speichern als**, einen Umschalter zwischen **Route** und **Fahrt**.

Die Karte bleibt oben stehen, während der Rest darunter scrollt. Hat die Datei Abbiegungen oder Punkte von Interesse, liegt eine zweite Seite einen Wisch nach links, mit zwei Punkten unten, die sagen, welche gerade oben ist: die **Abbiegeliste**, jede Abbiegung und jeder Punkt von Interesse mit der Entfernung vom Start, auf acht Zeilen gefaltet mit **Alle zeigen**. Tippe auf eine Zeile, und die Karte schwenkt dorthin, in dem Zoom, den du gerade hast, mit dem Namen angeheftet; tippe auf einen Marker auf der Karte, und die Abbiegeliste kommt mit der ausgewählten Zeile hoch, ins Bild gescrollt. Eine ausgewählte Zeile öffnet sich mit dem, was es zu wissen gibt, dem Hinweis einer Gefahrenstelle oder dem einfachen Manöver unter den Worten des Autors.

Eine GPX-Route mit Abbiegeliste, der Routen-Export von Ride with GPS oder eine Garmin-Strecke, bringt ihre Abbiegungen mit: Jeder Eintrag wird ein Abbiegehinweis mit den Worten des Autors, gezeigt im Abbiegeband, auf der Abbiegeliste der Aufnahme und gesagt von der Stimme. Ein GPX-Track hat keine Abbiegeliste; Velorkis eigenes Abbiegeband funktioniert darauf trotzdem, aus der Form der Route.

Velorki rät **Route** oder **Fahrt** danach, ob die Punkte Zeiten tragen: eine Aufnahme tut das, eine geplante Route nicht. FIT-Strecken tragen eine künstliche Zeitbasis und werden darum als Fahrt geraten, stell sie also von Hand um. Nichts wird geschrieben, bevor du auf **Speichern** tippst.

Danach bekommst du "Alpenrunde zur Bibliothek hinzugefügt" oder "Alpenrunde zu deinen Fahrten hinzugefügt" und landest auf der Seite des neuen Eintrags.

Lässt sich die Datei nicht öffnen, sagt Velorki, woran es lag: "Das ist keine GPX- oder FIT-Datei.", "Die Datei konnte nicht gelesen werden.", "Die Datei enthält keine Trackpunkte." oder "Die Datei konnte nicht geöffnet werden."

## Eine Datei hinausbekommen

**Aus einer Route** (Bibliothek → Routen → öffnen → **Export**):

| Format | Wofür |
|---|---|
| **GPX-Route** | eine geplante Route für einen anderen Planer, eine Handy-App oder einen Radcomputer |
| **FIT-Strecke** | ein Garmin, Wahoo oder ähnliches Gerät, das eine Strecke erwartet |

**Aus einer Fahrt** (Bibliothek → Fahrten → öffnen, oder die Fahrtenseite nach dem Beenden):

| Format | Wofür |
|---|---|
| **GPX-Track exportieren** | der aufgezeichnete Track mit seinen Zeitstempeln |
| **FIT-Aktivität exportieren** | eine Aktivitätsdatei für eine Trainingsplattform |

So oder so schreibt Velorki die Datei und reicht sie an das Teilen-Menü des Systems weiter, du kannst sie also in deine Dateien legen, per Mail verschicken oder in eine andere App schicken.

## Komoot, Garmin und der Rest

Velorki hat keine Anbindung an Komoot oder Garmin und braucht auch keine: Beide sprechen GPX und FIT.

- **Von Komoot zu Velorki**: Exportiere die Tour in Komoot als GPX und teile sie dann zu Velorki, oder speichere sie und öffne sie über die Schaltfläche **Datei importieren**.
- **Von Velorki zu Komoot**: Exportiere die Route als **GPX-Route** und teile sie in den Import von Komoot.
- **Auf einen Garmin-Radcomputer**: Exportiere die Route als **FIT-Strecke**, oder als **GPX-Route**, falls dein Gerät das lieber mag, und bring sie wie gewohnt auf das Gerät, über Garmin Connect oder durch Kopieren der Datei.
- **Von einem Garmin**: Die `.fit`-Aktivität vom Gerät wird als Fahrt importiert.

Eine Route **an Strava** zu senden, läuft ebenfalls über eine Datei, weil die API von Strava keine Routen anlegen kann. Siehe [Strava und Ride with GPS](./strava-and-ridewithgps).

## Weiterlesen

- [Bibliothek](./library)
- [Strava und Ride with GPS](./strava-and-ridewithgps)
- [Teilen](./sharing)
- [Fahrt aufzeichnen](./recording-a-ride)
