---
title: Libreria
description: Dove stanno i percorsi salvati e i giri registrati, cosa mostra il pannello di un percorso o di un giro e come rinominarli o eliminarli.
order: 10
---

La scheda Libreria contiene tutto quello che hai conservato: i percorsi che hai pianificato e i giri che hai registrato. È un pannello sopra la mappa, come le schede Pianifica e Registra: il suo contenuto scorre a qualsiasi altezza, e la maniglia in alto lo sposta; quando non c'è nulla da scorrere, si muove tutto il pannello. Tiralo su per avere più spazio, tiralo giù fino in fondo e il pannello si ripiega nella barra di navigazione, lasciando la mappa. Vieni qui per riaprire un percorso, leggere i grafici e i parziali di un giro, e far entrare e uscire i file.

Tutto quello che c'è nella libreria sta sul telefono. Non c'è alcun account e niente viene sincronizzato da nessuna parte.

## Percorsi e giri

Un selettore sotto il titolo del pannello sceglie l'elenco: **Percorsi** o **Giri**. Velorki ricorda quale stavi guardando l'ultima volta.

- La riga di un **percorso** mostra il nome e, sotto, la data, la distanza e il dislivello.
- La riga di un **giro** mostra il nome e, sotto, la data, la distanza e il tempo in movimento. Sopra l'elenco c'è un conteggio, "12 giri".

Tocca una riga per aprirla nel pannello, con il percorso o il giro disegnato sulla mappa sopra. La freccia in alto a sinistra del pannello, o l'indietro di sistema, riporta all'elenco.

Gli elenchi vuoti si spiegano da soli: "Nessun percorso salvato. Pianifica un percorso nella scheda Pianifica e salvalo." e "Ancora nessun giro."

## Rinominare ed eliminare

**Percorsi**: il menu a destra della riga ha **Rinomina** ed **Elimina**. Anche scorrere una riga verso sinistra la elimina. In entrambi i casi il messaggio che segue porta un **Annulla**.

**Giri**: scorri la riga verso sinistra per eliminarla, di nuovo con **Annulla**. Rinominare ed eliminare un giro con una conferma si fa dal pannello del giro, nel menu a destra della sua intestazione.

Le due finestre di rinomina sono identiche: un campo, **Nome**, poi **Annulla** o **Salva**.

## Il pannello di un percorso

Aprire un percorso lo disegna sulla mappa, adattato alla parte dello schermo sopra il pannello, con i suoi punti di interesse come piccoli marcatori con nome, se è stato importato con qualcuno. Il pannello mostra, dall'alto:

- la data, il profilo bici e il dislivello,
- la descrizione, se il percorso ne ha una,
- **Distanza**, **Dislivello**, **Discesa** e **Durata**,
- il pannello stesso si apre fino in alto quando l'elenco sullo schermo ha più di due voci, e altrimenti si ferma a metà altezza; una volta che lo hai trascinato, torna dove lo hai lasciato finché l'app non viene riavviata,
- sotto il nome, da dove viene un percorso importato: il formato del file e chi lo ha scritto, per esempio "Importato da GPX · Garmin Connect"; un percorso pianificato qui non dice nulla lì,
- le azioni qui sotto, **Apri nel pianificatore** per prima, così è in vista all'altezza di riposo del pannello,
- una riga **Descrizione** e una riga **Link**, ognuna con una matita: la descrizione è quella del file, dell'assistente o la tua, il link è il `<link>` del file o uno che scrivi tu, e un tocco su di esso apre la pagina,
- la ripartizione del fondo: i dati del motore di calcolo per un percorso pianificato qui, e per uno letto da un file la stessa associazione che riceve un giro, vedi sotto,
- il profilo altimetrico,
- **Punti di interesse**: i punti del percorso che non stanno sulla sua traccia, ognuno con l'icona del suo tipo, il nome e la nota — quelli con cui un file è arrivato fuori dal tracciato, e i luoghi che hai segnato accanto al percorso nel pianificatore; quelli sulla traccia sono invece righe dell'elenco svolte,
- per un percorso importato con svolte o punti di interesse, o con punti a cui hai dato un nome o scritto una nota nel pianificatore, l'elenco svolte: ogni svolta e ogni punto con la distanza dalla partenza, un tocco su una riga sposta la mappa lì al tuo zoom e un tocco su un marcatore fa scorrere il pannello fino a quella riga.

Le azioni:

