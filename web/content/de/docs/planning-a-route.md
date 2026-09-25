---
title: Route planen
description: Wegpunkte auf der Karte antippen, ein Radprofil wählen, Varianten vergleichen, Höhenprofil und Belag lesen und die Route in der Bibliothek speichern.
order: 2
---

Der Tab Planen macht aus Tippern auf der Karte eine Radroute, berechnet auf deinem Handy überall dort, wo du die Routing-Daten heruntergeladen hast. Nimm ihn, wenn du eine Fahrt vorher festlegen, anpassen und behalten willst.

## Start und Ziel setzen

1. Öffne den Tab **Planen** und verschiebe die Karte dorthin, wo du starten willst.
2. **Tippe auf die Karte**, um den Start zu setzen. Unten steht dann "Karte erneut antippen, um ein Ziel zu setzen."
3. **Tippe erneut** für den nächsten Punkt. Jeder Tipper hängt einen Punkt ans Ende der Route. Für einen Punkt mittendrin **tippe auf die Routenlinie**, wo er hin soll: Der Punkt landet dort auf der Linie, und du kannst ihn ziehen wie jeden anderen.
4. Velorki wartet nach deiner letzten Änderung einen Moment und berechnet dann. Währenddessen dreht sich unten ein Ladekreis mit **Route wird berechnet…**, danach erscheinen die Zahlen.

Du kannst auch von einem Ort aus starten statt mit einem Tipper. Tippe oben ins Suchfeld, wähle ein Ergebnis, und solange die Planung noch leer ist, erscheinen unter den Rad-Chips zwei Schaltflächen:

- **Von meiner Position** fährt von deinem Standort zum gesuchten Ort.
- **Hier starten** macht den gesuchten Ort zum ersten Punkt der Route.

Sobald eine Route geplant wird, hängt ein Suchergebnis den Ort einfach als nächsten Wegpunkt an. Was das Suchfeld alles findet, steht unter [Suche](./search).

## Einen Ort neben der Route markieren

**Halte die Karte gedrückt**, wo etwas Erinnernswertes liegt, und das Punktblatt öffnet sich für einen Ort dort: ein Brunnen, ein Bahnhof, ein Campingplatz. Die Route wird nicht dorthin gelegt. Die Markierung trägt das Symbol der gewählten Art, daneben ihren Namen, und ein Tippen darauf öffnet das Blatt wieder.

Um einen vorhandenen Punkt zu verschieben, **zieh seine Markierung**. Bei einer geschlossenen Runde verschiebt das Ziehen der Startmarkierung beide Enden, damit die Runde geschlossen bleibt. Eine Änderung berechnet nur die Abschnitte neben dem geänderten Punkt neu; der Rest der Route bleibt, wie er war.

## Auf der Route oder daneben

Jeder Punkt ist eines von beidem, und der Schalter oben in seinem Blatt sagt, was:

- **Auf der Route**: ein Punkt, durch den die Fahrt geht. Er trägt eine nummerierte Scheibe, und der Router legt die Route darüber.
- **Neben der Route**: ein Ort, an dem die Fahrt vorbeikommt. Er trägt das Symbol seiner Art, und die Route kümmert sich nicht um ihn.

Stellst du einen Punkt auf **Neben der Route**, verlässt er die Route, die ohne ihn neu gezeichnet wird; die Markierung bleibt, wo sie ist. Stellst du ihn auf **Auf der Route**, wird er ein Punkt dazwischen, an der Stelle der Route, an der er liegt, und die Route wird neu durch ihn gezeichnet. So oder so gehen Name, Art und Notiz mit.

## Einen Punkt ändern oder entfernen

Tippe auf eine Markierung, um ihr Blatt zu öffnen. Von oben:

- **Auf der Route** oder **Neben der Route**, der Schalter von oben,
- **Name**, mit dem Symbol der Art davor, vorbelegt mit dem Namen des Punkts oder, bei einem Punkt auf der Route ohne Namen, mit seiner Nummer; eine Nummer, die so stehen bleibt, benennt nichts. Ein Ort neben der Route öffnet sich mit leerem Namen,
- **Art**: ein Raster aus Kacheln, vier Reihen zu vier, bei jeder Breite alle auf einmal im Blick: **Gefahr**, **Wasser**, **Essen**, **Sonstiges**, **Gipfel**, **Aussicht**, **Unterstand**, **Laden**, **Fahrradwerkstatt**, **Erste Hilfe**, **Toilette**, **Campingplatz**, **Unterkunft**, **Parkplatz**, **Bahn/Fähre** und **Abbiegung**. **Unterkunft** ist ein Bett statt eines Stellplatzes: ein Hotel, ein Hostel, eine Pension. Eine **Abbiegung** bekommt darunter eine **Richtung** (links, rechts, leicht, scharf, links oder rechts halten, geradeaus, Wende) und wird eine Zeile der Abbiegeliste der Route, sodass Abbiegeband und Stimme sie dort sagen; eine mit Abbiegeliste importierte Route öffnet sich mit ihren geschriebenen Abbiegungen als Punkten dieser Art, bereit zum Ändern. **Abbiegung** gibt es nur für einen Punkt auf der Route: ein Hinweis für eine Straße, die die Fahrt nicht nimmt, sagt nichts,
- **Notiz**,
- **Früher anfahren** und **Später anfahren**, was den Punkt sofort mit seinem Nachbarn in der Reihenfolge tauscht und das Blatt offen lässt, sodass sich ein Punkt in einem Besuch verschieben und benennen lässt. Nur für einen Punkt auf der Route; ein Ort daneben hat keinen Platz in der Reihenfolge,
- **Punkt entfernen**, für beide Arten,
- **Fertig**, was Schalter, Name, Art und Notiz übernimmt. Zieh das Blatt nach unten, um sie zu lassen, wie sie waren.

