---
title: Datenschutz auf dem Handy
description: "Klartext für Radfahrende: Was auf deinem Handy bleibt, was es verlässt, wann und an wen. Es gibt kein Konto, und nichts geht ungefragt hoch."
order: 15
---

Velorki hat kein Konto, es gibt also nichts, wo man sich anmeldet, und nichts über dich auf einem Server. Diese Seite ist die Fassung in Klartext, was das in der Praxis heißt; die [Datenschutzerklärung](/privacy) ist die förmliche.

## Was auf dem Handy bleibt

Alles, was du machst, und alles, was du herunterlädst:

- geplante Routen, aufgezeichnete Fahrten und ihre GPS-Tracks,
- deine Einstellungen, auch die gewählten Einheiten und die gewählte Stimme sowie Gewicht, Geburtsjahr, Geschlecht, Maximalpuls, Gewicht des Rads, Radtyp und Schwellenleistung, die du unter Einstellungen → Fahrer eintragen kannst; sie sind Einstellungen auf dem Handy und werden nirgendwohin gesendet,
- heruntergeladene Offline-Kartengebiete,
- heruntergeladene Routing-Kacheln und die Ortssuch-Indizes, die mitkommen,
- die Zugriffstoken für Strava und Ride with GPS, falls du sie verbindest, die in den sicheren Speicher des Handys wandern, in einer Form, die nur der Velorki-Relay öffnen kann.

Nichts davon geht irgendwohin hoch, außer du forderst es an.

Unter Android ist Velorki bewusst aus Googles Cloud-Sicherung und aus der Übertragung von Gerät zu Gerät ausgenommen, deine Fahrten werden also auch vom System nicht vom Handy kopiert. Der Umzug auf ein neues Handy heißt, das Gewünschte als GPX- oder FIT-Datei zu exportieren, siehe [Import und Export](./import-and-export).

## Was das Handy verlässt und wann

### Während du auf die Karte schaust

Kartenkacheln werden von OpenFreeMap geholt, und von CyclOSM, wenn du das Rad-Overlay einschaltest. Eine Kachel anzufragen verrät dem Kachelserver, welches Quadrat der Welt du gerade ansiehst, und umfasst deine IP-Adresse, wie jede Anfrage. Ein heruntergeladenes Gebiet kommt vom Handy und fragt nach nichts.

### Während du planst

Das Routing läuft auf deinem Handy, wo immer du die Routing-Kacheln hast. Für ein Gebiet ohne Download gehen die Wegpunkte an einen Routing-Server, der die Route zurückschickt. Er bekommt die Wegpunkte und sonst nichts: keine Identität, keine anderen Routen, keine Fahrten.

**Einstellungen → Erweitert → Routing → Nur auf dem Gerät** schaltet den Server ganz ab; Velorki bietet dann den Download an, statt zu berechnen.

### Während du suchst

Die Suche wird auf dem Handy beantwortet, wo immer der Index des Gebiets heruntergeladen ist, und nichts von dem, was du tippst, verlässt das Gerät.

Sie geht online, wenn du auf **Online nach „…“ suchen** tippst, oder wenn du für das angesehene Gebiet keinen Index hast. Dann geht dein Text an Photon, zusammen mit einer groben Position, damit nahe Ergebnisse zuerst kommen.

### Während du aufzeichnest

Gar nichts verlässt das Handy. Aufnahme, Statistik, Diagramme und Splits werden alle auf dem Gerät berechnet. Dasselbe gilt für Puls, Trittfrequenz und Leistung von einer Uhr, einem Bluetooth-Sensor oder deiner Health-App: Sie werden mit der Fahrt gespeichert und, wenn du Health eingeschaltet hast, auf dem Handy selbst mit Apple Health oder Health Connect ausgetauscht.

### Wenn du den Assistenten fragst

