---
title: Informativa sulla privacy
description: "Cosa fa Velorki con i tuoi dati: nessun account, percorsi e giri restano sul telefono o nel browser a meno che tu non li sincronizzi con il tuo iCloud o Google Drive, e un elenco preciso di cosa lascia il dispositivo e quando."
draft: false
---

> **Nota sulla traduzione.** Questa è una traduzione della versione inglese.
> In caso di discrepanze prevale la versione inglese.

In vigore dal: 23 ottobre 2026.

Velorki è un'app per pianificare percorsi in bici e registrare giri, realizzata
da Orkitec, per iPhone, iPad e Android, e un pianificatore web su
app.velorki.com. Questa pagina spiega cosa succede ai tuoi dati.

**Chi è il titolare.** Il titolare del trattamento per tutto ciò che è
descritto qui è Steffen Roemer, operante con la denominazione "Orkitec", Straße
der Pariser Kommune 27, 10243 Berlin, Germania, ride@velorki.com. Non è nominato
alcun responsabile della protezione dei dati: il trattamento descritto di seguito
non lo richiede ai sensi dell'art. 37 GDPR. I dati completi del gestore sono
nella pagina [note legali](./imprint).

## In breve

- Non c'è **nessun account**. Non ti registri, e noi non sappiamo chi sei.
- I tuoi percorsi, i tuoi giri e le tue impostazioni restano **sul tuo
  telefono**, o nel tuo browser per il pianificatore web. Se attivi la
  sincronizzazione, vanno nel tuo iCloud o nel tuo Google Drive, mai a noi.
- Alcune cose hanno bisogno di un server: i riquadri della mappa, il calcolo del
  percorso fuori dalle aree che hai scaricato, la ricerca quando la richiedi e,
  se li usi, l'assistente IA, i collegamenti a Strava e RideWithGPS (gratuiti) e i link di
  condivisione. Ciascuno è descritto di seguito.
- Questo **sito web** non ha strumenti di analisi, pubblicità né tracciamento,
  quindi il breve avviso in fondo alla pagina non ti chiede nulla.
- Il **pianificatore web** su app.velorki.com funziona allo stesso modo: nessun
  account, nessuno strumento di analisi, la tua libreria conservata nel tuo
  browser.
- Non vendiamo i tuoi dati e non li usiamo per pubblicità o profilazione.

## Cosa resta sul tuo dispositivo

I percorsi pianificati, i giri registrati, le loro tracce GPS, le tue
impostazioni, le regioni di mappa offline scaricate, i riquadri di routing
scaricati e gli indici di ricerca dei luoghi che li accompagnano sono salvati
nella memoria propria dell'app sul tuo telefono. Non vengono caricati da nessuna
parte, a meno che non lo richieda tu; l'unica eccezione è la sincronizzazione
con il cloud, descritta più avanti, che va al tuo iCloud o al tuo Google Drive e
non a noi. Ciò che il pianificatore web conserva nel tuo browser è descritto
alla voce Il pianificatore web.

La frequenza cardiaca, la cadenza e la potenza provenienti da un Apple Watch, da
un sensore Bluetooth o dalla tua app di salute vengono salvate con il giro, sul
telefono, come la traccia stessa. Con l'interruttore Health attivo nelle Opzioni,
l'app legge la frequenza cardiaca da Apple Health o Health Connect e vi scrive i
tuoi giri conclusi come allenamenti di ciclismo; questo scambio avviene sul tuo
telefono e nulla arriva a noi. I valori dei sensori viaggiano con un giro solo
dove viaggia il giro: in un file GPX, FIT o TCX che esporti, in un caricamento
su Strava o RideWithGPS che avvii tu, o nel tuo cloud mentre la sincronizzazione
è attiva.

Se colleghi Strava o RideWithGPS, i token di accesso di quegli account vengono
conservati nell'archivio sicuro del telefono (Keychain su iOS, Keystore su
Android), in una forma cifrata che solo il nostro relay può aprire, e ciò che prendi da
Strava resta sul telefono; vedi la sezione su Strava e RideWithGPS più sotto.

Su Android l'app è esclusa dal backup su cloud di Google e dal trasferimento da
dispositivo a dispositivo, quindi nemmeno il sistema copia i tuoi giri e i tuoi
token di accesso fuori dal telefono. Per passare a un nuovo telefono, attiva la
sincronizzazione con Google (descritta più avanti) oppure esporta ciò che vuoi
conservare come file GPX, FIT o TCX.

