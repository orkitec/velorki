---
title: Primi passi
description: Installa Velorki, capisci le quattro schede, scopri quali permessi chiede e perché, e imposta le tue unità. Non serve nessun account.
order: 1
---

Velorki è un pianificatore di percorsi in bici e registratore di giri gratuito e open source per iPhone e Android, costruito sui dati di OpenStreetMap. Questa pagina copre i primi dieci minuti: installarlo, cosa chiede, com'è organizzata l'app e l'unica impostazione che la maggior parte dei ciclisti vuole cambiare subito.

## Cosa ti serve

- Un iPhone con iOS 15 o successivo, oppure un telefono Android con Android 8.0 o successivo.
- Nessun account. Velorki non ha registrazione, login né password. Nulla su di te viene salvato su un server.
- Nessuna connessione, una volta scaricata un'area. Pianificazione, calcolo del percorso, ricerca dei luoghi, navigazione e registrazione girano tutti sul telefono.

## Installalo

1. Installa Velorki dall'App Store o da Google Play, come qualsiasi altra app.
2. Aprilo. Non c'è una schermata di registrazione né un tour da sfogliare; l'app si apre sulla mappa.

Velorki è open source. Se preferisci compilarlo da solo, o far girare i tuoi server per le parti che li usano, il codice e le istruzioni sono su [github.com/orkitec/velorki](https://github.com/orkitec/velorki).

## Il primo avvio

Velorki si apre sulla scheda **Pianifica**, mostrando una mappa del mondo. Non è ancora stato scaricato nulla e non è ancora stato chiesto nessun permesso.

Una buona prima sessione:

1. Sposta la mappa dove pedali e allarga le dita per ingrandire.
2. Tocca la mappa per impostare una partenza, tocca di nuovo per aggiungere una destinazione. Un percorso compare in un attimo.
3. Tocca il pulsante di download a destra della mappa (**Dati offline**) e scarica l'area, così la mappa e il calcolo del percorso continuano a funzionare quando il segnale no. Vedi [mappe offline e calcolo del percorso](./offline-maps-and-routing) per cosa sono i due download e quanto diventano grandi.
4. Imposta le tue unità in **Opzioni → Aspetto → Unità** se l'app ha indovinato male.

## I permessi che chiede, e perché

Velorki non chiede nulla all'avvio. Ogni permesso viene richiesto nel momento in cui serve per la prima volta, e ognuno viene spiegato prima che compaia la finestra di sistema.

### Posizione

Chiesto la prima volta che tocchi **Mostra la mia posizione**, avvii un giro o chiedi un anello da dove sei.

Velorki mostra prima la sua finestra, intitolata **Mostrare la tua posizione?**: "Velorki usa la tua posizione per centrare la mappa su di te e registrare i giri. La posizione resta su questo dispositivo e non viene mai caricata." Puoi rispondere **Non ora** e continuare a usare l'app; solo le funzioni che devono sapere dove sei smettono di funzionare.

Con il permesso concesso, la mappa si apre dove l'avevi lasciata e poi scivola verso la tua posizione: subito dove il telefono ti ha visto l'ultima volta se è meno di un'ora fa, e al primo rilevamento fresco quando non lo è, o quando quel rilevamento ti mette a più di circa 300 m da lì, sia all'avvio dell'app sia quando ci torni dopo mezz'ora o più. Resta ferma mentre c'è un piano nella scheda Pianifica, una scheda di percorso o giro è aperta, un giro è in registrazione, sei già in vista, o hai spostato la mappa tu stesso.

"Mentre usi l'app" è sufficiente. Su Android, Velorki deliberatamente **non** chiede la posizione in background: la registrazione dei giri gira invece come servizio in primo piano con una notifica. Su iOS, "Mentre usi l'app" più la modalità posizione in background copre un giro registrato con lo schermo spento.

### Notifiche (Android)

Chiesto la prima volta che avvii un giro. La registrazione gira dentro una notifica che mostra distanza e tempo, e Android interrompe la registrazione se quella notifica non può essere pubblicata. Se rifiuti, Velorki lo dice: "Senza il permesso per le notifiche Android interrompe la registrazione quando esci dall'app."

### Ottimizzazione della batteria (Android)

Chiesto una volta sola, la prima volta che avvii un giro: **Continua a registrare in background**: "Android potrebbe interrompere la registrazione mentre il telefono dorme. Nelle impostazioni della batteria che si aprono, scegli Velorki e consenti l'uso della batteria senza limitazioni (su alcuni telefoni: non ottimizzata), così la traccia resta completa. Te lo chiediamo una sola volta." Rispondi **Apri impostazioni** o **Non ora**; non viene chiesto mai più.

### File

Nessun permesso permanente. Quando importi un file GPX, FIT o TCX, il selettore di file del sistema consegna quel singolo file all'app; quando esporti, il foglio di condivisione del sistema lo porta via di nuovo.

Velorki non chiede nient'altro. Non c'è accesso a contatti, foto, microfono, salute o pubblicità in nessun punto dell'app.

## Le quattro schede

La barra in basso ha quattro schede.

| Scheda | Cosa c'è |
|---|---|
| **Pianifica** | La mappa, la ricerca dei luoghi, il pianificatore di percorsi, gli anelli intelligenti e l'assistente. |
| **Registra** | Avviare, mettere in pausa e terminare un giro, i numeri in tempo reale e i tuoi giri recenti. |
| **Libreria** | Tutto ciò che hai salvato: **Percorsi** e **Giri**, con importazione ed esportazione. |
| **Opzioni** | Aspetto, unità e lingua, opzioni di navigazione e registrazione, dati offline, ricerca, connessioni, abbonamento e le pagine legali. |

La barra galleggia sopra il contenuto, così gli elenchi scorrono sotto di essa.

## Unità

Velorki mostra le distanze in chilometri e metri, o in miglia e piedi, e usa la tua scelta ovunque: le statistiche, i cursori, gli assi dei grafici, il banner di svolta e le indicazioni vocali.

1. Apri **Opzioni**.
2. Sotto **Aspetto**, trova **Unità**.
3. Scegli **Metrico** o **Imperiale**.

Finché non scegli, Velorki segue il paese del telefono: imperiale solo dove il paese lo usa, metrico ovunque altrove.

## Dove si trovano le cose

- **I controlli della mappa** stanno in una colonna a destra della mappa: **Mostra la mia posizione**, **Livelli** (la mappa ciclabile e le [soste sulla mappa](./stops-on-the-map)), **Dati offline** (non su uno schermo piccolo come un iPhone SE), **Ingrandisci** e **Riduci**. Nella scheda Registra si aggiunge un pulsante bussola, che alterna tra **Nord in alto** e **La mappa gira con te**.
- **Il campo di ricerca** è in alto nella scheda Pianifica.
- **Il profilo bici** (Trekking, Corsa, Gravel, MTB, Diretto) è la fila di chip sotto il campo di ricerca.
- **Il pannello del percorso** è il riquadro in basso nella scheda Pianifica. Trascinalo verso l'alto per l'altimetria e la ripartizione del fondo, verso il basso per vedere più mappa.
- **Un foglio sopra la mappa**, come Livelli, la scheda di un luogo, il foglio di un punto o quello degli anelli, porta la scheda del tab alla sua altezza minima finché è aperto; risale quando il foglio si chiude.

## Vedi anche

- [Pianificare un percorso](./planning-a-route)
- [Mappe offline e calcolo del percorso](./offline-maps-and-routing)
- [Registrare un giro](./recording-a-ride)
- [Opzioni e aspetto](./settings-and-appearance)
- [Privacy sul telefono](./privacy-on-the-phone)
