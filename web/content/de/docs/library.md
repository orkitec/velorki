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
- die Belagsverteilung.

Die Karte bleibt oben stehen, während die Seiten darunter scrollen, mit Punkten unter der Karte, die sagen, welche Seite gerade oben ist. Einen Wisch nach links liegt das Höhenprofil. Eine Route, die mit Abbiegungen oder Punkten von Interesse importiert wurde, hat noch eine Seite, die Abbiegeliste: jede Abbiegung und jeder Punkt mit der Entfernung vom Start, ein Tipp auf eine Zeile schwenkt die Karte in deinem Zoom dorthin und ein Tipp auf einen Marker bringt die Liste mit der ausgewählten Zeile hoch, wie auf dem Importbildschirm.

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
- das Diagramm **Herzfrequenz**, wenn die Fahrt einen Puls mitbrachte; wo der Wert eine Strecke lang fehlte, bricht die Linie ab, und hatte weniger als der Großteil der Fahrt einen Wert, sagt die Überschrift, wie viel, "Herzfrequenz · 24 % der Fahrt", damit ein Schnitt über diese Minuten nicht als der der Fahrt gelesen wird,
- die Tabelle **Splits**.

Berühre eines der beiden Diagramme und zieh darüber für eine Anzeige in der Form `12,3 km · 340 m`.

### Zahlen von einem Sensor

Eine Fahrt, die mit Pulsgurt, Apple Watch oder Leistungsmesser aufgezeichnet wurde, trägt mehr als die sieben: **Ø Puls**, **Max Puls**, **Ø Kadenz**, **Max Kadenz**, **Ø Leistung** und **Max Leistung** kommen zu den Zahlen dazu, jede nur, wenn die Fahrt sie hat, und unter dem Tempo-Diagramm wird das Diagramm **Herzfrequenz** gezeichnet. Eine ohne Sensor aufgezeichnete Fahrt zeigt nichts davon, und eine aus einer GPX- oder FIT-Datei importierte zeigt, was diese Datei mitbrachte. Siehe [Sensoren und deine Uhr](./sensors-and-watch).

### Kalorien, Pulszonen und geschätzte Leistung

Alle drei sind aus, bis du sie unter Einstellungen → Fahrer einschaltest, und alle drei werden auf dem Handy aus den Punkten der Fahrt berechnet, also auch für ältere Fahrten.

**Kalorien** ist eine Schätzung, und die kleine Zeile unter der Zahl sagt, worauf sie beruht. Mit einem Leistungsmesser über die Fahrt ist es die geleistete Arbeit, "aus Leistung": ein Kilojoule Treten ist ziemlich genau eine verbrannte Kilokalorie. Sonst, mit einem Puls über die Fahrt und deinem Gewicht, Geburtsjahr und Geschlecht, ist es "aus Puls". Sonst, wenn **Leistung schätzen** an ist, ist es "aus geschätzter Leistung", wieder die geschätzte Arbeit in Kilojoule. Sonst ist es "aus Tempo geschätzt", aus deinem Gewicht und deinem Tempo. Dein Gewicht braucht es in jedem Fall.

**Gesch. Leistung** erscheint nur mit eingeschaltetem Schalter und nur auf Fahrten ohne Leistungsmesser; eine Fahrt mit Messgerät zeigt das Messgerät und sonst nichts. Es ist der Mittelwert dessen, was du nach dem Leistungsmodell von Martin in die Pedale gebracht haben musst, um dich und dein Rad mit deinem Tempo die gefahrene Steigung hinaufzubewegen: aus deinem Tempo, der Steigung und dem Gesamtgewicht von Fahrer und Rad, unter der Annahme von Windstille, keinem Windschatten, einer Haltung am Oberlenker, einem festen Rollwiderstand je Radtyp, 2,5 % Verlust im Antrieb und dünnerer Luft mit der Höhe. Die Höhen werden über 20 m geglättet, weil GPS-Höhen springen; Rollen und Bremsen zählen als null. Rechne damit, dass die Zahl auf langen Anstiegen brauchbar ist, wo das Gewicht dominiert; in einer schnellen Gruppe zu hoch und bei Wind falsch, den sie nicht sehen kann. Sie ist eine Zahl, um deine eigenen Fahrten miteinander zu vergleichen, kein Leistungsmesser.

**Pulszonen** ist ein Balken unter dem Herzfrequenz-Diagramm, in fünf Zonen deines Maximalpulses geteilt, mit einer Zeile je Zone: ihr Bereich, die Zeit darin und der Anteil an der Pulszeit der Fahrt. Zone 1 ist alles unter 60 %, Zone 5 alles ab 90 %. Die Überschrift nennt den verwendeten Maximalpuls: den eingetragenen oder 220 minus dein Alter.

### Splits

Eine Zeile je Split, mit vier Spalten: **Split**, **Fahrzeit**, **Ø** und **Anstieg**. Die Überschrift sagt, wie lang ein Split ist, "Splits, alle 5 km". Standardmäßig folgt die Länge der Fahrt: ein Kilometer bis 30 km, fünf bis 150 km, darüber zehn, bei imperialen Einheiten in Meilen, damit die Tabelle auf einer langen Fahrt kurz bleibt; **Split-Länge** unter Einstellungen → Aufnahme legt sie stattdessen auf 1, 5 oder 10 fest. Die letzte Zeile ist der Rest und kann darum kürzer sein als die übrigen. Hinter jeder Zeile zeigt ein Balken das Durchschnittstempo dieses Splits im Verhältnis zu deinem schnellsten, was die harten Abschnitte auf einen Blick sichtbar macht.

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
