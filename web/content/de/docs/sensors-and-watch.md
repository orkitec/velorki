---
title: Sensoren und deine Uhr
description: Puls, Trittfrequenz und Leistung von einem Bluetooth-Sensor, einer Apple Watch oder der Health-App des Handys, einmal eingerichtet und bei jeder Fahrt dabei.
order: 16
---

Velorki kann während der Aufnahme deinen Puls, deine Trittfrequenz und deine Leistung zeigen und alle drei danach bei der Fahrt behalten. Die Werte kommen von einem Bluetooth-Sensor, von einer Apple Watch oder von der Health-App des Handys, und das alles ist kostenlos und läuft auf dem Gerät.

Nichts davon passiert, bevor du es einschaltest. Sind alle Quellen aus, fragt Velorki das Betriebssystem nach nichts, und kein Bildschirm erwähnt einen Sensor.

## Was sich messen lässt

| Quelle | Was sie liefert | Was sie braucht |
|---|---|---|
| Bluetooth-Sensor | Puls, Trittfrequenz, Radgeschwindigkeit, Leistung | den Sensor, einmal in Velorki gekoppelt |
| Apple Watch | Puls, und die Fahrt am Handgelenk | ein iPhone mit gekoppelter Uhr |
| Apple Health oder Health Connect | Puls, den etwas anderes aufs Handy geschrieben hat | die Health-App des Handys und einen Schalter |

Melden zwei davon dasselbe zur selben Zeit, gewinnt die Uhr vor einem Bluetooth-Sensor und ein Bluetooth-Sensor vor der Health-App. Ein Wert gilt zehn Sekunden lang als aktuell, und verstummt die führende Quelle, übernimmt die nächste von selbst. Ein Gurt, der zu Hause liegt, ist damit einfach nicht da.

## Eine Quelle einschalten

Alles steht unter **Einstellungen → Sensoren**, direkt unter **Aufnahme**:

