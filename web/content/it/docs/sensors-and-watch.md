---
title: Sensori e il tuo orologio
description: Frequenza cardiaca, cadenza e potenza da un sensore Bluetooth, un Apple Watch o l'app salute del telefono, configurate una volta e salvate con ogni giro.
order: 17
---

Velorki può mostrare la tua frequenza cardiaca, la cadenza di pedalata e la potenza mentre registri, e conservare tutte e tre con il giro una volta finito. I valori arrivano da un sensore Bluetooth, da un Apple Watch o dall'app salute del telefono, e tutto questo è gratuito e funziona sul telefono.

Niente di tutto questo succede finché non lo attivi. Con tutte le sorgenti disattivate, Velorki non chiede nulla al sistema operativo e nessuna schermata nomina un sensore.

## Cosa puoi misurare

| Sorgente | Cosa fornisce | Cosa serve |
|---|---|---|
| Sensore Bluetooth | frequenza cardiaca, cadenza, velocità della ruota, potenza | il sensore, associato una volta in Velorki |
| Apple Watch | frequenza cardiaca, e il giro al polso | un iPhone con un orologio abbinato |
| Apple Health o Health Connect | la frequenza cardiaca che qualcos'altro ha scritto sul telefono | l'app salute del telefono, e un interruttore |

Quando due di loro riportano la stessa cosa nello stesso momento, l'orologio vince su un sensore Bluetooth, e un sensore Bluetooth vince sull'app salute. Un valore conta come attuale per dieci secondi, e quando la sorgente che stava vincendo tace la successiva prende il suo posto da sola, così una fascia lasciata a casa semplicemente non c'è.

## Attivare una sorgente

Tutto si trova in **Opzioni → Sensori**, subito sotto **Registrazione**:

- **Apple Health** su iPhone, **Health Connect** su Android, con la riga "Legge la frequenza cardiaca che altre app salvano in Health, come l'app Allenamento dell'orologio. Viene controllata ogni pochi secondi, quindi è in ritardo; una fascia o l'app Velorki per l'orologio prende il posto appena trasmette". Attivarlo è l'unica cosa in Velorki che può far comparire la richiesta di autorizzazione per i dati di salute. Se la rifiuti, Velorki dice "Velorki non ha ottenuto l'accesso ai tuoi dati sulla salute." e lascia l'interruttore spento.
- **Salva i giri in Health** sotto di esso, "Ogni giro concluso finisce in Health come un allenamento in bici con inizio, fine e distanza", che puoi disattivare da solo. Non fa nulla finché l'interruttore sopra è spento.
- **Apple Watch**, con la riga "L'app Velorki per l'orologio: misura il battito dal vivo per tutto il giro, mostra il giro e ha Avvia, Pausa e Termina al polso. Consuma la batteria dell'orologio". La riga c'è solo su un iPhone con un orologio abbinato. **Sensore a riposo in pausa** sotto di essa è spiegato in [batteria al polso](#batteria-al-polso).
- **Sensori Bluetooth**, con la riga "Fasce cardio, sensori di velocità e cadenza, misuratori di potenza", oppure "1 sensore associato" quando ne hai uno. Apre una schermata a sé.

## Sensori Bluetooth

### Associare un sensore

1. Sveglia il sensore: indossa la fascia o gira le pedivelle. La maggior parte dei sensori non dice nulla finché non viene usata.
2. Apri **Opzioni → Sensori → Sensori Bluetooth** e tocca **Cerca**. Su iPhone la schermata avvisa "iOS chiede il Bluetooth alla prima ricerca." prima che tu tocchi. Una scansione dura circa quindici secondi.
3. Sotto **Trovati**, tocca il sensore che riconosci. Ogni riga ha il nome, piccole icone per ciò che misura e la potenza del segnale in dBm, con il più forte in alto.
4. Velorki si connette una volta per chiedere al dispositivo cosa ha davvero, lo archivia sotto **Associati** e lo lascia di nuovo andare.

Mentre quella schermata è aperta i tuoi sensori associati sono connessi, così ogni riga mostra cosa sta dicendo in quel momento invece di **Connesso**, **Connessione…** o **Non connesso**. Uscendo dalla schermata si disconnettono di nuovo, a meno che un giro sia in registrazione. **Dissocia**, nel menu a destra di una riga associata, rimuove un sensore.

### Con cosa si associa Velorki

I tre profili ciclistici standard, cioè quello che parla quasi tutto ciò che viene venduto come sensore per bici:

- **fasce cardio** e fasce da braccio,
- **sensori di velocità e cadenza**, sulla ruota, sulla pedivella, o un unico dispositivo per entrambe,
- **misuratori di potenza**, i cui contatori sulla pedivella danno anche una cadenza, quindi un misuratore di potenza rende superfluo un sensore di cadenza separato.

Un dispositivo che non parla nessuno dei tre non viene proposto. Velorki si associa ai sensori, non ai ciclocomputer: quelli sono un altro tipo di dispositivo e non si connettono qui.

