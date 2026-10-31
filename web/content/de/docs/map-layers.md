---
title: Ebenen auf der Karte
description: Die Radkarte offline und ihre Teile, die Online-Radkarte, Regenradar, Wolken, Wind und die Stopps, alles im Fenster Ebenen.
order: 6
---

**Ebenen** sitzt in der Spalte rechts neben der Karte, im Tab Planen und im Tab Aufzeichnen. Das Fenster enthält die Radkarte, die Online-Radkarte, das Regenradar, die Wolken, den Wind und die Stopps. Die Schaltfläche ist hervorgehoben, solange eine davon an ist.

<!-- screenshot: layers -->

## Radkarte

**Radkarte**: "Radwege, Radstreifen und Radrouten aus deinen heruntergeladenen Gebieten · funktioniert offline · beim Hineinzoomen". Von der App aus den Routingdaten auf dem Handy gezeichnet, braucht also keine Verbindung, und nur dort, wo ein Gebiet heruntergeladen ist.

Die Radkarte blendet zwischen Zoomstufe 12 und 13 ein und beim Herauszoomen wieder aus. Sie zeichnet, was die Routingdaten über das Radfahren wissen. Ist sie an, klappt unter dem Schalter pro Teil ein Chip auf, jeder mit einem Muster seiner Linie als Legende. Tippe auf einen Chip, um den Teil ein- oder auszublenden; die Wahl bleibt erhalten. Pfeile und Punkte, die ab Zoomstufe 15 erscheinen, blenden in der Zoomstufe davor ein.

| Teil | Gezeichnet als |
| --- | --- |
| **Radwege & -streifen** | Radwege durchgehend blau, Fahrradstraßen mit hellem Band; Radwege an der Straße durchgehend, Radstreifen gestrichelt, am Straßenrand, bei größeren Straßen weiter außen. Geteilte Streifen (Busspuren, die Räder nutzen dürfen, nur mit Fahrradsymbolen markierte Streifen, Seitenstreifen, Gehwege, die Räder nutzen dürfen) als lockere hellblaue Striche neben der Straße. Zweirichtungs-Radwege sowie Zweirichtungs-Radwege und -streifen an der Straße sind breiter gezeichnet als Einrichtungs-Radwege |
| **Einbahn-Pfeile** | Pfeilspitzen im eigenen Blau der Spur zeigen die Fahrtrichtung: auf Radwegen und Wegen, die nur in eine Richtung befahren werden, ab Zoomstufe 15, und auf Einrichtungs-Radwegen und -streifen an der Straße ab etwa Zoomstufe 15,5 |
| **Gemeinsame Wege** | Mit Fußgängern geteilte Wege blaugrün gestrichelt, Gehwege, die Räder nutzen dürfen, grau-blau gepunktet |
| **Einbahnstraßen** | Eine graue Pfeilspitze in der Mitte von Straßen, die auch für Räder Einbahnstraßen sind, zeigt ab Zoomstufe 15 in Richtung des Verkehrs. Einbahnstraßen, die Räder in beide Richtungen befahren dürfen, zeigen stattdessen das zweifarbige Zeichen von **Gegenverkehr frei**. Wo ein Radstreifen oder Radweg daneben seine eigene Richtung zeigt, bekommt die Straße keine eigene Pfeilspitze |
| **Gegenverkehr frei** | Auf Einbahnstraßen, die Räder in beide Richtungen befahren dürfen, zeigt ab Zoomstufe 15 eine graue Pfeilspitze die Richtung des Verkehrs und eine blaue die der Räder dagegen |
| **Fernrouten**, **Regionale Routen**, **Lokale Routen** | Beschilderte Radrouten als violetter Hof, kräftiger je weiter die Route reicht |
| **Unbefestigt & holprig** | Schotter als ockerfarbene Striche, grobes Gelände für Mountainbikes als braune Striche, holpriges Pflaster mit roten Zacken |
| **Hindernisse & Treppen** | Tore, Poller und Stiegen als Punkte ab Zoomstufe 15; rot, wo das Rad getragen werden muss. Treppen als braune Sprossen ab Zoomstufe 15, mit einem blauen Streifen daneben, wo es eine Rampe für Räder gibt |
| **Ruhige Straßen** | Straßen nach Ruhe eingefärbt: Türkis für 30 km/h (20 mph) oder weniger, Grün für 20 km/h oder verkehrsberuhigte Bereiche, Hellgrün für Schrittgeschwindigkeit, leuchtendes Grün ohne Kfz-Verkehr; für Räder gesperrte Straßen grau |
| **Mountainbike** | Schwierigkeitsstriche auf Trails ab Zoomstufe 14: blau für leicht (S0–S1), rot für S2, schwarz für S3 und schwerer (auf der Nachtkarte weiß); Mountainbike-Routen als oranger Hof |
| **Steigungen** | Steile Stücke der für Räder erlaubten Wege als Band: gelb ab 6 %, orange ab 10 %, rot ab 15 %; Winkel zeigen ab Zoomstufe 15 bergauf. Die Höhen stammen aus dem Geländemodell in den Routingdaten. Eine Steigung zählt nur, wenn sie mindestens 150 m lang ist und 10 m Höhe überwindet; kurze Rampen fehlen deshalb. In Innenstädten mit hohen Gebäuden kann sie dennoch eine Steigung zeigen, die es nicht gibt, oder eine übersehen. Brücken und Tunnel bleiben ausgespart. In den dichten Kernen der größten Städte, wo die Höhen die der Gebäude sind, werden keine Steigungen gezeigt. |

