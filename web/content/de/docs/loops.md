---
title: Runden
description: Velorki nach einer Rundfahrt über eine bestimmte Distanz fragen, die dort endet, wo sie begann, und die Vorschläge durchgehen, bis einer passt.
order: 3
---

Eine Runde ist eine Fahrt, die dorthin zurückkommt, wo sie begonnen hat, und Velorki erzeugt sie aus einer Distanz statt aus angetippten Punkten. Nimm die Schaltfläche **Runde**, wenn du weißt, wie weit du fahren willst, aber nicht wohin, und nimm sie, um eine schon gezeichnete Route zu schließen.

Der Rundengenerator ist ein ganz normaler Algorithmus auf deinem Handy. Er ist kostenlos, er braucht außer dem Routing selbst keinen Server, und kein Modell ist beteiligt.

## Öffnen

Tippe in der Leiste der Routenübersicht im Tab **Planen** auf **Runde**. Das Fenster heißt **Runde planen**, und was es anbietet, hängt davon ab, was der Planer schon enthält.

## Eine gezeichnete Route schließen

Hat der Planer schon zwei oder mehr Punkte, bietet das Fenster an, die Route zum Start zurückzuführen.

1. Es sagt "Zurück zum Startpunkt fahren."
2. Wähle unter **RAD** das Profil. Es ist dieselbe Einstellung wie die Chips im Planer, ein Wechsel hier wechselt sie also auch dort.
3. **Anderer Rückweg** ist voreingestellt an, mit dem Hinweis "Vermeidet die schon gefahrenen Wege." Schaltest du es aus, darf der Rückweg den Hinweg wiederverwenden.
4. Tippe auf **Runde schließen**. Velorki hängt eine Kopie deines ersten Punkts an, berechnet den Heimweg und zeigt das Ergebnis als `48,2 km · 720 m Anstieg`.
5. **Anderer Rückweg** lässt den Hinweg genau so, wie er ist, und fragt nur einen anderen Rückweg an. Drück es, so oft du magst; jeder Druck ist ein Schritt zum Rückgängigmachen. Es ist ausgegraut, solange **Anderer Rückweg** aus ist.
6. **Fertig** schließt das Fenster. Die Runde liegt als ganz gewöhnliche Route auf der Planerkarte und lässt sich bearbeiten und speichern.

## Eine Runde von Grund auf planen

Ist der Planer leer oder enthält er nur einen Punkt, fragt das Fenster stattdessen nach einer Distanz.

1. **Wo sie beginnt.** Liegt schon ein Punkt auf der Karte, ist das der Start. Sonst steht dort **Ab deiner Position**, und Velorki fragt beim ersten Mal nach dem Standort. Kommt keine Position zustande, weicht es auf die Kartenmitte aus und die Zeile wechselt zu **Ab der Kartenmitte**.
2. **DISTANZ.** Zieh den Schieberegler. Metrisch reicht er von 5 bis 200 km in Schritten von 5 km, imperial von 3 bis 125 Meilen in Schritten von 1 Meile, und der gewählte Wert steht groß darüber. Er öffnet mit dem zuletzt gewählten Wert, beim ersten Mal mit 30 km.
3. **RAD.** Dieselben fünf Profile wie im Planer.
4. **Anderer Rückweg.** An bedeutet einen echten Rundkurs; aus bedeutet, zu einem entfernten Punkt hinaus und denselben Weg zurück.
5. Tippe auf **Runde planen**.

## Während der Suche

Velorki schickt die Anfrage in acht Richtungen hinaus und gibt sich 25 Sekunden. Ein Fortschrittsbalken zählt die fertigen Anfragen, und **Stopp** rechts beendet die Suche früher und behält, was bis dahin gefunden wurde.

## Unter den Vorschlägen wählen

Du bekommst keine Liste zum Durchlesen. Jeder Vorschlag wird bewertet: wie nah er an die gewünschte Distanz kommt, wie viele Höhenmeter je Kilometer er hat, wie viel davon unbefestigt ist, wie viel auf Radwegen und Radnetzen verläuft, wie viel dieselben Wege wiederholt, und wie viel auf Hauptstraßen liegt. Der beste geht direkt an den Planer und wird auf der Karte gezeichnet, und das Fenster zeigt nur seine Zusammenfassung, `48,2 km · 720 m Anstieg`.

Für den nächstbesten tippe auf **Andere**. Das geht einen Schritt in der Rangfolge nach unten, ganz ohne neues Routing, also sofort. Ist die Rangfolge erschöpft, sucht Velorki erneut mit den acht Richtungen um einen halben Schritt gedreht, sodass die neuen Versuche zwischen den alten landen.

Jeder Vorschlag, den du ansiehst, ist eine echte Route im Planer: schwenk darum herum, zieh einen Punkt, lies das Höhenprofil, und **Speichern**, sobald einer passt.

Ändert sich nach einer Suche der Schieberegler oder das Radprofil, ist das Ergebnis veraltet und die Schaltfläche heißt wieder **Runde planen**.

## Eine Runde über einen bestimmten Ort

Das Rundenfenster hat kein Feld für einen Ort, an dem du vorbeifahren willst, und keine Vorliebe für Berge oder Belag. Das kommt vom [Assistenten](./assistant): Ein Satz wie "Eine Gravel-Runde von etwa 80 km mit Café-Stopp" oder "eine hügelige 60-km-Runde von hier am See vorbei" wird zu einer Anfrage mit Zwischenpunkt und Vorlieben, und den Rest erledigt der Rundengenerator. Der Assistent gehört zu Velorki Plus; das Rundenfenster selbst ist kostenlos.

## Wenn nichts gefunden wird

- **"Hier keine Runde gefunden, andere Distanz versuchen."** Manche Gegenden, eine Insel oder ein Sackgassental, haben schlicht kein Wegenetz für einen Rundkurs dieser Länge. Setz die Distanz deutlich herauf oder herunter, oder starte woanders.
- **"Standort einschalten oder Karte antippen, um den Start zu setzen."** Es ließ sich kein Startpunkt ermitteln. Erlaube den Standort, oder tippe zuerst auf die Karte.
- **"Rundensuche fehlgeschlagen:"** mit einem Grund heißt, dass das Routing selbst fehlgeschlagen ist. Siehe [Fehlerbehebung](./troubleshooting).

Das Schließen des Fensters bricht eine laufende Suche ab, behält aber, was schon gefunden wurde.

## Weiterlesen

- [Route planen](./planning-a-route)
- [Assistent](./assistant)
- [Offline-Karten und Routing](./offline-maps-and-routing)
- [Bibliothek](./library)
