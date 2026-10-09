---
title: Privacy sul telefono
description: "In parole semplici: cosa resta sul tuo telefono, cosa lo lascia, quando e verso chi. Non c'è nessun account e nulla viene caricato se non lo chiedi."
order: 16
---

Velorki non ha account, quindi non c'è nulla a cui accedere e nulla su di te su un server. Questa pagina è la versione in parole semplici di cosa significa in pratica; l'[informativa sulla privacy](/privacy) è quella formale.

## Cosa resta sul telefono

Tutto ciò che crei e tutto ciò che scarichi:

- i percorsi pianificati, i giri registrati e le loro tracce GPS,
- le tue impostazioni, comprese le unità e la voce che hai scelto, e il peso, l'anno di nascita, il sesso, la frequenza cardiaca massima, il peso della bici, il tipo di bici e la potenza di soglia che puoi inserire in Opzioni → Ciclista, che sono impostazioni sul telefono e non vengono mai inviate da nessuna parte,
- le aree di mappa offline scaricate,
- i riquadri di routing scaricati e gli indici di ricerca dei luoghi che li accompagnano,
- i token di accesso per Strava e Ride with GPS se li colleghi, che vanno nell'archivio sicuro del telefono in una forma che solo il relay di Velorki può aprire.

Nulla di tutto questo viene caricato da nessuna parte se non lo chiedi.

Su Android, Velorki è deliberatamente escluso dal backup cloud di Google e dal trasferimento da dispositivo a dispositivo, così i tuoi giri non vengono copiati fuori dal telefono nemmeno dal sistema. Passare a un nuovo telefono significa esportare quello che vuoi conservare come file GPX, FIT o TCX, vedi [importa ed esporta](./import-and-export).

## Cosa lascia il telefono, e quando

### Mentre guardi la mappa

I riquadri della mappa vengono scaricati da OpenFreeMap, e da CyclOSM se attivi **Mappa ciclabile online** sotto **Livelli**. La **Mappa ciclabile** è disegnata sul telefono e non chiede nulla a nessun server. Chiedere un riquadro dice al server dei riquadri quale quadrato del mondo stai guardando, e comporta il tuo indirizzo IP, come ogni richiesta. Un'area che hai scaricato viene servita dal telefono e non chiede nulla.

### Mentre pianifichi

Il calcolo del percorso avviene sul tuo telefono ovunque tu abbia i riquadri. Per un'area che non hai scaricato, i punti vanno a un server di routing, che rimanda il percorso. Riceve i punti, nient'altro: nessuna identità, nessun altro percorso, nessun giro.

**Opzioni → Avanzate → Calcolo percorso → Solo sul dispositivo** disattiva del tutto il server; Velorki allora offre il download invece di calcolare.

### Mentre cerchi

La ricerca riceve risposta sul telefono ovunque l'indice dell'area sia scaricato, e nulla di quello che scrivi lascia il dispositivo.

Va online quando tocchi **Cerca online "…"**, o quando non hai un indice per l'area che stai guardando. Allora quello che hai scritto va a Photon, insieme a una posizione approssimativa perché i risultati vicini vengano prima.

Le [soste sulla mappa](./stops-on-the-map) sono lette dall'indice sul telefono e non chiedono nulla.

Toccare **Dettagli** sulla scheda di un luogo recupera i suoi dettagli (orari di apertura, sito web e simili) da OpenStreetMap.

Un link breve a una mappa che condividi in Velorki (`maps.app.goo.gl`, `maps.apple/p`, `osm.org/go`) viene aperto una volta con il servizio che lo ha creato, per sapere dove punta; quel servizio vede il link e il tuo indirizzo IP, come farebbe in un browser.

### Mentre registri

Nulla lascia il telefono. La registrazione, le statistiche, i grafici e i parziali sono tutti calcolati sul dispositivo. Lo stesso vale per frequenza cardiaca, cadenza e potenza da un orologio, un sensore Bluetooth o la tua app salute: vengono salvati con il giro e, se hai attivato Salute, scambiati con Apple Health o Health Connect sul telefono stesso.

### Quando chiedi all'assistente

Solo con il tuo consenso, e solo quello che hai permesso: il tuo testo, facoltativamente una posizione arrotondata a circa un chilometro, le tue impostazioni di lingua e unità. Nessun nome, nessun account, nessuna cronologia dei percorsi, e mai la tua traccia. Vedi [assistente](./assistant).

### Quando colleghi Strava o Ride with GPS

Nulla va a nessuno dei due finché non colleghi l'account e poi chiedi qualcosa, un caricamento o un'importazione.

Collegare consegna un codice monouso al relay di Velorki, che lo trasforma in un token di accesso aggiungendo il nostro segreto applicativo, e dà il token al tuo telefono in forma sigillata, così che solo il relay possa aprirlo. Noi non conserviamo il token. Da quel momento ogni caricamento e ogni importazione passa dal relay: controlla il tuo abbonamento, apre il token per quella singola richiesta e la passa a Strava o Ride with GPS. Non conserva né il file né il token, e non può usare il token da solo.

### Quando crei un link di condivisione

Quel percorso o giro, con la sua traccia, il suo nome e i suoi numeri, viene copiato sul nostro server perché il link possa essere aperto. Il link è pubblico per chiunque lo abbia, mostra dove la traccia inizia e finisce, e viene eliminato automaticamente dopo un anno. Vedi [condivisione](./sharing).

### Quando acquisti Velorki Plus

Lo store gestisce il pagamento e noi non vediamo mai la tua carta. L'abbonamento viene verificato con un id casuale anonimo che non è collegato a un nome, a un indirizzo email o a un identificativo del dispositivo.

## Cosa Velorki non fa mai

- Nessun account, nessuna registrazione, nessun indirizzo email.
- Nessuna pubblicità, nessun SDK pubblicitario, nessuna profilazione.
- Nessun SDK di analisi o di segnalazione dei crash nell'app al momento in cui scriviamo. Se mai ne verrà aggiunto uno, l'informativa sulla privacy lo nominerà e dirà cosa raccoglie prima che venga rilasciato.
- Nessuna vendita di dati, a nessuno, mai.
- Nessuna funzione social e nessuna messaggistica tra utenti.

## Eliminare le cose

| Cosa | Come |
|---|---|
| Un percorso o un giro | eliminalo nella [libreria](./library) |
| Aree di mappa offline e riquadri di routing | eliminali nei [dati offline](./offline-maps-and-routing) |
| Un token di Strava o Ride with GPS | **Disconnetti** in Opzioni → Connessioni |
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