Nur mit deiner Zustimmung und nur, was du erlaubt hast: dein Text, auf Wunsch eine auf etwa einen Kilometer gerundete Position, deine Sprach- und Einheiteneinstellung. Kein Name, kein Konto, keine Routenhistorie, und niemals dein Track. Siehe [Assistent](./assistant).

### Wenn du Strava oder Ride with GPS verbindest

An keinen der beiden geht etwas, bevor du das Konto verbunden und dann etwas angefordert hast, einen Upload oder einen Import.

Beim Verbinden geht ein Einmalcode an den Velorki-Relay, der ihn mit unserem Anwendungsgeheimnis in einen Zugriffstoken tauscht und den Token deinem Handy verschlüsselt gibt, sodass nur der Relay ihn öffnen kann. Wir behalten den Token nicht. Danach läuft jeder Upload und jeder Import über den Relay: Er prüft dein Abo, zählt die Übertragung, öffnet den Token für diese eine Anfrage und leitet sie an Strava oder Ride with GPS weiter. Er behält weder die Datei noch den Token und kann den Token allein nicht verwenden.

### Wenn du einen Teilen-Link machst

Diese Route oder Fahrt wird mit ihrem Track, ihrem Namen und ihren Zahlen auf unseren Server kopiert, damit sich der Link öffnen lässt. Der Link ist für jeden offen, der ihn hat, er zeigt, wo der Track beginnt und endet, und er wird nach einem Jahr automatisch gelöscht. Siehe [Teilen](./sharing).

### Wenn du Velorki Plus kaufst

Der Store wickelt die Zahlung ab, und wir sehen deine Karte nie. Das Abo wird gegen eine anonyme Zufalls-ID geprüft, die weder mit einem Namen noch mit einer E-Mail-Adresse noch mit einer Gerätekennung verknüpft ist.

## Was Velorki nie tut

- Kein Konto, keine Registrierung, keine E-Mail-Adresse.
- Keine Werbung, kein Werbe-SDK, keine Profilbildung.
- Zum jetzigen Zeitpunkt kein Analyse- oder Absturzbericht-SDK in der App. Kommt je eines dazu, wird die Datenschutzerklärung es beim Namen nennen und sagen, was es erhebt, bevor es ausgeliefert wird.
- Kein Verkauf von Daten, an niemanden, niemals.
- Keine sozialen Funktionen und keine Nachrichten zwischen Nutzenden.

## Dinge wieder loswerden

| Was | Wie |
|---|---|
| Eine Route oder eine Fahrt | in der [Bibliothek](./library) löschen |
| Offline-Kartengebiete und Routing-Kacheln | unter [Offline-Daten](./offline-maps-and-routing) löschen |
| Ein Token von Strava oder Ride with GPS | **Trennen** unter Einstellungen → Verbindungen |
| Alles, was die App gespeichert hat | die App deinstallieren |
| Einen Teilen-Link | er läuft nach einem Jahr ab; für früher schreib mit dem Link an [hello@orkitec.com](mailto:hello@orkitec.com) |

Das Deinstallieren entfernt keine von dir erstellten Teilen-Links, und es entfernt nichts, was du zu Strava oder Ride with GPS hochgeladen hast.

## Deine Rechte

Wenn du in der EU oder im Vereinigten Königreich bist, gibt dir die DSGVO Rechte an deinen personenbezogenen Daten. Die meisten davon kannst du selbst wahrnehmen, weil die Daten auf deinem Handy liegen und sich jederzeit als GPX oder FIT exportieren lassen. Für alles auf unserer Seite, also Teilen-Links, Protokolleinträge und den Abo-Datensatz, schreib an [hello@orkitec.com](mailto:hello@orkitec.com). Die vollständige Darstellung, samt Rechtsgrundlage und Beschwerdestelle, steht in der [Datenschutzerklärung](/privacy).

## Weiterlesen

- [Datenschutzerklärung](/privacy)
- [Teilen](./sharing)
- [Assistent](./assistant)
- [Strava und Ride with GPS](./strava-and-ridewithgps)
- [Offline-Karten und Routing](./offline-maps-and-routing)
