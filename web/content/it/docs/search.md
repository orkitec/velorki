---
title: Ricerca
description: Trova luoghi, vie, numeri civici e cose come acqua potabile o bagni, sul telefono dove hai scaricato un'area e online ovunque altrove.
order: 4
---

Il campo di ricerca in alto nel tab Pianifica trova città, vie, numeri civici e punti di interesse come caffè, acqua potabile e negozi di bici. Dove hai scaricato un'area risponde dal telefono, all'istante e senza segnale; ovunque altrove interroga un geocoder online.

## Come cercare

1. Apri il tab **Pianifica** e tocca il campo in alto, con il suggerimento **Cerca un luogo**.
2. Digita almeno tre caratteri. I risultati compaiono in una scheda sotto il campo mentre scrivi.
3. Tocca un risultato. La mappa si sposta sul luogo, lo segna con uno spillo e ne apre la scheda.

Le coordinate scritte o incollate nel campo, `40.71747, -73.94840` o `40,71747° N, 73,94840° W` come le copiano le app di mappe, sono il luogo stesso: un solo risultato in quel punto, senza cercare né inviare nulla. Un luogo condiviso da un'altra app si apre allo stesso modo, vedi [importazione ed esportazione](./import-and-export#un-luogo-da-unaltra-app).

## La scheda del luogo

Un risultato di ricerca, una [sosta sulla mappa](./stops-on-the-map) o un luogo condiviso da un'altra app apre una scheda con il nome del luogo, cos'è, la sua città, quanto è distante da te e, con un percorso, quanto è lontano dal percorso. Non cambia nulla finché non scegli un'azione, che dipende dal piano:

- **Niente ancora pianificato**: **Percorso fin qui** va da dove sei al luogo; **Parti da qui** lo rende il primo punto del percorso.
- **Solo una partenza**: **Destinazione** lo rende la fine del percorso.
- **Un percorso**: **Aggiungi come sosta** lo inserisce nel percorso dove si trova lungo la strada; **Destinazione** lo aggiunge in fondo.

Nel tab Registra la scheda informa soltanto, senza azioni.

Sotto:

- **Dettagli** recupera il luogo da OpenStreetMap, solo quando lo tocchi: orari di apertura e se è aperto ora, sito web, numero di telefono, cucina, accesso per sedie a rotelle, posti all'aperto e la sua voce di Wikipedia, per quanto sono mappati. I dettagli restano sul telefono per una settimana, così la volta dopo il luogo li mostra subito. Il pulsante manca per vie e luoghi senza un id OpenStreetMap.
- **Apri in…** mostra il luogo in Apple Maps, in Google Maps se è installata (iPhone), in un'app di mappe a tua scelta (Android) o su OpenStreetMap nel browser, oppure lo passa a **Condividi…**.

Chiudere la scheda (la **X**, uno scorrimento verso il basso o un tocco sulla mappa) non cambia nulla e svuota la ricerca.

## Offline o online

Velorki decide in base al **centro della mappa**, non alla tua connessione. Ogni riquadro di routing scaricato porta con sé un indice di ricerca della sua area, quindi:

- se il riquadro sotto il centro della mappa ha il suo indice sul telefono, la richiesta viene risolta sul telefono;
- se non lo ha, la richiesta va online a Photon.

In fondo alla scheda dei risultati c'è esattamente una riga, e quale sia ti dice da dove vengono i risultati:

| Riga | Significa | Toccandola |
|---|---|---|
| **Cerca online "…"** | stai guardando risultati offline | esegue lo stesso testo online |
| **Mostra risultati offline** | stai guardando risultati online | esegue di nuovo lo stesso testo sul telefono |
| **Scarica quest'area per cercare offline** | quest'area non ha un indice sul telefono | apre la schermata offline per l'area visibile |

Quella riga resta visibile mentre scorri l'elenco, ed è mostrata anche sotto un messaggio di errore, dove conta di più.

## Cosa trova

- **Luoghi**: città, paesi, villaggi, frazioni, sobborghi, quartieri, località e isole.
- **Vie**, con i numeri civici.
- **Punti di interesse**, ognuno con la sua icona e la sua etichetta: Caffè, Ristorante, Fast food, Gelateria, Distributore, Pompa per bici, Acqua potabile, Bagni, Stazione di riparazione bici, Negozio di bici, Noleggio bici, Parcheggio bici, Ricarica e-bike, Riparo, Campeggio, Hotel, Ostello, Rifugio, Supermercato, Panetteria, Farmacia, Area picnic, Stazione, Terminal traghetti, Aeroporto, Punto panoramico, Vetta, Passo, Parco, Spiaggia, Acqua, Riserva naturale, Attrazione, Museo, Sito storico, Luogo di culto, Ospedale, Università, Impianto sportivo, Centro commerciale, Torre, Faro, Edificio.
- **Luoghi noti nella tua lingua**: "Parigi" trova Parigi, e un luogo famoso viene prima dei suoi omonimi.