## Cosa lascia il tuo dispositivo, e quando

### Calcolo del percorso

Normalmente il calcolo del percorso avviene interamente sul tuo telefono, a
partire dai riquadri di routing che hai scaricato, e nulla viene inviato da
nessuna parte. Per un'area di cui non hai i riquadri, l'app invia le coordinate
dei punti del tuo percorso a un server di routing (BRouter, gestito da noi), che
restituisce il percorso. Al server servono i punti per calcolare il percorso; non
riceve la tua identità, gli altri tuoi percorsi né i tuoi giri.

I riquadri di routing e gli indici di ricerca che li accompagnano vengono
scaricati dal nostro mirror dei riquadri su GitHub (`raw.githubusercontent.com`
e i download delle release di `github.com`). GitHub viene a sapere quali
riquadri di 5° scarichi e il tuo indirizzo IP, come in ogni richiesta web. Il
pianificatore web li recupera invece tramite app.velorki.com, così GitHub vede
Cloudflare e non te.

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

### Meteo

**La mappa meteo e la previsione gratuita del percorso.** Quando attivi la
pioggia, le nuvole o il vento sulla mappa, o colori un percorso in base al vento
o alla pioggia senza Velorki Plus, l'app recupera immagini e dati di previsione
direttamente da servizi meteorologici pubblici: il Deutscher Wetterdienst
(Germania), la National Oceanic and Atmospheric Administration statunitense e la
Iowa State University (USA), la NASA, EUMETSAT, il KNMI (Paesi Bassi) e
l'Istituto meteorologico finlandese. Ogni richiesta indica una parte della
mappa, o un rettangolo attorno al tuo percorso, e un orario, e comporta il tuo
indirizzo IP, come ogni richiesta web. Il percorso in sé, i tuoi giri e la tua
identità non vengono inviati.

**Meteo più preciso lungo il percorso (Velorki Plus).** L'app invia al
nostro relay i punti lungo il percorso arrotondati a una griglia di circa 2,5
km, ciascuno con la sua altitudine arrotondata a 50 m, e le ore in cui ci
passerai — non il percorso, il suo nome né i tuoi giri. Il relay verifica che il
tuo abbonamento sia attivo e chiede le previsioni per quei punti della griglia
al National Weather Service statunitense, a Bright Sky (per le previsioni del
Deutscher Wetterdienst) e a MET Norway. Questi vedono il nostro server, non il
tuo telefono. Ogni risposta viene conservata fino a due ore per punto della
griglia e condivisa con chiunque chieda lo stesso punto.

**Radar pioggia in tutta Europa (Velorki Plus).** L'app chiede al nostro
relay la parte della mappa che stai guardando e un orario. Il relay recupera il
radar una sola volta per tutti dall'archivio aperto di EUMETNET OPERA e, per
l'Italia, dal Dipartimento della Protezione Civile, lo conserva fino a due ore e
mezza e restituisce un'immagine di quella parte della mappa. I fornitori del
radar vedono il nostro server, non il tuo telefono, e il relay non tiene traccia
di quale parte della mappa hai chiesto.

### Strava e RideWithGPS

Entrambe le connessioni sono gratuite. Nulla viene inviato a Strava o
RideWithGPS a meno che tu non colleghi l'account di tua iniziativa e poi avvii
un'azione: caricare un giro, importare un percorso.

Quando colleghi l'account, l'app consegna un codice monouso al nostro server
relay (api.velorki.com), che lo scambia con un token di accesso aggiungendo il
segreto della nostra applicazione, cifra il token con una chiave che possiede
solo il relay e lo restituisce all'app in quella forma. Il tuo telefono conserva
il token cifrato nel suo archivio sicuro (Keychain su iOS, Keystore su Android),
escluso dai backup; da solo non può usarlo, e noi non lo conserviamo affatto.

Da quel momento, ogni caricamento, trasferimento di percorso, importazione e
scollegamento che avvii passa attraverso il relay: decifra il token per quella
singola richiesta, inoltra la richiesta a Strava o RideWithGPS e restituisce la
risposta all'app. Non conserva né il file né il token, nulla della risposta, né
alcuna traccia della chiamata. Per queste chiamate non viene verificato alcun
abbonamento; per fermare gli abusi il relay tiene solo contatori di limitazione
di frequenza di breve durata, legati all'ID anonimo della tua installazione e
all'indirizzo IP (vedi Log dei server più sotto). I suoi log non contengono mai
il token, il corpo della richiesta o quell'ID.

#### Strava