### Circonferenza della ruota

Un sensore di velocità conta i giri della ruota, quindi Velorki deve sapere quanto è lungo un giro. Il campo **Circonferenza ruota** compare in fondo alla schermata appena un sensore associato riporta la velocità, con il suggerimento "Millimetri per giro di ruota. 2105 è un copertone 700x25c." e **mm** dopo il numero.

Mentre un sensore sulla ruota sta riportando, la sua velocità sostituisce quella del GPS nel pannello Registra, ed è proprio questo il punto: una ruota è precisa a passo d'uomo, sotto gli alberi e in galleria, dove il GPS non lo è. Nient'altro nel giro la usa.

### Quando un sensore non viene trovato

- **"Ancora niente. Sveglia il sensore: indossa la fascia o gira i pedali."** Una fascia senza contatto con la pelle e una pedivella ferma sono invisibili. Muoviti, poi scansiona di nuovo.
- **"Attiva il Bluetooth per trovare i tuoi sensori."** La radio del telefono è spenta.
- **"Velorki non ha il permesso di usare il Bluetooth."** L'autorizzazione è stata rifiutata. Concedila a Velorki nelle impostazioni del telefono e scansiona di nuovo.
- **Il sensore sta parlando con qualcos'altro.** Questi sensori servono un dispositivo alla volta. Chiudi l'altra app o spegni il ciclocomputer.
- **Un sensore associato che dice Non connesso** è fuori portata, addormentato o scarico. Velorki continua a provare mentre un giro registra o quella schermata è aperta, aspettando un po' di più dopo ogni tentativo.

## Apple Watch

L'app per l'orologio è un display e un sensore, mai un secondo registratore. Il telefono registra il giro; l'orologio invia ciò che misura e ciò che tocchi, e disegna ciò che il telefono gli riporta.

### Avere l'app sull'orologio

L'app Velorki per l'orologio è inclusa nell'app per iPhone. Arriva sull'orologio da sola se il tuo orologio installa automaticamente le app complementari; altrimenti apri l'app **Watch** sull'iPhone e installa Velorki dall'elenco delle app disponibili. Poi attiva **Apple Watch** in **Opzioni → Sensori**; questo chiede anche, una volta, di poter inviare notifiche, per quella descritta sotto i pulsanti. La prima volta che un allenamento parte sull'orologio, l'orologio chiede il permesso di leggere la tua frequenza cardiaca. Quella richiesta viene dall'orologio, non dal telefono.

### Cosa mostra l'orologio

- La tua **frequenza cardiaca** in cifre grandi, con il cuore che batte mentre l'orologio misura; due trattini quando nulla sta misurando, e l'ultimo valore attenuato mentre il giro è in pausa. Il cuore e i pulsanti prendono il colore d'accento che hai scelto nell'app.
- Una riga in arancione quando qualcosa non va: accesso a Salute rifiutato, un allenamento che l'orologio non ha voluto avviare, o un telefono che non ha risposto.
- Mentre un giro è in corso, la sua distanza, il cronometro e la velocità, e **In pausa** quando è in pausa. Li formatta tutti il telefono, quindi sono nelle tue unità e nella tua lingua.
- La prossima svolta con la sua icona, il nome e la distanza, come sulla schermata di blocco, in arancione mentre sei fuori percorso; una volta calcolata una via di ritorno o un nuovo percorso, le sue svolte.
- Un tocco al polso quando è il momento di un'indicazione di svolta, e uno quando lasci il percorso. Un orologio che ha dormito per tre svolte tocca una volta sola invece di tre.

Le parole proprie dell'orologio, cioè i pulsanti e le due note a piè di pagina, sono in inglese qualunque sia la lingua del telefono. Non ci sono ancora complicazioni.

### Cosa fanno i pulsanti

| Pulsante | Cosa fa |
|---|---|
| **Inizia giro** | avvia la registrazione sul telefono |
| **Pausa**, **Riprendi** | mettono in pausa il giro e lo riprendono, come sul telefono |
| **Termina** | ferma la registrazione; "Dopo «Termina» salvi il giro sul telefono." |
| **Ferma la FC** | termina la misurazione sull'orologio mentre il giro continua |
| **Misura la FC** | la riavvia, oppure la avvia per un giro in cui l'app dell'orologio è stata aperta in ritardo |

Quando un giro parte sul telefono, l'app dell'orologio si apre da sola e inizia a misurare, quindi al polso non c'è nulla da toccare. Al contrario, **Inizia giro** sull'orologio avvia la registrazione sul telefono e porta il telefono al suo tab **Registra**. Un telefono in tasca, con Velorki in background, riceve una notifica, "Giro avviato dall'orologio", e un tocco su di essa apre l'app; conta, perché iOS non dà il GPS a un'app svegliata in background finché non è stata aperta una volta, quindi la traccia parte da lì. Un'app che hai chiuso del tutto scorrendola via non può essere svegliata dall'orologio, ed è una regola di iOS; dopo qualche tentativo l'orologio dice "Il telefono non risponde. Apri Velorki sul telefono e riprova." Un giro che termini dal polso viene salvato come ogni altro: la registrazione si ferma, e il pannello di salvataggio ti aspetta sul telefono la prossima volta che lo guardi.

