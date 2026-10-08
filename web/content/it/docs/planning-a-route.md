---
title: Pianificare un percorso
description: Tocca i punti sulla mappa, scegli un profilo bici, confronta le varianti, leggi altimetria e fondo e salva il percorso nella libreria.
order: 2
---

La scheda Pianifica trasforma i tocchi sulla mappa in un percorso in bici, calcolato sul tuo telefono ovunque tu abbia scaricato i dati di routing. Usala quando vuoi decidere un giro in anticipo, ritoccarlo e conservarlo.

## Imposta la partenza e la destinazione

1. Apri la scheda **Pianifica** e sposta la mappa dove vuoi partire.
2. **Tocca la mappa** per impostare la partenza. Il pannello in basso dice "Tocca di nuovo la mappa per aggiungere una destinazione."
3. **Tocca di nuovo** per il punto successivo. Ogni tocco aggiunge un punto alla fine del percorso, e l'ultimo, la destinazione, porta una bandierina. Per inserire invece un punto nel mezzo, **tocca la linea del percorso** dove deve andare: il punto si posa lì sulla linea, e puoi trascinarlo come qualsiasi altro.
4. Velorki aspetta un momento dopo la tua ultima modifica e poi calcola. Mentre lavora il pannello mostra una rotellina e **Calcolo del percorso…**; poi compaiono i numeri.

