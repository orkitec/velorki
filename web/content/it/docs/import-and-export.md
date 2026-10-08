---
title: Importa ed esporta
description: Apri file GPX, FIT e TCX da qualsiasi punto del telefono, salvali come percorsi o giri ed esporta i tuoi verso Komoot, Garmin o qualsiasi altra cosa.
order: 9
---

Velorki legge e scrive file GPX, FIT e TCX, ed è così che percorsi e giri si spostano tra l'app e il resto del mondo. Tutto è gratuito, non richiede né account né connessione, e funziona con Komoot, Garmin Connect, Strava, un ciclocomputer o un semplice file sul telefono.

## Portare dentro un file

Ci sono tre strade, e tutte e tre finiscono sulla stessa schermata di importazione.

**Apri con.** Tocca un file GPX, FIT o TCX nella tua app dei file, in un'email o nei download del browser, e scegli Velorki. Su un iPhone è "Apri in Velorki" da File, Mail o Safari.

**Foglio di condivisione.** In un'altra app, condividi il file e scegli Velorki. È così che arriva un percorso da Komoot o dal messaggio di un amico.

**Il selettore.** Nella scheda **Libreria**, tocca **Importa file** in alto a destra e scegli tu il file.

**Un link di Ride with GPS.** Condividi il link di un percorso dall'app Ride with GPS o da un browser e scegli Velorki, e il percorso arriva sulla schermata di importazione. Un percorso pubblico non richiede altro; uno privato viene recuperato tramite il tuo account Ride with GPS collegato, e senza account la schermata dice "Questo percorso di Ride with GPS è privato. Collega Ride with GPS nelle Opzioni per aprirlo."

Un file che non può essere importato apre la stessa schermata con il motivo: non è un file GPX, FIT o TCX, è illeggibile, è vuoto, oppure è un link che non è stato possibile recuperare.

Velorki capisce cos'è il file leggendone i primi byte, non fidandosi del nome o del tipo, quindi un `.gpx` che in realtà è un file FIT viene importato comunque. Un file TCX viene riconosciuto dal suo elemento radice.

## Un luogo da un'altra app

Velorki accetta anche un singolo luogo verso cui pedalare, e lo apre nella scheda **Pianifica** come si apre un risultato di ricerca: fissato sulla mappa, sulla sua scheda con **Percorso fin qui** e **Parti da qui**.

- **Foglio di condivisione.** Condividi un luogo da Google Maps, Apple Maps, OpenStreetMap, un browser o un'app di messaggi e scegli Velorki. Funzionano un link a una mappa, coordinate come `52.5200, 13.4050` o `52°31'12"N 13°24'18"E`, o un indirizzo; un indirizzo finisce nel campo di ricerca, che lo trova.
- **Apri con** (Android). Un luogo aperto da un'altra app (un link `geo:`) offre Velorki nella scelta.
- **Link brevi** come `maps.app.goo.gl/…`, `maps.apple/p/…` o `osm.org/go/…` dicono dove puntano solo quando vengono aperti. Online, Velorki li apre (una richiesta a quel servizio, nient'altro inviato) e arriva sul luogo; offline lo dice: apri prima il link in un browser, poi condividi il luogo da lì.

**Per gli sviluppatori di app**, Velorki apre questi link:

| Link | Apre |
|---|---|
| `velorki://navigate?lat=52.52&lon=13.405&name=Brandenburger%20Tor` | il luogo a quelle coordinate, etichettato con `name` (facoltativo) |
| `velorki://navigate?q=Pariser%20Platz%201%2C%20Berlin` | una ricerca dell'indirizzo o del nome del luogo |

Le coordinate sono gradi decimali (WGS 84); ogni valore è codificato per URL. Su Android funziona anche un intent `geo:` (`geo:LAT,LON`, `geo:0,0?q=LAT,LON(Etichetta)`, `geo:0,0?q=indirizzo`).

## La schermata di importazione

Intitolata **Importa**, mostra:

- un'anteprima della traccia sulla mappa, con i punti del file come piccoli segnaposto con il loro nome: i punti di interesse arrivati con un percorso, una zona in cui scendere dalla bici, una fontanella, un tratto sconnesso, nel colore del loro tipo,
- un campo **Nome**, precompilato dal nome del file,
- il formato e la dimensione, "GPX · 4.812 punti",
- l'intervallo di tempo, "16 set 2026, 09:12 – 16 set 2026, 13:40", oppure "Il file non contiene orari.",
- distanza, dislivello, discesa e durata,
- **SALVA COME**, un interruttore tra **Percorso** e **Giro**.

La mappa resta in alto mentre le pagine sotto scorrono, con dei puntini sotto la mappa che dicono quale pagina è in vista. Uno scorrimento a sinistra è l'altimetria. Quando il file ha svolte o punti di interesse, uno scorrimento ancora è l'**ELENCO SVOLTE**, ogni svolta e punto di interesse con la distanza dalla partenza, ripiegato a otto righe con **Mostra tutte**. Tocca una riga e la mappa si sposta lì allo zoom che hai, con il nome fissato; tocca un segnaposto sulla mappa e l'elenco svolte compare con la sua riga selezionata e scorsa in vista. Una riga selezionata si apre con quello che c'è da sapere, la nota di un pericolo o la manovra semplice sotto le parole dell'autore.

