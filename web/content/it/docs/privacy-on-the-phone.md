---
title: Privacy sul telefono
description: "In parole semplici: cosa resta sul tuo telefono, cosa lo lascia, quando e verso chi. Non c'è nessun account e nulla arriva a noi se non lo chiedi."
order: 17
---

Velorki non ha account, quindi non c'è nulla a cui accedere e nulla su di te su un server. Questa pagina è la versione in parole semplici di cosa significa in pratica; l'[informativa sulla privacy](/privacy) è quella formale.

## Cosa resta sul telefono

Tutto ciò che crei e tutto ciò che scarichi:

- i percorsi pianificati, i giri registrati e le loro tracce GPS,
- le tue impostazioni, comprese le unità e la voce che hai scelto, e il peso, l'anno di nascita, il sesso, la frequenza cardiaca massima, il peso della bici, il tipo di bici e la potenza di soglia che puoi inserire in Opzioni → Ciclista e bici, che sono impostazioni sul telefono e non vengono mai inviate da nessuna parte,
- le aree di mappa offline scaricate,
- i riquadri di routing scaricati e gli indici di ricerca dei luoghi che li accompagnano,
- i token di accesso per Strava e Ride with GPS se li colleghi, che vanno nell'archivio sicuro del telefono in una forma che solo il relay di Velorki può aprire, e sono esclusi dai backup,
- ciò che prendi da Strava: il tuo nome su Strava, l'elenco dei tuoi percorsi Strava per al massimo 48 ore, i percorsi che importi e i collegamenti dai giri caricati alle rispettive attività Strava. Disconnettere elimina tutto questo.

Nulla di tutto questo viene caricato da nessuna parte se non lo chiedi. L'unica eccezione è la sincronizzazione con il cloud: i tuoi percorsi, giri e alcune impostazioni vanno nel tuo iCloud o nel tuo Google Drive, mai a noi, e i dati di Strava restano sul telefono. Su un iPhone o un iPad iCloud è attivo per impostazione predefinita; su Android la sincronizzazione resta disattivata finché non scegli un cloud. **Opzioni → Sincronizzazione → Sincronizza con** sceglie il cloud o disattiva la sincronizzazione, vedi [la libreria](./library#sincronizzazione-con-icloud-o-google-drive).

Su Android, Velorki è deliberatamente escluso dal backup cloud di Google e dal trasferimento da dispositivo a dispositivo, così i tuoi giri non vengono copiati fuori dal telefono nemmeno dal sistema. Per passare a un nuovo telefono, attiva la sincronizzazione con Google, oppure esporta quello che vuoi conservare come file GPX, FIT o TCX, vedi [importa ed esporta](./import-and-export).

## Cosa lascia il telefono, e quando

### Mentre guardi la mappa

I riquadri della mappa vengono scaricati da OpenFreeMap, e da CyclOSM se attivi **Mappa ciclabile online** sotto **Livelli**. La **Mappa ciclabile** è disegnata sul telefono e non chiede nulla a nessun server. Chiedere un riquadro dice al server dei riquadri quale quadrato del mondo stai guardando, e comporta il tuo indirizzo IP, come ogni richiesta. Un'area che hai scaricato viene servita dal telefono e non chiede nulla.

### Meteo

La mappa meteo (pioggia, nuvole, vento) e un percorso colorato per vento o pioggia prendono immagini e dati di previsione direttamente da servizi meteo pubblici, come il Deutscher Wetterdienst, la NOAA, il KNMI, la NASA e EUMETSAT. Ogni richiesta indica una parte della mappa, o un riquadro attorno al tuo percorso, e un orario, e coinvolge il tuo indirizzo IP; il percorso in sé, i tuoi giri e la tua identità non vengono inviati. Con Velorki Plus, la previsione più precisa e il radar pioggia passano invece dal relay di Velorki: per la previsione i punti lungo il percorso, arrotondati a una griglia di circa 2,5 km, con le ore in cui ci passi; per il radar la parte di mappa che guardi e un orario. I servizi meteo vedono il nostro server, non il tuo telefono.

