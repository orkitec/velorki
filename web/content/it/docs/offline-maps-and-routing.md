---
title: Mappe offline e calcolo del percorso
description: Scarica la mappa che guardi e i dati da cui vengono calcolati i percorsi, così pianificazione, ricerca e navigazione funzionano anche senza segnale.
order: 6
---

Due download separati fanno funzionare Velorki senza connessione: la **mappa**, che è quello che vedi, e i **dati di routing**, da cui vengono calcolati i percorsi e la ricerca offline. Scarica entrambi per la zona in cui pedali prima di un giro che si lascia il segnale alle spalle.

## I due tipi

| | Mappa | Dati di routing |
|---|---|---|
| Mostrato come | **Mappa** | **Dati di routing** |
| Cos'è | riquadri vettoriali di mappa da OpenFreeMap, disegnati da OpenStreetMap | riquadri BRouter dal mirror di Velorki, costruiti da OpenStreetMap |
| Copre | esattamente il rettangolo che avevi sullo schermo | un quadrato fisso di 5° × 5° del mondo |
| Dimensione | decine di megabyte per una città | spesso da 125 a 250 MB per riquadro |
| Senza | riquadri grigi dove la mappa non è stata memorizzata | nessun calcolo del percorso e nessuna ricerca offline in quella zona |

I dati di routing contengono anche l'indice dei luoghi, quindi una zona scaricata permette anche la ricerca offline e mostra le sue [soste sulla mappa](./stops-on-the-map). Per questo la schermata dei riquadri di routing dice "Una regione scaricata permette anche la ricerca dei luoghi senza segnale." La stessa regione scaricata è quella che dà a un giro registrato la ripartizione del fondo, vedi [la libreria](./library).

## Scaricare una zona

1. Nella scheda **Pianifica**, sposta la mappa in modo che la zona che vuoi riempia lo schermo. Non allontanare lo zoom più del necessario: il download della mappa segue esattamente quello che c'è sullo schermo.
2. Tocca il pulsante **Dati offline** nella colonna a destra della mappa. Su uno schermo piccolo come quello di un iPhone SE la colonna non ha spazio per esso: lì tocca **Scarica quest'area per cercare offline** in fondo ai risultati del campo di ricerca, o il pulsante di download sotto un percorso a cui servono riquadri, e gestisci quello che hai in **Opzioni → Dati offline**.
3. Leggi i due pannelli, poi tocca **Scarica l'area visibile** in fondo.
4. La finestra **Scarica l'area visibile** elenca quello che stai per scaricare: "Mappa dell'area visibile · dimensione nota dopo il download" per la mappa, poi una riga per riquadro di routing con la sua dimensione, per esempio `E5_N45 · 187 MB`, oppure "I dati di routing per quest'area sono già sul dispositivo".
5. Tocca **Scarica**.

Entrambi i download avvengono mentre l'app è aperta. I pannelli mostrano **Download della mappa…** e **Download di E5_N45…** con barre di avanzamento.

La schermata ti avvisa per un motivo: "I riquadri sono grandi, spesso 125–250 MB ciascuno, e Velorki non distingue il Wi-Fi dai dati mobili. Avvia il download quando sei sotto Wi-Fi."

Puoi raggiungere questa schermata anche da **Opzioni → Dati offline**, ma aperta così non c'è una mappa dietro, quindi il pulsante di download è disattivato e la nota dice "Apri questa schermata dalla mappa per scaricare l'area che stai guardando."

## Gestire le aree di mappa

**Gestisci** sul pannello **Mappa** apre **Mappe offline**, una riga per area scaricata:

- Il nome che Velorki le ha dato, **Zona mappa 1**, **Zona mappa 2** e così via.
- La dimensione e la data, "12,3 MB · Scaricata il 14 set 2026".
- **Aggiornamento disponibile** in arancione quando l'area ha più di due mesi, e accanto un pulsante **Aggiorna**. Un aggiornamento è un nuovo download completo.
- Un pulsante **Elimina**, che chiede "Eliminare l'area offline?" con "I riquadri scaricati vengono rimossi da questo dispositivo."

