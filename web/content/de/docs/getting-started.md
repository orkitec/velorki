---
title: Erste Schritte
description: Velorki installieren, die vier Tabs verstehen, die Berechtigungen und ihren Zweck kennenlernen und die Einheiten einstellen. Ein Konto braucht es nicht.
order: 1
---

Velorki ist ein kostenloser Open-Source-Routenplaner und Fahrtenschreiber fürs Rad, für iPhone und Android, auf Basis von OpenStreetMap-Daten. Diese Seite deckt die ersten zehn Minuten ab: installieren, was die App wofür fragt, wie sie aufgebaut ist, und die eine Einstellung, die die meisten sofort ändern wollen.

## Was du brauchst

- Ein iPhone mit iOS 15 oder neuer, oder ein Android-Handy mit Android 8.0 oder neuer.
- Kein Konto. Velorki hat keine Registrierung, keinen Login und kein Passwort. Auf einem Server wird nichts über dich gespeichert.
- Keine Verbindung, sobald ein Gebiet heruntergeladen ist. Planen, Routing, Ortssuche, Navigation und Aufnahme laufen alle auf dem Handy.

## Installieren

1. Installiere Velorki aus dem App Store oder von Google Play, wie jede andere App.
2. Öffne die App. Es gibt keinen Anmeldebildschirm und keine Tour zum Wegklicken; die App startet auf der Karte.

