---
title: Assistente
description: Descrivi in una frase il giro che vuoi e Velorki lo trasforma in un percorso, con il tuo consenso, al più una posizione arrotondata e senza cronologia inviata.
order: 13
---

L'assistente trasforma una frase come "un anello gravel di circa 80 km su strade tranquille" in un percorso nel pianificatore. È l'unica parte di Velorki che invia a un server quello che hai scritto, quindi chiede prima il tuo consenso e ti dice esattamente cosa parte.

L'assistente fa parte di [Velorki Plus](./velorki-plus).

## Aprirlo

Tocca **Chiedi** nella barra degli strumenti del pannello del percorso nella scheda **Pianifica**. La scheda dell'assistente prende il posto del pannello del percorso, intitolata **Chiedi un percorso**: "Descrivi il giro che hai in mente. Velorki lo trasforma in una richiesta e pianifica il percorso sul tuo telefono." La mappa sopra resta la mappa: spostala, ingrandiscila e toccala come con il pannello del percorso aperto. Scorri la scheda verso il basso, o torna indietro, e il pannello del percorso è di nuovo lì come lo avevi lasciato; quello che hai scritto e le risposte restano per la prossima volta.

Con un percorso sulla mappa il pannello si apre invece su **Questo percorso**, una domanda su quel percorso (vedi [Fai domande su questo percorso](#fai-domande-su-questo-percorso)); **Nuovo percorso** sopra riporta indietro.

Se il pulsante **Chiedi** non c'è, questa build di Velorki non ha alcun indirizzo di server, come succede con una copia compilata da te senza un relay proprio.

## Il consenso, e cosa lascia il telefono

La prima volta che invii qualcosa, Velorki mostra **Prima che l'assistente chieda**:

> Quello che scrivi viene inviato al server Velorki, che lo passa al nostro fornitore di IA. Non parte nient'altro: nessun nome, nessun account, nessuna cronologia dei percorsi.
>
> Se lo consenti, viene inviata anche la tua posizione, arrotondata a circa un chilometro, così "da qui" ha un senso.

Tre risposte:

- **Consenti, con posizione approssimativa** invia il tuo testo e una posizione arrotondata a circa un chilometro.
- **Consenti, solo testo** invia il tuo testo e nient'altro.
- **Non ora** non invia nulla e disattiva l'assistente.

Cosa viaggia davvero: il tuo testo, facoltativamente la posizione arrotondata, le tue impostazioni di lingua e unità perché la risposta sia adatta, e, per una descrizione di percorso o una domanda su un percorso, un riepilogo del percorso (vedi sotto). Nessun identificativo tuo o del tuo telefono viene messo nella richiesta.

Puoi cambiare idea in qualsiasi momento in **Opzioni → Assistente IA → Cosa viene inviato**, il cui sottotitolo dice sempre in quale dei quattro stati ti trovi, con un pulsante **Cambia** accanto.

## Chiedi qualcosa

Scrivi una frase e tocca **Chiedi**. Tre esempi sono lì da toccare:

- **Un anello pianeggiante di 30 km da qui**
- **Un anello di 50 km su strade tranquille**
- **Un anello gravel di circa 80 km**

Appena scrivi, i chip sotto **Aggiungi** offrono i desideri su cui agisce il pianificatore: **piatto**, **collinare**, **su sterrato**, **su strade tranquille** e **ritorno alla partenza**, ciascuno finché non è già detto.

Altre cose che funzionano bene: una distanza e una direzione, un luogo da cui passare, un fondo, quanta salita vuoi, una partenza che non è dove sei.

Il pannello mostra **Sto pensando…** mentre il modello risponde, poi **Cerco i luoghi…** mentre i nomi dei luoghi vengono trasformati in coordinate. Poi riassume cosa ha capito: "Anello di circa 80 km", "Partenza da dove sei" o "Partenza da Friburgo", e un chip per ogni luogo da cui passare.

Se un nome corrisponde a più luoghi lontani tra loro, Velorki chiede **Quale Friburgo?** con fino a tre scelte. Toccarne una risolve la cosa sul telefono, senza un secondo viaggio al modello.

## Cosa succede con la risposta

Il pannello si chiude da solo e il pianificatore prende il comando:

- **Un anello senza un luogo particolare da cui passare** apre il [pannello degli anelli](./loops) con la ricerca già in corso. Finita la ricerca il pannello degli anelli si chiude e l'assistente torna su **Questo percorso**, con la tua richiesta sopra la domanda, così puoi fare subito domande sull'anello. Se la ricerca non ha trovato nessun anello, torna su **Nuovo percorso** e lo dice. Chiudi il pannello degli anelli o fai qualcosa al suo interno mentre cerca, e la ricerca è tua: l'assistente si tiene in disparte.
- **Un anello attraverso luoghi con nome** diventa punti con l'anello chiuso, e Velorki dice "Il percorso è sulla mappa."
- **Un percorso da A a B** diventa punti con il profilo bici impostato, e di nuovo "Il percorso è sulla mappa."

Da lì è un piano normale: modificalo, chiedi varianti, salvalo.

## Cosa non fa

Il modello non restituisce mai coordinate e non calcola mai un percorso. Restituisce una richiesta strutturata, una distanza, una forma, qualche nome di luogo e una preferenza o due, e tutto il resto avviene sul tuo telefono. Per questo l'assistente funziona come modo per esprimere quello che vuoi, e non come fonte di fatti sulle strade.

Può anche sbagliare. Se dice qualcosa che non intendevi, riformula con una distanza chiara e un luogo chiaro.

## Fai domande su questo percorso

Con un percorso sulla mappa del pianificatore, **Chiedi** si apre su **Questo percorso**: "Chiedi qualsiasi cosa sul percorso sulla mappa." Esempi da toccare: **Controlla questo percorso**, **Dove posso prendere un caffè a metà strada?**, **Dove posso riempire la borraccia?**, **Evita la strada principale**, **Va bene per una bici da corsa?**

Cosa parte: la tua domanda e il riepilogo del percorso descritto in [Descrivi questo percorso](#descrivi-questo-percorso), posizioni incluse. La tua posizione non parte in questa modalità.

La risposta è qualche frase e fino a sei segnalazioni lungo il percorso, ognuna con il punto in cui si trova. **Mostra** sposta la mappa lì. Una segnalazione su cui il pianificatore può agire ha un pulsante:

- **Aggiungi come sosta** fa passare il percorso per un bar, una fontanella o un altro luogo del riepilogo, inserito dove il percorso gli passa accanto.
- **Evita** tiene il router lontano da quel tratto. Viene disegnato tratteggiato sulla mappa, e il chip **1 tratto evitato** sopra la mappa ha **Consenti di nuovo**.
- **Usa Gravel** (o un'altra bici) pianifica di nuovo il percorso con quel profilo.

Ognuno è un singolo passo che **Annulla** annulla, e il pannello resta aperto e lo segna come **Applicato**. Il modello suggerisce solo luoghi del riepilogo; non inventa mai una sosta o una coordinata.

**Questo percorso** non è offerto per un percorso importato da Strava.

## Descrivi questo percorso

L'altra cosa che fa l'assistente è scrivere un paragrafo su un percorso che hai già. Apri un percorso nella libreria e tocca **Descrivi questo percorso**; il pannello inizia subito a scrivere, e **Salva come descrizione** conserva il testo con il percorso. **Riscrivi** chiede un altro tentativo.

Prima di chiedere, il telefono confronta il percorso con i suoi riquadri di routing e la sua ricerca offline dei luoghi e costruisce un riepilogo: la distanza, il dislivello, le quote asfaltate e sterrate, i nomi dei punti, i tratti del percorso con il loro tipo di strada, fondo e pendenza, le sue salite, le città e i paesi che attraversa, e bar, panetterie, fontanelle, bagni, punti panoramici e negozi di bici entro 300 m, ciascuno con la sua distanza lungo il percorso e la sua posizione. Senza riquadri scaricati per la zona partono solo i numeri. Il modello riceve anche le posizioni, a circa 10 m, così sa dov'è il giro; un percorso che parte dalla tua porta mostra dov'è la tua porta. Ogni luogo che la descrizione nomina viene dal riepilogo, così può dire "il bar a Caniço al km 9" e intendere un bar che esiste. Scrive nella lingua e nelle unità su cui è impostata l'app.

Il pulsante non è offerto per un percorso importato da Strava, perché le condizioni di Strava non permettono di dare i loro dati a un fornitore di IA.

## Limiti ed errori

L'assistente ha un limite: venti richieste all'ora e cento al giorno.

| Cosa dice il pannello | Cosa significa |
|---|---|
| "Troppe richieste. Riprova tra 90 secondi." | hai raggiunto il limite |
| "L'assistente IA fa parte di Velorki Plus." | nessun abbonamento |
| "L'assistente ha bisogno del tuo consenso prima di poter inviare qualcosa." | il consenso manca o è stato rifiutato |
| "Non sono sicuro di aver capito. Prova a indicare una distanza e un luogo." | il modello non era sicuro |
| "Non ho trovato "Friburgo". Prova con un'altra grafia o con una città vicina." | il nome del luogo non è stato risolto |
| "Devo sapere da dove partire. Attiva la posizione o indica un luogo di partenza." | "da qui" senza posizione |
| "L'assistente non ha potuto rispondere:" | il server o il modello non ha funzionato |

**Riprova** cancella l'errore e conserva quello che hai scritto.

## Segnalare una risposta sbagliata

**Opzioni → Assistente IA → Segnala risposta IA** apre un'email a noi: "Raccontaci di una risposta sbagliata o inappropriata." Usala, per favore. Le risposte sbagliate e inappropriate sono il modo in cui le richieste vengono corrette.

## Vedi anche

- [Velorki Plus](./velorki-plus)
- [Anelli](./loops)
- [Pianificare un percorso](./planning-a-route)
- [Privacy sul telefono](./privacy-on-the-phone)