**Cosa chiede Velorki.** Due permessi: `read`, il tuo profilo pubblico di Strava
(il tuo ID atleta e il tuo nome), e `activity:write`, per caricare i giri che
scegli di caricare. Velorki non legge le tue attività.

**Cosa legge e conserva, tutto solo sul tuo telefono:**

- il tuo ID atleta e il tuo nome, mostrati in Opzioni → Connessioni, finché non
  scolleghi l'account;
- l'elenco dei tuoi percorsi Strava (nome, distanza, dislivello positivo,
  descrizione e data), recuperato quando apri la schermata di importazione e
  tenuto sul telefono per al massimo **48 ore**;
- il file GPX di un percorso, quando importi quel percorso; viene salvato come
  percorso nella libreria dell'app, e così anche ogni percorso che modifichi a
  partire da esso, solo finché il percorso esiste ancora su Strava: mentre l'app
  è aperta, online e collegata, lo ricontrolla su Strava ogni 48 ore, e lo
  rimuove se è stato eliminato su Strava o non è stato possibile controllarlo
  per 7 giorni, e te lo comunica. Viene rimosso anche quando lo elimini o
  scolleghi l'account;
- dopo un caricamento, l'ID dell'attività Strava e il suo link, conservati
  insieme al giro perché l'app possa mostrare "View on Strava", finché non
  scolleghi l'account.

Un giro che carichi viene inviato a Strava, che lo elabora come descritto
nell'[informativa sulla privacy di Strava](https://www.strava.com/legal/privacy).
Strava e Orkitec sono ciascuno responsabile del proprio trattamento.

**I dati di Strava restano con te.** I dati di Strava vengono solo mostrati a
te, nell'app. Non vengono mai inviati all'assistente IA, mai inseriti in un link
di condivisione e mai inviati a RideWithGPS o a qualsiasi altro servizio. Sui
nostri server non conserviamo alcun dato di Strava.

**Eliminazione.** Scollegare Strava in Opzioni → Connessioni revoca
l'autorizzazione di Velorki presso Strava, elimina i token ed elimina dal
telefono ogni elemento che proviene da Strava: i percorsi Strava importati e
quelli modificati a partire da essi, l'elenco dei percorsi in cache e i
collegamenti alle attività salvati. L'app conferma poi: "I tuoi dati Strava
sono stati eliminati da questo telefono." Se invece revochi l'accesso di Velorki
su strava.com, l'app se ne accorge alla successiva chiamata a Strava, elimina gli
stessi dati e te lo dice. Anche disinstallare l'app li elimina. Dato che sono
tutti sul tuo telefono, questi sono i modi per eliminarli; per domande o una
richiesta di eliminazione, scrivi a ride@velorki.com.

**Dati di utilizzo presso Strava.** Strava può monitorare e raccogliere dati
sul modo in cui Velorki usa l'API di Strava (dati di utilizzo) e può usarli per
qualsiasi finalità commerciale, interna o esterna, compresi il miglioramento
dell'API di Strava o della piattaforma Strava, la fornitura di assistenza a
sviluppatori o utenti e la verifica del rispetto del proprio contratto sull'API.

#### RideWithGPS

Ciò che RideWithGPS fa con i dati che gli invii è regolato dalla sua
informativa sulla privacy.

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

### Sincronizzazione con il cloud (iCloud o Google Drive)

Ogni dispositivo si sincronizza con al massimo un cloud, scelto in **Opzioni →
Sincronizza con**: iCloud (iPhone e iPad con iOS 17 o successivo, e il
pianificatore web), Google (l'iPhone, l'iPad, Android e il pianificatore web) o
disattivato. Su un iPhone o un iPad iCloud è attivo per impostazione
predefinita; su Android e nel browser la sincronizzazione resta disattivata
finché non scegli un cloud.

**Cosa viene sincronizzato.** I tuoi percorsi salvati, e i tuoi giri registrati,
ciascuno con la sua traccia, le note, le statistiche, i lap e la frequenza
cardiaca, la cadenza, la potenza e la temperatura registrate con esso. Vengono
sincronizzate anche alcune impostazioni: tema, colore d'accento, aspetto della
mappa, aspetto del radar pioggia, stile della barra, lato della colonna,
unità e le impostazioni di svolta, vocali e di ricalcolo del percorso. Nel
browser con iCloud, le impostazioni restano nel browser. Ogni app scrive inoltre
un piccolo record Plus nello stesso cloud, descritto alla voce Abbonamenti.