- **Apple Health** auf dem iPhone, **Health Connect** unter Android, mit der Zeile "Liest den Puls, den andere Apps in Health ablegen, etwa das Training der Uhr. Wird alle paar Sekunden abgefragt, hinkt also nach; ein Gurt oder die Velorki-Uhren-App übernimmt, sobald sie melden". Das Einschalten ist das Einzige in Velorki, was die Health-Abfrage auslösen kann. Lehnst du ab, sagt Velorki "Velorki hat keinen Zugriff auf deine Gesundheitsdaten bekommen." und lässt den Schalter aus.
- **Fahrten in Health speichern** darunter, "Jede beendete Fahrt landet in Health als ein Radfahr-Training mit Start, Ende und Distanz", getrennt abschaltbar. Solange der Schalter darüber aus ist, tut er nichts.
- **Apple Watch**, mit der Zeile "Velorkis eigene Uhren-App: misst deinen Puls die ganze Fahrt live, zeigt die Fahrt und hat Start, Pause und Ende am Handgelenk. Kostet Akku der Uhr". Die Zeile gibt es nur auf einem iPhone, mit dem eine Uhr gekoppelt ist. **Sensor in Pausen ruhen lassen** darunter ist unter [Akku am Handgelenk](#akku-am-handgelenk) erklärt.
- **Bluetooth-Sensoren**, mit der Zeile "Brustgurte, Geschwindigkeits- und Trittfrequenzsensoren, Leistungsmesser", oder "1 Sensor gekoppelt", sobald du einen hast. Dahinter liegt ein eigener Bildschirm.

## Bluetooth-Sensoren

### Einen Sensor koppeln

1. Weck den Sensor auf: Gurt anlegen oder Kurbel drehen. Die meisten Sensoren sagen gar nichts, solange sie nicht benutzt werden.
2. Öffne **Einstellungen → Sensoren → Bluetooth-Sensoren** und tippe auf **Scannen**. Auf dem iPhone steht vorher "iOS fragt beim ersten Scannen nach Bluetooth." auf dem Bildschirm. Ein Scan läuft etwa fünfzehn Sekunden.
3. Tippe unter **Gefunden** auf den Sensor, den du wiedererkennst. Jede Zeile trägt seinen Namen, kleine Symbole für das, was er misst, und seine Signalstärke in dBm; der lauteste steht oben.
4. Velorki verbindet sich einmal, um das Gerät zu fragen, was es wirklich hat, legt es unter **Gekoppelt** ab und lässt es wieder los.

Solange dieser Bildschirm offen ist, sind deine gekoppelten Sensoren verbunden, jede Zeile zeigt also statt **Verbunden**, **Wird verbunden…** oder **Nicht verbunden**, was der Sensor gerade sagt. Verlässt du den Bildschirm, werden sie wieder getrennt, außer es läuft eine Aufnahme. **Entkoppeln** im Menü rechts an einer gekoppelten Zeile entfernt einen Sensor.

### Womit Velorki sich koppelt

Mit den drei Standardprofilen fürs Rad, die fast alles spricht, was als Radsensor verkauft wird:

- **Pulsgurte** und Armbänder,
- **Geschwindigkeits- und Trittfrequenzsensoren**, am Rad, an der Kurbel oder ein Gerät für beides,
- **Leistungsmesser**, deren Kurbelzähler auch eine Trittfrequenz liefern, ein Leistungsmesser macht einen eigenen Trittfrequenzsensor also überflüssig.

Ein Gerät, das keines der drei spricht, wird nicht angeboten. Velorki koppelt sich mit Sensoren, nicht mit Radcomputern: Ein Head-Unit ist etwas anderes und wird hier nicht verbunden.

### Radumfang

Ein Geschwindigkeitssensor zählt Radumdrehungen, Velorki muss also wissen, wie weit eine Umdrehung ist. Das Feld **Radumfang** erscheint unten auf dem Bildschirm, sobald ein gekoppelter Sensor Geschwindigkeit meldet, mit dem Hinweis "Millimeter pro Radumdrehung. 2105 ist ein 700x25c-Reifen." und **mm** hinter der Zahl.

Solange ein Radsensor meldet, ersetzt seine Geschwindigkeit die GPS-Geschwindigkeit in der Aufnahmeübersicht, und genau darum geht es: Ein Rad stimmt im Schritttempo, unter Bäumen und im Tunnel, wo GPS das nicht tut. Sonst benutzt die Fahrt diesen Wert nirgends.

### Wenn ein Sensor nicht gefunden wird

- **"Noch nichts. Weck den Sensor auf: Gurt anlegen oder Kurbel drehen."** Ein Gurt ohne Hautkontakt und eine stehende Kurbel sind unsichtbar. Beweg dich und scanne noch einmal.
- **"Schalte Bluetooth ein, um deine Sensoren zu finden."** Das Funkmodul des Handys ist aus.
- **"Velorki durfte Bluetooth nicht benutzen."** Die Berechtigung wurde abgelehnt. Erteile sie Velorki in den Einstellungen des Handys und scanne noch einmal.
- **Der Sensor spricht mit etwas anderem.** Diese Sensoren bedienen jeweils ein Gerät. Schließe die andere App oder schalte den Radcomputer aus.
- **Ein gekoppelter Sensor, der Nicht verbunden zeigt**, ist außer Reichweite, schläft oder ist leer. Velorki versucht es weiter, solange eine Aufnahme läuft oder der Bildschirm offen ist, und wartet nach jedem Versuch etwas länger.

## Apple Watch

Die App auf der Uhr ist Anzeige und Sensor, nie ein zweites Aufnahmegerät. Das Handy zeichnet die Fahrt auf; die Uhr schickt, was sie misst und was du tippst, und zeigt, was das Handy zurückmeldet.

### Die App auf die Uhr bekommen

Velorkis Uhren-App steckt in der iPhone-App. Sie landet von selbst auf der Uhr, wenn diese Begleit-Apps automatisch installiert; sonst öffne die App **Watch** auf dem iPhone und installiere Velorki aus der Liste der verfügbaren Apps. Schalte danach **Apple Watch** unter **Einstellungen → Sensoren** ein; das fragt einmal auch, ob Velorki Mitteilungen zeigen darf, für die unter den Knöpfen beschriebene. Beim ersten Training fragt die Uhr um Erlaubnis, deinen Puls zu lesen. Diese Abfrage kommt von der Uhr, nicht vom Handy.

### Was die Uhr zeigt

- Deinen **Puls** in großen Ziffern, mit schlagendem Herz, solange die Uhr misst; zwei Striche, solange nichts gemessen wird, und den letzten Wert abgedunkelt, solange die Fahrt pausiert ist. Herz und Knöpfe tragen die Akzentfarbe, die du in der App gewählt hast.
- Eine Zeile in Orange, wenn etwas nicht stimmt: Health-Zugriff abgelehnt, ein Training, das die Uhr nicht starten wollte, oder ein Handy, das nicht geantwortet hat.
- Während einer Fahrt ihre Distanz, die laufende Uhr und das Tempo, und **Paused**, wenn pausiert ist. Formatiert wird alles vom Handy, es steht also in deinen Einheiten und deiner Sprache da.
- Die nächste Abbiegung mit Symbol, Namen und Entfernung, so wie auf dem Sperrbildschirm, in Orange, solange du von der Route ab bist; sobald ein Weg zurück oder eine neue Route berechnet ist, deren Abbiegungen.
- Ein Tippen aufs Handgelenk, wenn ein Abbiegehinweis fällig ist, und eines, wenn du die Route verlässt. Eine Uhr, die drei Abbiegungen verschlafen hat, tippt einmal statt dreimal.

Die eigenen Worte der Uhr, also die Knöpfe und die zwei Fußnoten, sind englisch, in welcher Sprache das Handy auch läuft. Komplikationen gibt es noch nicht.

### Was die Knöpfe tun

| Knopf | Was er tut |
|---|---|
| **Start ride** | startet die Aufnahme auf dem Handy |
| **Pause**, **Resume** | pausieren und weiterfahren, wie am Handy |
| **Finish** | beendet die Aufnahme; "Finish opens the save sheet on the phone." |
| **Stop heart rate** | beendet das Messen auf der Uhr, während die Fahrt weiterläuft |
| **Start heart rate** | startet es wieder, oder startet es für eine Fahrt, in die die Uhren-App erst später geöffnet wurde |

Startet eine Fahrt am Handy, öffnet sich die Uhren-App von selbst und beginnt zu messen, am Handgelenk ist also nichts zu tippen. Umgekehrt startet **Start ride** auf der Uhr die Aufnahme auf dem Handy und bringt das Handy auf seinen Tab **Aufnahme**. Ein Handy in der Tasche, mit Velorki im Hintergrund, bekommt eine Mitteilung, "Ride started from your watch", und ein Tipp darauf öffnet die App; das zählt, weil iOS einer im Hintergrund geweckten App kein GPS gibt, bis sie einmal geöffnet wurde, der Track beginnt also dann. Eine App, die du ganz weggewischt hast, kann die Uhr gar nicht wecken, das ist eine Regel von iOS; nach ein paar Versuchen sagt die Uhr "The phone did not answer. Open Velorki on the phone and try again." Eine Fahrt, die du am Handgelenk beendest, wird gespeichert wie jede andere: Die Aufnahme hört auf, und die Speichern-Übersicht wartet auf dem Handy, wenn du das nächste Mal hinsiehst.

### Akku am Handgelenk

Stundenlang einen Puls zu messen ist es, was die Uhr ihren Tag kostet. Gemessen wird die ganze Fahrt über, Pausen eingeschlossen: Eine Uhren-App, die nicht mehr misst, legt watchOS innerhalb einer Minute schlafen, und dann hört sie nichts mehr vom Handy; wach zu bleiben ist es, was den Puls weiter kommen lässt. Solange die Fahrt pausiert ist, zeichnet das Handy keinen Puls auf. Für Fahrten mit vielen Stopps lässt **Sensor in Pausen ruhen lassen** unter dem Apple-Watch-Schalter in den Einstellungen die Uhr in jeder Pause aufhören zu messen. Der Tausch: Der Sensor ruht bei jedem Stopp, aber das Handy muss die Uhr wieder wecken, wenn du weiterfährst, der erste Puls nach jedem Stopp braucht einen Moment, und schlägt das Wecken fehl, fehlt der Puls, bis das Handy es erneut versucht. Für einen lückenlosen Puls lass ihn aus. Verstummt die Uhr mitten in der Fahrt doch einmal für eine Dreiviertelminute, startet das Handy ihre App von selbst neu. **Stop heart rate** beendet das Messen, ohne die Fahrt anzurühren. Den Rest sagt die Fußnote auf dem Bildschirm, "Low Power Mode in the watch's settings makes a long ride last." Schaltest du **Apple Watch** in den Einstellungen aus, endet eine noch laufende Sitzung ebenfalls.

## Apple Health und Health Connect

Diese Quelle ist der Puls, den dein Handy ohnehin schon kennt: was eine Apple Watch über ihr eigenes Training geschrieben hat, oder was eine andere App in den Speicher gelegt hat. Sie ist die langsamste und am wenigsten lebendige der drei, ein direkt meldender Gurt oder eine Uhr übernimmt sofort.

### Was gelesen und was geschrieben wird

- **Gelesen**: der Puls, und sonst nichts. Während einer Aufnahme fragt Velorki alle fünf Sekunden nach neuen Messwerten, bei eingeschaltetem **Energiesparen** alle dreißig.
- **Danach ergänzt**: Beim Speichern der Fahrt füllen Messwerte aus dem Speicher die Punkte des Tracks, die keinen Puls tragen, sofern ein Wert höchstens eine halbe Minute daneben liegt, und die Zahlen der Fahrt werden neu berechnet. Ein Punkt, der seinen Wert live von einem Gurt oder einer Uhr bekommen hat, behält ihn.
- **Geschrieben**: ein Radfahr-Training pro Fahrt, mit Start, Ende und Distanz, und nur mit eingeschaltetem **Fahrten in Health speichern**. Jede Fahrt wird einmal geschrieben. Ist der Schalter aus, liest Velorki nur.

## Wo die Zahlen auftauchen

### Während der Fahrt

In der Aufnahmeübersicht erscheint eine dritte Zeile mit dem, was in der Fahrt gemeldet wurde: **Herzfrequenz** mit dem **Ø Puls** der Fahrt darunter, **Trittfrequenz** und **Leistung**. Eine Uhr allein bringt also eine Kachel, und ohne Sensor steht dort gar nichts. Ein Sensor, der verstummt, behält seine Kachel, abgedunkelt und mit dem Zeichen für die unterbrochene Verbindung, bis die Fahrt endet. Auf dem iPhone kommt der Puls zu den Zahlen auf der Sperrbildschirm-Karte und in der Dynamic Island dazu.

### Auf einer gespeicherten Fahrt

Das Blatt einer Fahrt in der [Bibliothek](./library) wächst um das, was diese Fahrt wirklich trägt:

- **Ø Puls**, **Max Puls**, **Ø Kadenz** und **Ø Leistung** bei den Zahlen, jede nur, wenn die Fahrt sie hat,
- ein Diagramm **Herzfrequenz** unter dem Diagramm **Tempo**, an dem du entlangziehen kannst, um an jeder Stelle abzulesen.

Die **Splits**-Tabelle bleibt, wie sie war: **Split**, **Fahrzeit**, **Ø** und **Anstieg**, ohne Sensorspalten. Eine aus einer GPX-, FIT- oder TCX-Datei importierte Fahrt bringt ihren Puls, ihre Trittfrequenz und ihre Leistung mit und zeigt sie genauso.

## Was gespeichert wird und was das Handy verlässt

Die Werte gehören zur Fahrt: ein Puls, eine Trittfrequenz und eine Leistung an jedem Punkt des Tracks, dazu die Mittelwerte und der höchste Puls bei ihren Zahlen. Sie liegen in Velorkis eigenem Speicher auf dem Handy, beim Track.

Von allein wird nichts hochgeladen. Ein GPX-, FIT- oder TCX-Export nimmt die Werte mit dem Track mit, eine Fahrt, die du exportierst oder zu Strava oder Ride with GPS schickst, kommt also vollständig an. Der Austausch mit Apple Health oder Health Connect findet auf dem Handy statt. Das ganze Bild steht unter [Privatsphäre auf dem Handy](./privacy-on-the-phone).

## Weiterlesen

- [Fahrt aufzeichnen](./recording-a-ride)
- [Bibliothek](./library)
- [Einstellungen und Darstellung](./settings-and-appearance)
- [Privatsphäre auf dem Handy](./privacy-on-the-phone)
- [Fehlerbehebung](./troubleshooting)
