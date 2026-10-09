---
title: Registrare un giro
description: Avvia, metti in pausa e termina un giro, continua a registrare con lo schermo spento, risparmia batteria e recupera un giro dopo una chiusura forzata.
order: 9
---

La scheda Registra traccia il tuo giro e lo salva nella libreria quando termini. Continua a registrare con lo schermo spento e con l'app in background, e sopravvive alla chiusura o alla terminazione forzata dell'app.

La registrazione è gratuita e funziona anche senza alcuna connessione.

## Avvia, pausa, termina

1. Apri la scheda **Registra**. Il pannello dice **Pronto a partire**, con un breve suggerimento sotto.
2. Sotto **Segui un percorso** scegli cosa segue il giro: **Nessun percorso**, **Il percorso nella scheda Pianifica** (offerto finché ce n'è uno) oppure uno dei tuoi percorsi salvati. Un percorso attiva la guida descritta in [navigazione svolta per svolta](./navigation). Finché non scegli, la scheda propone il percorso da cui arrivi: il percorso di cui avevi la scheda aperta nella Libreria, o il piano nella scheda Pianifica; la tua scelta vale poi fino al riavvio dell'app.
3. Tocca **Inizia giro**.
4. Durante il giro il pannello mostra un'etichetta di stato, il cronometro e i numeri: **Distanza**, **Velocità**, **Media**, poi **Dislivello**, **Discesa**, **In movimento**. Mentre segui un percorso si aggiunge una riga **Rimanenti** e **Arrivo**: la distanza ancora da pedalare e quando arriverai alla tua velocità media finora, due trattini finché il giro non ha una media.
5. **Pausa** ferma la traccia dove sei; **Riprendi** continua. L'interruzione appare come un vuoto nella traccia. In pausa i numeri si attenuano e l'etichetta diventa **IN PAUSA**, così lo stato è chiaro a colpo d'occhio.
6. **Termina** salva il giro con un nome predefinito come **Giro 17 set 2026** e apre la sua pagina.

Se termini senza aver registrato nulla, Velorki dice "Non è stato registrato nulla." e non salva alcun giro.

### Pausa automatica

Velorki si mette in pausa da solo dopo circa dieci secondi senza movimento; l'etichetta dice allora **PAUSA AUTOMATICA**. A differenza di una pausa manuale continua ad ascoltare, e il primo movimento vero la fa riprendere. Una pausa manuale smette di ascoltare finché non premi **Riprendi**.

## Frequenza cardiaca, cadenza e potenza

Quando un sensore è attivo, una terza riga di numeri si aggiunge al pannello con ciò che è stato riportato durante questo giro: **Frequenza cardiaca**, **Cadenza** e **Potenza**, quindi un orologio da solo aggiunge un riquadro. Il riquadro della frequenza cardiaca porta sotto la **FC media** del giro. Un sensore che tace a metà giro, un orologio fuori portata o una fascia che si è spostata, conserva il suo riquadro con l'ultimo valore attenuato e un segno di collegamento interrotto, così vedi che qualcosa ha smesso di riportare; mentre il giro è in pausa il sensore riposa di proposito e nulla viene segnato. Possono venire da un sensore Bluetooth, da un Apple Watch o dall'app salute del telefono, vengono scritti sulla traccia mentre pedali, e su un iPhone il battito compare anche sulla scheda della schermata di blocco. Mentre un sensore ruota riporta, la sua velocità è quella che **Velocità** mostra.

Senza un sensore non compare nulla di tutto questo, e nulla è attivo finché non lo attivi in **Opzioni → Sensori**. Vedi [sensori e il tuo orologio](./sensors-and-watch).

## L'altimetria e l'elenco svolte

Il pannello sotto la mappa ha tre pagine, uno scorrimento di distanza, con tre puntini sotto i numeri che dicono quale è in vista. Un nuovo giro parte sui numeri. Il pannello scorre a qualsiasi altezza e si muove dalla maniglia o dal titolo, o da un punto qualsiasi quando non c'è nulla da scorrere, come durante un giro. Prima di un giro, tirato tutto in basso, si ripiega nella barra di navigazione e lascia solo la maniglia sopra le schede, così la mappa è libera; trascina la maniglia verso l'alto per riaverlo. Durante un giro le schede scompaiono, e il pannello si ripiega in una barra della stessa forma con i primi quattro numeri del giro, distanza, velocità, media e dislivello, e la mappa sopra; un punto su di essa significa in pausa. Non ha pulsanti: toccala o tirala su per riavere il pannello.

**L'altimetria**, uno scorrimento a sinistra: il percorso seguito come altitudine in funzione della distanza, la parte già pedalata riempita nel colore d'accento, la strada davanti in grigio, una linea dove sei, e sopra ciò che resta, "12,4 km rimanenti, 320 m di salita". Su una salita del 3 % o più una seconda riga dice la pendenza e quanto manca alla cima, "Salita al 6 %, 120 m alla cima", e quando il giro ha una velocità media la stessa riga dice quando arriverai, "Arrivo 14:32". Senza un percorso da seguire la pagina lo dice: "Segui un percorso per vederne qui l'altimetria."

**L'elenco svolte**, uno scorrimento ancora: **Prossime svolte**, le prossime otto svolte del percorso in ordine con la distanza a ciascuna, i punti di interesse sul percorso tra di esse, e **Arrivo a destinazione** alla fine, con "Altre 3" sotto quando ne seguono altre. La prima riga è ciò che mostra il banner di svolta. Un percorso importato con un elenco svolte mostra per ogni svolta le parole dell'autore, "Turn left onto Main Street", invece dell'istruzione semplice.

## Cosa chiede la prima volta

Il primo giro fa comparire fino a tre richieste, descritte per intero in [primi passi](./getting-started):

- **Posizione**, con prima la spiegazione di Velorki.
- **Notifiche** su Android, perché la registrazione vive in una di esse. Rifiuta e Velorki avverte "Senza il permesso per le notifiche Android interrompe la registrazione quando esci dall'app."
- **Ottimizzazione della batteria** su Android, una volta sola: **Apri impostazioni** porta alle impostazioni della batteria, dove scegli Velorki e consenti l'uso della batteria senza limitazioni.

## Schermo spento, app chiusa

La traccia viene scritta sul telefono mentre pedali, salvata ogni pochi secondi, quindi nulla dipende dal fatto che l'app resti in primo piano.

- **Android**: il giro gira in un servizio in primo piano con una notifica permanente intitolata **Registrazione di un giro**, la cui seconda riga porta distanza e tempo, e la prossima svolta quando segui un percorso. Toccarla riporta all'app.
- **iPhone**: il giro continua con lo schermo bloccato, e un'attività in tempo reale mostra gli stessi numeri sulla schermata di blocco.

**Schermo sempre acceso** nel pannello Registra impedisce al display di spegnersi mentre un giro è in corso nella scheda Registra, comodo su un supporto al manubrio e costoso per la batteria. Resta attivo finché non lo disattivi, e la tua scelta vale anche per il prossimo giro; **Opzioni → Registrazione** ha lo stesso interruttore. Lo schermo può spegnersi di nuovo mentre metti in pausa il giro (non quando si mette in pausa da solo a una fermata), quando passi a un'altra scheda e quando il giro finisce.

## Risparmio energetico

È lo schermo che scarica il telefono su un giro lungo, quindi **Risparmio batteria** prende di mira lo schermo. Attivalo nel pannello Registra o in **Opzioni → Registrazione**: "Mappa scura, niente animazioni, dopo 30 s una pagina semplice con i numeri; è lo schermo a consumare la batteria".

Mentre un giro registra con il risparmio attivo, Velorki:

- forza il tema scuro e una mappa nera,
- disegna un semplice punto di posizione, senza anello di precisione e senza cono di direzione,
- fa saltare la camera invece di animarla,
- attenua il display al 40 % mentre **Schermo sempre acceso** lo tiene sveglio,
- e dopo **30 secondi senza un tocco** sostituisce tutto con una pagina a colpo d'occhio: bianco su nero, la prossima svolta se c'è, poi il primo dei tuoi numeri, per impostazione predefinita **Distanza**, in grande con il secondo, **Velocità**, e **Tempo** sotto.

Tocca ovunque per riavere la mappa; il conto alla rovescia ricomincia. Tutto torna come prima quando il giro finisce o il risparmio viene disattivato. Il risparmio non cambia mai il tema che hai scelto per il resto dell'app.

**Precisione GPS** in **Opzioni → Registrazione** è l'altra metà: **Risparmio**, **Normale** o **Precisa**, con il suggerimento "Precisa è per i sentieri; Normale basta per le strade".

## Se un giro viene interrotto

Velorki scrive la traccia in un file di registro man mano, quindi un crash, una chiusura forzata o un telefono rimasto senza batteria non perdono il giro.

- Se il servizio di registrazione è ancora vivo quando torni, l'app si apre sulla scheda Registra, si riaggancia in silenzio e continua.
- Se non lo è, l'app si apre sulla scheda Registra e chiede subito, **Giro non terminato**: "Un giro del 16 set 2026 non è mai stato terminato. 42,1 km e 2 h 10 min sono salvati. Vuoi riprenderlo o terminarlo ora?" con tre risposte:
  - **Riprendi** riprende il giro dove si era fermato,
  - **Termina** salva quello che c'è e apre la scheda del giro nella scheda Libreria,
  - **Scarta** lo butta via.

La finestra non può essere chiusa senza rispondere, così un giro recuperato non si perde mai in silenzio. Viene chiesto una volta per avvio dell'app; un file o un percorso condiviso con cui l'app è stata aperta aspetta la risposta e si apre dopo.

## Continuare un giro terminato

Un giro che hai già terminato può essere proseguito: aprilo dalla libreria e scegli **Continua questo giro** dal menu in alto a destra. "La registrazione riprende su questo giro: traccia, distanza, tempo e dislivello proseguono da dove si erano fermati, e la sosta fino a ora conta come pausa."

Se un altro giro sta registrando viene prima terminato e salvato, e se questo era già stato caricato su Strava o Ride with GPS ti viene detto che il giro continuato dovrà essere inviato di nuovo.

## Giri recenti

Sotto **Giri recenti** nella scheda Registra ci sono i tuoi ultimi cinque, dal più recente, ognuno con data, distanza e tempo in movimento. Scorri una riga verso sinistra per eliminarla, con un **Annulla** nel messaggio che segue. L'elenco completo è nella [libreria](./library).

## Vedi anche

- [Navigazione svolta per svolta](./navigation)
- [Sensori e il tuo orologio](./sensors-and-watch)
- [Libreria](./library)
- [Importa ed esporta](./import-and-export)
- [Strava e Ride with GPS](./strava-and-ridewithgps)
- [Opzioni e aspetto](./settings-and-appearance)