- **Apri nel pianificatore** lo carica nella scheda Pianifica con tutti i suoi punti, punti intermedi con nomi, tipi e note compresi, dove puoi modificarlo e salvarlo di nuovo. Un percorso importato invece che pianificato si apre con la linea esatta del file e con punti solo alle estremità e sui punti del file che stanno sulla traccia, che arrivano con il loro tipo e la loro nota; una modifica ricalcola solo i tratti accanto, e la linea del file resta ovunque altrove. La linea del file viene conservata con il percorso attraverso ogni modifica e salvataggio, così **Ripristina** nel pianificatore può rimetterla al suo posto. I punti fuori dalla traccia arrivano come luoghi accanto al percorso, dove possono ricevere un nome, un tipo, essere spostati sul percorso o rimossi come qualsiasi altro punto. Il prossimo salvataggio scrive entrambi gli insiemi, quindi un luogo che elimini nel pianificatore sparisce anche dal pannello.
- **Esporta** offre **Percorso GPX** e **Percorso FIT**, vedi [importazione ed esportazione](./import-and-export).
- **Invia** offre **Invia a Ride with GPS** e **Invia a Strava**, vedi [Strava e Ride with GPS](./strava-and-ridewithgps).
- **Condividi link** lo trasforma in un link, vedi [condivisione](./sharing).
- **Descrivi questo percorso** chiede all'assistente di scrivere un paragrafo su di esso, vedi [assistente](./assistant).

## Il pannello di un giro

