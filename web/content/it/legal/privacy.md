---
title: Informativa sulla privacy
description: "Cosa fa Velorki con i tuoi dati: nessun account, percorsi e giri restano sul telefono, e un elenco preciso di cosa lascia il dispositivo e quando."
draft: true
---

> **Nota sulla traduzione.** Questa è una traduzione della versione inglese.
> In caso di discrepanze prevale la versione inglese.

In vigore dal: 30 settembre 2026.

Velorki è un'app per pianificare percorsi in bici e registrare giri, realizzata
da Orkitec. Questa pagina spiega cosa succede ai tuoi dati.

**Chi è il responsabile.** Il titolare del trattamento per tutto ciò che è
descritto qui è Steffen Roemer, operante con la denominazione "Orkitec", Straße
der Pariser Kommune 27, 10243 Berlin, Germania, ride@velorki.com. Non è nominato
alcun responsabile della protezione dei dati: il trattamento descritto di seguito
non lo richiede ai sensi dell'art. 37 GDPR. I dati completi del fornitore sono
nella pagina [note legali](./imprint).

## In breve

- Non c'è **nessun account**. Non ti registri, e noi non sappiamo chi sei.
- I tuoi percorsi, i tuoi giri e le tue impostazioni restano **sul tuo
  telefono**.
- Alcune cose hanno bisogno di un server: i riquadri della mappa, il calcolo del
  percorso fuori dalle aree che hai scaricato, la ricerca quando la richiedi e,
  se li usi, l'assistente IA, i collegamenti a Strava e RideWithGPS e i link di
  condivisione. Ciascuno è descritto di seguito.
- Questo **sito web** non ha analisi, pubblicità né tracciamento, quindi il
  breve avviso in fondo alla pagina non ti chiede nulla.
- Non vendiamo i tuoi dati e non li usiamo per pubblicità o profilazione.

## Cosa resta sul tuo dispositivo

I percorsi pianificati, i giri registrati, le loro tracce GPS, le tue
impostazioni, le regioni di mappa offline scaricate, i riquadri di routing
scaricati e gli indici di ricerca dei luoghi che li accompagnano sono salvati
nella memoria propria dell'app sul tuo telefono. Non vengono caricati da nessuna
parte, a meno che non lo richieda tu.

La frequenza cardiaca, la cadenza e la potenza provenienti da un Apple Watch, da
un sensore Bluetooth o dalla tua app di salute vengono salvate con il giro, sul
telefono, come la traccia stessa. Con l'interruttore Salute attivo nelle Opzioni,
l'app legge la frequenza cardiaca da Apple Health o Health Connect e vi scrive i
tuoi giri conclusi come allenamenti di ciclismo; questo scambio avviene sul tuo
telefono e nulla arriva a noi. I valori dei sensori viaggiano con un giro solo
dove viaggia il giro: in un file GPX, FIT o TCX che esporti, o in un caricamento
su Strava o RideWithGPS che avvii tu.

Se colleghi Strava o RideWithGPS, i token di accesso di quegli account vengono
conservati nell'archivio sicuro del telefono (Keychain su iOS, Keystore su
Android), in una forma cifrata che solo il nostro relay può aprire; vedi la
sezione su Strava e RideWithGPS più sotto.

Su Android l'app è esclusa dal backup su cloud di Google e dal trasferimento da
dispositivo a dispositivo, quindi nemmeno il sistema copia i tuoi giri e i tuoi
token di accesso fuori dal telefono. Passare a un nuovo telefono significa
esportare ciò che vuoi conservare come file GPX, FIT o TCX.

## Cosa lascia il tuo dispositivo, e quando

### Calcolo del percorso

Normalmente il calcolo del percorso avviene interamente sul tuo telefono, a
partire dai riquadri di routing che hai scaricato, e nulla viene inviato da
nessuna parte. Per un'area di cui non hai i riquadri, l'app invia le coordinate
dei punti del tuo percorso a un server di routing (BRouter, gestito da noi), che
restituisce il percorso. Al server servono i punti per calcolare il percorso; non
riceve la tua identità, gli altri tuoi percorsi né i tuoi giri.

### Ricerca