### Quando scarichi un'area

Le aree di mappa offline vengono da OpenFreeMap, come la mappa stessa. I riquadri di routing e l'indice di ricerca accanto vengono dal mirror dei riquadri su GitHub; GitHub viene a sapere quali riquadri scarichi e il tuo indirizzo IP. Se ci sono nuovi dati di mappa, Velorki lo chiede allo stesso mirror; oltre a quella richiesta non esce nulla.

### Mentre pianifichi

Il calcolo del percorso avviene sul tuo telefono ovunque tu abbia i riquadri. Per un'area che non hai scaricato, i punti vanno a un server di routing, che rimanda il percorso. Riceve i punti, nient'altro: nessuna identità, nessun altro percorso, nessun giro.

**Opzioni → Mappe e dati → Calcolo percorso → Solo sul dispositivo** disattiva del tutto il server; Velorki allora offre il download invece di calcolare.

### Mentre cerchi

La ricerca viene risolta sul telefono su un'area scaricata, e nulla di ciò che scrivi lascia il dispositivo.

Non va mai online da sola: non viene inviato nulla se non tocchi **Cerca online "…"**. Dove non è scaricato nulla, o la mappa è su un'area non scaricata, non si cerca nulla finché non lo scegli; **Cerca nelle aree scaricate** resta sul telefono. Allora quello che hai scritto va a Photon, insieme a una posizione approssimativa perché i risultati vicini vengano prima.

Le [soste sulla mappa](./stops-on-the-map) sono lette dall'indice sul telefono e non chiedono nulla.

Toccare **Dettagli** sulla scheda di un luogo recupera i suoi dettagli (orari di apertura, sito web e simili) da OpenStreetMap.

Un link breve a una mappa che condividi in Velorki (`maps.app.goo.gl`, `maps.apple/p`, `osm.org/go`) viene aperto una volta con il servizio che lo ha creato, per sapere dove punta; quel servizio vede il link e il tuo indirizzo IP, come farebbe in un browser.

### Mentre registri

Nulla lascia il telefono. La registrazione, le statistiche, i grafici e i parziali sono tutti calcolati sul dispositivo. Lo stesso vale per frequenza cardiaca, cadenza e potenza da un orologio, un sensore Bluetooth o la tua app salute: vengono salvati con il giro e, se hai attivato Salute, scambiati con Apple Health o Health Connect sul telefono stesso.

La tua posizione centra la mappa e registra i tuoi giri, e resta sul telefono. Velorki chiede il permesso una volta, al primo avvio. Lascia il telefono solo in due casi, entrambi quando li attivi tu: arrotondata a circa un chilometro verso l'assistente, se lo hai consentito, e come posizione approssimativa verso Photon quando cerchi online.

### Quando chiedi all'assistente

Solo con il tuo consenso, e solo quello che hai permesso: il tuo testo, facoltativamente una posizione arrotondata a circa un chilometro, le tue impostazioni di lingua e unità. Nessun nome, nessun account, nessuna cronologia dei percorsi, e mai la tua traccia. Vedi [assistente](./assistant).

### Quando colleghi Strava o Ride with GPS

Nulla va a nessuno dei due finché non colleghi l'account e poi chiedi qualcosa, un caricamento o un'importazione.

Collegare consegna un codice monouso al relay di Velorki, che lo trasforma in un token di accesso aggiungendo il nostro segreto applicativo, e dà il token al tuo telefono in forma sigillata, così che solo il relay possa aprirlo. Noi non conserviamo il token. Da quel momento ogni caricamento e ogni importazione passa dal relay: apre il token per quella singola richiesta e la passa a Strava o Ride with GPS. Non conserva né il file né il token, né alcuna traccia della chiamata, e non può usare il token da solo. Le connessioni sono gratuite, quindi non viene controllato alcun abbonamento; il relay si limita a contare le chiamate per id di installazione anonimo e per indirizzo, per breve tempo, per fermare gli abusi.

