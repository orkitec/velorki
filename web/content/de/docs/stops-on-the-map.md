---
title: Stopps auf der Karte
description: Trinkwasser, Cafés, Toiletten, Fahrradwerkstätten und andere Stopps auf der Karte zeigen, im Gebiet, das du ansiehst, oder entlang der Route voraus, und die Radkarte einschalten.
order: 5
---

Velorki kann die Orte, an denen eine Fahrt hält, auf der Karte zeichnen: Trinkwasser, Cafés, Bäckereien, Toiletten, Fahrrad-Reparaturstationen und mehr. Sie kommen aus dem Ortsindex der Routing-Daten auf dem Handy, brauchen also das heruntergeladene Gebiet (siehe [Offline-Karten und Routing](./offline-maps-and-routing)), funktionieren ohne Empfang und senden nichts irgendwohin.

## Die Schaltfläche Ebenen

**Ebenen** sitzt in der Spalte rechts neben der Karte, im Tab Planen und im Tab Aufnahme. Das Fenster enthält:

- **Radkarte**: "Radwege, Radstreifen und Radrouten aus deinen heruntergeladenen Gebieten · funktioniert offline · beim Hineinzoomen". Von der App aus den Routingdaten auf dem Handy gezeichnet, braucht also keine Verbindung, und nur dort, wo ein Gebiet heruntergeladen ist. Ihre Teile klappen unter dem Schalter auf, siehe [die Radkarte](#die-radkarte).
- **Online-Radkarte**: "Die Karte von CyclOSM mit Radläden und Abstellplätzen · braucht eine Verbindung". Das Overlay von CyclOSM, online geholt. Die beiden Radkarten wechseln sich ab: Schaltest du eine ein, geht die andere aus.
- **Stopps**, ein Schalter, aus, bis du ihn einschaltest. Darunter die Arten, die gezeigt werden, nach Gruppen: **Stopps unterwegs**, **Übernachten** und **Sehenswürdigkeiten**. Tippe auf eine Art, um sie zu zeigen oder zu verbergen. Beim ersten Mal sind Trinkwasser, Cafés, Bäckereien, Toiletten und Fahrrad-Reparaturstationen gewählt. Bei ausgeschaltetem Schalter klappen die Arten ein; deine Wahl bleibt für das nächste Mal.

Die Schaltfläche ist hervorgehoben, solange die Radkarte, die Online-Radkarte oder die Stopps an sind.

## Die Radkarte

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

Zu Beginn sind alle Teile an außer **Unbefestigt & holprig**, **Einbahnstraßen**, **Ruhige Straßen** und **Mountainbike**. Ein Teil, der in einer späteren Version dazukommt, startet mit seiner Voreinstellung; frühere Entscheidungen bleiben erhalten.

Im Tab Planen sagt ein Chip bei eingeschalteter Radkarte über einem nicht heruntergeladenen Gebiet **Keine Radkarte hier – Gebiet nicht heruntergeladen**, mit **Herunterladen**; ein Tipp öffnet den Download für das sichtbare Gebiet. Gilt auch der Chip der Stopps, steht er vorn.

## Im Gebiet, das du ansiehst

Mit **Stopps** an erscheinen die Stopps im sichtbaren Teil der Karte ab Zoomstufe 11. Weiter draußen werden nahe Stopps zu Blasen mit einer Zahl zusammengefasst; ab Zoomstufe 15 lösen sie sich in einzelne Stopps mit ihren Symbolen auf. Tippe auf eine Blase, um dorthin zu zoomen, wo sie sich auflöst.

Weiter draußen als das sagt ein Chip **Hineinzoomen, um Stopps zu sehen**; tippe darauf, und die Karte zoomt dorthin, wo sie sichtbar sind.

Ist das Gebiet nicht heruntergeladen, steht stattdessen **Keine Stopps hier – Gebiet nicht heruntergeladen** mit **Herunterladen** da; ein Tipper öffnet den Download für das sichtbare Gebiet.

## Entlang der Route voraus

Ist im Tab Aufnahme unter **Einer Route folgen** eine Route gewählt, sind die Stopps die höchstens 300 m neben der Route, die noch vor dir liegt, bis zu 50 km weit, bei jeder Zoomstufe. Eine Zeile über der Karte nennt den nächsten jeder Art mit seiner Entfernung entlang der Route, "Trinkwasser · 2,4 km"; tippe auf einen Eintrag, um den Stopp auf der Karte zu sehen. Folgt die Karte dir auf einer Fahrt, bleibt sie bei dir und der Stopp wird nur hervorgehoben.

Ist von den nächsten 50 km der Route nichts heruntergeladen, tritt derselbe Chip an die Stelle dieser Zeile.

**Entlang der Route** und **In diesem Gebiet** im Fenster Ebenen wechseln zwischen beiden.

## Einen Stopp antippen

Ein Stopp öffnet seine Ortskarte, dieselbe Karte, die ein Suchergebnis öffnet: Name, Art, Ort, wie weit von dir und, mit einer Route, wie weit daneben. Im Tab Planen bietet sie an, was sich mit dem Ort tun lässt, **Route hierher**, **Hier starten**, **Als Stopp einfügen** oder **Als Ziel**; im Tab Aufnahme informiert sie nur. **Details** und **Öffnen in…** gibt es in beiden. Siehe [die Ortskarte](./search#die-ortskarte).

## Weiterlesen

- [Suche](./search)
- [Route planen](./planning-a-route)
- [Navigation mit Abbiegehinweisen](./navigation)
- [Offline-Karten und Routing](./offline-maps-and-routing)