I luoghi vengono cercati sul tuo telefono, negli indici di ricerca che
accompagnano i riquadri di routing che hai scaricato. Nulla di ciò che digiti lì
lascia il dispositivo.

Se tocchi "Cerca online …" in fondo ai risultati (o se non hai scaricato alcun
riquadro di routing, nel qual caso la casella di ricerca va online subito), ciò
che hai digitato viene inviato a Photon, un servizio di geocodifica, insieme a
una posizione approssimativa, così che i risultati vicini compaiano per primi.
Photon restituisce suggerimenti di luoghi.

Toccando "Dettagli" sulla scheda di un luogo, i suoi dettagli (orari di
apertura, sito web e simili) vengono recuperati da OpenStreetMap.

### Riquadri della mappa

La mappa viene disegnata a partire da riquadri recuperati da OpenFreeMap e, se
attivi il livello ciclabile, da CyclOSM. Recuperare un riquadro comunica al
fornitore dei riquadri quale parte della mappa stai guardando e comporta il tuo
indirizzo IP, come ogni richiesta web. Dati della mappa © collaboratori di
OpenStreetMap.

### Strava e RideWithGPS (Velorki Plus)

Nulla viene inviato a Strava o RideWithGPS a meno che tu non colleghi l'account
di tua iniziativa e poi avvii un'azione: caricare un giro, importare un percorso.

Quando colleghi l'account, l'app consegna un codice monouso al nostro server
relay, che lo scambia con un token di accesso aggiungendo il segreto della nostra
applicazione, cifra il token con una chiave che possiede solo il relay e lo
restituisce all'app in quella forma. Il tuo telefono conserva il token cifrato;
da solo non può usarlo, e noi non lo conserviamo affatto.

Da quel momento, ogni caricamento, trasferimento di percorso, importazione e
scollegamento che avvii passa attraverso il relay: verifica che il tuo
abbonamento sia attivo, decifra il token per quella singola richiesta, inoltra la
richiesta a Strava o RideWithGPS e restituisce la risposta all'app. Non conserva
né il file né il token, e nulla della risposta, e applica la stessa limitazione
di frequenza di ogni altra chiamata al relay (vedi Log dei server più sotto). I
suoi log non contengono mai il token, il corpo della richiesta o l'ID di
abbonato.

Cosa facciano poi Strava o RideWithGPS con i dati che invii loro è regolato dalle
loro informative sulla privacy.

### L'assistente IA (Velorki Plus)

L'assistente è disattivato finché non lo attivi, e la prima volta che lo apri ti
viene chiesto il consenso. Puoi scegliere di inviare solo il tuo testo, oppure il
testo insieme a una posizione di partenza approssimativa, oppure rifiutare. Puoi
revocare il consenso nelle impostazioni in qualsiasi momento.

Quando lo usi, quanto segue viene inviato tramite il nostro server relay al
nostro fornitore di IA:

- il testo che hai digitato,
- facoltativamente, una posizione di partenza **arrotondata a circa un
  chilometro**,
- le impostazioni di lingua e unità, perché la risposta sia adeguata,
- se chiedi una descrizione del percorso, una sintesi del percorso costruita sul
  tuo telefono: distanza, dislivello, quote dei tipi di fondo, i tratti che
  attraversa con tipo di strada, fondo e pendenza, le sue salite, le località che
  tocca e le soste nelle vicinanze, ciascuna con la distanza lungo il percorso e
  la posizione (a circa 10 m). Anche il fornitore di IA riceve queste posizioni;
  un percorso che parte da casa tua mostra quindi dove abiti.

Nessun identificativo tuo o del tuo telefono viene inserito nel prompt. Il
modello restituisce una richiesta strutturata: una distanza, una forma, nomi di
luoghi, preferenze. Il calcolo vero e proprio del percorso avviene poi nell'app;
il modello non vede mai il tuo percorso.

Il nostro relay passa la richiesta a **OpenRouter, Inc.** (USA), un servizio che
dà accesso a modelli linguistici di diversi fornitori, e OpenRouter la inoltra al
fornitore che eroga il modello che usiamo. Abbiamo configurato OpenRouter in modo
che invii le richieste solo a fornitori che non le usano per addestrare modelli e
non le conservano. Il trasferimento verso gli Stati Uniti si fonda sulle clausole
contrattuali tipo della Commissione europea. OpenRouter e il fornitore del
modello ricevono la richiesta dal nostro relay, non dal tuo telefono, quindi
vedono l'indirizzo del nostro server e non il tuo.