Aprire un giro disegna sulla mappa **la traccia colorata per velocità**, da lento a veloce, adattata sopra il pannello, con una legenda **lento**/**veloce** in alto nel pannello. Le fasce sono i quantili di quel giro, quindi i colori confrontano il giro con sé stesso e non con una scala fissa. Un giro senza marche temporali è disegnato come una linea semplice. Il pannello mostra, dall'alto:

- la data,
- sette valori: **Distanza**, **In movimento**, **Tempo**, **Media**, **Max**, **Dislivello**, **Discesa**. **In movimento** lascia fuori il tempo in cui eri fermo; **Tempo** è l'intero giro dall'inizio alla fine.
- il grafico **Altimetria**, quota in funzione della distanza, disegnato solo quando la traccia aveva le quote,
- il grafico **Velocità**, il cui asse parte sempre da zero,
- il grafico **Frequenza cardiaca**, quando il giro ne aveva una; dove la lettura è mancata per un tratto la linea si interrompe, e quando meno della maggior parte del giro aveva una lettura la didascalia dice quanto, "Frequenza cardiaca · 24 % del giro", così una media su quei minuti non viene letta come quella del giro,
- la tabella **Parziali**.

Tocca un grafico e trascina lungo di esso per una lettura nella forma `12,3 km · 340 m`. Pizzica un grafico per ingrandire un tratto, trascina per spostarti quando sei ingrandito, e tocca due volte oppure tocca **Tutto il giro** per rivedere tutto il giro; i tre grafici si ingrandiscono insieme.

### Percorso e punti di interesse

Un giro che ha seguito un percorso mostra quel percorso sotto la traccia, nel colore più discreto di un'alternativa del pianificatore, e i punti di interesse del percorso come marcatori sulla mappa e come segni sul grafico **Altimetria** nel punto in cui li hai superati — solo per i punti a cui il giro si è avvicinato entro 60 m. Un tocco su un marcatore lo fissa con il suo nome; la lettura nomina il segno su cui si ferma il dito. Il pulsante del percorso in alto nella colonna dei controlli della mappa nasconde tutto questo, e la scelta viene ricordata.

### Valori da un sensore

Un giro registrato con una fascia cardio, un Apple Watch o un misuratore di potenza porta più dei sette valori: **FC media**, **FC max**, **Cadenza media**, **Cadenza max**, **Potenza media**, **Potenza max** e **Potenza norm.** si aggiungono ai valori, ognuno solo se il giro lo ha, e il grafico **Frequenza cardiaca** viene disegnato sotto il grafico della velocità. **Potenza norm.** sono le letture del misuratore pesate come le sentono le gambe: la potenza su una griglia di un secondo, la sua media mobile a 30 s, ogni media elevata alla quarta, la media di queste e poi la radice quarta. Un giro regolare esce alla sua media; un giro di scatti e pause esce più alto. Servono almeno trenta secondi di letture consecutive, e un buco di più di cinque secondi nel misuratore inizia un nuovo tratto. Con **Zone di potenza** attive e una soglia impostata, accanto c'è **Intensità**: la potenza normalizzata divisa per la tua potenza di soglia, così 0,80 è un giro ai quattro quinti di quello che riesci a tenere per un'ora. Un giro registrato senza sensore non mostra niente di tutto questo, e un giro importato da un file GPX, FIT o TCX mostra quello che quel file conteneva. Vedi [sensori e orologio](./sensors-and-watch).

### Calorie, zone di frequenza cardiaca, zone di potenza e potenza stimata

Tutte e quattro sono disattivate finché non le accendi in Opzioni → Ciclista, e tutte e quattro sono calcolate sul telefono dai punti del giro stesso, quindi le ricevono anche i giri più vecchi.

**Calorie** è una stima, e la piccola riga sotto il valore dice su cosa si basa. Con un misuratore di potenza per tutto il giro è il lavoro svolto, "dalla potenza": un chilojoule di pedalata è quasi esattamente una chilocaloria bruciata. Altrimenti, con una frequenza cardiaca per tutto il giro e il tuo peso, anno di nascita e sesso, è "dal battito". Altrimenti, con **Stima potenza** attivo, è "dalla potenza stim.", di nuovo il lavoro stimato in chilojoule. Altrimenti è "dalla velocità", dal tuo peso e da quanto veloce hai pedalato. In ogni caso serve il tuo peso.

**Potenza stim.** appare solo con l'interruttore attivo e solo nei giri senza misuratore di potenza; un giro con un misuratore mostra il misuratore e nient'altro. È la media di quello che il modello di potenza di Martin dice che devi aver messo sui pedali per spostare te e la tua bici alla velocità a cui sei andato sulla pendenza che hai percorso: dalla tua velocità, dalla pendenza e dal peso totale di ciclista e bici, assumendo niente vento, nessuna scia, una posizione con le mani sulle leve, una resistenza al rotolamento fissa per tipo di bici, una perdita di trasmissione del 2,5 % e aria più rarefatta con la quota. Le quote sono lisciate su 50 m perché le quote GPS saltano, e il lavoro viene sommato su mezzo minuto alla volta prima di scartare quello che sta sotto zero, così una quota che oscilla su e giù non costa nulla; andare a ruota libera e frenare contano zero, e l'accelerazione è calcolata da velocità mediate su dieci secondi, che in città è la maggior parte del lavoro. Aspettati che sia ragionevole sulle salite lunghe, dove il peso domina; troppo alto in un gruppo veloce e sbagliato con il vento, che non può vedere. È un numero per confrontare i tuoi giri tra loro, non un misuratore di potenza.

**Zone di frequenza cardiaca** è una barra sotto il grafico della frequenza cardiaca, divisa in cinque zone della tua frequenza cardiaca massima, con una riga per zona: il suo intervallo, il tempo passato lì e la quota del tempo con frequenza cardiaca del giro. La zona 1 è tutto sotto il 60 %, la zona 5 tutto dal 90 % in su. La didascalia indica il massimo usato: quello che hai inserito, oppure 220 meno la tua età.

**Zone di potenza** è la stessa barra per i giri con misuratore di potenza, divisa in sette zone della tua potenza di soglia: sotto il 55 %, 55–75, 75–90, 90–105, 105–120, 120–150 e dal 150 % in su. Ogni secondo del giro va nella zona della lettura del misuratore in quel momento; il tempo da fermo non conta da nessuna parte. La didascalia indica la soglia, "Zone di potenza · soglia 250 W". Richiede l'interruttore e la tua potenza di soglia in Opzioni → Ciclista, e mette il valore **Intensità** tra i riquadri.

### Parziali

Una riga per parziale, con quattro colonne: **Parziale**, **In movimento**, **Media** e **Dislivello**. La didascalia dice quanto è lungo un parziale, "Parziali, ogni 5 km". Di default la lunghezza segue il giro: un chilometro fino a 30 km, cinque fino a 150 km, dieci oltre, in miglia con le unità imperiali, così la tabella resta corta su un giro lungo; **Lunghezza parziali** in Opzioni → Registrazione la fissa invece a 1, 5 o 10. L'ultima riga è il resto, quindi può essere più corta delle altre. Dietro ogni riga una barra mostra la velocità media di quel parziale rispetto al tuo parziale più veloce, il che rende evidenti a colpo d'occhio i tratti duri. Tocca una riga per vedere quel parziale ombreggiato sui grafici e disegnato sopra la traccia sulla mappa, dove un chip lo nomina, "Parziale 3 · 2–3 km"; tocca di nuovo la riga o il chip per toglierlo.

### Salite

Sotto i parziali, in un giro che ne aveva, una tabella **Salite**: una riga per salita con **Inizio** (dove lungo il giro è cominciata, "a 12,3 km"), **Lunghezza**, **Dislivello** e **Pendenza**, e una riga più discreta sotto con il tempo in movimento, la VAM e, quando il giro le aveva, la frequenza cardiaca e la potenza medie sulla salita. La VAM sono i metri di quota guadagnati per ora di tempo in movimento, la misura abituale di quanto velocemente è stata fatta una salita: 1.000 m/h sono cento metri ogni sei minuti. Dietro ogni riga una barra mostra il dislivello di quella salita rispetto alla più grande. Tocca una riga per vedere quella salita ombreggiata sui grafici e disegnata sopra la traccia sulla mappa, dove un chip la nomina, "Salita 1 · 0,5–2,5 km"; tocca di nuovo la riga o il chip per toglierla. Viene evidenziato un tratto alla volta, che sia un parziale o una salita.

Una salita viene individuata come il profilo del pannello di registrazione individua quella su cui ti trovi: inizia dove i prossimi 100 m di strada salgono almeno del 3 %, e finisce al suo punto più alto una volta che la strada è scesa di 10 m sotto di esso, così un avvallamento in una salita lunga non la taglia in due. Le salite più corte di 300 m, che guadagnano meno di 20 m o con una media sotto il 3 % dai piedi alla cima non vengono elencate. Le quote sono prima lisciate su 50 m, come per la stima della potenza, e le pause non contano né per il tempo né per la quota.

### Fondo

Un percorso letto da un file riceve il suo **Fondo** nello stesso modo, e per la stessa ragione: nessuno lo ha mai calcolato, quindi niente ha mai detto su cosa è asfaltato. La prima volta che un percorso del genere viene aperto, la sua traccia viene posata sui riquadri di routing offline e le percentuali vengono lette dalle strade su cui cade, poi conservate con il percorso così da essere calcolate una volta sola. Valgono le stesse avvertenze — la regione di routing deve essere scaricata, e una traccia che la mappa non riesce a seguire lo dice — e un percorso pianificato qui non viene toccato, perché il motore di calcolo ha già risposto. I percorsi salvati da un file prima che questo esistesse vengono associati la prima volta che li apri.

Sotto le salite, una barra **Fondo** come quella sul pannello di un percorso: quanto del giro era asfaltato, sterrato o sconosciuto, con le percentuali di piste ciclabili e strade trafficate accanto. Il giro non è mai stato pianificato, quindi l'app lo scopre dopo: posa la traccia registrata sui riquadri di routing offline sul telefono e legge il fondo dalle strade su cui cade. Nessuna traccia lascia il telefono per questo. Richiede che la regione di routing di quella zona sia scaricata; finché non lo è, la sezione lo dice. Una traccia che la mappa non riesce a seguire, attraverso un parco, su un traghetto o lungo una scorciatoia, mostra invece "Impossibile allineare la traccia alla mappa", e il risultato, in entrambi i casi, viene conservato con il giro, così viene calcolato una volta sola. Un nuovo riquadro di routing dà a un giro non associato un altro tentativo.

### Azioni di un giro

- Il pulsante nuvola a destra dell'intestazione del pannello carica il giro su un servizio collegato.
- Il menu accanto: **Esporta traccia GPX**, **Esporta attività FIT**, **Continua questo giro**, **Rinomina**, **Elimina**.
- In fondo: le stesse due esportazioni e **Condividi link**.

## Far entrare file e percorsi

I due pulsanti a destra dell'intestazione del pannello:

- **Importa file** apre il selettore di file del telefono per un file GPX, FIT o TCX.
- Il pulsante nuvola offre **Importa da Strava** e **Importa da Ride with GPS**, quando quei servizi sono configurati.

Entrambi sono descritti in [importazione ed esportazione](./import-and-export) e [Strava e Ride with GPS](./strava-and-ridewithgps).

## Vedi anche

- [Registrare un giro](./recording-a-ride)
- [Sensori e orologio](./sensors-and-watch)
- [Importazione ed esportazione](./import-and-export)
- [Condivisione](./sharing)
- [Strava e Ride with GPS](./strava-and-ridewithgps)
- [Pianificare un percorso](./planning-a-route)
