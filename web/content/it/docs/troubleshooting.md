---
title: Risoluzione dei problemi
description: "Soluzioni ai problemi più comuni: nessuna posizione, nessun percorso, il banner dei riquadri, una voce muta su iOS, download bloccati e link che non si aprono."
order: 19
---

Le cose che vanno storte più spesso, e cosa fare in ogni caso. Se il tuo problema non è qui, l'ultima sezione dice come segnalarlo.

## Velorki non trova la mia posizione

I sintomi sono "Posizione non ancora disponibile.", un pulsante di localizzazione che non fa nulla, oppure "Attiva la posizione o tocca la mappa per impostare la partenza."

1. **Hai rifiutato il permesso?** Velorki chiede con una sua finestra, **Mostrare la tua posizione?**, prima di quella di sistema. Se hai risposto **Non ora**, tocca di nuovo il pulsante di localizzazione e rispondi **Continua**.
2. **È disattivato per Velorki?** "Il permesso di localizzazione è disattivato per Velorki. Attivalo nelle impostazioni di sistema." arriva con un'azione **Impostazioni** che ti porta direttamente lì. Concedi "Mentre usi l'app" o "Quando in uso".
3. **I servizi di localizzazione sono spenti sul telefono?** "I servizi di localizzazione sono disattivati su questo dispositivo." riguarda il telefono, non Velorki. L'azione **Impostazioni** apre il posto giusto.
4. **Al chiuso, o appena acceso?** "Posizione non ancora disponibile." spesso significa che il telefono non ha ancora alcuna posizione. Esci all'aperto e dagli mezzo minuto.

Velorki non ha mai bisogno della posizione in background. "Mentre usi l'app" basta, anche per registrare un giro.

## Non appare nessun percorso

**"Questo percorso richiede riquadri di routing che non sono su questo dispositivo."** Il tuo telefono non ha dati di routing per la zona e non c'è un server di routing su cui ripiegare. Tocca il pulsante, che conta i riquadri e la loro dimensione, e scaricali. Vedi [mappe offline e calcolo del percorso](./offline-maps-and-routing).

**"Nessun server di routing configurato, impostane uno in Opzioni → Avanzate."** Questa build non include alcun indirizzo di server. Scarica i riquadri di routing per dove ti trovi e calcola invece sul telefono.

**Opzioni → Avanzate → Calcolo percorso è su "Solo sul dispositivo".** Allora Velorki non chiederà mai a un server, per scelta. Passalo ad **Automatico** o scarica i riquadri.

**"Calcolo del percorso non riuscito:" con un motivo.** Di solito il server non era raggiungibile. Riprova, e controlla che un punto non sia finito in mare o su un'autostrada dove le bici non possono andare. Spostare il punto in questione di qualche metro su una strada vera di solito risolve.

## Il banner dei riquadri mancanti non va via

Il banner sta nel pianificatore ogni volta che il percorso attraversa una zona il cui riquadro di routing non è sul telefono. Velorki non calcola mai su una copertura parziale, perché il motore di calcolo tratterebbe il riquadro mancante come terra vuota e restituirebbe in silenzio un percorso sbagliato.

1. Tocca il pulsante sul banner. Apre **Dati di routing offline** con già selezionati esattamente i riquadri che servono al percorso.
2. Scaricali. I riquadri pesano da 125 a 250 MB ciascuno, quindi stai sul Wi-Fi.
3. Quando un riquadro arriva, il pianificatore ricalcola da solo e il banner viene sostituito dai dati del percorso.

Se i riquadri che ti servono mostrano **Serve un Velorki più recente**, aggiorna prima l'app; la finestra spiega perché.

## La voce non dice nulla

Controlla in quest'ordine:

1. **Opzioni → Navigazione → Indicazioni di svolta** attivo, e **Voce** attivo. Voce è in grigio finché Indicazioni di svolta è disattivato.
2. **Il pulsante silenzia sul banner delle svolte.** Silenzia la voce solo per il resto di quel giro. Toccalo di nuovo.
3. **Stai seguendo un percorso?** La guida richiede un percorso scelto sotto **Segui un percorso** nella scheda Registra, e un giro che sta effettivamente registrando.
4. **Il volume e l'interruttore silenzioso del telefono.**

### Su un iPhone

Se Velorki mostra **Voci migliori, basta scaricarle**, il telefono ha solo la voce compatta per la tua lingua. Segui i passi nel pannello: **Impostazioni → Accessibilità → Contenuto letto → Voci → la tua lingua → tocca la nuvola** accanto a una voce Migliorata o Premium. Velorki usa poi da solo la voce migliore sul telefono.

