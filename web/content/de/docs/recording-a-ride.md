---
title: Fahrt aufzeichnen
description: Eine Fahrt starten, pausieren und beenden, mit ausgeschaltetem Bildschirm weiter aufzeichnen, Akku sparen und eine Fahrt nach einem Absturz zurückholen.
order: 7
---

Der Tab Aufnahme zeichnet deine Fahrt auf und speichert sie am Ende in der Bibliothek. Er zeichnet mit ausgeschaltetem Bildschirm und mit der App im Hintergrund weiter, und er übersteht es, wenn die App geschlossen oder beendet wird.

Die Aufnahme ist kostenlos und funktioniert ganz ohne Verbindung.

## Starten, pausieren, beenden

1. Öffne den Tab **Aufnahme**. Dort steht **Bereit zur Fahrt** und "Der Track wird während der Fahrt auf dem Handy gespeichert, auch bei ausgeschaltetem Bildschirm."
2. Wähle bei Bedarf unter **Einer Route folgen** eine Route, was die Führung aus [Navigation mit Abbiegehinweisen](./navigation) einschaltet.
3. Tippe auf **Fahrt starten**.
4. Während der Fahrt zeigt die Übersicht eine Zustandsplakette, die laufende Uhr und die Zahlen: **Distanz**, **Tempo**, **Ø**, dann **Anstieg**, **Abstieg**, **Fahrzeit**.
5. **Pause** hält den Track an deiner Stelle an; **Fortsetzen** macht weiter. Die Unterbrechung zeigt sich als Lücke im Track.
6. **Beenden** speichert die Fahrt unter einem voreingestellten Namen wie **Fahrt 17. Sept. 2026** und öffnet ihre Seite.

Beendest du, ohne dass etwas aufgezeichnet wurde, sagt Velorki "Es wurde nichts aufgezeichnet." und speichert keine Fahrt.

### Auto-Pause

Velorki pausiert nach etwa zehn Sekunden ohne Bewegung von selbst; die Plakette liest sich dann **Auto-Pause**. Anders als bei einer Pause von Hand hört es weiter zu, und die erste richtige Bewegung setzt fort. Eine Pause von Hand hört auf zuzuhören, bis du auf **Fortsetzen** drückst.

## Puls, Trittfrequenz und Leistung

Ist ein Sensor eingeschaltet, kommt in der Übersicht eine dritte Zeile mit Zahlen dazu, solange er meldet: **Heart rate**, **Cadence** und **Power**. Sie können von einem Bluetooth-Sensor, von einer Apple Watch oder von der Health-App des Handys kommen, werden während der Fahrt in den Track geschrieben, und auf dem iPhone steht der Puls auch auf der Sperrbildschirm-Karte. Solange ein Radsensor meldet, ist seine Geschwindigkeit das, was **Tempo** zeigt.

Ohne Sensor erscheint nichts davon, und eingeschaltet wird nichts, bevor du es unter **Einstellungen → Sensors** tust. Siehe [Sensoren und deine Uhr](./sensors-and-watch).

## Was beim ersten Mal gefragt wird

Die erste Fahrt löst bis zu drei Abfragen aus, ausführlich beschrieben unter [Erste Schritte](./getting-started):

- **Standort**, mit Velorkis eigener Erklärung vorweg.
- **Mitteilungen** unter Android, weil die Aufnahme in einer davon lebt. Lehnst du ab, warnt Velorki: "Ohne Benachrichtigungsberechtigung stoppt Android die Aufnahme, sobald du die App verlässt."
- **Akku-Optimierung** unter Android, ein einziges Mal: "Android kann die Aufnahme stoppen, während das Handy schläft. Darf Velorki die Akku-Optimierung ignorieren, bleibt der Track vollständig. Die Frage kommt nur einmal."

## Bildschirm aus, App geschlossen

Der Track wird während der Fahrt auf das Handy geschrieben und alle paar Sekunden gesichert, nichts hängt also davon ab, dass die App im Vordergrund bleibt.

- **Android**: Die Fahrt läuft als Vordergrunddienst mit einer laufenden Mitteilung namens **Fahrt wird aufgezeichnet**, deren zweite Zeile Distanz und Zeit trägt, und die nächste Abbiegung, wenn du einer Route folgst. Ein Tipper darauf bringt dich zurück in die App.
- **iPhone**: Die Fahrt läuft mit gesperrtem Bildschirm weiter, und eine Live-Aktivität zeigt dieselben Zahlen auf dem Sperrbildschirm.

