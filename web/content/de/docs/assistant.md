---
title: Assistent
description: Die gewünschte Fahrt in einem Satz beschreiben und Velorki macht eine Route daraus, mit deiner Zustimmung, höchstens grober Position und ohne Routenhistorie.
order: 12
---

Der Assistent macht aus einem Satz wie "eine Gravel-Runde von etwa 80 km mit Café-Stopp" eine Route im Planer. Er ist der einzige Teil von Velorki, der dein Geschriebenes an einen Server schickt, deshalb fragt er zuerst nach deiner Zustimmung und sagt genau, was mitgeht.

Der Assistent gehört zu [Velorki Plus](./velorki-plus).

## Öffnen

Tippe in der Leiste der Routenübersicht im Tab **Planen** auf **Fragen**. Die Karte des Assistenten tritt an die Stelle der Routenübersicht und heißt **Nach einer Route fragen**: "Beschreibe die geplante Fahrt. Velorki macht daraus eine Anfrage und plant die Route auf dem Handy." Die Karte darüber bleibt die Karte: verschieben, zoomen und antippen wie bei offener Routenübersicht. Wisch die Karte nach unten oder geh zurück, und die Routenübersicht ist wieder da, wie du sie verlassen hast; was du eingetippt hast und die Antworten bleiben für das nächste Mal.

