---
title: Bibliothek
description: Wo deine gespeicherten Routen und aufgezeichneten Fahrten liegen, was eine Fahrtenseite zeigt und wie du beides umbenennst oder löschst.
order: 8
---

Der Tab Bibliothek enthält alles, was du behalten hast: die geplanten Routen und die aufgezeichneten Fahrten. Geh hierher, um eine Route wieder zu öffnen, die Diagramme und Splits einer Fahrt zu lesen und Dateien hinein- und hinauszubekommen.

Alles in der Bibliothek liegt auf dem Handy. Es gibt kein Konto, und nichts wird irgendwohin abgeglichen.

## Routen und Fahrten

Ein Umschalter unter dem Titel wählt die Liste: **Routen** oder **Fahrten**. Velorki merkt sich, was du zuletzt angesehen hast.

- Eine Zeile mit einer **Route** zeigt ihren Namen und darunter Datum, Distanz und Anstieg.
- Eine Zeile mit einer **Fahrt** zeigt ihren Namen und darunter Datum, Distanz und Fahrzeit. Über der Liste steht eine Anzahl, "12 Fahrten".

Tippe auf eine Zeile, um sie zu öffnen.

Leere Listen erklären sich selbst: "Noch keine gespeicherten Routen." mit "Im Tab Planen eine Route planen und speichern." und "Noch keine Fahrten."

## Umbenennen und löschen

**Routen**: Das Menü rechts in der Zeile hat **Umbenennen** und **Löschen**. Ein Wisch nach links löscht die Zeile ebenfalls. In beiden Fällen trägt die Meldung danach ein **Rückgängig**.

**Fahrten**: Wisch die Zeile nach links, um sie zu löschen, wieder mit **Rückgängig**. Umbenennen und Löschen mit Rückfrage liegen auf der Seite der Fahrt selbst, unter dem Menü oben rechts.

Beide Dialoge zum Umbenennen sind gleich: ein Feld, **Name**, dann **Abbrechen** oder **Speichern**.

## Eine Routenseite

Eine geöffnete Route zeigt von oben nach unten:

- eine Karte der Route, mit ihren Punkten von Interesse als kleinen benannten Markern, wenn sie mit welchen importiert wurde,
- Datum, Radprofil und Anstieg,
- die Beschreibung, falls die Route eine hat,
- **Distanz**, **Anstieg**, **Abstieg** und **Dauer**,
- das Höhenprofil,
- die Belagsverteilung.

Die Karte bleibt oben stehen, während der Rest darunter scrollt. Eine Route, die mit Abbiegungen oder Punkten von Interesse importiert wurde, hat eine zweite Seite einen Wisch nach links, die Abbiegeliste: jede Abbiegung und jeder Punkt mit der Entfernung vom Start, ein Tipp auf eine Zeile schwenkt die Karte in deinem Zoom dorthin und ein Tipp auf einen Marker bringt die Liste mit der ausgewählten Zeile hoch, wie auf dem Importbildschirm.

Dann die Aktionen:

- **Im Planer öffnen** lädt sie in den Tab Planen, wo du sie bearbeiten und erneut speichern kannst.
- **Export** bietet **GPX-Route** und **FIT-Strecke**, siehe [Import und Export](./import-and-export).
- **Senden** bietet **An Ride with GPS senden** und **An Strava senden**, siehe [Strava und Ride with GPS](./strava-and-ridewithgps).
- **Link teilen** macht einen Link daraus, siehe [Teilen](./sharing).
- **Diese Route beschreiben** lässt den Assistenten einen Absatz darüber schreiben, siehe [Assistent](./assistant).

## Eine Fahrtenseite

Eine geöffnete Fahrt zeigt von oben nach unten:

- **den nach Tempo eingefärbten Track**, von langsam bis schnell, mit einer Legende **langsam**/**schnell** unter der Karte. Die Bänder sind die Quantile dieser Fahrt selbst, die Farben vergleichen die Fahrt also mit sich und nicht mit einer festen Skala. Eine Fahrt ohne Zeitstempel wird als einfache Linie gezeichnet.
- das Datum,
- sieben Zahlen: **Distanz**, **Fahrzeit**, **Zeit**, **Ø**, **Max**, **Anstieg**, **Abstieg**. **Fahrzeit** lässt die Zeit im Stand weg; **Zeit** ist die ganze Fahrt von Anfang bis Ende.
- das Diagramm **Höhenprofil**, Höhe über Distanz, nur gezeichnet, wenn der Track Höhen mitbrachte,
- das Diagramm **Tempo**, dessen Achse immer bei null beginnt,
- das Diagramm **Herzfrequenz**, wenn die Fahrt einen Puls mitbrachte,
- die Tabelle **Splits**.

Berühre eines der beiden Diagramme und zieh darüber für eine Anzeige in der Form `12,3 km · 340 m`.

### Zahlen von einem Sensor

Eine Fahrt, die mit Pulsgurt, Apple Watch oder Leistungsmesser aufgezeichnet wurde, trägt mehr als die sieben: **Ø Puls**, **Max Puls**, **Ø Kadenz** und **Ø Leistung** kommen zu den Zahlen dazu, jede nur, wenn die Fahrt sie hat, und unter dem Tempo-Diagramm wird das Diagramm **Herzfrequenz** gezeichnet. Eine ohne Sensor aufgezeichnete Fahrt zeigt nichts davon, und eine aus einer GPX- oder FIT-Datei importierte zeigt, was diese Datei mitbrachte. Siehe [Sensoren und deine Uhr](./sensors-and-watch).

### Splits

Eine Zeile je Kilometer, oder je Meile bei imperialen Einheiten, mit vier Spalten: **Split**, **Fahrzeit**, **Ø** und **Anstieg**. Die letzte Zeile ist der Rest und kann darum kürzer sein als die übrigen. Hinter jeder Zeile zeigt ein Balken das Durchschnittstempo dieses Splits im Verhältnis zu deinem schnellsten, was die harten Abschnitte auf einen Blick sichtbar macht.

### Aktionen einer Fahrt

- Die Wolken-Schaltfläche oben rechts lädt die Fahrt zu einem verbundenen Dienst hoch.
- Das Menü daneben: **GPX-Track exportieren**, **FIT-Aktivität exportieren**, **Fahrt fortsetzen**, **Umbenennen**, **Löschen**.
- Ganz unten: dieselben zwei Exporte und **Link teilen**.

## Dateien und Routen hereinbekommen

Die beiden Schaltflächen oben rechts im Tab Bibliothek:

- **Datei importieren** öffnet die Dateiauswahl des Handys für eine GPX- oder FIT-Datei.
- Die Wolken-Schaltfläche bietet **Aus Strava importieren** und **Aus Ride with GPS importieren**, sofern diese Dienste eingerichtet sind.

Beides steht unter [Import und Export](./import-and-export) und [Strava und Ride with GPS](./strava-and-ridewithgps).

## Weiterlesen

- [Fahrt aufzeichnen](./recording-a-ride)
- [Sensoren und deine Uhr](./sensors-and-watch)
- [Import und Export](./import-and-export)
- [Teilen](./sharing)
- [Strava und Ride with GPS](./strava-and-ridewithgps)
- [Route planen](./planning-a-route)