I dati di Strava restano sul tuo telefono: non vanno mai all'assistente, in un link di condivisione né a Ride with GPS o a qualsiasi altro servizio. Vedi [Strava e Ride with GPS](./strava-and-ridewithgps).

### Quando crei un link di condivisione

Quel percorso o giro, con la sua traccia, il suo nome e i suoi numeri, viene copiato sul nostro server perché il link possa essere aperto. Il link è pubblico per chiunque lo abbia, mostra dove la traccia inizia e finisce, e viene eliminato automaticamente dopo un anno. Vedi [condivisione](./sharing).

### Quando acquisti Velorki Plus

Lo store gestisce il pagamento e noi non vediamo mai la tua carta. L'abbonamento viene verificato con un id casuale anonimo che non è collegato a un nome, a un indirizzo email o a un identificativo del dispositivo. Con la sincronizzazione attiva, l'app mette quell'id anche nel tuo cloud, così che il pianificatore nel browser, collegato allo stesso account, possa usare il tuo Plus.

### Avvisi di aggiornamento e valutazioni

Su un iPhone Velorki interroga la ricerca pubblica dell'App Store per sapere se esiste una versione più recente, con l'identificativo del bundle dell'app, il tuo paese e la tua lingua; su Android lo dice Google Play. La finestra di valutazione è quella del sistema, Apple o Google decidono se e quando compare, e una valutazione non ci arriva mai.

## Cosa Velorki non fa mai

- Nessun account, nessuna registrazione, nessun indirizzo email.
- Nessuna pubblicità, nessun SDK pubblicitario, nessuna profilazione.
- Nessun SDK di analisi o di segnalazione dei crash nell'app al momento in cui scriviamo. Se mai ne verrà aggiunto uno, l'informativa sulla privacy lo nominerà e dirà cosa raccoglie prima che venga rilasciato.
- Nessuna vendita di dati, a nessuno, mai.
- Nessuna funzione social e nessuna messaggistica tra utenti.

## Eliminare le cose

| Cosa | Come |
|---|---|
| Un percorso o un giro | eliminalo nella [libreria](./library); con la sincronizzazione attiva, sparisce anche dal tuo cloud e dagli altri tuoi dispositivi |
| Aree di mappa offline e riquadri di routing | eliminali nei [dati offline](./offline-maps-and-routing) |
| Un token di Strava o Ride with GPS, e tutto ciò che viene da Strava | **Disconnetti** in Opzioni → Connessioni |
| Tutto ciò che l'app ha salvato | disinstalla l'app |
| Un link di condivisione | scade dopo un anno; scrivi a [hello@orkitec.com](mailto:hello@orkitec.com) con il link per farlo rimuovere prima |

Disinstallare non rimuove i link di condivisione che hai creato, e non rimuove nulla di ciò che hai caricato su Strava o Ride with GPS.

## I tuoi diritti

Se sei nell'UE o nel Regno Unito, il GDPR ti dà dei diritti sui tuoi dati personali. La maggior parte puoi esercitarla da solo, perché i dati sono sul tuo telefono e si esportano come GPX, FIT o TCX in qualsiasi momento. Per tutto ciò che è dalla nostra parte, cioè link di condivisione, voci di log e il record dell'abbonamento, scrivi a [hello@orkitec.com](mailto:hello@orkitec.com). La dichiarazione completa, compresa la base giuridica e a chi rivolgere un reclamo, è nell'[informativa sulla privacy](/privacy).

## Vedi anche

- [Informativa sulla privacy](/privacy)
- [Condivisione](./sharing)
- [Assistente](./assistant)
- [Strava e Ride with GPS](./strava-and-ridewithgps)
- [Mappe offline e calcolo del percorso](./offline-maps-and-routing)