**Alcune cose non vengono mai sincronizzate.** I percorsi letti da Strava e i
percorsi modificati a partire da essi, e i link Strava dei giri che hai caricato
su Strava, restano su quel solo telefono, come descritto sopra alla voce
Strava. Neppure i link dei caricamenti su Ride with GPS vengono sincronizzati;
un percorso che importi da Ride with GPS viene sincronizzato come tuo percorso,
senza il suo ID di Ride with GPS. Le regioni di mappa scaricate e i riquadri di
routing, i permessi, i sensori associati, la voce, la lingua, gli account
collegati e l'abbonamento stesso non ne fanno parte.

**iCloud.** I dati passano da CloudKit di Apple e finiscono nel tuo database
privato iCloud. Apple li conserva e li trasferisce, e contano nello spazio
iCloud a tua disposizione. Apple li cifra in transito e sui suoi server; con la
Protezione avanzata dei dati attiva sono cifrati end-to-end, come descritto
nella [panoramica di Apple sulla sicurezza dei dati di iCloud](https://support.apple.com/en-us/102651).
Nel browser accedi con il pulsante di Apple, in una finestra di Apple; lo script
CloudKit JS di Apple viene caricato da Apple solo quando scegli iCloud, e
conserva il tuo accesso ad Apple in un cookie sul sito del pianificatore finché
non esci (anche cancellare i dati del sito nel browser lo rimuove).

Il server di caricamento di Apple non accetta caricamenti inviati direttamente
dal nostro sito. Perciò, quando il pianificatore web salva un percorso o un giro
su iCloud, il file del record (la traccia e i dettagli del percorso o del giro)
viene inviato a app.velorki.com/cloudkit/upload, una piccola funzione Cloudflare
che lo passa invariato all'indirizzo di caricamento monouso che Apple ha fornito
per esso e restituisce la ricevuta di Apple. Non conserva nulla, e non ne
teniamo log. Gli altri campi del record vanno direttamente ad Apple.

**Google Drive.** Accedi con il tuo account Google, e Velorki chiede un solo
permesso: la propria cartella nascosta dell'app nel tuo Drive
(`drive.appdata`). Non può vedere né modificare nessun altro file del tuo Drive,
e la cartella non compare tra i tuoi file. Google conserva i dati, che contano
nello spazio Google a tua disposizione; Google li cifra in transito e sui suoi
server, non end-to-end. Il telefono conserva l'ID e l'indirizzo email del tuo
account Google per mostrare chi ha effettuato l'accesso. Nel browser accedi con
il pulsante di Google; lo script di accesso di Google viene caricato solo quando
scegli Google, e il suo token di accesso vive solo quanto la pagina e al massimo
un'ora.

**Cosa vede Orkitec.** Nulla. Orkitec non gestisce alcun server per la
sincronizzazione e non può leggere, accedere né eliminare ciò che si trova nel
tuo iCloud o nel tuo Drive; non esiste un account Velorki. Apple e Google
agiscono in base al tuo accordo con loro.

**Eliminare, disattivare.** Mentre la sincronizzazione è attiva, eliminare un
percorso o un giro su un dispositivo lo elimina anche nel tuo cloud e sugli
altri tuoi dispositivi. Scegliere **Disattivato**, uscire dall'account o passare
all'altro cloud ferma la sincronizzazione su quel dispositivo e non elimina
nulla; il passaggio invia la tua libreria al nuovo cloud e lascia la vecchia
copia dov'era. Ciò che è già in iCloud resta lì finché non lo elimini nelle
impostazioni iCloud di un dispositivo Apple. Ciò che è in Google Drive resta lì
finché non lo elimini: in Google Drive sul web, Impostazioni → Gestisci app →
Velorki → Opzioni → Elimina dati app nascosti; revocare l'accesso di Velorki su
myaccount.google.com/permissions impedisce a Velorki di raggiungere la cartella.

### Abbonamenti

Velorki Plus è venduto tramite l'App Store e Google Play e gestito per nostro
conto da RevenueCat. RevenueCat assegna alla tua installazione un **ID utente app
anonimo**, una stringa casuale non collegata a un nome, a un indirizzo email o a
un identificativo del dispositivo. RevenueCat riceve inoltre dallo store la
ricevuta d'acquisto. Il nostro relay invia quell'ID anonimo a RevenueCat per
verificare se il tuo abbonamento è attivo, e per nient'altro.

Non vediamo mai i tuoi dati di pagamento; restano presso Apple o Google.

**Plus nel browser.** Plus non si può acquistare nel pianificatore web. Per
usare lì il Plus acquistato nell'app per telefono, ogni app che si sincronizza
scrive un proprio record nel cloud con cui si sincronizza: il suo ID utente app
di RevenueCat, se è un'app per iPhone o per Android, se all'ultimo controllo il
suo store ha indicato che Plus è attivo, e quando l'ha scritto l'ultima volta,
sotto un ID casuale del dispositivo. Lo riscrive ogni sei ore e quando Plus
inizia o finisce. Il pianificatore web, collegato allo stesso account iCloud o
Google, legge questi record, li conserva nel browser e invia l'ID di quello più
recente al nostro relay con ogni richiesta Plus, esattamente come farebbe l'app.
Il relay verifica quell'ID presso RevenueCat come fa per le app; il browser non
contatta RevenueCat, non crea alcun ID proprio per Plus e non scrive mai un
record Plus.

Il record va solo nell'account con cui la sincronizzazione è partita la prima
volta, o in uno che scegli poi in Opzioni → Sincronizza con: dopo un'uscita
dall'account, con un altro account o con la sincronizzazione disattivata, l'app
smette di scriverlo e non lo copia mai da sola in un secondo account. Non viene
eliminato dal cloud; il pianificatore web ignora un record non scritto da 30
giorni, e dimentica i record che ha conservato quando esci o cambi account o
cloud.

### Avvisi di aggiornamento e valutazioni

Qualche secondo dopo l'avvio, e di nuovo dopo un giorno in background, l'app
chiede al suo store se esiste una versione più recente. Su iOS interroga la
ricerca pubblica dell'App Store di Apple (`itunes.apple.com`) con il bundle ID
di Velorki e i codici di paese e di lingua del tuo telefono; su Android
interroga il servizio di aggiornamento in-app di Google Play sul telefono, che
risponde solo per un'installazione da Play. Ciascuna comporta il tuo indirizzo
IP, come ogni richiesta web, e nient'altro di tuo.

Di tanto in tanto l'app chiede al sistema di mostrare il suo pannello di
valutazione. Apple o Google decidono se compare e quanto spesso; una valutazione
o una recensione che lasci lì va a loro con il tuo account dello store, e all'app
non viene detto se hai valutato né come. Il pianificatore web non fa né l'una né
l'altra cosa.

### Segnalazione degli arresti anomali e analytics

Non ce ne sono. L'app non contiene alcun SDK di segnalazione degli arresti
anomali, di analisi o pubblicitario, e non invia statistiche d'uso; ogni
richiesta di rete che effettua è una di quelle descritte sopra. Gli arresti
anomali vengono
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

velorki.com è un sito web semplice: nessun account, nessuna pubblicità, nessuno
strumento di analisi, nessun tracciamento. Nulla di ciò che fai qui viene
misurato, quindi l'avviso che potresti aver visto in fondo alla pagina è
esattamente questo, un
avviso: non c'è alcun consenso da dare o da rifiutare, perché nulla viene salvato
sul tuo dispositivo finché non lo richiedi. La voce 🍪 Cookie nel piè di pagina lo
richiama.

- **Log del server.** Ogni richiesta viene registrata come descritto sopra in
  Log dei server: ora, indirizzo richiesto, stato, dimensione, il tuo indirizzo
  IP e lo user agent del tuo browser, conservati 14 giorni.
- **Segnalazioni di errore.** Se una pagina di questo sito genera un errore nel
  tuo browser, invia l'errore, l'indirizzo della pagina e lo user agent del tuo
  browser al nostro server, solo perché possiamo correggere il bug.
- **Cloudflare.** Il sito è servito tramite Cloudflare, che termina la
  connessione, filtra gli attacchi e passa la richiesta al nostro server. Tratta
  quindi il tuo indirizzo IP e la richiesta stessa. Cloudflare si trova negli
  Stati Uniti; il trasferimento si fonda sulle clausole contrattuali tipo
  dell'UE.
- **Un cookie per la lingua.** Scegliere una lingua nell'intestazione imposta un
  cookie chiamato `NEXT_LOCALE` (il codice della lingua scelta, ad esempio `it`, un anno). Esiste perché il
  sito si apra nella lingua che hai scelto. Non vi è salvato nient'altro, e viene
  impostato solo quando fai quella scelta — è strettamente necessario per una
  funzione che hai richiesto e non richiede consenso ai sensi del § 25, comma 2,
  della legge tedesca TDDDG.
- **Una preferenza di tema.** Scegliere chiaro, scuro o un colore d'accento
  scrive `velorki.theme` nella memoria locale del tuo browser. Non lascia mai il
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
  conversazione e il nome e l'email che hai fornito nella memoria locale del tuo
  browser, così una risposta ti ritrova quando torni, e li cancella quando
  chiudi la chat. Se apri il selettore di sticker, la tua ricerca va a Klipy,
  che restituisce le immagini. Non scrivere nella chat nulla che non vorresti in
  un ticket di supporto; per una segnalazione di sicurezza usa invece
  l'indirizzo in
  [SECURITY.md](https://github.com/orkitec/velorki/blob/main/SECURITY.md).
- **Font e immagini** provengono tutti da questo server e, a parte la chat di
  supporto, non c'è alcuno script di terze parti, alcuna CDN per le nostre
  risorse né alcun servizio di font.

## Il pianificatore web (app.velorki.com)

app.velorki.com è la stessa app che gira nel tuo browser: pianifica, cerca e
tiene una libreria, ma non registra e non naviga. Non c'è alcun account, nessuno
strumento di analisi e nessuna pubblicità. Su un telefono o un tablet l'indirizzo
mostra la pagina di download dell'app e non carica nient'altro.

- **Salvato nel tuo browser.** I tuoi percorsi, giri e impostazioni sono
  conservati in un database nella memoria propria del browser (IndexedDB, o
  l'Origin Private File System in alcuni browser), i riquadri di routing e gli
  indici di ricerca che hai scaricato nella sua Cache Storage, e le
  impostazioni, l'account cloud con cui hai effettuato l'accesso e un ID
  anonimo come quello dell'app nella sua memoria locale. Restano in quel
  browser, su quel computer, finché non li elimini nel pianificatore o non
  cancelli i dati del sito nel browser. Questa memoria è ciò a cui serve il
  pianificatore, quindi non richiede consenso ai sensi del § 25, comma 2, della
  legge tedesca TDDDG.
- **Cosa contatta.** Gli stessi servizi dell'app, alle stesse regole descritte
  sopra: i riquadri della mappa da OpenFreeMap (e CyclOSM se lo attivi), Photon
  per una ricerca online, i servizi meteorologici pubblici per i livelli meteo,
  e il nostro relay per l'assistente IA, il meteo Plus e i link di
  condivisione. Non usa mai il server di routing: i percorsi vengono calcolati
  nel browser. I riquadri di routing arrivano tramite app.velorki.com. Quando un
  testo richiede un sistema di scrittura (alfabeto) che i font dell'app non
  hanno, il browser carica
  un font di riserva da Google Fonts (`fonts.gstatic.com`), che vede il tuo
  indirizzo IP. La sincronizzazione con il cloud contatta Apple o Google, solo
  dopo che ne hai scelto uno.
- **Cloudflare.** Il pianificatore è servito da Cloudflare Pages. Due piccole
  funzioni lì rispondono a `/tiles/` (che recupera i riquadri dal nostro mirror
  su GitHub) e a `/cloudkit/upload` (vedi Sincronizzazione con il cloud). Come
  ogni server vedono il tuo indirizzo IP e la richiesta; non conservano nulla, e
  non ne teniamo log.

## Conservazione ed eliminazione

| Dati | Conservati | Come eliminarli |
|---|---|---|
| Percorsi, giri, impostazioni, dati offline | sul tuo telefono, finché non li elimini | eliminali nell'app, oppure disinstalla l'app (con la sincronizzazione attiva, eliminare un percorso o un giro lo elimina anche nel tuo cloud) |
| Token di Strava / RideWithGPS | sul tuo telefono, cifrati in modo che solo il nostro relay possa aprirli, finché non scolleghi l'account; mai conservati da parte nostra | disconnetti l'account nell'app, oppure disinstalla |
| Dati di Strava: il tuo nome, i collegamenti alle attività | sul tuo telefono, finché non scolleghi l'account; mai conservati da parte nostra | scollega Strava nell'app, oppure disinstalla; domande a ride@velorki.com |
| Percorsi importati da Strava e percorsi modificati a partire da essi | sul tuo telefono, solo finché il percorso esiste ancora su Strava: ricontrollato ogni 48 ore, rimosso se è stato eliminato lì o non è stato possibile controllarlo per 7 giorni; mai conservati da parte nostra | eliminalo nell'app, scollega Strava, oppure disinstalla |
| L'elenco in cache dei tuoi percorsi Strava | sul tuo telefono, al massimo 48 ore | scollega Strava, oppure disinstalla |
| Contatori di limitazione di frequenza (ID anonimo dell'installazione, indirizzo IP) | sul nostro server, per la finestra di conteggio, al massimo un giorno | non applicabile |
| Link di condivisione | un anno, poi eliminati automaticamente | eliminali dall'app |
| Percorsi, giri e impostazioni sincronizzati con iCloud | nel tuo iCloud, finché non li elimini lì; mai conservati da parte nostra | eliminali nelle impostazioni iCloud di un dispositivo Apple |
| Percorsi, giri e impostazioni sincronizzati con Google Drive | nella cartella nascosta di Velorki nel tuo Drive, finché non la elimini; mai conservati da parte nostra | in Google Drive sul web: Impostazioni → Gestisci app → Velorki → Opzioni → Elimina dati app nascosti |
| Record Plus (ID di RevenueCat, piattaforma, Plus attivo, ultima scrittura) | nel cloud con cui ti sincronizzi, finché non elimini lì i dati dell'app; ignorati dal pianificatore web dopo 30 giorni | come i percorsi sincronizzati sopra |
| La libreria, i riquadri e le impostazioni del pianificatore web | nel tuo browser, finché non li elimini | eliminali nel pianificatore, oppure cancella i dati del sito nel browser |
| Prompt all'IA | non conservati da noi oltre quanto contenuto nei log di cui sopra | non applicabile |
| Dati presso RevenueCat | secondo l'informativa di RevenueCat | contattaci e trasmetteremo la richiesta |
| Conversazioni della chat di supporto | nel nostro canale Discord, finché non le eliminiamo | chiedi a ride@velorki.com |

Disinstallare l'app rimuove tutto ciò che l'app ha salvato sul dispositivo. Ciò
che la sincronizzazione ha messo nel tuo iCloud o nel tuo Google Drive resta lì;
vedi Sincronizzazione con il cloud sopra. Non
rimuove i link di condivisione che hai creato (scadono dopo un anno, o su
richiesta), e non rimuove nulla di ciò che hai caricato su Strava o RideWithGPS.

## Basi giuridiche

Per chi legge nell'UE e nel Regno Unito, le basi giuridiche ai sensi dell'art. 6,
par. 1, GDPR sono:

| Cosa | Base |
|---|---|
| Erogazione del sito web e delle pagine condivise, mantenimento dei server, individuazione dei guasti, limiti di frequenza, difesa dagli attacchi | lett. f) legittimo interesse a gestire un servizio che funziona e non è oggetto di abusi |
| Calcolo del percorso e ricerca online, quando li richiedi | lett. b) esecuzione del servizio che hai richiesto, e lett. f) per le coordinate strettamente necessarie a rispondere |
| Velorki Plus: verifica presso RevenueCat che un abbonamento sia attivo | lett. b) esecuzione del contratto |
| Velorki Plus: il meteo più preciso lungo il percorso e il radar pioggia | lett. b) esecuzione del contratto |
| Strava e RideWithGPS: collegamento di un account, ogni trasferimento che avvii e i dati di Strava conservati sul tuo telefono | lett. b) esecuzione del servizio che hai richiesto, più lett. a) consenso, prestato collegando l'account e revocato scollegandolo |
| Link di condivisione che crei | lett. b) esecuzione del contratto |
| Sincronizzazione con iCloud o Google Drive, finché è attiva, compresi i record Plus e il caricamento del pianificatore web tramite `/cloudkit/upload` | lett. b) esecuzione del servizio che hai richiesto; Apple e Google agiscono in base al tuo accordo con loro |
| Il pianificatore web: erogarlo, conservare la tua libreria nel tuo browser, recuperare i riquadri tramite app.velorki.com | lett. b) esecuzione del servizio che hai richiesto, e lett. f) per l'indirizzo IP e la richiesta strettamente necessari a rispondere |
| Avvisi di aggiornamento | lett. f) legittimo interesse a informarti di una versione più recente; vengono inviati solo il bundle ID, il paese e la lingua |
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
  per velorki.com e api.velorki.com, e hosting del pianificatore web su
  app.velorki.com con le sue funzioni `/tiles/` e `/cloudkit/upload`. Indirizzi
  IP e metadati delle richieste, e il caricamento verso iCloud che inoltra senza
  leggerlo.