Liegt eine Route auf der Karte, öffnet das Fenster stattdessen auf **Diese Route**, mit einer Frage zu dieser Route (siehe [Nach dieser Route fragen](#nach-dieser-route-fragen)); **Neue Route** darüber schaltet zurück.

Fehlt die Schaltfläche **Fragen**, hat dieser Velorki-Build gar keine Serveradresse, was bei einer selbst gebauten Kopie ohne eigenen Relay so ist.

## Zustimmung und was das Handy verlässt

Beim ersten Absenden zeigt Velorki **Bevor der Assistent fragt**:

> Was du eingibst, geht an den Velorki-Server und von dort an unseren KI-Anbieter. Mehr geht nicht mit: kein Name, kein Konto, keine Routenhistorie.
>
> Wenn du es erlaubst, geht auch deine Position mit, auf etwa einen Kilometer gerundet, damit "von hier" etwas bedeutet.

Drei Antworten:

- **Erlauben, mit grober Position** schickt deinen Text und eine auf rund einen Kilometer gerundete Position.
- **Erlauben, nur Text** schickt deinen Text und sonst nichts.
- **Jetzt nicht** schickt nichts und schaltet den Assistenten aus.

Was tatsächlich reist: dein Text, auf Wunsch die gerundete Position, deine Sprach- und Einheiteneinstellung, damit die Antwort passt, und bei einer Routenbeschreibung oder einer Frage zu einer Route eine Übersicht der Route (siehe unten). In die Anfrage kommt keine Kennung von dir oder deinem Handy.

Du kannst es jederzeit unter **Einstellungen → KI-Assistent → Was gesendet wird** ändern; der Untertitel dort sagt immer, in welchem der vier Zustände du bist, mit einer Schaltfläche **Ändern** daneben.

## Nach etwas fragen

Tippe einen Satz ein und tippe auf **Fragen**. Drei Beispiele stehen zum Antippen bereit:

- **Eine flache 30-km-Runde von hier**
- **60 km nach Freiburg auf ruhigen Straßen**
- **Eine Gravel-Runde von etwa 80 km mit Café-Stopp**

Was ebenfalls gut funktioniert: eine Distanz und eine Richtung, ein Ort zum Vorbeifahren, ein Belag, wie viele Höhenmeter du willst, ein Start, der nicht dein Standort ist.

Das Fenster zeigt **Denkt nach…**, solange das Modell antwortet, dann **Orte werden gesucht…**, während aus den Ortsnamen Koordinaten werden. Danach fasst es zusammen, was es verstanden hat: "Runde von etwa 80 km", "Start an der aktuellen Position" oder "Start bei Freiburg", und einen Chip je Ort zum Vorbeifahren.

Passt ein Name auf mehrere weit auseinanderliegende Orte, fragt Velorki **Freiburg – welcher Ort?** mit bis zu drei Möglichkeiten. Ein Tipper darauf klärt es auf dem Handy, ohne zweiten Weg zum Modell.

## Was mit der Antwort passiert

Das Fenster schließt sich von selbst und der Planer übernimmt:

- **Eine Runde ohne bestimmten Ort zum Vorbeifahren** öffnet das [Rundenfenster](./loops) mit bereits laufender Suche. Ist die Suche fertig, schließt sich das Rundenfenster und der Assistent kommt auf **Diese Route** zurück, mit deiner Anfrage über der Frage, damit du gleich nach der Runde fragen kannst. Hat die Suche keine Runde gefunden, kommt er auf **Neue Route** zurück und sagt das. Schließt du das Rundenfenster oder tust darin etwas, während es sucht, gehört die Suche dir: der Assistent bleibt weg.
- **Eine Runde über benannte Orte** wird zu Wegpunkten mit geschlossener Runde, und Velorki sagt "Die Route liegt auf der Karte."
- **Eine Route von A nach B** wird zu Wegpunkten mit gesetztem Radprofil, und wieder "Die Route liegt auf der Karte."

Ab da ist es eine gewöhnliche Planung: bearbeiten, Varianten anfragen, speichern.

## Was er nicht tut

Das Modell liefert nie Koordinaten und berechnet nie eine Route. Es liefert eine strukturierte Anfrage, eine Distanz, eine Form, ein paar Ortsnamen und die eine oder andere Vorliebe, und alles danach passiert auf deinem Handy. Deshalb taugt der Assistent dazu, auszudrücken, was du willst, und nicht als Quelle für Tatsachen über Straßen.

Er kann sich auch irren. Sagt er etwas, was du nicht gemeint hast, formulier es neu, mit klarer Distanz und klarem Ort.

## Nach dieser Route fragen

Liegt eine Route auf der Karte des Planers, öffnet **Fragen** auf **Diese Route**: "Frag alles zur Route auf der Karte." Beispiele zum Antippen: **Prüf diese Route**, **Wo gibt es etwa auf halber Strecke Kaffee?**, **Wo kann ich Wasser auffüllen?**, **Meide die Hauptstraße**, **Geht das mit dem Rennrad?**

Was mitgeht: deine Frage und die Übersicht der Route, wie sie unter [Diese Route beschreiben](#diese-route-beschreiben) steht, mit den Positionen. Deine eigene Position geht in diesem Modus nicht mit.

Die Antwort sind ein paar Sätze und bis zu sechs Hinweise entlang der Route, jeweils mit der Stelle. **Zeigen** bewegt die Karte dorthin. Ein Hinweis, mit dem der Planer etwas anfangen kann, hat eine Schaltfläche:

- **Als Stopp einfügen** führt die Route über ein Café, eine Trinkwasserstelle oder einen anderen Ort aus der Übersicht, eingefügt dort, wo die Route daran vorbeikommt.
- **Meiden** hält den Router von diesem Abschnitt fern. Er wird gestrichelt auf der Karte gezeichnet, und der Chip **1 Abschnitt wird gemieden** über der Karte hat **Wieder erlauben**.
- **Gravel verwenden** (oder ein anderes Rad) plant die Route mit diesem Profil neu.

Jede davon ist ein einzelner Schritt, den **Rückgängig** zurücknimmt; das Fenster bleibt offen und markiert sie als **Übernommen**. Das Modell schlägt nur Orte aus der Übersicht vor; es erfindet nie einen Stopp oder eine Koordinate.

Für eine aus Strava importierte Route wird **Diese Route** nicht angeboten.

## Diese Route beschreiben

Das andere, was der Assistent kann, ist einen Absatz über eine Route zu schreiben, die du schon hast. Öffne eine Route in der Bibliothek und tippe auf **Diese Route beschreiben**; das Fenster fängt sofort an zu schreiben, und **Als Beschreibung speichern** legt den Text zur Route. **Neu schreiben** fragt einen weiteren Versuch an.

Bevor er fragt, gleicht das Handy die Route mit seinen Routing-Kacheln und seiner Offline-Ortssuche ab und stellt eine Übersicht zusammen: Distanz, Anstieg, die befestigten und unbefestigten Anteile, die Namen der Wegpunkte, die Abschnitte der Route mit Straßenart, Belag und Steigung, ihre Anstiege, die Städte und Dörfer, durch die sie führt, und Cafés, Bäckereien, Trinkwasserstellen, Toiletten, Aussichtspunkte und Radläden bis 300 m neben ihr, jeweils mit dem Kilometer entlang der Route und ihrer Position. Ohne heruntergeladene Kacheln für die Gegend gehen nur die Zahlen. Das Modell bekommt auch die Positionen, auf etwa 10 m genau, damit es weiß, wo die Tour liegt; beginnt die Route vor deiner Tür, zeigt sie, wo deine Tür ist. Jeder Ort, den die Beschreibung nennt, stammt aus der Übersicht, so kann sie „das Café in Caniço bei km 9“ sagen und ein Café meinen, das es gibt. Geschrieben wird in der Sprache und den Einheiten, auf die die App eingestellt ist.

Für eine aus Strava importierte Route wird die Schaltfläche nicht angeboten, weil die Bedingungen von Strava nicht erlauben, ihre Daten an einen KI-Anbieter zu geben.

## Grenzen und Fehler

Der Assistent ist begrenzt: zwanzig Anfragen pro Stunde und hundert pro Tag.

| Was das Fenster sagt | Was es heißt |
|---|---|
| "Zu viele Anfragen. In 90 Sekunden erneut versuchen." | du bist an die Grenze gestoßen |
| "Der KI-Assistent gehört zu Velorki Plus." | kein Abo |
| "Der Assistent braucht deine Zustimmung, bevor er etwas senden kann." | die Zustimmung fehlt oder wurde abgelehnt |
| "Ich bin nicht sicher, ob ich das verstanden habe. Nenne eine Distanz und einen Ort." | das Modell war unsicher |
| "„Freiburg“ wurde nicht gefunden. Andere Schreibweise oder einen Ort in der Nähe versuchen." | der Ortsname ließ sich nicht auflösen |
| "Der Start ist unbekannt. Standort einschalten oder einen Startort nennen." | "von hier" ohne Position |
| "Der Assistent konnte nicht antworten:" | der Server oder das Modell ist ausgefallen |

**Erneut versuchen** räumt den Fehler weg und behält, was du eingetippt hast.

## Eine schlechte Antwort melden

**Einstellungen → KI-Assistent → KI-Antwort melden** öffnet eine Mail an uns: "Melde eine Antwort, die falsch oder unpassend war." Bitte nutze das. Falsche und unpassende Antworten sind der Weg, auf dem die Anfragen besser werden.

## Weiterlesen

- [Velorki Plus](./velorki-plus)
- [Runden](./loops)
- [Route planen](./planning-a-route)
- [Datenschutz auf dem Handy](./privacy-on-the-phone)