L'assistente raggiunge il modello tramite un'interfaccia compatibile con OpenAI,
quindi chi ospita Velorki in autonomia può puntare il proprio relay verso
qualsiasi fornitore o verso un proprio modello; in quel caso si applica
l'informativa di quel gestore, non questa.

I dati provenienti da Strava non vengono mai inviati al fornitore di IA.

### Link di condivisione (Velorki Plus)

Se crei un link di condivisione per un percorso o un giro, quel percorso o giro,
con la sua traccia, il suo nome e le sue statistiche, viene caricato sul nostro
server e lì conservato, così che chiunque abbia il link possa aprirlo. Frequenza
cardiaca, cadenza e potenza restano fuori: un giro condiviso porta con sé la
traccia e i tempi, non ciò che un sensore ha misurato. Il link è pubblico:
chiunque lo abbia può vedere il contenuto, compresi il punto di partenza e quello
di arrivo della traccia. Tienilo presente prima di condividere un giro che parte
da casa tua.

Un elemento condiviso viene conservato per **un anno** e poi eliminato
automaticamente. Per farlo rimuovere prima, invia il link all'indirizzo di
contatto indicato in fondo e lo eliminiamo. Aprire un link condiviso non richiede
alcun account.

### Abbonamenti

Velorki Plus è venduto tramite l'App Store e Google Play e gestito per nostro
conto da RevenueCat. RevenueCat assegna alla tua installazione un **ID utente app
anonimo**, una stringa casuale non collegata a un nome, a un indirizzo email o a
un identificativo del dispositivo. RevenueCat riceve inoltre dallo store la
ricevuta d'acquisto. Il nostro relay invia quell'ID anonimo a RevenueCat per
verificare se il tuo abbonamento è attivo, e per nient'altro.

Non vediamo mai i tuoi dati di pagamento; restano presso Apple o Google.

### Segnalazione degli arresti anomali e analisi

Non ce n'è. L'app non contiene alcun SDK di segnalazione degli arresti anomali,
di analisi o pubblicitario, e non invia statistiche d'uso; ogni richiesta di rete
che effettua è una di quelle descritte sopra. Gli arresti anomali vengono
segnalati dagli app store in forma aggregata all'account sviluppatore, senza
nulla che ti identifichi, e solo se hai attivato quella funzione nelle
impostazioni del tuo telefono. Se mai venisse aggiunto un sistema di segnalazione
degli arresti anomali, questa sezione lo nominerà e dirà cosa raccoglie prima che
quella versione venga pubblicata.

### Log dei server

Il nostro relay e il nostro server di routing tengono log operativi (ora della
richiesta, endpoint, stato, indirizzo IP e un header con la versione del client)
per far funzionare il servizio, individuare guasti e applicare limiti di
frequenza. Non vengono usati per costruire profili degli utenti e non contengono
mai un token di accesso, il corpo di una richiesta o un ID di abbonato.

- I log di accesso del server web restano sulla macchina per **14 giorni** e
  vengono poi eliminati dalla rotazione dei log.
- Le righe di log proprie dell'applicazione sono raccolte da Orkify, il pannello
  di deployment che il gestore esegue sulla stessa infrastruttura Hetzner, e vi
  vengono cancellate al più tardi dopo **90 giorni**.

## Questo sito

velorki.com è un sito web semplice: nessun account, nessuna pubblicità, nessuna
analisi, nessun tracciamento. Nulla di ciò che fai qui viene misurato, quindi
l'avviso che potresti aver visto in fondo alla pagina è esattamente questo, un
avviso: non c'è alcun consenso da dare o da rifiutare, perché nulla viene salvato
sul tuo dispositivo finché non lo richiedi. La voce 🍪 Cookie nel piè di pagina lo
richiama.

- **Log del server.** Ogni richiesta viene registrata come descritto sopra in
  Log dei server: ora, indirizzo richiesto, stato, dimensione, il tuo indirizzo
  IP e lo user agent del tuo browser, conservati 14 giorni.