Ein Tausch, ein Entfernen, ein Umstellen und ein Fertig, das etwas geändert hat, sind je ein Schritt zum Rückgängigmachen. Ein benannter Punkt auf der Route zeigt auf seiner Markierung seinen Namen statt seiner Nummer, daneben das Symbol seiner Art. Die Details werden mit der Route gespeichert und kommen zurück, wenn sie wieder im Planer geöffnet wird; bei einer aus der Bibliothek geöffneten Route landen sie sofort in der Bibliothek, solange die Route seitdem nicht neu berechnet wurde, für einen Namen oder eine Notiz allein gibt es also kein Speichern zu drücken.

## Was aus jedem Punkt in einer exportierten Datei wird

Beide Arten gehen hinaus, und ein Radcomputer unterscheidet sie, so gut das Format es zulässt:

- **GPX**: jeder Ort neben der Route und jeder Punkt auf der Route mit Namen oder Notiz wird als `<wpt>` mit Art und Notiz geschrieben. Die Punkte auf der Route sind außerdem die `<rtept>`-Liste, sodass sich die Datei wieder planen lässt.
- **FIT** und **TCX**: beide Arten werden zu Kurspunkten auf dem Kurs, neben den Abbiegungen der Abbiegeliste. FIT hat eine eigene Art für Wasser, Essen, Gefahr, Gipfel, Erste Hilfe, Toilette und Campingplatz; TCX nur für Wasser, Essen, Gefahr, Gipfel und Erste Hilfe. Unterkunft, Parkplatz und Bahn/Fähre haben in beiden keine Art und gehen als allgemeine Kurspunkte mit ihrem Namen hinaus. Alles andere geht als allgemeiner Kurspunkt mit seinem Namen hinaus.
- Ein Punkt aus einer Datei behält das Wort, das diese Datei für ihn benutzt hat. Exportierst du ihn wieder, ohne seine Art zu ändern, wird genau dieses Wort zurückgeschrieben, sodass eine Bergwertung, ein Sprint oder eine Segmentmarke — Dinge, für die Velorki keine eigene Art hat — die Runde übersteht. Änderst du die Art, wird stattdessen das Wort der neuen Art geschrieben.

## Das Rad wählen

Die Reihe von Chips unter dem Suchfeld ist das Radprofil, und sie entscheidet, welche Straßen und Wege der Router mag:

| Profil | Wofür es da ist |
|---|---|
| **Trekking** | die Voreinstellung: eine vernünftige Mischung aus ruhigen Straßen und Radwegen |
| **Rennrad** | Asphalt, weniger Umwege, meidet raue Beläge |
| **Gravel** | fühlt sich auf Wirtschaftswegen und unbefestigtem Untergrund wohl |
| **MTB** | Trails und Singletrails |
| **Direkt** | der kürzeste Weg, mit möglichst wenig Rücksicht auf Komfort |

Jedes Profil außer **Direkt** ist das von BRouter mit einer Änderung von Velorki: Es schickt dich nicht falsch herum durch eine Einbahnstraße oder über einen Gehweg, um einen Block zu sparen. Ein Profilwechsel berechnet die ganze Planung neu, auch eine Route aus einer Datei, und verwirft geladene Varianten; **Rückgängig** holt Route und Profil zurück. Das zuletzt gewählte Profil behält Velorki für den nächsten Start.

## Eine Route aus einer Datei

Eine aus einer Datei geöffnete Route behält die Linie der Datei genau, mit Punkten nur am Start, am Ziel und an den benannten Orten auf dem Track. Ein Punkt verschoben, hinzugefügt oder entfernt berechnet nur die Abschnitte daneben neu; überall sonst bleibt die Linie die der Datei. Solange die Route von der Datei abweicht, liegt die Linie der Datei blass darunter, und ein Chip über der Karte sagt **Weicht von der Datei ab**; sein **Wiederherstellen** holt die Route der Datei zurück, in einem Schritt, den Rückgängig zurücknehmen kann.

## Die Leiste

Die Reihe von Schaltflächen in der Routenübersicht:

