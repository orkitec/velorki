---
title: Suche
description: Orte, Straßen, Hausnummern und Dinge wie Trinkwasser oder Toiletten finden, auf dem Handy in heruntergeladenen Gebieten und überall sonst online.
order: 4
---

Das Suchfeld oben im Tab Planen findet Städte, Straßen, Hausnummern und Ziele wie Cafés, Trinkwasser und Fahrradläden. Wo du ein Gebiet heruntergeladen hast, antwortet es vom Handy, sofort und ohne Empfang; überall sonst fragt es einen Online-Geocoder.

## So suchst du

1. Öffne den Tab **Planen** und tippe oben ins Feld mit dem Hinweis **Ort suchen**.
2. Tippe mindestens drei Zeichen ein. Die Ergebnisse erscheinen während des Tippens in einer Karte unter dem Feld.
3. Tippe auf ein Ergebnis.

Was dann passiert, hängt von der Planung ab:

- **Noch nichts geplant**: Die Karte fährt zum Ort und setzt eine Nadel, und unter den Rad-Chips erscheinen zwei Schaltflächen, **Von meiner Position** und **Hier starten**.
- **Eine Route wird schon geplant**: Der Ort wird direkt als nächster Wegpunkt angehängt.

Das **X** im Feld löscht den Text, die Nadel und die beiden Schaltflächen.

## Offline oder online

Velorki entscheidet nach der **Kartenmitte**, nicht nach deiner Verbindung. Jede heruntergeladene Routing-Kachel bringt einen Suchindex ihres Gebiets mit, also:

- liegt der Index der Kachel unter der Kartenmitte auf dem Handy, wird die Anfrage auf dem Handy beantwortet;
- liegt er nicht dort, geht die Anfrage online an Photon.

Ganz unten in der Ergebniskarte steht genau eine Zeile, und welche es ist, verrät dir, woher die Ergebnisse kommen:

| Zeile | Bedeutet | Ein Tipper darauf |
|---|---|---|
| **Online nach „…“ suchen** | du siehst Offline-Ergebnisse | sucht denselben Text online |
| **Offline-Ergebnisse anzeigen** | du siehst Online-Ergebnisse | sucht denselben Text wieder auf dem Handy |
| **Gebiet herunterladen, um offline zu suchen** | für dieses Gebiet liegt kein Index auf dem Handy | öffnet den Offline-Bildschirm für das sichtbare Gebiet |

Diese Zeile bleibt beim Scrollen durch die Liste sichtbar, und sie steht auch unter einer Fehlermeldung, wo sie am meisten zählt.

## Was sie findet

- **Orte**: Städte, Kleinstädte, Dörfer, Weiler, Stadtteile, Viertel, Ortslagen und Inseln.
- **Straßen**, mit Hausnummern.
- **Sonderziele**, jedes mit eigenem Symbol und eigener Beschriftung: Café, Trinkwasser, Toiletten, Fahrrad-Reparaturstation, Fahrradladen, Fahrradverleih, Fahrradparkplatz, E-Bike-Ladestation, Schutzhütte, Campingplatz, Hotel, Hostel, Berghütte, Supermarkt, Bäckerei, Apotheke, Picknickplatz, Bahnhof, Fähranleger, Flughafen, Aussichtspunkt, Gipfel, Pass, Park, Strand, Gewässer, Naturschutzgebiet, Sehenswürdigkeit, Museum, Historische Stätte, Gotteshaus, Krankenhaus, Universität, Sportstätte, Einkaufszentrum, Turm, Leuchtturm, Gebäude.

Offline-Zeilen zeigen unter dem Namen die Art, die Entfernung, die Hausnummer und den Ort, in dieser Reihenfolge, soweit jeweils bekannt: "Trinkwasser · 350 m", "Straße · 400 · Manhattan". Ein Wasserhahn, eine Toilette, eine Schutzhütte oder ein Fahrradständer ohne eigenen Namen steht stattdessen unter seiner Art.