- **Segnalazioni di errore.** Se una pagina di questo sito fallisce nel tuo
  browser, invia l'errore, l'indirizzo della pagina e lo user agent del tuo
  browser al nostro server, solo perché possiamo correggere il bug.
- **Cloudflare.** Il sito è servito tramite Cloudflare, che termina la
  connessione, filtra gli attacchi e passa la richiesta al nostro server. Tratta
  quindi il tuo indirizzo IP e la richiesta stessa. Cloudflare si trova negli
  Stati Uniti; il trasferimento si fonda sulle clausole contrattuali tipo
  dell'UE.
- **Un cookie per la lingua.** Scegliere una lingua nell'intestazione imposta un
  cookie chiamato `NEXT_LOCALE` (valore `en` o `de`, un anno). Esiste perché il
  sito si apra nella lingua che hai scelto. Non vi è salvato nient'altro, e viene
  impostato solo quando fai quella scelta — è strettamente necessario per una
  funzione che hai richiesto e non richiede consenso ai sensi del § 25, comma 2,
  della legge tedesca TTDSG.
- **Una preferenza di tema.** Scegliere chiaro, scuro o un colore d'accento
  scrive `velorki.theme` nell'archivio locale del tuo browser. Non lascia mai il
  browser e non è leggibile da noi. Chiudere l'avviso di cui sopra scrive
  un'altra chiave, `velorki.cookie-notice`, così non viene mostrato di nuovo.
- **Pagine condivise.** Aprire un link `velorki.com/s/…` carica il percorso
  condiviso dal nostro server e i riquadri della mappa da OpenFreeMap, che vede
  il tuo indirizzo IP come in ogni richiesta web. La pagina non ha altri
  contenuti di terze parti.
- **La chat di supporto.** Il pulsante della chat nell'angolo è il widget di
  Orkify. Orkitec gestisce anche Orkify, quindi è infrastruttura nostra, ma è un
  sito diverso: lo script viene caricato da orkify.com e chiede a orkify.com le
  sue impostazioni quando la pagina si apre, il che significa che il tuo
  indirizzo IP lo raggiunge come raggiunge qualsiasi server a cui fai una
  richiesta. Non succede nient'altro finché non apri la chat.

  Quando ci scrivi, il tuo messaggio — e il nome e l'indirizzo email che digiti
  nel suo modulo — viene recapitato in un canale Discord privato dove
  rispondiamo, e la conversazione resta lì finché non la eliminiamo. Chiedi a
  ride@velorki.com e rimuoviamo la tua. Il widget conserva l'ID della
  conversazione e il nome e l'email che hai fornito nell'archivio locale del tuo
  browser, così una risposta ti ritrova quando torni, e li cancella quando
  chiudi la chat. Se apri il selettore di sticker, la tua ricerca va a Klipy,
  che restituisce le immagini. Non scrivere nella chat nulla che non vorresti in
  un ticket di supporto; per una segnalazione di sicurezza usa invece
  l'indirizzo in
  [SECURITY.md](https://github.com/orkitec/velorki/blob/main/SECURITY.md).
- **Font e immagini** provengono tutti da questo server e, a parte la chat di
  supporto, non c'è alcuno script di terze parti, alcuna CDN per le nostre
  risorse né alcun servizio di font.

## Conservazione ed eliminazione

| Dati | Conservati | Come eliminarli |
|---|---|---|
| Percorsi, giri, impostazioni, dati offline | sul tuo telefono, finché non li elimini | eliminali nell'app, oppure disinstalla l'app |
| Token di Strava / RideWithGPS | sul tuo telefono, cifrati in modo che solo il nostro relay possa aprirli, finché non scolleghi l'account; mai conservati da parte nostra | scollega l'account nell'app, oppure disinstalla |
| Link di condivisione | un anno, poi eliminati automaticamente | eliminali dall'app |
| Prompt all'IA | non conservati da noi oltre quanto contenuto nei log di cui sopra | non applicabile |
| Dati presso RevenueCat | secondo l'informativa di RevenueCat | contattaci e trasmetteremo la richiesta |
| Conversazioni della chat di supporto | nel nostro canale Discord, finché non le eliminiamo | chiedi a ride@velorki.com |

Disinstallare l'app rimuove tutto ciò che l'app ha salvato sul dispositivo. Non
rimuove i link di condivisione che hai creato (scadono dopo un anno, o su
richiesta), e non rimuove nulla di ciò che hai caricato su Strava o RideWithGPS.

## Basi giuridiche

Per chi legge nell'UE e nel Regno Unito, le basi giuridiche ai sensi dell'art. 6,
par. 1, GDPR sono:

| Cosa | Base |
|---|---|
| Erogazione del sito web e delle pagine condivise, mantenimento dei server, individuazione dei guasti, limiti di frequenza, difesa dagli attacchi | lett. f) legittimo interesse a gestire un servizio che funziona e non viene abusato |
| Calcolo del percorso e ricerca online, quando li richiedi | lett. b) esecuzione del servizio che hai richiesto, e lett. f) per le coordinate strettamente necessarie a rispondere |
| Velorki Plus: verifica presso RevenueCat che un abbonamento sia attivo | lett. b) esecuzione del contratto |
| Strava e RideWithGPS: collegamento di un account e ogni trasferimento che avvii | lett. b) esecuzione del contratto, più lett. a) consenso, prestato collegando l'account |
| Link di condivisione che crei | lett. b) esecuzione del contratto |
| L'assistente IA | lett. a) consenso, richiesto separatamente nell'app e revocabile nelle impostazioni |
| Risponderti nella chat di supporto | lett. b) ove riguardi un abbonamento, altrimenti lett. f) legittimo interesse a rispondere alla persona che ci ha scritto |
| Conservazione dei documenti fiscalmente rilevanti di un abbonamento | lett. c) obbligo legale — e i dati di fatturazione li detengono Apple e Google, non noi |

