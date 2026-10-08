---
title: Anelli
description: Chiedi a Velorki un giro ad anello di una certa distanza che finisce dove è iniziato, poi scorri i candidati finché uno ti convince.
order: 3
---

Un anello è un giro che torna dove è partito, e Velorki li genera a partire da una distanza invece che dai punti che tocchi. Usa il pulsante **Anello** quando sai quanto vuoi pedalare ma non dove, e usalo per chiudere un percorso che hai già disegnato.

Il generatore di anelli è un semplice algoritmo che gira sul tuo telefono. È gratis, non richiede alcun server oltre al calcolo del percorso stesso, e non c'è nessun modello coinvolto.

## Aprirlo

Tocca **Anello** nella barra degli strumenti del pannello del percorso nella scheda **Pianifica**. La finestra si intitola **Crea un anello**, e quello che offre dipende da cosa contiene già il pianificatore.

## Chiudere un percorso che hai disegnato

Se il pianificatore ha già due o più punti, la finestra offre di riportare il percorso alla sua partenza.

1. Dice "Torna al punto di partenza."
2. Sotto **BICI**, scegli il profilo. È la stessa impostazione dei chip nel pianificatore, quindi cambiarla qui la cambia anche là.
3. **Ritorno diverso** è attivo di default, con la nota "Evita le strade già percorse." Disattivalo e il tratto di ritorno può riusare la strada dell'andata.
4. Tocca **Chiudi l'anello**. Velorki aggiunge una copia del tuo primo punto, calcola la strada di casa e mostra il risultato come `48,2 km · 720 m di dislivello`.
5. **Altro ritorno** lascia l'andata esattamente com'è e chiede solo un ritorno diverso. Premilo quante volte vuoi; ogni pressione è un passo da annullare. È in grigio finché **Ritorno diverso** è disattivato.
6. **Fatto** chiude la finestra. L'anello è sulla mappa del pianificatore come un percorso normale che puoi modificare e salvare.

## Creare un anello da zero

Se il pianificatore è vuoto, o contiene un solo punto, la finestra chiede invece una distanza.

1. **Dove inizia.** Con un punto già sulla mappa, quel punto è la partenza. Altrimenti la riga dice **Dalla tua posizione**, e Velorki chiede la posizione la prima volta. Se non riesce ad avere una posizione ripiega sul centro della mappa e la riga cambia in **Dal centro della mappa**.
2. **DISTANZA.** Trascina il cursore. In metrico va da 5 a 200 km a passi di 5 km, in imperiale da 3 a 125 miglia a passi di 1 miglio, e il valore scelto è mostrato in grande sopra. Si apre su quello che hai chiesto l'ultima volta, 30 km la prima volta.
3. **BICI.** Gli stessi cinque profili del pianificatore.
4. **Ritorno diverso.** Attivo significa un vero cerchio; disattivato significa andare fino a un punto lontano e tornare per la stessa strada.
5. Tocca **Crea un anello**.

## Mentre cerca

Velorki manda la richiesta in otto direzioni e calcola ognuna sul telefono, il che richiede da pochi secondi a un minuto o più, secondo la distanza e il telefono. Una barra di avanzamento avanza man mano che le direzioni finiscono, con una riga sotto: "Provo 8 direzioni · 3 già verificate".

Il miglior anello finora è sulla mappa appena ce n'è uno, con il suo riepilogo, **Un altro** e **Fatto** accanto alla barra, mentre la riga dice che la ricerca continua per un anello più tranquillo e più scorrevole. Alla fine la riga dice tra quanti anelli è stato scelto quello mostrato, "Il migliore di 6 anelli". **Ferma** termina la ricerca in anticipo e tiene quello che è stato trovato; **Fatto** lascia in mostra l'anello e fa finire la ricerca in background senza sostituirlo.

## Scegliere tra i candidati

Non ti viene dato un elenco da leggere. Ogni candidato riceve un punteggio per quanto si avvicina alla distanza che hai chiesto, quanta salita ha per chilometro, quanto è sterrato, quanto corre su piste ciclabili e reti ciclabili, quanto ripete le stesse strade, e quanto sta su strade principali. Il migliore viene passato direttamente al pianificatore e disegnato sulla mappa, e la finestra mostra solo la sua riga di riepilogo, `48,2 km · 720 m di dislivello`.

Per vedere il successivo, tocca **Un altro**. Scende di un passo nella classifica senza alcun nuovo calcolo, quindi è istantaneo. Quando la classifica si esaurisce, Velorki cerca di nuovo con le otto direzioni ruotate di mezzo passo, così i nuovi tentativi cadono tra quelli vecchi.

Ogni candidato che guardi è un percorso vero nel pianificatore: spostati intorno, trascina un punto, leggi il suo profilo altimetrico, e **Salva** quando uno è quello giusto.

Se il cursore o il profilo bici cambiano dopo una ricerca, il risultato è superato e il pulsante torna a **Crea un anello**.

## Chiedere un anello che passi per un posto preciso

La finestra degli anelli non ha un campo per un posto da cui passare, e nessuna preferenza su colline o fondo. Quelle arrivano dall'[assistente](./assistant): una frase come "un anello collinare di 60 km da qui passando per il lago" diventa una richiesta con un punto intermedio e le preferenze allegate, e il generatore di anelli fa il lavoro. L'assistente fa parte di Velorki Plus; la finestra degli anelli in sé è gratis.

## Quando non trova nulla

- **"Nessun anello trovato qui, prova un'altra distanza."** Alcuni posti, un'isola o una valle senza uscita, semplicemente non hanno una rete stradale per un cerchio di quella lunghezza. Sposta la distanza su o giù di un buon margine, o parti da un altro posto.
- **"Attiva la posizione o tocca la mappa per impostare la partenza."** Non è stato possibile determinare un punto di partenza. Consenti la posizione, o tocca prima la mappa.
- **"La ricerca dell'anello ha richiesto troppo tempo su questo telefono. Prova una distanza più breve."** La ricerca si è arresa dopo 30 minuti.
- **"Ricerca dell'anello non riuscita:"** con un motivo significa che il calcolo del percorso stesso è fallito. Vedi [risoluzione dei problemi](./troubleshooting).

Chiudere la finestra annulla una ricerca in corso ma tiene quello che aveva già trovato.

## Vedi anche

- [Pianificare un percorso](./planning-a-route)
- [Assistente](./assistant)
- [Mappe offline e calcolo del percorso](./offline-maps-and-routing)
- [Libreria](./library)
