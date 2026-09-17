---
title: Fehlerbehebung
description: "Lösungen für die häufigen Probleme: keine Position, keine Route, das Kachel-Banner, eine stumme Stimme unter iOS, hängende Downloads und tote Links."
order: 16
---

Was am häufigsten schiefgeht, und was jeweils dagegen hilft. Steht dein Problem nicht hier, sagt der letzte Abschnitt, wie du es meldest.

## Velorki findet meine Position nicht

Die Anzeichen sind "Noch keine Position ermittelt.", eine Positions-Schaltfläche, die nichts tut, oder "Standort einschalten oder Karte antippen, um den Start zu setzen."

1. **Wurde die Berechtigung abgelehnt?** Velorki fragt mit einem eigenen Dialog, **Deine Position anzeigen?**, bevor der des Systems kommt. Hast du **Jetzt nicht** geantwortet, tippe erneut auf die Positions-Schaltfläche und antworte **Weiter**.
2. **Ist sie für Velorki ausgeschaltet?** "Die Standortberechtigung ist für Velorki ausgeschaltet. Schalte sie in den Systemeinstellungen ein." kommt mit einer Aktion **Einstellungen**, die dich direkt dorthin bringt. Erlaube "Beim Verwenden der App" oder "Beim Verwenden".
3. **Sind die Ortungsdienste auf dem Handy aus?** "Die Ortungsdienste sind auf diesem Gerät ausgeschaltet." betrifft das Handy, nicht Velorki. Die Aktion **Einstellungen** öffnet die richtige Stelle.
4. **Drinnen, oder gerade erst eingeschaltet?** "Noch keine Position ermittelt." heißt oft, dass das Handy überhaupt noch keine Position hat. Geh nach draußen und gib ihm eine halbe Minute.

Velorki braucht nie den Standort im Hintergrund. "Beim Verwenden der App" reicht, auch für die Aufnahme einer Fahrt.

## Es erscheint keine Route

**"Diese Route braucht Routing-Kacheln, die nicht auf diesem Gerät sind."** Dein Handy hat keine Routing-Daten für das Gebiet, und es gibt keinen Routing-Server, der einspringt. Tippe auf die Schaltfläche, die die Kacheln und ihre Größe zählt, und lade sie herunter. Siehe [Offline-Karten und Routing](./offline-maps-and-routing).

**"Kein Routing-Server konfiguriert, einen unter Einstellungen → Erweitert festlegen."** Dieser Build liefert keine Serveradresse mit. Lade die Routing-Kacheln für dein Gebiet herunter und berechne stattdessen auf dem Handy.

**Einstellungen → Erweitert → Routing steht auf "Nur auf dem Gerät".** Dann fragt Velorki nie einen Server, so ist es gedacht. Stell es auf **Automatisch** oder lade die Kacheln herunter.

**"Routing fehlgeschlagen:" mit einem Grund.** Meist war der Server nicht erreichbar. Versuch es erneut und prüf, ob ein Wegpunkt im Meer oder auf einer Autobahn gelandet ist, wo kein Rad fahren darf. Den störenden Punkt ein paar Meter auf eine echte Straße zu ziehen, hilft in der Regel.

## Das Kachel-Banner geht nicht weg

Das Banner steht im Planer, sobald die Route ein Gebiet quert, dessen Routing-Kachel nicht auf dem Handy ist. Velorki berechnet nie auf lückenhafter Abdeckung, denn der Router würde die fehlende Kachel für leeres Land halten und still eine falsche Route zurückgeben.

1. Tippe auf die Schaltfläche im Banner. Sie öffnet **Offline-Routing-Daten** mit genau den Kacheln ausgewählt, die die Route braucht.
2. Lade sie herunter. Kacheln sind 125 bis 250 MB pro Stück, sei also im Wi-Fi.
3. Sobald eine Kachel ankommt, berechnet der Planer von selbst neu und das Banner weicht den Zahlen der Route.

Zeigen die gebrauchten Kacheln **Update braucht ein neueres Velorki**, aktualisiere erst die App; der Dialog erklärt, warum.

## Die Stimme sagt nichts

Prüf in dieser Reihenfolge:

1. **Einstellungen → Navigation → Abbiegehinweise** an und **Stimme** an. Stimme ist ausgegraut, solange Abbiegehinweise aus ist.
2. **Die Stummschalt-Schaltfläche im Abbiegeband.** Sie legt die Stimme nur für den Rest dieser Fahrt still. Tippe sie erneut an.
3. **Folgst du einer Route?** Die Führung braucht eine unter **Einer Route folgen** im Tab Aufnahme gewählte Route und eine tatsächlich laufende Aufnahme.
4. **Die Lautstärke und der Stummschalter des Handys.**

### Auf einem iPhone

Zeigt Velorki **Bessere Stimmen gibt es zum Download**, hat das Handy für deine Sprache nur die kompakte Stimme. Folge den Schritten auf der Karte: **Einstellungen → Bedienungshilfen → Gesprochene Inhalte → Stimmen → deine Sprache → die Wolke antippen** neben einer Stimme Erweitert oder Premium. Velorki nimmt danach von selbst die beste Stimme auf dem Handy.

Ist die gewählte Stimme mit **Braucht Internet** gekennzeichnet, wird sie auf einem Server erzeugt: Ohne Empfang bleibt die Ansage aus oder kommt zu spät. Nimm für Fahrten eine Stimme ohne diese Kennzeichnung. Sie sind verborgen, solange **Online-Stimmen zeigen** unten in der Stimmenliste nicht an ist.