Zu Beginn sind alle Teile an außer **Unbefestigt & holprig**, **Einbahnstraßen**, **Ruhige Straßen**, **Mountainbike** und **Steigungen**. Ein Teil, der in einer späteren Version dazukommt, startet mit seiner Voreinstellung; frühere Entscheidungen bleiben erhalten.

Im Tab Planen sagt ein Chip bei eingeschalteter Radkarte über einem nicht heruntergeladenen Gebiet **Keine Radkarte hier – Gebiet nicht heruntergeladen**, mit **Herunterladen**; ein Tipp öffnet den Download für das sichtbare Gebiet. Gilt auch der Chip der Stopps, steht er vorn.

## Online-Radkarte

**Online-Radkarte**: "Die Karte von CyclOSM mit Radläden und Abstellplätzen · braucht eine Verbindung". Das Overlay von CyclOSM, online geholt. Die beiden Radkarten wechseln sich ab: Schaltest du eine ein, geht die andere aus.

## Regenradar und Wolken

**Regenradar**: "Jetzt: Radar in Deutschland, den Niederlanden, Finnland und den USA, sonst in Europa und Afrika eine Schätzung aus Satellitendaten. Voraus: Radarprognose für 2 Stunden in Deutschland, Modellvorhersage bis 24 Stunden (in Europa stündlich, sonst alle 6 Stunden)". **Wolken**: "Europa, Afrika und Amerika · in Europa stündlich aktualisiert". Beide sind kostenlos, aus, bis du sie einschaltest, und brauchen eine Verbindung.

Der Regen kommt aus drei Arten von Quellen. Jetzt: Radar vom Deutschen Wetterdienst über Deutschland und seinen Nachbargebieten vom US-Wetterdienst (National Weather Service) über den USA, vom KNMI über den Niederlanden und vom Finnischen Meteorologischen Institut über Finnland, und rundherum, über dem übrigen Europa, Afrika und dem Atlantik, Regen, den H SAF von EUMETSAT aus dem Meteosat-Satelliten schätzt, alle zehn Minuten. Eine Schätzung aus Satellitendaten ist gröber als Radar und übersieht manchen leichten Regen; über den Gebieten der Radare wird sie nie gezeichnet, also widersprechen sich die beiden auf der Karte nie. Mit Velorki Plus tritt echtes Radar von EUMETNET OPERA, dem europäischen Radarverbund, und von Radar-DPC (Italien), dem Radar des italienischen Zivilschutzes, überall an die Stelle des Satelliten, wo es misst, etwa in Frankreich, Spanien, Italien, Großbritannien, der Schweiz und Skandinavien: 1-km-Zellen, alle fünf Minuten ein neues Bild, die letzten zwei Stunden, keine Prognose. Die nächsten zwei Stunden: in Deutschland die Radarprognose des Deutschen Wetterdiensts, der Regen des Radars in Viertelstunden weitergeschoben; überall sonst, und ab drei Stunden überall, die Vorhersage seines Wettermodells ICON, über Europa Stunde für Stunde und anderswo in Sechs-Stunden-Schritten. Alle fünf Minuten schaut die App nach neueren Bildern. Der Regen wird bei jedem Zoom gezeichnet, bis hinaus zur ganzen Welt, wo seine Bilder gröber sind. Wo das Gebiet des Radars endet, gehen das Radar und der Satellit oder die Vorhersage daneben über etwa 25 km ineinander über, statt hart aneinanderzustoßen.