Non facciamo profilazione, non prendiamo decisioni automatizzate su di te e non
usiamo nulla di tutto questo per il marketing diretto.

## Chi altro riceve dati

Non vendiamo, non affittiamo e non scambiamo dati personali. Raggiungono questi
soggetti, e nessun altro:

**Responsabili del trattamento, che agiscono per noi in base a un accordo sul
trattamento dei dati**

- **Hetzner Cloud GmbH**, Gunzenhausen, Germania — il server su cui girano il
  relay, i link di condivisione e questo sito web. I dati restano in Germania.
- **Cloudflare, Inc.**, San Francisco, USA — DNS, CDN e protezione dagli attacchi
  per velorki.com e api.velorki.com. Indirizzi IP e metadati delle richieste.
- **RevenueCat, Inc.**, San Francisco, USA — la verifica dell'abbonamento. L'ID
  utente app anonimo e la ricevuta dello store, nessun nome e nessun indirizzo
  email.
- **Orkify**, gestito dallo stesso gestore sull'infrastruttura Hetzner di cui
  sopra — il pannello di deployment che raccoglie i log dell'applicazione e le
  metriche di processo descritti in Log dei server e le segnalazioni di errore
  di questo sito web, e il widget della chat di supporto.
- **Discord Netherlands B.V.** (per gli utenti in Europa; Discord Inc., San
  Francisco, USA, per il servizio sottostante) — dove una conversazione della
  chat di supporto viene recapitata e conservata.
- **Klipy** — la ricerca di sticker e GIF nella chat di supporto, e solo mentre
  quel selettore è aperto.
- **OpenRouter, Inc.**, USA, e il fornitore del modello a cui inoltra —
  l'assistente IA, solo dopo il tuo consenso, limitato a fornitori che non usano
  le richieste per l'addestramento né le conservano.

**Servizi che il tuo telefono o il tuo browser contatta direttamente, ciascuno
responsabile del proprio trattamento**

- **OpenFreeMap** (riquadri della mappa) e **OpenStreetMap France** (il livello
  CyclOSM, solo quando lo attivi) — i riquadri della parte di mappa che stai
  guardando, e il tuo indirizzo IP.
- **komoot GmbH**, Potsdam, Germania — il geocoder Photon su
  `photon.komoot.io`, e solo per una ricerca online che hai richiesto.
- **OpenStreetMap** (`api.openstreetmap.org`) — i dettagli di un luogo, quando
  tocchi "Dettagli" sulla sua scheda.
- **Apple Inc.** e **Google Ireland Ltd** — la vendita di Velorki Plus. Sono loro
  i venditori; non vediamo mai i tuoi dati di pagamento.