Se la voce scelta è contrassegnata con **Richiede internet**, viene generata su un server: senza segnale la svolta non viene detta o arriva in ritardo. Per i giri scegli una voce senza quel contrassegno. Sono nascoste finché **Mostra voci online** in fondo all'elenco delle voci non è attivo.

"Nessuna voce installata per la tua lingua." significa che il telefono non ha nulla con cui parlare; aggiungi una voce nelle impostazioni di sintesi vocale o di Contenuto letto del telefono.

## Un download è bloccato o fallisce

- **I download avvengono solo mentre l'app è aperta.** Lascia Velorki in primo piano per un riquadro grande. Se si interrompe, la parte arrivata viene conservata e il tentativo successivo riprende da lì.
- **"Download non riuscito:"** con un motivo. Tocca di nuovo il riquadro per riprovare. Un download ripreso non parte da zero.
- **"Impossibile caricare l'elenco dei riquadri:"** significa che il mirror non era raggiungibile. **Riprova** è sullo schermo.
- **Controlla lo spazio libero sul telefono.** Un riquadro di routing da 250 MB richiede 250 MB, più l'area della mappa.
- **Annulla e riavvia** con il pulsante di chiusura nell'intestazione dell'avanzamento se un download si è chiaramente bloccato.
- Velorki non distingue il Wi-Fi dai dati mobili, quindi avvisa invece di bloccare. Avvia tu i download grandi sul Wi-Fi.

## Un link di condivisione non si apre nell'app

- **Il link ha più di un anno.** Gli elementi condivisi vengono eliminati automaticamente dopo 365 giorni, e la pagina poi dice non trovato. Chiedi un link nuovo.
- **L'app non è installata su quel telefono.** La pagina funziona comunque nel browser: la mappa, i dati e **Scarica GPX**.
- **"Apri in Velorki" non ha fatto nulla.** Scarica il GPX dalla pagina e aprilo con Velorki; arriva sulla stessa schermata di importazione. Un link scaduto o scritto male viene ignorato in silenzio invece di mostrare un errore.

## Un file non si importa

Velorki legge GPX, FIT e TCX, e decide dai byte, non dal nome del file.

| Messaggio | Significato |
|---|---|
| "Non è un file GPX, FIT o TCX." | il contenuto non è nessuno dei tre formati, qualunque cosa dica il nome |
| "Impossibile leggere il file." | il file è uno dei formati ma è danneggiato |
| "Il file non contiene punti traccia." | un file vuoto, o un GPX con soli waypoint |
| "Impossibile aprire il file." | il sistema non ha consegnato il file |

Se un file viene importato come il tipo sbagliato, cambia **SALVA COME** tra **Percorso** e **Giro** nella schermata di importazione prima di salvare. I percorsi FIT vengono interpretati come giri per come funzionano le loro marche temporali.

## La registrazione si è fermata da sola

Su Android, rispondi **Apri impostazioni** a **Continua a registrare in background**, consenti lì a Velorki l'uso della batteria senza limitazioni e concedi il permesso per le notifiche; sono entrambe le cose che impediscono al sistema di uccidere la registrazione mentre il telefono dorme. Su entrambe le piattaforme la traccia viene scritta in continuazione, quindi se l'app è stata chiusa trovi **Giro non terminato** al prossimo avvio, con **Riprendi**, **Termina** e **Scarta**. Vedi [registrare un giro](./recording-a-ride).

## Un sensore Bluetooth non viene trovato

1. **Sveglia il sensore.** Una fascia trasmette solo a contatto con la pelle, un sensore di cadenza solo con la pedivella che gira. Lo schermo lo dice: "Ancora niente. Sveglia il sensore: indossa la fascia o gira i pedali."
2. **Attiva il Bluetooth.** "Attiva il Bluetooth per trovare i tuoi sensori." riguarda la radio del telefono, non il sensore.
3. **Concedi il permesso.** "Velorki non ha il permesso di usare il Bluetooth." significa che è stato rifiutato. iOS chiede la prima volta che tocchi **Cerca**, e solo allora.
4. **Libera il sensore.** Questi sensori servono un dispositivo alla volta, quindi un ciclocomputer o un'altra app che tiene il tuo impedisce a Velorki di vederlo.
5. **Cerca di nuovo.** Una ricerca dura circa quindici secondi ed elenca solo i dispositivi che parlano i profili standard di frequenza cardiaca, velocità e cadenza, o potenza.