**Bildschirm anlassen** in der Aufnahmeübersicht hält das Display wach, was am Lenker praktisch und für den Akku teuer ist.

## Energiesparen

Der Bildschirm ist es, der auf einer langen Fahrt den Akku leert, deshalb geht **Energiesparen** den Bildschirm an. Schalte es in der Aufnahmeübersicht oder unter **Einstellungen → Aufnahme** ein: "Dunkle Karte, keine Animationen, nach 30 s eine schlichte Seite mit den Zahlen; der Bildschirm zieht den Akku leer".

Läuft eine Aufnahme mit eingeschaltetem Energiesparen, wird Velorki:

- das dunkle Design und eine schwarze Karte erzwingen,
- nur einen schlichten Positionspunkt zeichnen, ohne Genauigkeitsring und ohne Richtungskegel,
- die Kamera springen lassen statt sie zu animieren,
- das Display auf 40 % dimmen, solange **Bildschirm anlassen** es wach hält,
- und nach **30 Sekunden ohne Berührung** alles durch eine Blickseite ersetzen: weiß auf schwarz, die nächste Abbiegung, falls es eine gibt, dann **Distanz** als große Zahl mit **Tempo** und **Zeit** darunter.

Berühre den Bildschirm irgendwo, und die Karte kommt zurück; der Countdown beginnt von vorn. Alles kehrt zurück, sobald die Fahrt endet oder Energiesparen ausgeht. Das Design, das du für den Rest der App gewählt hast, ändert Energiesparen nie.

**GPS-Genauigkeit** unter **Einstellungen → Aufnahme** ist die andere Hälfte: **Energiesparen**, **Normal** oder **Genau**, mit dem Hinweis "Genau für Trails, Normal reicht für Straßen".

## Wenn eine Fahrt unterbrochen wird

Velorki schreibt den Track unterwegs in eine Journaldatei, ein Absturz, ein erzwungenes Beenden oder ein leerer Akku kostet die Fahrt also nicht.

- Lebt der Aufnahmedienst noch, wenn du zurückkommst, hängt sich die App still wieder an und macht weiter.
- Lebt er nicht mehr, zeigt der Tab Aufnahme beim Öffnen **Nicht beendete Fahrt**: "Eine Fahrt vom 16. Sept. 2026 wurde nie beendet. 42,1 km und 2 h 10 min sind gespeichert. Jetzt fortsetzen oder beenden?" mit drei Antworten:
  - **Fortsetzen** nimmt die Fahrt dort auf, wo sie stehen blieb,
  - **Beenden** speichert, was da ist, und öffnet die Seite der Fahrt,
  - **Verwerfen** wirft sie weg.

Der Dialog lässt sich nicht ohne Antwort schließen, eine wiederhergestellte Fahrt geht also nie still verloren.

## Eine beendete Fahrt fortsetzen

Eine bereits beendete Fahrt lässt sich weiterführen: Öffne sie aus der Bibliothek und wähle im Menü oben rechts **Fahrt fortsetzen**. "Die Aufnahme läuft auf dieser Fahrt weiter: Track, Distanz, Zeit und Anstieg setzen dort an, wo sie aufgehört haben, und die Zeit bis jetzt zählt als Pause."

Läuft gerade eine andere Aufnahme, wird sie zuerst beendet und gespeichert, und war diese Fahrt schon zu Strava oder Ride with GPS hochgeladen, wirst du darauf hingewiesen, dass die fortgesetzte Fahrt erneut gesendet werden muss.

## Letzte Fahrten

Unter **Letzte Fahrten** im Tab Aufnahme stehen deine letzten fünf, die neueste zuerst, jede mit Datum, Distanz und Fahrzeit. Wisch eine Zeile nach links, um sie zu löschen, mit einem **Rückgängig** in der Meldung danach. Die vollständige Liste steht in der [Bibliothek](./library).

## Weiterlesen

- [Navigation mit Abbiegehinweisen](./navigation)
- [Sensoren und deine Uhr](./sensors-and-watch)
- [Bibliothek](./library)
- [Import und Export](./import-and-export)
- [Strava und Ride with GPS](./strava-and-ridewithgps)
- [Einstellungen und Darstellung](./settings-and-appearance)