- **Strava, Inc.** e **Ride with GPS** — solo dopo che hai collegato l'account e
  solo per un trasferimento che avvii. Cosa ne facciano è regolato dalle loro
  informative.

Consegneremo inoltre dati a un tribunale o a un'autorità dove la legge lo
richiede.

## Trasferimenti al di fuori dell'UE

Cloudflare, RevenueCat, OpenRouter e il fornitore del modello dietro di esso,
Discord, Klipy, Strava, Ride with GPS, Apple e Google si trovano negli Stati
Uniti o vi trasferiscono dati. Questi trasferimenti si fondano sulle clausole
contrattuali tipo della Commissione europea o, dove il fornitore ne dispone,
sulla sua certificazione ai sensi dell'EU-US Data Privacy Framework, insieme
alle misure tecniche di sicurezza del fornitore. Hetzner, komoot e i servizi di
riquadri della mappa su cui ci basiamo si trovano nell'UE, OpenStreetMap nel
Regno Unito. Tutto ciò che l'app conserva per te resta sul tuo telefono e non
viene trasferito da nessuna parte.

## Sicurezza

Ogni connessione ai nostri server e ai servizi di cui sopra è cifrata con TLS. I
token di Strava e RideWithGPS non si trovano mai in chiaro da nessuna parte: il
tuo telefono li tiene nell'archivio sicuro della piattaforma, protetti con una
chiave che possiede solo il relay, e il relay ne apre uno per la singola
richiesta per cui serve e non conserva nulla. Il database delle condivisioni è
sul disco del server, fuori dalla directory di rilascio, leggibile solo
dall'utente del servizio. I log sono epurati: nessun header `Authorization`,
nessun corpo di richiesta, nessun ID di abbonato. L'accesso al server richiede
una chiave, non una password, ed è riservato al gestore. Se una violazione
dovesse mettere a rischio i tuoi diritti, la notificheremo all'autorità di
controllo entro 72 ore (art. 33 GDPR) e, dove la legge lo richiede, a te.

## I tuoi diritti

Se ti trovi nell'UE o nel Regno Unito, hai diritto di accesso (art. 15 GDPR),
rettifica (16), cancellazione (17), limitazione del trattamento (18),
portabilità dei dati (20) e opposizione a un trattamento basato su un legittimo
interesse (21), e dove ci basiamo sul tuo consenso — l'assistente — puoi
revocarlo in qualsiasi momento senza pregiudicare la liceità di quanto avvenuto
prima (art. 7, par. 3). La maggior parte di questi diritti puoi esercitarla in
autonomia, perché i dati sono sul tuo telefono e si possono esportare come file
GPX, FIT o TCX quando vuoi.

Per tutto ciò che si trova da parte nostra (link di condivisione, voci di log, il
record presso RevenueCat) scrivi a **ride@velorki.com**. Rispondiamo entro 30
giorni. Ci serviranno informazioni sufficienti a identificare i dati, il che per
un link di condivisione significa il link stesso, dato che non c'è alcun account
tramite cui cercarti.

Puoi anche presentare reclamo a un'autorità di controllo. La nostra è la
[Berliner Beauftragte für Datenschutz und Informationsfreiheit](https://www.datenschutz-berlin.de),
e puoi rivolgerti allo stesso modo all'autorità del luogo in cui vivi.

Il titolare del trattamento è Steffen Roemer, operante con la denominazione
"Orkitec", Straße der Pariser Kommune 27, 10243 Berlin, Germania.

## Minori

Velorki non è rivolto ai minori e non raccoglie consapevolmente dati da loro. Non
ha funzioni social, nessuna messaggistica tra utenti e nessuna pubblicità.

## Modifiche

Se questa informativa cambia in un modo che riguarda ciò che lascia il tuo
dispositivo, l'app te lo dirà alla prossima apertura, e la data in alto
cambierà. Le versioni precedenti restano nella cronologia git del repository.

## Contatti

Orkitec, ride@velorki.com; indirizzo postale nelle [note legali](./imprint). Per
le segnalazioni di sicurezza vedi
[SECURITY.md](https://github.com/orkitec/velorki/blob/main/SECURITY.md) nel
repository del codice sorgente.