Un sensore associato che dice **Non connesso** è fuori portata, in standby o scarico. Velorki continua a provare mentre un giro registra o la schermata **Sensori Bluetooth** è aperta. Vedi [sensori e orologio](./sensors-and-watch).

## L'orologio non si collega

- **Non c'è l'interruttore Apple Watch.** Appare in **Opzioni → Sensori** solo su un iPhone a cui è abbinato un orologio.
- **L'app non è sull'orologio.** Viene fornita dentro l'app per iPhone; se non è arrivata da sola, installa Velorki dall'app **Watch** sull'iPhone.
- **Il giro è in corso ma l'orologio non misura nulla.** Un giro avviato sul telefono apre l'app dell'orologio e la fa misurare da sola. Se l'app dell'orologio mostra comunque due trattini, tocca lì **Misura la FC**; una riga arancione sotto il cuore dice cosa è andato storto, se l'orologio lo sa.
- **L'orologio non mostra il battito.** L'orologio chiede il permesso di leggere la frequenza cardiaca la prima volta che un allenamento parte lì. Se è stato rifiutato, concedilo nelle impostazioni della privacy dell'orologio.
- **"Inizia giro" sull'orologio non fa nulla sul telefono.** Con Velorki in background il giro parte e il telefono mostra una notifica da toccare. Un'app chiusa con uno scorrimento non può essere svegliata dall'orologio, è una regola di iOS: l'orologio dice "Il telefono non risponde", e aprire Velorki sul telefono è la soluzione.
- **La traccia inizia solo quando apro il telefono.** iOS non dà GPS a un'app svegliata in background finché non è stata aperta una volta. Tocca la notifica, o apri Velorki, e la traccia parte; dopo il telefono può restare bloccato.

## Nessuna frequenza cardiaca da Salute

- **L'interruttore è disattivato.** **Apple Health**, o **Health Connect** su Android, deve essere attivo in **Opzioni → Sensori**. Finché è disattivato non viene letto nulla.
- **L'accesso è stato rifiutato.** "Velorki non ha ottenuto l'accesso ai tuoi dati sulla salute." lascia l'interruttore disattivato. Riattivalo e consenti la frequenza cardiaca, oppure concedila nell'app di salute stessa.
- **Nessuno ha scritto una frequenza cardiaca.** Velorki legge solo quello che è già nell'archivio, quindi senza un orologio e senza un'app che ci mette un battito, non c'è nulla da leggere.
- **Arriva in ritardo.** L'archivio viene interrogato ogni cinque secondi, o ogni trenta con il risparmio energetico attivo, e i buchi vengono riempiti ancora una volta quando il giro viene salvato. Una fascia o un orologio che riportano direttamente sono sempre più veloci.

## Manca una funzione Plus

- **"Non disponibile in questa build"** su una riga di collegamento, o nella pagina dell'abbonamento, significa che questa copia di Velorki è stata compilata senza le chiavi per quel servizio o quello store. È così che appare una copia compilata da te.
- **Il pulsante Chiedi o il pulsante Condividi link non c'è proprio** in una build senza un server Velorki configurato.
- **Tutto il resto** dovrebbe dire "… fa parte di Velorki Plus" e offrire la pagina dell'abbonamento. Se hai un abbonamento e non lo fa, tocca **Ripristina acquisti** in **Opzioni → Abbonamento**.

## Segnalare un bug

**Opzioni → Informazioni → Segnala un problema** apre il tracker delle segnalazioni, oppure vai direttamente su [github.com/orkitec/velorki/issues](https://github.com/orkitec/velorki/issues).

Una buona segnalazione contiene:

1. cosa hai fatto, passo per passo, e cosa è successo invece di quello che ti aspettavi;
2. il telefono e la versione del sistema operativo;
3. la versione di Velorki, da **Opzioni → Informazioni**;
4. dove è successo, se c'entrano la mappa o il calcolo del percorso, perché molti problemi sono specifici di un angolo dei dati della mappa;
5. uno screenshot, che di solito vale tutto quanto sopra.

Velorki non ha segnalazione automatica dei crash e non ci invia nulla da solo, quindi una tua segnalazione è l'unico modo in cui veniamo a sapere di un problema.

## Vedi anche

- [Mappe offline e calcolo del percorso](./offline-maps-and-routing)
- [Navigazione svolta per svolta](./navigation)
- [Registrare un giro](./recording-a-ride)
- [Sensori e orologio](./sensors-and-watch)
- [Importazione ed esportazione](./import-and-export)
- [Primi passi](./getting-started)