## Nach Art suchen

Tippe den Namen einer Art ein statt den Namen eines Orts. "Trinkwasser", "Bäckerei", "Toiletten" und alle anderen funktionieren, in der Sprache, in der die App läuft.

Die Liste beginnt dann mit den fünf nächstgelegenen dieser Art rund um die Kartenmitte, jede mit ihrer Entfernung, und die gewöhnlichen Namenstreffer folgen darunter. Velorki schaut in einem Kasten nach, der von 5 auf 50 km um die Kartenmitte wächst, bis es genug hat. Das ist der schnelle Weg zur Antwort auf "wo ist der nächste Wasserhahn" mitten in einer Fahrt.

Eine Suche nach Art ignoriert die unten beschriebenen Gruppenschalter.

## Hausnummern

Setz die Nummer an den Anfang oder ans Ende: "Hauptstraße 12", "400 W 42nd". Velorki nimmt die Nummer weg, sucht die Straße und antwortet an der Position der Nummer entlang dieser Straße.

Kennt der Index genau diese Nummer, ist die Position exakt. Fällt die Nummer zwischen zwei bekannte, rechnet Velorki dazwischen und kennzeichnet die Zeile mit **≈ 400**, damit du die Schätzung erkennst. Eine Nummer mitten in der Anfrage gilt als Teil des Namens, ebenso eine Ordnungszahl wie "42nd".

## Tippfehler

Findet eine Anfrage überhaupt nichts, nimmt Velorki die Wörter, die es nicht kennt, sucht im Index die wahrscheinlichsten Wörter, die ein oder zwei Buchstaben entfernt liegen, und sucht erneut. Die Karte sagt dann **Ergebnisse für „…“** über der Liste, mit dem, wonach tatsächlich gesucht wurde.

## Die Gruppen sortieren

Offline-Ergebnisse sind gruppiert, und du entscheidest, welche Gruppen erscheinen und in welcher Reihenfolge.

1. Öffne **Einstellungen**.
2. Tippe auf **Suche**, mit dem Untertitel "Was die Offline-Suche zeigt und in welcher Reihenfolge. Zum Ändern der Priorität ziehen."
3. Zieh eine Zeile an ihrem Griff nach oben oder unten. Mit dem Schalter rechts schaltest du eine Gruppe aus.

Die acht Gruppen in ihrer voreingestellten Reihenfolge: **Orte**, **Straßen und Adressen**, **Sehenswürdigkeiten**, **Stopps unterwegs**, **Übernachten**, **Natur**, **Verkehr**, **Einrichtungen**.

Es gibt keine Schaltfläche zum Speichern; die Änderungen greifen beim nächsten Tastendruck. Eine ausgeschaltete Gruppe verschwindet aus den Namenstreffern, und die Reihenfolge entscheidet bei Ergebnissen, die gleich gut zum Text passen.

## Wenn die Suche nicht funktioniert

- **"Nichts gefunden."** Der Text passte zu nichts, weder offline noch online. Nimm die Zeile am Ende, um die Quelle zu wechseln, oder weniger Wörter.
- **"Suche fehlgeschlagen."** mit einem Grund heißt, dass der Online-Geocoder nicht erreichbar war. Die Offline-Suche läuft weiter, wo du ein Gebiet heruntergeladen hast.
- **"Kein Suchserver konfiguriert, einen unter Einstellungen → Erweitert festlegen."** heißt, dass dieser Build weder eine Geocoder-Adresse noch einen heruntergeladenen Index hat. Das Feld ist gesperrt, bis es eines von beidem gibt.

## Weiterlesen

- [Offline-Karten und Routing](./offline-maps-and-routing)
- [Route planen](./planning-a-route)
- [Einstellungen und Darstellung](./settings-and-appearance)
- [Datenschutz auf dem Handy](./privacy-on-the-phone)