Il pannello nella schermata offline riassume la stessa cosa: "3 aree, 48 MB", e "2 aree hanno più di due mesi e possono essere aggiornate".

## Gestire i riquadri di routing

**Gestisci** sul pannello **Dati di routing** apre **Dati di routing offline**. Ogni riga è un riquadro di 5° × 5° con nome, dimensione e stato:

| Stato | Significato |
|---|---|
| **Su questo dispositivo** | pronto, calcolo del percorso e ricerca offline funzionano qui |
| **Aggiornamento disponibile** | il mirror ha ricostruito questo riquadro; **Aggiorna** lo scarica di nuovo |
| **Serve un Velorki più recente** | il riquadro ricostruito è in un formato dati che questa versione dell'app non può leggere |
| **Download in corso…** | in corso |
| **Non scaricato** | noto al mirror, non sul telefono |

Sempre nella schermata:

- **Necessari per questo percorso** appare quando arrivi dal banner dei riquadri mancanti del pianificatore, con i riquadri che servono a quel percorso già selezionati e un pulsante che li conta, per esempio **Scarica 1 riquadro (187 MB)**.
- **Scarica per l'area visibile** in fondo, con il totale di tutto quello che hai: "3 riquadri, 540 MB".
- **Aggiornato sul mirror 1 set 2026** sotto ogni riga, cioè la data in cui il mirror ha prodotto quel riquadro l'ultima volta.
- Un pulsante **Elimina** su ogni riga, con l'avviso "Il riquadro viene rimosso da questo dispositivo. I percorsi in quell'area torneranno a richiedere il server di routing."
- Un pulsante **Annulla download** nell'intestazione dell'avanzamento mentre uno è in corso.

Velorki controlla ogni settimana se il mirror ha ricostruito qualcosa che possiedi. Quando è così, la riga **Dati offline** in Opzioni diventa arancione, mostra "2 riquadri hanno aggiornamenti" e mette un contatore sulla freccia.

## Il gazetteer, ovvero l'indice di ricerca

Ogni riquadro di routing che il mirror pubblica ha accanto un piccolo indice di ricerca, e Velorki li scarica insieme. Niente di questo è esposto come impostazione separata o download separato.

Se il download dell'indice fallisce, il riquadro in sé va comunque bene: la zona resta percorribile e la sua ricerca passa semplicemente online. Lo stesso vale per un indice in un formato che questa versione dell'app non legge; viene saltato, le altre zone continuano a rispondere offline, e quella zona cerca online.

## Dove sta tutto, e come liberarsene

Tutto è dentro lo spazio di archiviazione dell'app sul telefono, non nei tuoi documenti o nella tua libreria fotografica, e niente viene copiato in un backup cloud.

Per liberare spazio:

- elimina singole aree di mappa in **Mappe offline**,
- elimina singoli riquadri di routing in **Dati di routing offline**,
- oppure disinstalla l'app, che rimuove tutto, insieme ai tuoi percorsi e giri. Esporta prima quello che vuoi conservare, vedi [importazione ed esportazione](./import-and-export).

## "Aggiorna prima Velorki"

I riquadri di routing cambiano formato di tanto in tanto. Quando il mirror offre un riquadro che questa versione dell'app non può leggere, Velorki lo dice invece di scaricare spazzatura: **Aggiorna prima Velorki**, "Questi riquadri sono nel formato dati 5, e questo Velorki legge fino a 4. Servono un Velorki più recente; scaricali dopo l'aggiornamento." Rispondi **Non ora**, oppure **Apri lo store** per andare ad aggiornare.

I riquadri che hai già continuano a funzionare.

## Vedi anche

- [Ricerca](./search)
- [Pianificare un percorso](./planning-a-route)
- [Navigazione svolta per svolta](./navigation)
- [Risoluzione dei problemi](./troubleshooting)