- **Rückgängig** nimmt die letzte Änderung zurück. Es gibt keine Grenze und kein Wiederherstellen. Punkte hinzufügen, einfügen, verschieben, entfernen und umsortieren, **Umkehren**, **Leeren**, ein Profilwechsel, **Wiederherstellen**, das Schließen einer Runde und ein anderer Rückweg lassen sich rückgängig machen; ein Variantenwechsel und das Laden einer gespeicherten Route nicht.
- **Umkehren** fährt die Route andersherum.
- **Leeren** wirft die Planung weg. Auch das lässt sich rückgängig machen.
- **Varianten** fragt Alternativen an (siehe unten).
- **Runde** öffnet das Fenster für smarte Runden, beschrieben unter [Runden](./loops).
- **Fragen** öffnet den [Assistenten](./assistant). Es ist nur da, wenn der Build mit einem Velorki-Server spricht.

Unter der Reihe sitzt die Schaltfläche **Speichern** über die volle Breite.

## Varianten

Velorki holt Alternativen nicht von selbst, weil jede davon ein eigener Routing-Lauf ist. Tippe auf **Varianten**, und die App fragt bis zu vier Routen für dieselben Punkte an.

Über der Leiste erscheint dann eine Chip-Reihe: **Hauptroute**, **Alt 1**, **Alt 2**, **Alt 3**, jede mit einem farbigen Punkt passend zu ihrer Linie auf der Karte. Ein Tipper auf einen Chip wechselt sofort, ohne neue Berechnung, und legt diese Linie nach oben.

Varianten sind ganze Routen des Routers, auf einer Route aus einer Datei ersetzen sie also deren Linie; **Rückgängig** holt sie zurück. Oft kommen weniger als vier zurück; du bekommst, was der Router gefunden hat. Findet er nichts, sagt Velorki "Keine Alternativen verfügbar." Ein geänderter Wegpunkt oder ein Profilwechsel verwirft die Varianten, frag danach also erneut an.

## Die Route lesen

Der Kopf der Übersicht zeigt vier Zahlen: **Distanz**, **Anstieg**, **Abstieg** und **Dauer**. Die geschätzte Dauer kommt aus dem typischen Tempo des gewählten Radprofils, nicht von einem Server, und sie rechnet keine Café-Pausen ein.

Die Übersicht scrollt in jeder Höhe; zieh ihren Griff oder ihren Titel nach oben für mehr Platz, oder sie selbst, wenn es nichts zu scrollen gibt. Ganz nach unten gezogen faltet sie sich in die Navigationsleiste und lässt nur den Griff über den Tabs, damit die Karte frei ist; zieh den Griff nach oben, um sie zurückzuholen.

### Höhenprofil

Das Diagramm **Höhenprofil** zeichnet die Höhe über der Distanz. Berühre es und zieh darüber: Neben der Beschriftung erscheint eine Anzeige in der Form `12,3 km · 340 m`, die deinem Finger folgt. Nimmst du ihn weg, verschwindet sie. Eine Route ohne Höhendaten sagt "Keine Höhendaten für diese Route."

### Belag

Der Balken **Belag** ist ein einzelner gestapelter Balken aus drei Anteilen, die zusammen die ganze Route ergeben: **Befestigt**, **Unbefestigt** und **Unbekannt**, mit einer Legende mit Prozentwerten darunter. Zwei weitere Einträge in der Legende, **Radweg** und **Stark befahren**, überlagern die ersten drei, statt sich dazuzuaddieren: Sie sagen dir, wie viel der Route auf einem eigenen Radweg liegt und wie viel auf einer großen Straße. Ist die Route nicht ganz die des Routers, etwa mit der Linie einer Datei darin, wird für die Zahlen die ganze Linie über die Routing-Daten gelegt; dafür muss die Region geladen sein.

## Speichern

1. Tippe auf **Speichern**.
2. Der Dialog **Route speichern** schlägt einen Namen vor, entweder den, unter dem sie schon einmal gespeichert war, oder **Route 17. Sept. 2026** mit dem heutigen Datum.
3. Tippe einen eigenen Namen ein oder lass ihn stehen, dann tippe auf **Speichern**.

Du bekommst "Route gespeichert", und die Route liegt unter **Bibliothek → Routen**. Speicherst du eine bereits gespeicherte Route, wird derselbe Eintrag aktualisiert statt ein zweiter angelegt.

## Wenn keine Route zustande kommt

- **"Diese Route braucht Routing-Kacheln, die nicht auf diesem Gerät sind."** erscheint anstelle der Zahlen, wenn dein Handy keine Routing-Daten für das Gebiet hat und kein Routing-Server einspringen kann. Die Schaltfläche darunter zählt die Kacheln und ihre Größe, zum Beispiel **3 Kacheln herunterladen (412 MB)**, und öffnet den Offline-Bildschirm mit genau diesen Kacheln ausgewählt. Siehe [Offline-Karten und Routing](./offline-maps-and-routing).
- **"Kein Routing-Server konfiguriert, einen unter Einstellungen → Erweitert festlegen."** ist eine Karte unter den Rad-Chips und heißt, dass dieser Build gar keine Serveradresse hat.
- Alles andere erscheint als **Routing fehlgeschlagen:** mit dem Grund.

## Weiterlesen

- [Runden](./loops)
- [Suche](./search)
- [Offline-Karten und Routing](./offline-maps-and-routing)
- [Bibliothek](./library)
- [Navigation mit Abbiegehinweisen](./navigation)