Le righe offline mostrano il tipo, la distanza e la città sotto il nome, per quanto ciascuno sia noto: "Acqua potabile · 350 m", "Via · Manhattan". Una fontanella, un bagno, un riparo o una rastrelliera senza un nome proprio è elencato sotto il suo tipo.

## Cercare per tipo

Digita il nome di un tipo anziché il nome di un luogo. "acqua potabile", "panetteria", "bagni" e tutti gli altri funzionano, nella lingua in cui gira l'app.

L'elenco si apre allora con i cinque più vicini di quel tipo al centro della mappa, ognuno con la sua distanza, e sotto seguono le normali corrispondenze per nome. Velorki cerca in un'area che cresce da 5 a 50 km intorno al centro della mappa finché non ne ha abbastanza. È il modo veloce per rispondere a "dov'è la fontanella più vicina" nel mezzo di un giro.

Una ricerca per tipo ignora gli interruttori dei gruppi descritti sotto.

## Numeri civici

Scrivi il numero dove lo mette il tuo paese: "Via Roma 12/A", "Hauptstrasse 12", "400 W 42nd", "Budapest, Fő utca 12". Velorki trova la via e risponde alla posizione del numero lungo di essa; la riga è l'indirizzo come l'hai scritto, "400 West 42nd Street". Una città prima della via con una virgola, o dopo, dice di quale luogo intendi la via. Un CAP viene ignorato, e un numero che fa parte del nome di una via, "Route 66", resta parte del nome.

Dove il numero cade tra due che l'indice conosce, Velorki ne stima la posizione e la riga dice **≈ 400** così vedi che è una stima.

## Errori di battitura, forme brevi e altri alfabeti

La ricerca offline perdona una lettera o due sbagliate, una parola scritta unita o separata, e forme brevi come "V." o "Str.". I nomi in cirillico o in greco si possono scrivere in lettere latine, "aleksandar nevski" o "Nafplio". Quando nulla risponde bene, Velorki prova invece le parole più probabili dell'indice e la scheda dice **Risultati per "…"** sopra l'elenco, con ciò che ha cercato davvero.

## Ordinare i gruppi

I risultati offline sono raggruppati, e decidi tu quali gruppi compaiono e in che ordine.

1. Apri **Opzioni**.
2. Tocca **Ricerca**, con il sottotitolo "Cosa mostra la ricerca offline, e in che ordine. Trascina per cambiare la priorità."
3. Trascina una riga dalla sua maniglia per spostarla in su o in giù. Usa l'interruttore a destra per disattivare un gruppo.

Gli otto gruppi, nell'ordine predefinito: **Luoghi**, **Vie e indirizzi**, **Punti di riferimento**, **Soste in bici**, **Pernottamento**, **Natura**, **Trasporti**, **Servizi**.

Non c'è un pulsante di salvataggio; le modifiche hanno effetto al prossimo tasto premuto. Un gruppo disattivato sparisce dalle corrispondenze per nome, e l'ordine decide i pareggi tra risultati che corrispondono al testo altrettanto bene.

## Quando la ricerca non funziona

- **"Nessun risultato."** Il testo non corrisponde a nulla, né offline né online. Prova la riga in fondo per cambiare sorgente, o meno parole.
- **"Ricerca non riuscita."** con un motivo significa che il geocoder online non era raggiungibile. La ricerca offline continua a funzionare dove hai scaricato un'area.
- **"Nessun server di ricerca configurato, impostane uno in Opzioni → Avanzate."** significa che questa build non ha né un indirizzo del geocoder né alcun indice scaricato. Il campo è disabilitato finché non ne esiste uno.

## Vedi anche

- [Soste sulla mappa](./stops-on-the-map)
- [Mappe offline e calcolo del percorso](./offline-maps-and-routing)
- [Pianificare un percorso](./planning-a-route)
- [Impostazioni e aspetto](./settings-and-appearance)
- [Privacy sul telefono](./privacy-on-the-phone)