- **RevenueCat, Inc.**, San Francisco, USA — la verifica dell'abbonamento. L'ID
  utente app anonimo e la ricevuta dello store, nessun nome e nessun indirizzo
  email.
- **Orkify**, gestito dallo stesso operatore sull'infrastruttura Hetzner di cui
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
- **Servizi meteorologici pubblici** — il Deutscher Wetterdienst, la NOAA, la
  Iowa State University, la NASA, EUMETSAT, il KNMI e l'Istituto meteorologico
  finlandese — la parte della mappa o il rettangolo attorno al tuo percorso che
  hai richiesto, un orario e il tuo indirizzo IP, solo mentre un livello meteo o
  la previsione gratuita del percorso è attivo.
- **Apple Inc.** (iCloud) — i percorsi, i giri, le impostazioni e i record Plus
  della sincronizzazione con iCloud, nel tuo iCloud e solo finché ti sincronizzi
  con iCloud. Non li riceviamo; Apple agisce in base al tuo accordo iCloud con
  Apple.
- **Google Ireland Ltd**, Dublino (Google LLC, USA, al di fuori del SEE e della
  Svizzera) — i percorsi, i giri, le impostazioni e i record Plus della
  sincronizzazione con Google, nella cartella nascosta dell'app nel tuo Drive, e
  solo finché ti sincronizzi con Google. Non li riceviamo; Google agisce in base
  al tuo accordo con Google. Google fornisce inoltre i font di riserva del
  pianificatore web (`fonts.gstatic.com`) e il controllo degli aggiornamenti di
  Google Play su Android.