"Für deine Sprache ist keine Stimme installiert." heißt, dass das Handy nichts zum Sprechen hat; füge in den eigenen Einstellungen des Handys unter Text-to-Speech oder Gesprochene Inhalte eine Stimme hinzu.

## Ein Download hängt oder schlägt fehl

- **Downloads laufen nur, solange die App offen ist.** Lass Velorki bei einer großen Kachel im Vordergrund. Bricht es ab, bleibt der angekommene Teil erhalten und der nächste Versuch setzt dort an.
- **"Der Download ist fehlgeschlagen:"** mit einem Grund. Tippe die Kachel erneut an, um es zu wiederholen. Ein fortgesetzter Download beginnt nicht bei null.
- **"Die Kachelliste konnte nicht geladen werden:"** heißt, dass der Mirror nicht erreichbar war. **Erneut versuchen** steht auf dem Bildschirm.
- **Prüf den freien Speicher auf dem Handy.** Eine Routing-Kachel von 250 MB braucht 250 MB, und das Kartengebiet kommt obendrauf.
- **Abbrechen und neu starten** mit der Schließen-Schaltfläche im Fortschrittskopf, wenn ein Download erkennbar steht.
- Velorki kann Wi-Fi nicht von mobilen Daten unterscheiden, deshalb warnt es, statt zu blockieren. Starte große Downloads selbst im Wi-Fi.

## Ein Teilen-Link geht nicht in der App auf

- **Der Link ist älter als ein Jahr.** Geteilte Einträge werden nach 365 Tagen automatisch gelöscht, und die Seite sagt dann "nicht gefunden". Bitte um einen frischen Link.
- **Die App ist auf diesem Handy nicht installiert.** Die Seite funktioniert trotzdem im Browser: die Karte, die Zahlen und **GPX herunterladen**.
- **"In Velorki öffnen" hat nichts getan.** Lade die GPX von der Seite herunter und öffne sie stattdessen mit Velorki; sie landet auf demselben Importbildschirm. Ein abgelaufener oder vertippter Link wird still ignoriert statt mit einem Fehler beantwortet.

## Eine Datei lässt sich nicht importieren

Velorki liest GPX und FIT und entscheidet nach den Bytes, nicht nach dem Dateinamen.

| Meldung | Bedeutung |
|---|---|
| "Das ist keine GPX- oder FIT-Datei." | der Inhalt ist keines von beidem, egal was der Name sagt |
| "Die Datei konnte nicht gelesen werden." | die Datei ist eines von beidem, aber beschädigt |
| "Die Datei enthält keine Trackpunkte." | eine leere Datei, oder eine GPX nur mit Wegpunkten |
| "Die Datei konnte nicht geöffnet werden." | das System hat die Datei nicht herausgerückt |

Wird eine Datei als falsche Art importiert, stell **Speichern als** auf dem Importbildschirm vor dem Speichern zwischen **Route** und **Fahrt** um. FIT-Strecken werden wegen ihrer Zeitstempel als Fahrten geraten.

## Die Aufnahme hat von selbst aufgehört

Antworte unter Android auf **Im Hintergrund weiter aufzeichnen** mit **Erlauben** und erteile die Berechtigung für Mitteilungen; beides ist es, was das System davon abhält, die Aufnahme zu beenden, während das Handy schläft. Auf beiden Plattformen wird der Track fortlaufend geschrieben, wurde die App also beendet, bekommst du beim nächsten Start **Nicht beendete Fahrt** mit **Fortsetzen**, **Beenden** und **Verwerfen**. Siehe [Fahrt aufzeichnen](./recording-a-ride).

## Eine Plus-Funktion fehlt

- **"In diesem Build nicht verfügbar"** in einer Verbindungszeile oder auf der Abo-Seite heißt, dass diese Velorki-Kopie ohne die Schlüssel für diesen Dienst oder Store gebaut wurde. So sieht eine selbst gebaute Kopie aus.
- **Die Schaltfläche Fragen oder die Schaltfläche Link teilen fehlt ganz** in einem Build ohne konfigurierten Velorki-Server.
- **Alles andere** sollte "… gehört zu Velorki Plus" sagen und die Abo-Seite anbieten. Hast du ein Abo und es tut das nicht, tippe unter **Einstellungen → Abo** auf **Käufe wiederherstellen**.

## Einen Fehler melden

**Einstellungen → Über → Problem melden** öffnet den Issue-Tracker, oder geh direkt zu [github.com/orkitec/velorki/issues](https://github.com/orkitec/velorki/issues).

Eine gute Meldung enthält:

1. was du getan hast, Schritt für Schritt, und was statt des Erwarteten passiert ist;
2. das Handy und die Version des Betriebssystems;
3. die Velorki-Version, aus **Einstellungen → Über**;
4. wo es passiert ist, falls Karte oder Routing beteiligt sind, denn viele Probleme hängen an einer bestimmten Ecke der Kartendaten;
5. einen Screenshot, der meist mehr wert ist als alles davor.

Velorki hat keine Absturzberichte und schickt uns von selbst nichts, eine Meldung von dir ist also der einzige Weg, auf dem wir von einem Problem erfahren.

## Weiterlesen

- [Offline-Karten und Routing](./offline-maps-and-routing)
- [Navigation mit Abbiegehinweisen](./navigation)
- [Fahrt aufzeichnen](./recording-a-ride)
- [Import und Export](./import-and-export)
- [Erste Schritte](./getting-started)