Velorki ist Open Source. Wer die App lieber selbst baut oder eigene Server für die Teile betreiben will, die welche brauchen, findet Code und Anleitung unter [github.com/orkitec/velorki](https://github.com/orkitec/velorki).

## Der erste Start

Velorki öffnet den Tab **Planen** mit einer Weltkarte. Es ist noch nichts heruntergeladen und noch keine Berechtigung angefragt.

Eine gute erste Sitzung:

1. Verschiebe die Karte in dein Fahrgebiet und zieh sie mit zwei Fingern auf.
2. Tippe auf die Karte, um den Start zu setzen, und tippe erneut für ein Ziel. Kurz darauf erscheint eine Route.
3. Tippe rechts neben der Karte auf die Download-Schaltfläche (**Offline-Daten**) und lade das Gebiet herunter, damit Karte und Routing auch ohne Empfang weiterlaufen. Was die beiden Downloads sind und wie groß sie werden, steht unter [Offline-Karten und Routing](./offline-maps-and-routing).
4. Stelle unter **Einstellungen → Darstellung → Einheiten** deine Einheiten ein, falls die App falsch geraten hat.

## Die Berechtigungen und wofür sie da sind

Velorki fragt beim Start nach nichts. Jede Berechtigung wird genau dann angefragt, wenn sie zum ersten Mal gebraucht wird, und jede wird erklärt, bevor der Systemdialog kommt.

### Standort

Wird gefragt, sobald du zum ersten Mal auf **Meine Position anzeigen** tippst, eine Fahrt startest oder eine Runde ab deiner Position anforderst.

Velorki zeigt zuerst einen eigenen Dialog mit dem Titel **Deine Position anzeigen?**: "Velorki nutzt deinen Standort, um die Karte auf dich zu zentrieren und Fahrten aufzuzeichnen. Die Position bleibt auf diesem Gerät und wird nie hochgeladen." Du kannst **Jetzt nicht** antworten und die App weiter nutzen; nur die Funktionen, die deine Position kennen müssen, fallen dann aus.

Mit der Berechtigung öffnet sich die Karte dort, wo du sie verlassen hast, und gleitet dann zu deiner Position: sofort dorthin, wo das Telefon dich zuletzt kannte, wenn das weniger als eine Stunde her ist, und zur ersten frischen Ortung, wenn nicht, oder wenn diese dich mehr als etwa 300 m davon entfernt zeigt, beim Start der App ebenso wie bei einer Rückkehr nach einer halben Stunde oder mehr. Sie bleibt, wo sie ist, solange eine Planung im Tab Planen liegt, eine Routen- oder Fahrtenkarte offen ist, eine Fahrt aufgezeichnet wird, du schon zu sehen bist oder du die Karte selbst bewegt hast.

"Beim Verwenden der App" reicht. Unter Android fragt Velorki bewusst **nicht** nach dem Standort im Hintergrund: Die Aufnahme läuft stattdessen als Vordergrunddienst mit einer Mitteilung. Unter iOS deckt "Beim Verwenden" zusammen mit dem Hintergrund-Standortmodus eine Aufnahme bei ausgeschaltetem Bildschirm ab.

### Mitteilungen (Android)

Wird gefragt, sobald du zum ersten Mal eine Fahrt startest. Die Aufnahme läuft in einer Mitteilung, die Distanz und Zeit zeigt, und Android beendet die Aufnahme, wenn diese Mitteilung nicht angezeigt werden kann. Lehnst du ab, sagt Velorki das: "Ohne Benachrichtigungsberechtigung stoppt Android die Aufnahme, sobald du die App verlässt."

### Akku-Optimierung (Android)

Wird ein einziges Mal gefragt, beim ersten Start einer Fahrt: **Im Hintergrund weiter aufzeichnen**: "Android kann die Aufnahme stoppen, während das Handy schläft. Darf Velorki die Akku-Optimierung ignorieren, bleibt der Track vollständig. Die Frage kommt nur einmal." Antworte **Erlauben** oder **Jetzt nicht**; gefragt wird nie wieder.

### Dateien

Keine dauerhafte Berechtigung. Beim Import einer GPX-, FIT- oder TCX-Datei reicht die Dateiauswahl des Systems genau diese eine Datei an die App weiter; beim Export nimmt das Teilen-Menü des Systems sie wieder mit.

Mehr fragt Velorki nicht. Nirgends in der App gibt es Zugriff auf Kontakte, Fotos, Mikrofon, Gesundheitsdaten oder Werbung.

## Die vier Tabs

Die Leiste am unteren Rand hat vier Tabs.

| Tab | Was dort liegt |
|---|---|
| **Planen** | Die Karte, die Ortssuche, der Routenplaner, smarte Runden und der Assistent. |
| **Aufnahme** | Fahrt starten, pausieren und beenden, die Zahlen währenddessen und deine letzten Fahrten. |
| **Bibliothek** | Alles Gespeicherte: **Routen** und **Fahrten**, mit Import und Export. |
| **Einstellungen** | Darstellung und Einheiten, Navigation und Aufnahme, Offline-Daten, Suche, Verbindungen, Abo und die Rechtstexte. |

Die Leiste schwebt über dem Inhalt, Listen scrollen also darunter hindurch.

## Einheiten

Velorki zeigt Distanzen in Kilometern und Metern oder in Meilen und Fuß, und deine Wahl gilt überall: für die Zahlen, die Schieberegler, die Achsen der Diagramme, das Abbiegeband und die Sprachansagen.

1. Öffne **Einstellungen**.
2. Unter **Darstellung** findest du **Einheiten**.
3. Wähle **Metrisch** oder **Imperial**.

Bis du wählst, folgt Velorki dem Land des Handys: imperial nur dort, wo das Land es verwendet, sonst metrisch.

## Wo was liegt

- **Die Kartenbedienung** sitzt in einer Spalte rechts neben der Karte: meine Position anzeigen, das Rad-Overlay, Offline-Daten, hinein- und herauszoomen. Während einer Aufnahme kommt eine Kompass-Schaltfläche dazu, die zwischen **Norden oben** und **Karte dreht mit** wechselt.
- **Das Suchfeld** steht oben im Tab Planen.
- **Das Radprofil** (Trekking, Rennrad, Gravel, MTB, Direkt) ist die Reihe von Chips unter dem Suchfeld.
- **Die Routenübersicht** ist das Feld am unteren Rand des Tabs Planen. Zieh es nach oben für Höhenprofil und Belagsverteilung, nach unten für mehr Karte.

## Weiterlesen

- [Route planen](./planning-a-route)
- [Offline-Karten und Routing](./offline-maps-and-routing)
- [Fahrt aufzeichnen](./recording-a-ride)
- [Einstellungen und Darstellung](./settings-and-appearance)
- [Datenschutz auf dem Handy](./privacy-on-the-phone)