- **GitHub, Inc.**, San Francisco, USA — il nostro mirror dei riquadri, da cui
  l'app scarica i riquadri di routing e gli indici di ricerca; i nomi dei
  riquadri e il tuo indirizzo IP.
- **Apple Inc.** e **Google Ireland Ltd** — la vendita di Velorki Plus, il
  controllo degli aggiornamenti e il pannello di valutazione. Sono loro i
  venditori; non vediamo mai i tuoi dati di pagamento.
- **Strava, Inc.** e **Ride with GPS** — solo dopo che hai collegato l'account e
  solo per un trasferimento che avvii. Cosa ne facciano è regolato dalle loro
  informative.

Comunicheremo inoltre dati a un tribunale o a un'autorità dove la legge lo
richiede.

## Trasferimenti al di fuori dell'UE

Cloudflare, RevenueCat, OpenRouter e il fornitore del modello dietro di esso,
Discord, Klipy, Strava, Ride with GPS, GitHub, Apple e Google si trovano negli Stati
Uniti o vi trasferiscono dati. Questi trasferimenti si fondano sulle clausole
contrattuali tipo della Commissione europea o, dove il fornitore ne dispone,
sulla sua certificazione ai sensi dell'EU-US Data Privacy Framework, insieme
alle misure tecniche di sicurezza del fornitore. Hetzner, komoot e i servizi di
riquadri della mappa su cui ci basiamo si trovano nell'UE, OpenStreetMap nel
Regno Unito. Tutto ciò che l'app conserva per te resta sul tuo telefono, o nel
tuo browser, e non viene trasferito da nessuna parte a meno che tu non attivi la
sincronizzazione, che va al tuo iCloud o al tuo Google Drive.