### Batteria al polso

Misurare una frequenza cardiaca per ore è ciò che costa all'orologio la sua giornata. La misurazione continua per tutto il giro, pause incluse: un'app dell'orologio che smette di misurare viene messa a dormire da watchOS entro un minuto e non sente più nulla dal telefono, quindi tenerla sveglia è ciò che fa continuare ad arrivare il battito. Il telefono non registra battiti mentre il giro è in pausa. Per giri con molte fermate, **Sensore a riposo in pausa** sotto l'interruttore Apple Watch nelle Opzioni fa smettere l'orologio di misurare a ogni pausa. Lo scambio: il sensore riposa a ogni fermata, ma il telefono deve risvegliare l'orologio quando riparti, il primo battito dopo ogni fermata richiede un momento, e se il risveglio fallisce il battito manca finché il telefono non riprova. Lascialo spento per un battito senza interruzioni. Se l'orologio tace davvero per tre quarti di minuto a metà giro, il telefono rilancia da solo la sua app. **Ferma la FC** termina la misurazione senza toccare il giro. La nota a piè di pagina sulla schermata dice il resto, "Con la modalità risparmio energetico nelle impostazioni dell'orologio, la batteria regge un giro lungo." Disattivare **Apple Watch** nelle Opzioni termina anche una sessione ancora in corso.

## Apple Health e Health Connect

Questa sorgente è la frequenza cardiaca che il tuo telefono già conosce: quella che un Apple Watch ha scritto tramite il suo allenamento, o quella che un'altra app ha messo nell'archivio. È la più lenta e la meno dal vivo delle tre, e una fascia o un orologio che riportano direttamente prendono subito il suo posto.

### Cosa viene letto e cosa viene scritto

- **Letto**: la frequenza cardiaca, e nient'altro. Mentre un giro registra, Velorki chiede all'archivio nuovi campioni ogni cinque secondi, o ogni trenta con **Risparmio batteria** attivo.
- **Completato dopo**: quando il giro viene salvato, i campioni dell'archivio riempiono i punti della traccia senza frequenza cardiaca, purché un campione cada entro mezzo minuto dal punto, e le cifre del giro vengono ricalcolate. Un punto che ha avuto un valore dal vivo da una fascia o da un orologio tiene quello.
- **Scritto**: un allenamento in bici per giro, con partenza, fine e distanza, e solo con **Salva i giri in Health** attivo. Ogni giro viene scritto una volta. Con quell'interruttore spento, Velorki legge soltanto.

## Dove compaiono i valori

### Mentre pedali

Una terza riga di valori compare nel pannello Registra con tutto ciò che è stato riportato durante il giro: **Frequenza cardiaca** con la **FC media** del giro sotto, **Cadenza** e **Potenza**, così un orologio da solo aggiunge un riquadro e nessun sensore non aggiunge nulla. Un sensore che tace tiene il suo riquadro, attenuato e segnato con un collegamento interrotto, fino alla fine del giro. Su iPhone il battito si unisce ai valori sulla scheda della schermata di blocco e nella Dynamic Island.

### Su un giro salvato

La scheda di un giro nella [libreria](./library) cresce con ciò che quel giro porta davvero:

- **FC media**, **FC max**, **Cadenza media** e **Potenza media** tra i valori, ognuno solo se il giro lo ha,
- un grafico **Frequenza cardiaca** sotto il grafico della velocità, lungo il quale puoi trascinare per leggere il valore a qualsiasi distanza.

La tabella **Parziali** resta com'era: **Parziale**, **In movimento**, **Media** e **Dislivello**, senza colonne dei sensori. Un giro importato da un file GPX, FIT o TCX porta con sé frequenza cardiaca, cadenza e potenza e le mostra allo stesso modo.

## Cosa viene salvato e cosa lascia il telefono

I valori fanno parte del giro: una frequenza cardiaca, una cadenza e una potenza su ogni punto della traccia, più le medie e la frequenza cardiaca massima tra le sue cifre. Vivono nell'archivio di Velorki sul telefono, insieme alla traccia.

Nulla viene caricato da solo. Un'esportazione GPX, FIT o TCX porta i valori insieme alla traccia, così un giro che esporti o invii a Strava o Ride with GPS arriva completo. Lo scambio con Apple Health o Health Connect avviene sul telefono. Vedi [privacy sul telefono](./privacy-on-the-phone) per il quadro completo.

## Vedi anche

- [Registrare un giro](./recording-a-ride)
- [Libreria](./library)
- [Impostazioni e aspetto](./settings-and-appearance)
- [Privacy sul telefono](./privacy-on-the-phone)
- [Risoluzione dei problemi](./troubleshooting)