Puoi anche partire da un luogo invece che da un tocco. Scrivi nel campo di ricerca in alto e scegli un risultato, oppure tocca una [sosta sulla mappa](./stops-on-the-map); finché il piano è ancora vuoto, la [scheda del luogo](./search#la-scheda-del-luogo) offre:

- **Percorso fin qui** porta da dove sei fino al luogo.
- **Parti da qui** rende il luogo il primo punto del percorso.

Con la sola partenza offre **Destinazione**. Quando un percorso è già in pianificazione, la scheda offre **Aggiungi come sosta**, che inserisce il luogo nel percorso nel punto in cui si trova lungo la strada, e **Destinazione**, che lo aggiunge alla fine. Vedi [ricerca](./search) per ciò che il campo di ricerca sa trovare.

## Segna un luogo accanto al percorso

**Tieni premuta la mappa** dove c'è qualcosa da ricordare, e il pannello del punto si apre per un luogo lì: una fontana, una stazione, un campeggio. Il percorso non viene tracciato attraverso di esso. Il segnaposto porta l'icona del tipo che scegli, con il nome accanto, e un tocco su di esso riapre il pannello.

Per spostare un punto che hai già, **trascina il suo segnaposto**. Su un anello chiuso, trascinare il segnaposto di partenza sposta entrambe le estremità, così l'anello resta chiuso. Una modifica ricalcola solo i tratti accanto al punto toccato; il resto del percorso rimane com'era.

## Sul percorso o accanto

Ogni punto è una di due cose, e l'interruttore in alto nel suo pannello dice quale:

- **Sul percorso**: un punto per cui il giro passa. Porta un disco numerato, la destinazione una bandierina con il numero accanto, e il router piega il percorso per visitarlo.
- **Accanto al percorso**: un luogo davanti a cui il giro passa. Porta l'icona del suo tipo, e il percorso lo ignora.

Imposta un punto su **Accanto al percorso** e lascia il percorso, che viene ridisegnato senza di lui; il segnaposto resta dov'è. Impostalo su **Sul percorso** e diventa un punto nel mezzo, nel punto del percorso in cui si trova, e il percorso viene ridisegnato attraverso di esso. In entrambi i casi nome, tipo e nota lo seguono.

## Modifica o rimuovi un punto

Tocca un segnaposto per aprire il suo pannello. Dall'alto:

- **Sul percorso** o **Accanto al percorso**, l'interruttore di cui sopra,
- **Nome**, con l'icona del tipo davanti, precompilato con il nome del punto oppure, per un punto sul percorso senza nome, con il suo numero; un numero lasciato com'è non dà nessun nome. Un luogo accanto al percorso si apre con il nome vuoto,
- **Tipo**: una griglia di riquadri, quattro file da quattro, tutti visibili insieme a qualsiasi larghezza: **Pericolo**, **Acqua**, **Cibo**, **Altro**, **Cima**, **Panorama**, **Riparo**, **Negozio**, **Riparazione bici**, **Pronto soccorso**, **Bagno**, **Campeggio**, **Alloggio**, **Parcheggio**, **Trasporti** e **Svolta**. **Alloggio** è un letto, non una piazzola: un hotel, un ostello, una pensione. Una **Svolta** prende sotto una **Direzione** (sinistra, destra, leggera, stretta, tieni la sinistra o la destra, dritto, inversione) e diventa una riga dell'elenco svolte del percorso, così il banner di svolta e la voce la dicono lì; un percorso importato con un elenco svolte si apre con le sue svolte scritte come punti di questo tipo, pronti per essere modificati. **Svolta** è offerto solo per un punto sul percorso: un'indicazione per una strada che il giro non prende non dice nulla,
- **Nota**,
- **Visita prima** e **Visita dopo**, che scambiano subito il punto con il suo vicino nell'ordine e lasciano il pannello aperto, così un punto può essere spostato e nominato in una sola visita. Solo per un punto sul percorso; un luogo accanto non ha un posto nell'ordine,
- **Rimuovi punto**, per entrambi i tipi,
- **Fatto**, che applica interruttore, nome, tipo e nota. Trascina il pannello verso il basso per lasciarli com'erano.

Uno scambio, una rimozione, un cambio di interruttore e un Fatto che ha cambiato qualcosa sono ciascuno un passo nella cronologia di Annulla. Un punto sul percorso con un nome mostra sul segnaposto il nome invece del numero, con l'icona del tipo accanto. I dettagli vengono salvati con il percorso e tornano quando lo riapri nel pianificatore; per un percorso aperto dalla libreria finiscono subito nella libreria, purché il percorso non sia stato ricalcolato da allora, quindi per un nome o una nota da soli non c'è nessun Salva da premere.

## Cosa diventa ogni punto in un file esportato

Entrambi i tipi vengono esportati, e un ciclocomputer li distingue per quanto il formato lo permette:

- **GPX**: ogni luogo accanto al percorso, e ogni punto sul percorso con un nome o una nota, viene scritto come `<wpt>` con il suo tipo e la sua nota. I punti sul percorso sono anche l'elenco `<rtept>`, così il file può essere pianificato di nuovo.
- **FIT** e **TCX**: entrambi i tipi diventano punti del percorso (course point), accanto alle svolte dell'elenco svolte. FIT ha un tipo proprio per acqua, cibo, pericolo, vetta, primo soccorso, bagno e campeggio; TCX solo per acqua, cibo, pericolo, vetta e primo soccorso. Alloggio, parcheggio e trasporti non hanno un tipo in nessuno dei due e vengono esportati come punti generici con il loro nome. Tutto il resto viene esportato come punto generico con il suo nome.
- Un punto arrivato da un file conserva la parola che quel file usava per lui. Esportalo di nuovo senza cambiarne il tipo e quella parola viene riscritta, così una categoria di salita, uno sprint o un marcatore di segmento — cose per cui Velorki non ha un tipo proprio — sopravvivono al viaggio di andata e ritorno. Cambia il tipo e viene scritta invece la parola del nuovo tipo.

## Scegli la bici

La fila di chip sotto il campo di ricerca è il profilo bici, e decide quali strade e sentieri piacciono al router:

| Profilo | A cosa serve |
|---|---|
| **Trekking** | il predefinito: un mix sensato di strade tranquille e piste ciclabili |
| **Corsa** | asfalto, meno deviazioni, evita i fondi sconnessi |
| **Gravel** | a suo agio su strade bianche e fondi non asfaltati |
| **MTB** | sentieri e singletrack |
| **Diretto** | la via più corta, con il minimo riguardo per il comfort |

Ogni profilo tranne **Diretto** è quello di BRouter con una modifica di Velorki: non ti manda contromano in un senso unico né su un marciapiede per risparmiare un isolato. Cambiare profilo ricalcola l'intero piano, compreso un percorso da file, e cancella le varianti che avevi caricato; **Annulla** rimette a posto percorso e profilo. Velorki conserva l'ultimo profilo scelto per il prossimo avvio.

## Un percorso da file

Un percorso aperto da un file conserva esattamente la linea del file, con punti solo alla partenza, alla fine e nei luoghi con nome sulla traccia. Spostare, aggiungere o rimuovere un punto ricalcola solo i tratti accanto; ovunque altrove la linea resta quella del file. Finché il percorso differisce dal file, la linea del file è disegnata in trasparenza sotto e un chip sopra la mappa dice **Diverso dal file**; il suo **Ripristina** rimette il percorso del file, in un passo che Annulla può annullare.

## La barra degli strumenti

La fila di pulsanti dentro il pannello del percorso:

- **Annulla** annulla l'ultima modifica. Non c'è limite e non c'è ripeti. Aggiungere, inserire, spostare, rimuovere e riordinare punti, **Inverti**, **Cancella**, il cambio di profilo bici, **Ripristina**, chiudere un anello e scegliere un'altra via di ritorno sono tutti annullabili; cambiare variante e caricare un percorso salvato no.
- **Inverti** percorre il percorso al contrario.
- **Cancella** butta via il piano. Anche questo è annullabile.
- **Varianti** chiede alternative (vedi sotto).
- **Anello** apre il pannello degli anelli intelligenti, descritto in [anelli](./loops).
- **Chiedi** apre l'[assistente](./assistant). C'è solo quando la build parla con un server Velorki.

Sotto la fila c'è il pulsante **Salva** a tutta larghezza.

## Varianti

Velorki non cerca alternative da solo, perché ognuna è un calcolo a parte. Tocca **Varianti** e chiede fino a quattro percorsi per gli stessi punti.

Sopra la barra compare allora una fila di chip: **Principale**, **Alt 1**, **Alt 2**, **Alt 3**, ognuno con un punto colorato che corrisponde alla sua linea sulla mappa. Toccare un chip cambia all'istante, senza nuovo calcolo, e porta quella linea in primo piano.

Le varianti sono percorsi interi disegnati dal router, quindi su un percorso da file sostituiscono la linea del file; **Annulla** la riporta indietro. Spesso ne arrivano meno di quattro; quello che il router ha trovato è quello che ottieni. Se non ne trova nessuna, Velorki dice "Nessuna alternativa disponibile." Modificare un punto o cambiare il profilo bici cancella le varianti, quindi chiedile di nuovo dopo.

## Leggi il percorso

L'intestazione del pannello mostra quattro numeri: **Distanza**, **Dislivello**, **Discesa** e **Durata**. Il tempo stimato viene dalla velocità tipica del profilo bici scelto, non da un server, e non tiene conto delle tue soste al bar.

Il pannello scorre a qualsiasi altezza; trascina la sua maniglia o il suo titolo verso l'alto per avere più spazio, o un punto qualsiasi quando non c'è nulla da scorrere. Tirato tutto in basso, si ripiega nella barra di navigazione e lascia solo la maniglia sopra le schede, così la mappa è libera; trascina la maniglia verso l'alto per riaverlo.

### Altimetria

Il grafico **Altimetria** disegna l'altitudine in funzione della distanza. Toccalo e trascina lungo di esso: accanto alla didascalia compare una lettura nella forma `12,3 km · 340 m`, che segue il tuo dito. Sollevalo e la lettura scompare. Un percorso senza dati altimetrici dice "Nessun dato altimetrico per questo percorso."

### Fondo

La barra **Fondo** è un'unica barra impilata di tre quote che insieme fanno l'intero percorso, **Asfaltato**, **Sterrato** e **Sconosciuto**, con sotto una legenda di percentuali. Altre due voci nella legenda, **Pista ciclabile** e **Strade trafficate**, si sovrappongono alle prime tre invece di sommarsi: ti dicono quanta parte del percorso è su una ciclabile dedicata e quanta su una strada grande. Per un percorso che non è tutto del router, con dentro la linea di un file, l'intera linea viene confrontata con i dati di routing per ottenere i numeri, e questo richiede la regione scaricata.

## Salvalo

1. Tocca **Salva**.
2. La finestra **Salva percorso** propone un nome, quello con cui era stato salvato prima oppure **Percorso 17 set 2026** con la data di oggi.
3. Scrivi un nome tuo, o lascialo, e tocca **Salva**.

Ricevi "Percorso salvato", e il percorso è in **Libreria → Percorsi**. Salvare un percorso che avevi già salvato aggiorna la stessa voce invece di crearne una seconda.

## Quando non calcola

- **"Questo percorso richiede riquadri di routing che non sono su questo dispositivo."** compare al posto dei numeri quando il tuo telefono non ha dati di routing per la zona e nessun server di routing su cui ripiegare. Il pulsante sotto conta i riquadri e la loro dimensione, per esempio **Scarica 3 riquadri (412 MB)**, e apre la schermata offline con esattamente quei riquadri selezionati. Vedi [mappe offline e calcolo del percorso](./offline-maps-and-routing).
- **"Nessun server di routing configurato, impostane uno in Opzioni → Avanzate."** è una scheda sotto i chip della bici, e significa che questa build non ha alcun indirizzo di server.
- Tutto il resto compare come **Calcolo del percorso non riuscito:** con il motivo.

## Vedi anche

- [Anelli](./loops)
- [Ricerca](./search)
- [Mappe offline e calcolo del percorso](./offline-maps-and-routing)
- [Libreria](./library)
- [Navigazione svolta per svolta](./navigation)
