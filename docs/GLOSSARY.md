# Glossary

The words Velorki uses, in every language it ships. Read it before
translating anything: the app's ARB files, the website's messages and guide,
the store texts and release notes. A term listed here is used exactly as
listed; a new one is added here in the same commit that first uses it.
`app_<locale>.arb` is the source of truth for a label: this file names the
ones whose choice is a decision, and the rules around them.

## Rules for every language

- **A label is quoted exactly as the app shows it**, in the app's own
  language: the guide, the store texts and the app's own hints say the same
  word the button says.
- **A menu path starts with the tab's own name** and follows the page titles
  the rider sees on the way: German "Optionen → Verbindungen", not
  "Einstellungen → Verbindungen". The phone's own settings app keeps the
  system's name ("Einstellungen auf dem iPhone öffnen").
- **One word, one thing.** A recorded ride is always the same noun, a planned
  route always the other; the Ride button never shares its word with a tab or
  another button on the same screen unless both do the same thing.
- **Not translated:** Velorki, Velorki Plus, OpenStreetMap, Strava, Ride with
  GPS, iCloud, Google Drive, Apple Watch, Wear OS, GPX, FIT, TCX, Gravel,
  MTB (French: VTT).
- Placeholders (`{count}`) stay as they are; see `LOCALISATION.md` for the ICU
  and turn-by-turn rules.
- Plain, friendly and short, as the English is. No exclamation marks, no
  marketing superlatives.

## Each language

| Language | Address | Quotes | Notes |
|---|---|---|---|
| German | du, lower case | „…“ | "Optionen" is the tab: "unter Optionen → …", "in den Optionen", never "in den Einstellungen" for Velorki's own; "Einstellungen" only for the stored preferences ("Routen, Fahrten und Einstellungen") and the phone's settings. "Aufzeichnen" is the tab, "Aufzeichnung" a recording in progress or the setting; "Fahrt" a recorded ride |
| French | vous | « … » with spaces | "sortie" a recorded ride, "itinéraire" a route; "étape" a stop added to a route, "haltes" the stops layer |
| Spanish | tú | «…» | "salida" a recorded ride (never "recorrido"), "ruta" a route |
| Italian | tu | «…» | "giro" a recorded ride (never "uscita", which is a junction's exit), "percorso" a route |
| Dutch | je | ‘…’ | "rit" a recorded ride, "route" a route |

## Terms

| English | German | French | Spanish | Italian | Dutch |
|---|---|---|---|---|---|
| Plan (tab) | Planen | Planifier | Planificar | Pianifica | Plannen |
| Record (tab) | Aufzeichnen | Rouler | Grabar | Registra | Opnemen |
| Library (tab) | Bibliothek | Bibliothèque | Biblioteca | Libreria | Bibliotheek |
| Settings (tab) | Optionen | Réglages | Ajustes | Opzioni | Instellingen |
| Save | Speichern | Enregistrer | Guardar | Salva | Opslaan |
| Ride (button beside Save) | Losfahren | Rouler | Salir | Parti | Rijden |
| Start ride | Fahrt starten | Démarrer | Iniciar salida | Inizia giro | Rit starten |
| route / routes | Route / Routen | itinéraire / itinéraires | ruta / rutas | percorso / percorsi | route / routes |
| ride / rides (recorded) | Fahrt / Fahrten | sortie / sorties | salida / salidas | giro / giri | rit / ritten |
| Loop | Runde | Boucle | Circular | Anello | Rondje |
| Stops (layer, places) | Stopps | Haltes | Paradas | Soste | Stopplekken |
| Add as a stop | Als Stopp einfügen | Ajouter comme étape | Añadir como parada | Aggiungi come sosta | Als tussenstop |
| Cycle map | Radkarte | Carte vélo | Mapa ciclista | Mappa ciclabile | Fietskaart |
| Layers | Ebenen | Calques | Capas | Livelli | Kaartlagen |
| Offline data | Offline-Daten | Données hors ligne | Datos sin conexión | Dati offline | Offline gegevens |
| Download | Herunterladen | Télécharger | Descargar | Scarica | Downloaden |
| Update | Aktualisieren | Mettre à jour | Actualizar | Aggiorna | Bijwerken |
| turn instructions | Abbiegehinweise | indications de direction | indicaciones de giro | indicazioni di svolta | afslaginstructies |
| AI assistant | KI-Assistent | Assistant IA | Asistente de IA | Assistente IA | AI-assistent |
| Sync | Synchronisierung | Synchronisation | Sincronización | Sincronizzazione | Synchronisatie |
| Connections | Verbindungen | Connexions | Conexiones | Connessioni | Koppelingen |
| Maps & data | Karten & Daten | Cartes et données | Mapas y datos | Mappe e dati | Kaarten en gegevens |
| Rider & bike | Fahrer & Rad | Cycliste et vélo | Ciclista y bici | Ciclista e bici | Fietser en fiets |
| Touring (profile) | Trekking | Rando | Trekking | Trekking | Toer |

## Known overlaps

Kept on purpose, and why, so that nobody "fixes" one half:

- French "Rouler" is both the Record tab and the Ride button: both start a
  ride, and "Enregistrer" is already Save.
- French "Annuler" and Italian "Annulla" are both Undo and Cancel, as in the
  phones' own systems.