## Sicurezza

Ogni connessione ai nostri server e ai servizi di cui sopra è cifrata con TLS. I
token di Strava e RideWithGPS non si trovano mai in chiaro da nessuna parte: il
tuo telefono li tiene nell'archivio sicuro della piattaforma, protetti con una
chiave che possiede solo il relay, e il relay ne apre uno per la singola
richiesta per cui serve e non conserva nulla. Il database delle condivisioni è
sul disco del server, fuori dalla directory di rilascio, leggibile solo
dall'utente del servizio. Dai log sono rimossi i dati sensibili: nessun header
`Authorization`, nessun corpo di richiesta, nessun ID di abbonato. L'accesso al
server richiede
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
autonomia, perché i dati sono sul tuo telefono, nel tuo browser o nel tuo cloud,
e si possono esportare come file GPX, FIT o TCX quando vuoi.

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

Le modifiche a questa informativa vengono pubblicate su questa pagina, con la
data in alto aggiornata; quelle significative vengono annunciate anche sul sito
web. Le versioni precedenti restano nella cronologia git del repository.

## Contatti

Orkitec, ride@velorki.com; indirizzo postale nelle [note legali](./imprint). Per
le segnalazioni di sicurezza vedi
[SECURITY.md](https://github.com/orkitec/velorki/blob/main/SECURITY.md) nel
repository del codice sorgente.
