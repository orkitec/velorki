---
title: Suche
description: Orte, Straßen, Hausnummern und Dinge wie Trinkwasser oder Toiletten finden, auf dem Handy in heruntergeladenen Gebieten und online, wenn du es wählst.
order: 4
---

Das Suchfeld oben im Tab Planen findet Städte, Straßen, Hausnummern und Ziele wie Cafés, Trinkwasser und Fahrradläden. Über einem heruntergeladenen Gebiet antwortet es vom Handy, sofort und ohne Empfang; über einem nicht heruntergeladenen Gebiet wählst du zwischen einem Online-Geocoder und den Gebieten, die du heruntergeladen hast.

## So suchst du

1. Öffne den Tab **Planen** und tippe oben ins Feld mit dem Hinweis **Ort suchen**.
2. Tippe mindestens drei Zeichen ein. Die Ergebnisse erscheinen während des Tippens in einer Karte unter dem Feld.
3. Tippe auf ein Ergebnis. Die Karte fährt zum Ort, setzt eine Nadel und öffnet seine Ortskarte.

Koordinaten, die du ins Feld tippst oder einfügst, `40.71747, -73.94840` oder `40,71747° N, 73,94840° W`, wie Karten-Apps sie kopieren, sind der Ort selbst: ein Ergebnis an dieser Stelle, nichts wird nachgeschlagen und nichts gesendet. Ein Ort aus einer anderen App öffnet sich genauso, siehe [Import und Export](./import-and-export#ein-ort-aus-einer-anderen-app).

## Die Ortskarte

Ein Suchergebnis, ein [Stopp auf der Karte](./stops-on-the-map) oder ein Ort aus einer anderen App öffnet eine Karte mit dem Namen des Orts, was er ist, seinem Ort, wie weit er von dir entfernt ist und, wenn es eine Route gibt, wie weit neben der Route. Nichts ändert sich, bis du eine Aktion wählst, und welche es gibt, hängt von der Planung ab:

- **Noch nichts geplant**: **Route hierher** fährt von deinem Standort zum Ort; **Hier starten** macht ihn zum ersten Punkt der Route.
- **Nur ein Start**: **Als Ziel** macht ihn zum Ende der Route.
- **Eine Route**: **Als Stopp einfügen** setzt ihn dort in die Route, wo er unterwegs liegt; **Als Ziel** hängt ihn ans Ende.

Im Tab Aufnahme informiert die Karte nur, ohne Aktionen.

Darunter:

- **Details** holt den Ort von OpenStreetMap, nur wenn du darauf tippst: Öffnungszeiten und ob gerade geöffnet ist, Website, Telefonnummer, Küche, Rollstuhlzugang, Außensitzplätze und seinen Wikipedia-Artikel, soweit sie eingetragen sind. Die Details bleiben eine Woche auf dem Handy, der Ort zeigt sie beim nächsten Mal also sofort. Bei Straßen und Orten ohne OpenStreetMap-ID fehlt die Schaltfläche.
- **Öffnen in…** zeigt den Ort in Apple Karten, in Google Maps, wenn installiert (iPhone), in einer Karten-App deiner Wahl (Android) oder im Browser auf OpenStreetMap, oder reicht ihn an **Teilen…** weiter.

Die Ortskarte zu schließen (das **X**, nach unten wischen oder auf die Karte tippen) ändert nichts und leert die Suche.

## Offline oder online

Velorki entscheidet nach der **Kartenmitte**, nicht nach deiner Verbindung. Jede heruntergeladene Routing-Kachel bringt einen Suchindex ihres Gebiets mit.

- **Kartenmitte über einem heruntergeladenen Gebiet**: Die Anfrage wird auf dem Handy beantwortet. Die letzte Zeile der Ergebniskarte, **Online nach „…“ suchen**, sucht denselben Text online.
- **Kartenmitte über einem nicht heruntergeladenen Gebiet, während andere heruntergeladen sind**: Es wird nichts gesucht und nichts verlässt das Handy, bis du wählst. Die Liste zeigt einen Hinweis, **Dieses Gebiet ist nicht heruntergeladen**, eine Zeile mit dem Grund und die Schaltfläche **Herunterladen**, die den Offline-Bildschirm für das sichtbare Gebiet öffnet, dazu zwei Möglichkeiten: **Online nach „…“ suchen** und **In heruntergeladenen Gebieten suchen**, was jedes heruntergeladene Gebiet durchsucht, das der Karte nächste zuerst. Deine Wahl gilt für die folgenden Tastendrücke, bis du die Suche leerst. Online-Ergebnisse stehen unter der Überschrift **Online-Ergebnisse**, und die letzte Zeile, **Offline-Ergebnisse anzeigen**, wechselt zu den heruntergeladenen Gebieten; Ergebnisse vom Handy enden mit **Online nach „…“ suchen**.
- **Gar nichts heruntergeladen**: Die Suche geht gleich online, mit dem Hinweis oben.
- **Keine Online-Suche eingerichtet**: Die heruntergeladenen Gebiete antworten.
- **Keine Kartenmitte**: online.

Der Hinweis bleibt beim Scrollen durch die Liste sichtbar, und ist die Suche fehlgeschlagen, steht er über der Fehlermeldung, wo er am meisten zählt.

## Was sie findet

- **Orte**: Städte, Kleinstädte, Dörfer, Weiler, Stadtteile, Viertel, Ortslagen und Inseln.
- **Straßen**, mit Hausnummern.
- **Sonderziele**, jedes mit eigenem Symbol und eigener Beschriftung: Café, Restaurant, Imbiss, Eisdiele, Tankstelle, Luftpumpe, Trinkwasser, Toiletten, Fahrrad-Reparaturstation, Fahrradladen, Fahrradverleih, Fahrradparkplatz, E-Bike-Ladestation, Schutzhütte, Campingplatz, Hotel, Hostel, Berghütte, Supermarkt, Bäckerei, Apotheke, Picknickplatz, Bahnhof, Fähranleger, Flughafen, Aussichtspunkt, Gipfel, Pass, Park, Strand, Gewässer, Naturschutzgebiet, Sehenswürdigkeit, Museum, Historische Stätte, Gotteshaus, Krankenhaus, Universität, Sportstätte, Einkaufszentrum, Turm, Leuchtturm, Gebäude.
- **Bekannte Orte in deiner Sprache**: „Parigi“ findet Paris, und eine berühmte Sehenswürdigkeit kommt vor ihren Namensvettern.

Offline-Zeilen zeigen unter dem Namen die Art, die Entfernung und den Ort, soweit jeweils bekannt: "Trinkwasser · 350 m", "Straße · Manhattan". Ein Wasserhahn, eine Toilette, eine Schutzhütte oder ein Fahrradständer ohne eigenen Namen steht stattdessen unter seiner Art.

## Nach Art suchen

Tippe den Namen einer Art ein statt den Namen eines Orts. "Trinkwasser", "Bäckerei", "Toiletten" und alle anderen funktionieren, in der Sprache, in der die App läuft.

Die Liste beginnt dann mit den fünf nächstgelegenen dieser Art rund um die Kartenmitte, jede mit ihrer Entfernung, und die gewöhnlichen Namenstreffer folgen darunter. Velorki schaut in einem Kasten nach, der von 5 auf 50 km um die Kartenmitte wächst, bis es genug hat. Das ist der schnelle Weg zur Antwort auf "wo ist der nächste Wasserhahn" mitten in einer Fahrt.

Eine Suche nach Art ignoriert die unten beschriebenen Gruppenschalter.

## Hausnummern

Tipp die Nummer dorthin, wo dein Land sie hinsetzt: "Hauptstraße 12", "400 W 42nd", "Via Roma 12/A", "Budapest, Fő utca 12". Velorki findet die Straße und antwortet an der Position der Nummer entlang dieser Straße; die Zeile ist die Adresse, wie du sie getippt hast, "400 West 42nd Street". Ein Ort vor der Straße mit Komma oder dahinter sagt, welche Straße gemeint ist. Eine Postleitzahl bleibt außen vor, und eine Nummer, die zum Namen einer Straße gehört, "Route 66", bleibt Teil des Namens.

Fällt die Nummer zwischen zwei, die der Index kennt, schätzt Velorki ihre Position, und die Zeile sagt **≈ 400**, damit du siehst, dass es geraten ist.

## Tippfehler, Kurzformen und andere Schriften

Die Offline-Suche verzeiht ein oder zwei falsche Buchstaben, ein zusammen oder getrennt geschriebenes Wort und Kurzformen wie "St" oder "Str.". Namen in Kyrillisch oder Griechisch lassen sich in lateinischen Buchstaben tippen, "aleksandar nevski" oder "Nafplio". Antwortet nichts gut, probiert Velorki stattdessen die wahrscheinlichsten Wörter aus dem Index, und die Karte sagt **Ergebnisse für „…“** über der Liste, mit dem, wonach tatsächlich gesucht wurde.

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

- [Stopps auf der Karte](./stops-on-the-map)
- [Offline-Karten und Routing](./offline-maps-and-routing)
- [Route planen](./planning-a-route)
- [Einstellungen und Darstellung](./settings-and-appearance)
- [Datenschutz auf dem Handy](./privacy-on-the-phone)