Ist das Regenradar an, sitzt sein Zeitregler oben im Fenster von Planen und auf der Karte von Aufzeichnen, während einer Fahrt unter den Werten: ein Schieberegler von **Jetzt** in Viertelstunden bis zwei Stunden voraus, dann in Stunden bis 24 Stunden voraus. Seine Beschriftung nennt den Schritt, die Uhrzeit des Bilds über der Mitte der Karte und voraus, was es ist, etwa **Jetzt · 20:25**, **+45 min · 21:30 · Radarprognose** oder **+3 h · 23:00 · Vorhersage**. Während ein Schritt gezeigt wird, lädt die App die übrigen Schritte für den sichtbaren Ausschnitt im Hintergrund, die nächsten zwei Stunden zuerst; ziehst du den Regler, erscheint so jeder Schritt sofort. Ein Schritt, der noch nicht geladen ist, zeigt den nächsten, der es ist, und die Beschriftung sagt, welchen. Lässt du los, wird der Schritt geladen, falls er noch fehlt. Der Schritt ist in allen Tabs derselbe und springt auf **Jetzt** zurück, wenn die App nach mehr als einer halben Stunde wiederkommt. Die Bibliothek nennt die Uhrzeit in einer kleinen Beschriftung auf der Karte. Auf dem Reiter Plan ist derselbe Regler zugleich die Abfahrtszeit der Route: Er verschiebt auch das Wetter entlang der Route und ihre Einfärbung, siehe [Route planen](./planning-a-route).

Die Wolken sind Satellitenbilder, weiß über die Karte gezeichnet: Meteosat von EUMETSAT über Europa, Afrika und Umgebung, ein neues Bild zu jeder vollen Stunde, und die GOES-Satelliten über die NASA für Amerika. Sie reichen von 70° Süd bis 70° Nord, und wo sich zwei Satelliten überlappen, über dem Atlantik und dem östlichen Pazifik, geht der eine in den anderen über. Sie zeigen immer ihr neuestes Bild, wo auch immer der Regler des Regens steht; seine Uhrzeit steht im Fenster Ebenen unter dem Schalter **Wolken**, solange die Wolken an sind. Die dicksten, kältesten Wolken sind am hellsten; Nebel und tiefe Wolken erscheinen schwach oder gar nicht.

Antwortet ein Dienst nicht, sagt die Karte **Regenradar gerade nicht verfügbar**, **Regen vom Satelliten gerade nicht verfügbar**, **Regenvorhersage gerade nicht verfügbar** oder **Wolken gerade nicht verfügbar**, damit eine leere Karte nicht für einen trockenen, klaren Tag gehalten wird. Die App lädt die Bilder direkt beim Deutschen Wetterdienst, beim KNMI, beim Finnischen Meteorologischen Institut, bei NOAA, NASA und EUMETSAT, nicht über Velorki; diese Dienste sehen also den angefragten Kartenausschnitt. Nur das Radar von Velorki Plus, von OPERA und Radar-DPC (Italien), kommt über den Server von Velorki, der dann den angefragten Kartenausschnitt sieht. Ihre Quellenangaben stehen in der Zeile unten auf der Karte, solange eine Ebene gezeichnet ist.

## Wind

**Wind**: "Pfeile nach Stärke, weltweit · jetzt und bis 24 Stunden voraus (Modell, etwa 28 km)". Kostenlos, aus, bis du ihn einschaltest, und braucht eine Verbindung.

Pfeile über der Karte zeigen, wohin der Wind weht. Jeder ist ein langer, schmaler Pfeil mit voller Spitze, weiß umrandet, damit man ihn nicht für die Einbahnpfeile der Karte hält. Farbe und Größe wachsen mit seiner Stärke: ein kleiner grauer Pfeil bei Flaute (unter 2 m/s, 7 km/h), himmelblau ab 2 m/s, blau ab 5 m/s (18 km/h), violett ab 8 m/s (29 km/h) und magenta ab 11 m/s (40 km/h). Der Wind 10 m über dem Boden kommt aus dem globalen Wettermodell ICON des Deutschen Wetterdienstes, auf einem Gitter von etwa 28 km; er zeigt also den Wind der Gegend, nicht die Böe um eine Ecke oder hinter einer Hecke. Die Pfeile erscheinen bei jedem Zoom, bis hinaus zur ganzen Welt, etwa eine Fingerbreite auseinander, über Regen und Wolken.

Der Zeitregler des Regenradars bewegt auch den Wind, Stunde für Stunde: **Jetzt** ist die laufende Stunde. Ist nur der Wind an, erscheint der Regler allein, und seine Beschriftung nennt die Stunde des Winds, etwa **Jetzt · 20:00** oder **+3 h · 23:00 · Vorhersage**. Antwortet der Dienst nicht, sagt die Karte **Wind gerade nicht verfügbar**. Die App lädt den Wind wie den Regen direkt beim Deutschen Wetterdienst; seine Quellenangabe steht in der Zeile unten auf der Karte, solange die Pfeile gezeichnet sind.

## Stopps

**Stopps** ist ein Schalter im selben Fenster, aus, bis du ihn einschaltest. Er zeichnet Trinkwasser, Cafés, Toiletten, Fahrrad-Reparaturstationen und mehr aus dem Ortsindex auf dem Handy. Die Arten, das Gebiet, das du ansiehst, und die Route voraus stehen unter [Stopps auf der Karte](./stops-on-the-map).