Un percorso GPX con un elenco svolte, l'esportazione di percorso di Ride with GPS o un percorso Garmin, porta con sé le sue svolte: ogni indicazione diventa un'istruzione di svolta con le parole dell'autore, mostrata nel banner di svolta, nella pagina dell'elenco svolte e detta dalla voce. Una traccia GPX non ha un elenco svolte; il banner di svolta di Velorki funziona comunque su di essa a partire dalla forma del percorso.

Velorki indovina **Percorso** o **Giro** dal fatto che i punti abbiano o no un orario: una registrazione lo ha, un percorso pianificato no. Un percorso FIT viene riconosciuto come percorso e proposto come percorso, qualunque cosa dica la sua base temporale sintetica, e così un percorso TCX; i suoi course point diventano l'elenco svolte del percorso (svolte) e i suoi punti di interesse (acqua, cibo, pericoli, luoghi con nome). Nulla viene scritto finché non tocchi **Salva**.

Un percorso si apre con la bici che il suo file indica: un `<type>` GPX come `road_biking` o `mountain_biking`, o il sotto-sport di un percorso o di un'attività FIT (strada, mountain bike, gravel), diventa **Corsa**, **MTB**, **Gravel** o **Trekking**. Un file che non ne indica nessuna si apre con la bici con cui hai pedalato l'ultima volta. Un percorso esportato riscrive la sua bici allo stesso modo; un file TCX non ha una parola per questo.

Un'attività FIT da un ciclocomputer porta più della sua traccia: i lap che il dispositivo ha tagliato sostituiscono i parziali fissi nella pagina del giro, i totali scritti dal dispositivo (distanza, tempo in movimento, dislivello, calorie) sono mostrati sotto **Come registrato dal dispositivo** dove differiscono da ciò che Velorki calcola dalle posizioni, e una temperatura, quando il dispositivo ne ha registrata una, ha un grafico tutto suo. Un giro GPX porta frequenza cardiaca, cadenza, potenza e temperatura dalle sue estensioni allo stesso modo. Un file GPX con più tracce, per esempio un tour di più giorni, le elenca con una casella ciascuna, e salva un giro (o un percorso) per ogni traccia spuntata.

Dopo ricevi "Anello alpino aggiunto alla libreria" o "Anello alpino aggiunto ai tuoi giri", e arrivi sulla scheda del nuovo elemento nella scheda Libreria.

Se il file non si apre, Velorki dice qual era il problema: "Non è un file GPX, FIT o TCX.", "Impossibile leggere il file.", "Il file non contiene punti traccia." oppure "Impossibile aprire il file."

## Portare fuori un file

**Da un percorso** (Libreria → Percorsi → aprilo → **Esporta**):

| Formato | A cosa serve |
|---|---|
| **Percorso GPX** | un percorso pianificato per un altro pianificatore, un'app per telefono o un ciclocomputer. Un percorso con elenco svolte viene scritto come lo scrive Ride with GPS: una `<rte>` delle svolte, ciascuna con direzione e parole, e accanto un `<trk>` dell'intera linea; un percorso senza elenco svolte conserva ogni punto nella `<rte>`. |
| **Percorso FIT** | un Garmin, Wahoo o ciclocomputer simile che si aspetta un course; l'elenco svolte e i punti di interesse vanno con esso come course point, così il dispositivo mostra la prossima svolta |
| **Percorso TCX** | un Garmin più vecchio o un sito di allenamento che legge Training Center XML; l'elenco svolte e i punti di interesse vanno con esso come course point, con i nomi tagliati ai dieci caratteri che il formato permette |

**Da un giro** (Libreria → Giri → aprilo, oppure la scheda del giro dopo averlo terminato):

| Formato | A cosa serve |
|---|---|
| **Esporta traccia GPX** | la traccia registrata con le sue marche temporali; frequenza cardiaca, cadenza, potenza e temperatura vanno con essa. |
| **Esporta attività FIT** | un file di attività per una piattaforma di allenamento |
| **Esporta attività TCX** | lo stesso in Training Center XML, un lap per ogni lap con cui il giro è arrivato, frequenza cardiaca, cadenza e potenza su ogni punto |

In entrambi i casi Velorki scrive il file e lo passa al foglio di condivisione del sistema, così puoi metterlo nei tuoi file, inviarlo per email o mandarlo in un'altra app.

## Komoot, Garmin e gli altri

Velorki non ha un'integrazione con Komoot o Garmin, e non ne ha bisogno: tutti parlano GPX e FIT, e la maggior parte legge ancora TCX.

- **Da Komoot a Velorki**: esporta il tour come GPX in Komoot, poi condividilo con Velorki, oppure salvalo e aprilo con il pulsante **Importa file**.
- **Da Velorki a Komoot**: esporta il percorso come **Percorso GPX** e condividilo nell'importazione di Komoot.
- **Verso un ciclocomputer Garmin**: esporta il percorso come **Percorso FIT**, o come **Percorso GPX** se il tuo dispositivo lo preferisce, e mettilo sul dispositivo come fai di solito, tramite Garmin Connect o copiando il file.
- **Da un Garmin**: l'attività `.fit` del dispositivo si importa come giro.

Anche inviare un percorso **a Strava** passa da un file, perché l'API di Strava non può creare percorsi. Vedi [Strava e Ride with GPS](./strava-and-ridewithgps).

## Vedi anche

- [Libreria](./library)
- [Strava e Ride with GPS](./strava-and-ridewithgps)
- [Condivisione](./sharing)
- [Registrare un giro](./recording-a-ride)
